/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      29_Customer_Analysis.sql
Purpose:     Analyze customer value, behavior, acquisition, cohorts and retention.
Author:      Akshay Aswani
Version:     2.0
Depends on:  28_Sales_Analysis.sql
Rerunnable:  Yes. Read-only analysis using session-scoped temporary tables.

Important definitions
---------------------
- Active customer: at least one delivered order in the analysis period.
- New customer: first delivered order occurs in the period.
- Repeat customer: at least two delivered orders in the period.
- Customer lifetime value: realized historical pretax net revenue, not a
  prediction of future customer value.
- Cohort month: month of the customer's first delivered order.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51490, 'Customer analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimCustomer', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
    THROW 51491, 'Customer analysis stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51492, 'Customer analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #DeliveredLine;
DROP TABLE IF EXISTS #OrderRefund;
DROP TABLE IF EXISTS #CustomerOrder;
DROP TABLE IF EXISTS #CustomerProfile;
DROP TABLE IF EXISTS #CustomerMonth;
DROP TABLE IF EXISTS #CustomerCohort;
DROP TABLE IF EXISTS #RFMScore;

/* ============================================================================
   1. BUILD DELIVERED CUSTOMER-ORDER PERFORMANCE
   ============================================================================ */

SELECT
    fact_sales.SalesOrderItemID,
    fact_sales.SalesOrderID,
    fact_sales.DeliveredDateKey,
    fact_sales.CustomerKey,
    fact_sales.ProductKey,
    fact_sales.StoreKey,
    fact_sales.Quantity AS DeliveredUnits,
    fact_sales.UnitCost,
    CONVERT(DECIMAL(19,2), fact_sales.GrossAmount - fact_sales.DiscountAmount) AS RecognizedRevenue,
    CONVERT(DECIMAL(19,2), fact_sales.Quantity * fact_sales.UnitCost) AS RecognizedCost
INTO #DeliveredLine
FROM analytics.FactSales AS fact_sales
WHERE fact_sales.IsDelivered = 1;

CREATE UNIQUE CLUSTERED INDEX CIX_CustomerDeliveredLine
    ON #DeliveredLine (SalesOrderItemID);
CREATE INDEX IX_CustomerDeliveredLine_Order
    ON #DeliveredLine (SalesOrderID);

;WITH ReturnEligibility AS
(
    SELECT
        fact_return.ProductReturnID,
        fact_return.SalesOrderID,
        SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnedUnits,
        SUM(CASE WHEN fact_return.IsReusable = 1
                 THEN CONVERT(DECIMAL(19,2), fact_return.QuantityAccepted * delivered_line.UnitCost)
                 ELSE CONVERT(DECIMAL(19,2), 0) END) AS ReusableReturnCost,
        SUM(CONVERT(DECIMAL(19,2), fact_return.EligibleRefundAmount)) AS EligibleRefundValue,
        SUM
        (
            CONVERT
            (
                DECIMAL(19,2),
                fact_return.EligibleRefundAmount
                * COALESCE
                  (
                      NULLIF(delivered_line.RecognizedRevenue, 0)
                      / NULLIF(source_item.NetAmount, 0),
                      0
                  )
            )
        ) AS EligiblePretaxRefundValue
    FROM analytics.FactReturns AS fact_return
    INNER JOIN #DeliveredLine AS delivered_line
        ON delivered_line.SalesOrderItemID = fact_return.SalesOrderItemID
    INNER JOIN sales.SalesOrderItem AS source_item
        ON source_item.SalesOrderItemID = fact_return.SalesOrderItemID
    WHERE fact_return.QuantityAccepted > 0
    GROUP BY fact_return.ProductReturnID, fact_return.SalesOrderID
),
ReturnRefund AS
(
    SELECT
        return_eligibility.SalesOrderID,
        return_eligibility.ProductReturnID,
        return_eligibility.AcceptedReturnedUnits,
        return_eligibility.ReusableReturnCost,
        CONVERT
        (
            DECIMAL(19,2),
            SUM(fact_refund.CompletedRefundAmount)
            * COALESCE
              (
                  NULLIF(return_eligibility.EligiblePretaxRefundValue, 0)
                  / NULLIF(return_eligibility.EligibleRefundValue, 0),
                  0
              )
        ) AS PretaxRefundValue
    FROM ReturnEligibility AS return_eligibility
    INNER JOIN analytics.FactRefunds AS fact_refund
        ON fact_refund.ProductReturnID = return_eligibility.ProductReturnID
    GROUP BY
        return_eligibility.SalesOrderID,
        return_eligibility.ProductReturnID,
        return_eligibility.AcceptedReturnedUnits,
        return_eligibility.ReusableReturnCost,
        return_eligibility.EligibleRefundValue,
        return_eligibility.EligiblePretaxRefundValue
)
SELECT
    return_refund.SalesOrderID,
    SUM(return_refund.AcceptedReturnedUnits) AS AcceptedReturnedUnits,
    SUM(return_refund.ReusableReturnCost) AS ReusableReturnCost,
    SUM(return_refund.PretaxRefundValue) AS PretaxRefundValue
INTO #OrderRefund
FROM ReturnRefund AS return_refund
GROUP BY return_refund.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_CustomerOrderRefund
    ON #OrderRefund (SalesOrderID);

;WITH DeliveredOrder AS
(
    SELECT
        delivered_line.SalesOrderID,
        MAX(delivered_line.DeliveredDateKey) AS DeliveredDateKey,
        MAX(delivered_line.CustomerKey) AS CustomerKey,
        MAX(delivered_line.StoreKey) AS StoreKey,
        SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
        SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
        SUM(delivered_line.RecognizedCost) AS RecognizedCost
    FROM #DeliveredLine AS delivered_line
    GROUP BY delivered_line.SalesOrderID
)
SELECT
    delivered_order.SalesOrderID,
    delivered_order.DeliveredDateKey,
    delivered_date.[Date] AS DeliveredDate,
    delivered_date.MonthStartDate AS ActivityMonth,
    delivered_order.CustomerKey,
    delivered_order.StoreKey,
    delivered_order.DeliveredUnits,
    delivered_order.DeliveredUnits - COALESCE(order_refund.AcceptedReturnedUnits, 0) AS NetUnitsSold,
    delivered_order.RecognizedRevenue - COALESCE(order_refund.PretaxRefundValue, 0) AS NetRevenue,
    delivered_order.RecognizedCost - COALESCE(order_refund.ReusableReturnCost, 0) AS COGS,
    delivered_order.RecognizedRevenue
        - COALESCE(order_refund.PretaxRefundValue, 0)
        - delivered_order.RecognizedCost
        + COALESCE(order_refund.ReusableReturnCost, 0) AS GrossProfit
INTO #CustomerOrder
FROM DeliveredOrder AS delivered_order
INNER JOIN analytics.DimDate AS delivered_date
    ON delivered_date.DateKey = delivered_order.DeliveredDateKey
LEFT JOIN #OrderRefund AS order_refund
    ON order_refund.SalesOrderID = delivered_order.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_CustomerOrder
    ON #CustomerOrder (SalesOrderID);
CREATE INDEX IX_CustomerOrder_CustomerDate
    ON #CustomerOrder (CustomerKey, DeliveredDate);

DECLARE @AnalysisDate DATE = (SELECT MAX(DeliveredDate) FROM #CustomerOrder);

SELECT
    customer_order.CustomerKey,
    MIN(customer_order.DeliveredDate) AS FirstDeliveredDate,
    MAX(customer_order.DeliveredDate) AS LastDeliveredDate,
    DATEDIFF(DAY, MAX(customer_order.DeliveredDate), @AnalysisDate) AS RecencyDays,
    COUNT_BIG(*) AS DeliveredOrders,
    COUNT_BIG(DISTINCT customer_order.ActivityMonth) AS ActiveMonths,
    SUM(customer_order.NetUnitsSold) AS NetUnitsSold,
    SUM(customer_order.NetRevenue) AS CustomerLifetimeValue,
    SUM(customer_order.GrossProfit) AS LifetimeGrossProfit,
    CONVERT(DECIMAL(19,2), SUM(customer_order.NetRevenue) / NULLIF(COUNT_BIG(*), 0)) AS AverageOrderValue
INTO #CustomerProfile
FROM #CustomerOrder AS customer_order
GROUP BY customer_order.CustomerKey;

CREATE UNIQUE CLUSTERED INDEX CIX_CustomerProfile
    ON #CustomerProfile (CustomerKey);

/* ============================================================================
   2. CUSTOMER KPI SCORECARD
   ============================================================================ */

DECLARE @RegisteredCustomers BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.DimCustomer WHERE IsUnknown = 0);
DECLARE @ActiveCustomers BIGINT = (SELECT COUNT_BIG(*) FROM #CustomerProfile);
DECLARE @RepeatCustomers BIGINT =
    (SELECT COUNT_BIG(*) FROM #CustomerProfile WHERE DeliveredOrders >= 2);
DECLARE @DeliveredOrders BIGINT = (SELECT COUNT_BIG(*) FROM #CustomerOrder);
DECLARE @CustomerRevenue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(CustomerLifetimeValue), 0) FROM #CustomerProfile);

SELECT
    @AnalysisDate AS AnalysisAsOfDate,
    @RegisteredCustomers AS RegisteredCustomers,
    @ActiveCustomers AS ActiveCustomers,
    @RepeatCustomers AS RepeatCustomers,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @RepeatCustomers)
        / NULLIF(@ActiveCustomers, 0)) AS RepeatCustomerRate,
    @DeliveredOrders AS DeliveredOrders,
    CONVERT(DECIMAL(19,2), CONVERT(DECIMAL(38,6), @DeliveredOrders)
        / NULLIF(@ActiveCustomers, 0)) AS PurchaseFrequency,
    @CustomerRevenue AS RealizedCustomerLifetimeValue,
    CONVERT(DECIMAL(19,2), @CustomerRevenue / NULLIF(@ActiveCustomers, 0)) AS AverageValuePerActiveCustomer,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @ActiveCustomers)
        / NULLIF(@RegisteredCustomers, 0)) AS CustomerActivationRate;

/* ============================================================================
   3. MONTHLY ACQUISITION, ACTIVE AND REPEAT CUSTOMERS
   ============================================================================ */

SELECT DISTINCT
    customer_order.CustomerKey,
    customer_order.ActivityMonth
INTO #CustomerMonth
FROM #CustomerOrder AS customer_order;

CREATE UNIQUE CLUSTERED INDEX CIX_CustomerMonth
    ON #CustomerMonth (CustomerKey, ActivityMonth);

;WITH FirstActivity AS
(
    SELECT CustomerKey, MIN(ActivityMonth) AS FirstActivityMonth
    FROM #CustomerMonth
    GROUP BY CustomerKey
),
MonthlyFrequency AS
(
    SELECT CustomerKey, ActivityMonth, COUNT_BIG(*) AS DeliveredOrders
    FROM #CustomerOrder
    GROUP BY CustomerKey, ActivityMonth
)
SELECT
    customer_month.ActivityMonth,
    COUNT_BIG(DISTINCT customer_month.CustomerKey) AS ActiveCustomers,
    COUNT_BIG(DISTINCT CASE WHEN first_activity.FirstActivityMonth = customer_month.ActivityMonth
                            THEN customer_month.CustomerKey END) AS NewCustomers,
    COUNT_BIG(DISTINCT CASE WHEN monthly_frequency.DeliveredOrders >= 2
                            THEN customer_month.CustomerKey END) AS RepeatCustomersWithinMonth,
    SUM(monthly_frequency.DeliveredOrders) AS DeliveredOrders,
    CONVERT(DECIMAL(19,2), CONVERT(DECIMAL(38,6), SUM(monthly_frequency.DeliveredOrders))
        / NULLIF(COUNT_BIG(DISTINCT customer_month.CustomerKey), 0)) AS PurchaseFrequency
FROM #CustomerMonth AS customer_month
INNER JOIN FirstActivity AS first_activity
    ON first_activity.CustomerKey = customer_month.CustomerKey
INNER JOIN MonthlyFrequency AS monthly_frequency
    ON monthly_frequency.CustomerKey = customer_month.CustomerKey
   AND monthly_frequency.ActivityMonth = customer_month.ActivityMonth
GROUP BY customer_month.ActivityMonth
ORDER BY customer_month.ActivityMonth;

/* ============================================================================
   4. TOP CUSTOMERS BY REALIZED HISTORICAL VALUE
   ============================================================================ */

SELECT TOP (20)
    customer_dimension.CustomerCode,
    customer_dimension.CustomerName,
    customer_dimension.CustomerSegment,
    customer_dimension.City,
    customer_dimension.StateName,
    customer_profile.FirstDeliveredDate,
    customer_profile.LastDeliveredDate,
    customer_profile.RecencyDays,
    customer_profile.DeliveredOrders,
    customer_profile.ActiveMonths,
    customer_profile.NetUnitsSold,
    customer_profile.CustomerLifetimeValue,
    customer_profile.LifetimeGrossProfit,
    customer_profile.AverageOrderValue,
    DENSE_RANK() OVER (ORDER BY customer_profile.CustomerLifetimeValue DESC) AS ValueRank
FROM #CustomerProfile AS customer_profile
INNER JOIN analytics.DimCustomer AS customer_dimension
    ON customer_dimension.CustomerKey = customer_profile.CustomerKey
ORDER BY ValueRank, customer_dimension.CustomerCode;

/* ============================================================================
   5. RFM SCORING AND ACTIONABLE SEGMENTS
   Scores of 5 represent the most desirable behavior.
   ============================================================================ */

;WITH RFMBase AS
(
    SELECT
        customer_profile.*,
        6 - NTILE(5) OVER (ORDER BY customer_profile.RecencyDays ASC) AS RecencyScore,
        NTILE(5) OVER (ORDER BY customer_profile.DeliveredOrders ASC) AS FrequencyScore,
        NTILE(5) OVER (ORDER BY customer_profile.CustomerLifetimeValue ASC) AS MonetaryScore
    FROM #CustomerProfile AS customer_profile
)
SELECT
    rfm_base.*,
    CONCAT(rfm_base.RecencyScore, rfm_base.FrequencyScore, rfm_base.MonetaryScore) AS RFMCode,
    CASE
        WHEN rfm_base.RecencyScore >= 4 AND rfm_base.FrequencyScore >= 4 AND rfm_base.MonetaryScore >= 4 THEN 'Champions'
        WHEN rfm_base.RecencyScore >= 3 AND rfm_base.FrequencyScore >= 4 THEN 'Loyal Customers'
        WHEN rfm_base.RecencyScore = 5 AND rfm_base.FrequencyScore <= 2 THEN 'New Customers'
        WHEN rfm_base.RecencyScore >= 4 AND rfm_base.FrequencyScore BETWEEN 2 AND 3 THEN 'Potential Loyalists'
        WHEN rfm_base.RecencyScore <= 2 AND rfm_base.FrequencyScore >= 4 THEN 'At Risk'
        WHEN rfm_base.RecencyScore = 1 AND rfm_base.FrequencyScore <= 2 THEN 'Lost'
        ELSE 'Needs Attention'
    END AS RFMCustomerSegment
INTO #RFMScore
FROM RFMBase AS rfm_base;

CREATE UNIQUE CLUSTERED INDEX CIX_RFMScore ON #RFMScore (CustomerKey);

SELECT
    rfm_score.RFMCustomerSegment,
    COUNT_BIG(*) AS CustomerCount,
    SUM(rfm_score.DeliveredOrders) AS DeliveredOrders,
    SUM(rfm_score.CustomerLifetimeValue) AS CustomerLifetimeValue,
    SUM(rfm_score.LifetimeGrossProfit) AS LifetimeGrossProfit,
    CONVERT(DECIMAL(19,2), SUM(rfm_score.CustomerLifetimeValue) / NULLIF(COUNT_BIG(*), 0)) AS AverageCustomerValue,
    CONVERT(DECIMAL(9,4), SUM(rfm_score.CustomerLifetimeValue)
        / NULLIF(@CustomerRevenue, 0)) AS RevenueContributionRate
FROM #RFMScore AS rfm_score
GROUP BY rfm_score.RFMCustomerSegment
ORDER BY CustomerLifetimeValue DESC;

/* ============================================================================
   6. CUSTOMER COHORT RETENTION MATRIX
   Retention = active cohort customers in activity month / original cohort size.
   ============================================================================ */

SELECT
    customer_month.CustomerKey,
    MIN(customer_month.ActivityMonth) OVER (PARTITION BY customer_month.CustomerKey) AS CohortMonth,
    customer_month.ActivityMonth,
    DATEDIFF
    (
        MONTH,
        MIN(customer_month.ActivityMonth) OVER (PARTITION BY customer_month.CustomerKey),
        customer_month.ActivityMonth
    ) AS CohortMonthNumber
INTO #CustomerCohort
FROM #CustomerMonth AS customer_month;

CREATE UNIQUE CLUSTERED INDEX CIX_CustomerCohort
    ON #CustomerCohort (CustomerKey, ActivityMonth);

;WITH CohortSize AS
(
    SELECT CohortMonth, COUNT_BIG(DISTINCT CustomerKey) AS CohortCustomers
    FROM #CustomerCohort
    WHERE CohortMonthNumber = 0
    GROUP BY CohortMonth
),
CohortActivity AS
(
    SELECT
        CohortMonth,
        CohortMonthNumber,
        COUNT_BIG(DISTINCT CustomerKey) AS RetainedCustomers
    FROM #CustomerCohort
    GROUP BY CohortMonth, CohortMonthNumber
)
SELECT
    cohort_activity.CohortMonth,
    cohort_activity.CohortMonthNumber,
    cohort_size.CohortCustomers,
    cohort_activity.RetainedCustomers,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), cohort_activity.RetainedCustomers)
        / NULLIF(cohort_size.CohortCustomers, 0)) AS CustomerRetentionRate
FROM CohortActivity AS cohort_activity
INNER JOIN CohortSize AS cohort_size
    ON cohort_size.CohortMonth = cohort_activity.CohortMonth
ORDER BY cohort_activity.CohortMonth, cohort_activity.CohortMonthNumber;

/* ============================================================================
   7. GEOGRAPHIC AND SOURCE-SEGMENT PERFORMANCE
   ============================================================================ */

SELECT
    customer_dimension.CustomerSegment,
    customer_dimension.StateName,
    customer_dimension.City,
    COUNT_BIG(*) AS ActiveCustomers,
    SUM(customer_profile.DeliveredOrders) AS DeliveredOrders,
    SUM(customer_profile.CustomerLifetimeValue) AS CustomerLifetimeValue,
    SUM(customer_profile.LifetimeGrossProfit) AS LifetimeGrossProfit,
    CONVERT(DECIMAL(19,2), SUM(customer_profile.CustomerLifetimeValue)
        / NULLIF(COUNT_BIG(*), 0)) AS AverageValuePerCustomer,
    CONVERT(DECIMAL(19,2), CONVERT(DECIMAL(38,6), SUM(customer_profile.DeliveredOrders))
        / NULLIF(COUNT_BIG(*), 0)) AS PurchaseFrequency
FROM #CustomerProfile AS customer_profile
INNER JOIN analytics.DimCustomer AS customer_dimension
    ON customer_dimension.CustomerKey = customer_profile.CustomerKey
GROUP BY
    customer_dimension.CustomerSegment,
    customer_dimension.StateName,
    customer_dimension.City
ORDER BY CustomerLifetimeValue DESC;

/* ============================================================================
   8. RECENCY-BASED ENGAGEMENT RISK
   These descriptive bands support action; they are not predictive churn scores.
   ============================================================================ */

;WITH EngagementRisk AS
(
    SELECT
        customer_profile.*,
        CASE
            WHEN customer_profile.RecencyDays <= 30 THEN '01 Active: 0-30 days'
            WHEN customer_profile.RecencyDays <= 60 THEN '02 Recent: 31-60 days'
            WHEN customer_profile.RecencyDays <= 90 THEN '03 Watch: 61-90 days'
            WHEN customer_profile.RecencyDays <= 180 THEN '04 At Risk: 91-180 days'
            ELSE '05 Dormant: 181+ days'
        END AS EngagementRiskBand
    FROM #CustomerProfile AS customer_profile
)
SELECT
    engagement_risk.EngagementRiskBand,
    COUNT_BIG(*) AS CustomerCount,
    SUM(engagement_risk.DeliveredOrders) AS LifetimeDeliveredOrders,
    SUM(engagement_risk.CustomerLifetimeValue) AS CustomerLifetimeValue,
    CONVERT(DECIMAL(19,2), SUM(engagement_risk.CustomerLifetimeValue)
        / NULLIF(COUNT_BIG(*), 0)) AS AverageCustomerValue
FROM EngagementRisk AS engagement_risk
GROUP BY engagement_risk.EngagementRiskBand
ORDER BY engagement_risk.EngagementRiskBand;

/* ============================================================================
   9. CUSTOMER ANALYSIS VALIDATION
   ============================================================================ */

DECLARE @CustomerValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(100) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

DECLARE @FactDeliveredOrders BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, OrderCount)), 0)
     FROM analytics.FactSales WHERE IsDelivered = 1);
DECLARE @FactActiveCustomers BIGINT =
    (SELECT COUNT_BIG(DISTINCT CustomerKey)
     FROM analytics.FactSales WHERE IsDelivered = 1);

INSERT INTO @CustomerValidation VALUES
(1, 'Delivered-order grain reconciliation',
 ABS(@FactDeliveredOrders - @DeliveredOrders),
 CASE WHEN @FactDeliveredOrders = @DeliveredOrders THEN 'PASSED' ELSE 'FAILED' END),
(2, 'Active-customer reconciliation',
 ABS(@FactActiveCustomers - @ActiveCustomers),
 CASE WHEN @FactActiveCustomers = @ActiveCustomers THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Repeat customers cannot exceed active customers',
 CASE WHEN @RepeatCustomers <= @ActiveCustomers THEN 0 ELSE 1 END,
 CASE WHEN @RepeatCustomers <= @ActiveCustomers THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Customer profiles contain valid dates',
 (SELECT COUNT_BIG(*) FROM #CustomerProfile
  WHERE FirstDeliveredDate > LastDeliveredDate OR RecencyDays < 0),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #CustomerProfile
       WHERE FirstDeliveredDate > LastDeliveredDate OR RecencyDays < 0)
      THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Customer value reconciles to order value',
 CASE WHEN @CustomerRevenue = (SELECT COALESCE(SUM(NetRevenue), 0) FROM #CustomerOrder)
      THEN 0 ELSE 1 END,
 CASE WHEN @CustomerRevenue = (SELECT COALESCE(SUM(NetRevenue), 0) FROM #CustomerOrder)
      THEN 'PASSED' ELSE 'FAILED' END),
(6, 'RFM assigns every active customer once',
 ABS(@ActiveCustomers - (SELECT COUNT_BIG(*) FROM #RFMScore)),
 CASE WHEN @ActiveCustomers = (SELECT COUNT_BIG(*) FROM #RFMScore)
      THEN 'PASSED' ELSE 'FAILED' END),
(7, 'Every customer has one cohort start',
 (SELECT COUNT_BIG(*)
  FROM
  (
      SELECT CustomerKey
      FROM #CustomerCohort
      WHERE CohortMonthNumber = 0
      GROUP BY CustomerKey
      HAVING COUNT_BIG(*) <> 1
  ) AS invalid_cohort),
 CASE WHEN NOT EXISTS
      (
          SELECT 1
          FROM #CustomerCohort
          WHERE CohortMonthNumber = 0
          GROUP BY CustomerKey
          HAVING COUNT_BIG(*) <> 1
      ) THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @CustomerValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @CustomerValidation WHERE ValidationStatus = 'FAILED')
    THROW 51493, 'Customer analysis validation failed. Review the final validation result set.', 1;

RAISERROR('29_Customer_Analysis.sql completed successfully: customer value, RFM and cohort analyses validated.', 10, 1) WITH NOWAIT;
GO
