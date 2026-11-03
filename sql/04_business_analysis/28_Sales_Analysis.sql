/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      28_Sales_Analysis.sql
Purpose:     Analyze sales demand, fulfillment, revenue, growth and contribution.
Author:      Akshay Aswani
Version:     2.0
Depends on:  27_Executive_KPIs.sql
Rerunnable:  Yes. Read-only analysis using session-scoped temporary tables.

Date-role policy
----------------
- Demand, bookings and cancellations use OrderDateKey.
- Recognized revenue, AOV and sales growth use DeliveredDateKey.
- Refund adjustments are attributed to the delivered-order cohort.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51480, 'Sales analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimProduct', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimStore', N'U') IS NULL
    THROW 51481, 'Sales analysis stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51482, 'Sales analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #OrderDemand;
DROP TABLE IF EXISTS #DeliveredLine;
DROP TABLE IF EXISTS #OrderRefund;
DROP TABLE IF EXISTS #DeliveredOrder;
DROP TABLE IF EXISTS #MonthlyDemand;
DROP TABLE IF EXISTS #MonthlySales;

/* ============================================================================
   1. CONTROLLED ANALYTICAL GRAINS
   ============================================================================ */

-- One row per placed order. OrderCount marks exactly one item row per order.
SELECT
    fact_sales.SalesOrderID,
    MAX(fact_sales.OrderNumber) AS OrderNumber,
    MAX(fact_sales.OrderDateKey) AS OrderDateKey,
    MAX(fact_sales.CustomerKey) AS CustomerKey,
    MAX(fact_sales.StoreKey) AS StoreKey,
    MAX(fact_sales.EmployeeKey) AS EmployeeKey,
    MAX(fact_sales.OrderStatusKey) AS OrderStatusKey,
    MAX(CONVERT(TINYINT, fact_sales.IsDelivered)) AS IsDelivered,
    MAX(CONVERT(TINYINT, fact_sales.IsCancelled)) AS IsCancelled,
    SUM(CONVERT(BIGINT, fact_sales.Quantity)) AS OrderedUnits,
    SUM(CONVERT(DECIMAL(19,2), fact_sales.GrossAmount)) AS GrossLineValue,
    SUM(CONVERT(DECIMAL(19,2), fact_sales.DiscountAmount)) AS DiscountValue,
    SUM(CONVERT(DECIMAL(19,2), fact_sales.TaxAmount)) AS TaxValue,
    SUM(CONVERT(DECIMAL(19,2), fact_sales.NetAmount)) AS InvoiceValue,
    SUM(CASE WHEN fact_sales.IsCancelled = 0 THEN CONVERT(DECIMAL(19,2), fact_sales.GrossAmount) ELSE 0 END) AS GrossOrderValue,
    SUM(CASE WHEN fact_sales.IsCancelled = 0 THEN CONVERT(DECIMAL(19,2), fact_sales.NetAmount) ELSE 0 END) AS BookedOrderValue
INTO #OrderDemand
FROM analytics.FactSales AS fact_sales
GROUP BY fact_sales.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_OrderDemand ON #OrderDemand (SalesOrderID);
CREATE INDEX IX_OrderDemand_OrderDate ON #OrderDemand (OrderDateKey);

-- One row per delivered order item. Recognized revenue excludes tax.
SELECT
    fact_sales.SalesOrderItemID,
    fact_sales.SalesOrderID,
    fact_sales.DeliveredDateKey,
    fact_sales.CustomerKey,
    fact_sales.ProductKey,
    fact_sales.StoreKey,
    fact_sales.EmployeeKey,
    fact_sales.Quantity AS DeliveredUnits,
    fact_sales.UnitCost,
    CONVERT(DECIMAL(19,2), fact_sales.GrossAmount - fact_sales.DiscountAmount) AS RecognizedRevenue,
    CONVERT(DECIMAL(19,2), fact_sales.Quantity * fact_sales.UnitCost) AS RecognizedCost
INTO #DeliveredLine
FROM analytics.FactSales AS fact_sales
WHERE fact_sales.IsDelivered = 1;

CREATE UNIQUE CLUSTERED INDEX CIX_DeliveredLine ON #DeliveredLine (SalesOrderItemID);
CREATE INDEX IX_DeliveredLine_Order ON #DeliveredLine (SalesOrderID);
CREATE INDEX IX_DeliveredLine_DateProduct ON #DeliveredLine (DeliveredDateKey, ProductKey);

-- Refund facts are aggregated independently before being attached to sales orders.
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
        return_eligibility.ProductReturnID,
        return_eligibility.SalesOrderID,
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
        return_eligibility.ProductReturnID,
        return_eligibility.SalesOrderID,
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

CREATE UNIQUE CLUSTERED INDEX CIX_OrderRefund ON #OrderRefund (SalesOrderID);

-- One row per delivered order: the governed grain for AOV and order growth.
;WITH DeliveredSales AS
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
    delivered_sales.SalesOrderID,
    delivered_sales.DeliveredDateKey,
    delivered_sales.CustomerKey,
    delivered_sales.StoreKey,
    delivered_sales.DeliveredUnits,
    delivered_sales.DeliveredUnits - COALESCE(order_refund.AcceptedReturnedUnits, 0) AS NetUnitsSold,
    delivered_sales.RecognizedRevenue,
    COALESCE(order_refund.PretaxRefundValue, 0) AS PretaxRefundValue,
    delivered_sales.RecognizedRevenue - COALESCE(order_refund.PretaxRefundValue, 0) AS NetRevenue,
    delivered_sales.RecognizedCost - COALESCE(order_refund.ReusableReturnCost, 0) AS COGS,
    delivered_sales.RecognizedRevenue
        - COALESCE(order_refund.PretaxRefundValue, 0)
        - delivered_sales.RecognizedCost
        + COALESCE(order_refund.ReusableReturnCost, 0) AS GrossProfit
INTO #DeliveredOrder
FROM DeliveredSales AS delivered_sales
LEFT JOIN #OrderRefund AS order_refund
    ON order_refund.SalesOrderID = delivered_sales.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_DeliveredOrder ON #DeliveredOrder (SalesOrderID);
CREATE INDEX IX_DeliveredOrder_DateStore ON #DeliveredOrder (DeliveredDateKey, StoreKey);

/* ============================================================================
   2. SALES-PAGE KPI CARDS
   ============================================================================ */

DECLARE @TotalOrders BIGINT = (SELECT COUNT_BIG(*) FROM #OrderDemand);
DECLARE @CancelledOrders BIGINT = (SELECT COUNT_BIG(*) FROM #OrderDemand WHERE IsCancelled = 1);
DECLARE @DeliveredOrders BIGINT = (SELECT COUNT_BIG(*) FROM #DeliveredOrder);
DECLARE @GrossOrderValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(GrossOrderValue), 0) FROM #OrderDemand);
DECLARE @BookedOrderValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(BookedOrderValue), 0) FROM #OrderDemand);
DECLARE @NetRevenue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(NetRevenue), 0) FROM #DeliveredOrder);

SELECT
    @TotalOrders AS TotalOrders,
    @GrossOrderValue AS GrossOrderValue,
    @BookedOrderValue AS BookedOrderValue,
    @DeliveredOrders AS DeliveredOrders,
    @NetRevenue AS NetRevenue,
    CONVERT(DECIMAL(19,2), @NetRevenue / NULLIF(@DeliveredOrders, 0)) AS AverageOrderValue,
    @CancelledOrders AS CancelledOrders,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @CancelledOrders)
        / NULLIF(@TotalOrders, 0)) AS OrderCancellationRate;

/* ============================================================================
   3. MONTHLY DEMAND AND CANCELLATION TREND — ORDER DATE
   ============================================================================ */

SELECT
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    date_dimension.CalendarYear,
    date_dimension.CalendarQuarterLabel,
    COUNT_BIG(*) AS TotalOrders,
    SUM(CASE WHEN order_demand.IsDelivered = 1 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS DeliveredOrders,
    SUM(CASE WHEN order_demand.IsCancelled = 1 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS CancelledOrders,
    SUM(CASE WHEN order_demand.IsDelivered = 0 AND order_demand.IsCancelled = 0
             THEN CONVERT(BIGINT, 1) ELSE 0 END) AS ActiveOrders,
    SUM(order_demand.OrderedUnits) AS OrderedUnits,
    SUM(order_demand.GrossOrderValue) AS GrossOrderValue,
    SUM(order_demand.BookedOrderValue) AS BookedOrderValue,
    CONVERT
    (
        DECIMAL(9,4),
        SUM(CASE WHEN order_demand.IsCancelled = 1 THEN CONVERT(DECIMAL(38,6), 1) ELSE 0 END)
        / NULLIF(COUNT_BIG(*), 0)
    ) AS OrderCancellationRate
INTO #MonthlyDemand
FROM #OrderDemand AS order_demand
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = order_demand.OrderDateKey
GROUP BY
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    date_dimension.CalendarYear,
    date_dimension.CalendarQuarterLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_MonthlyDemand ON #MonthlyDemand (YearMonthNumber);

SELECT *
FROM #MonthlyDemand
ORDER BY YearMonthNumber;

/* ============================================================================
   4. MONTHLY RECOGNIZED SALES, MOM AND YOY — DELIVERED DATE
   ============================================================================ */

SELECT
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    date_dimension.CalendarYear,
    date_dimension.MonthNumber,
    date_dimension.FinancialYearLabel,
    COUNT_BIG(*) AS DeliveredOrders,
    COUNT_BIG(DISTINCT delivered_order.CustomerKey) AS ActiveCustomers,
    SUM(delivered_order.NetUnitsSold) AS NetUnitsSold,
    SUM(delivered_order.NetRevenue) AS NetRevenue,
    SUM(delivered_order.GrossProfit) AS GrossProfit,
    CONVERT(DECIMAL(19,2), SUM(delivered_order.NetRevenue) / NULLIF(COUNT_BIG(*), 0)) AS AverageOrderValue
INTO #MonthlySales
FROM #DeliveredOrder AS delivered_order
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = delivered_order.DeliveredDateKey
GROUP BY
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    date_dimension.CalendarYear,
    date_dimension.MonthNumber,
    date_dimension.FinancialYearLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_MonthlySales ON #MonthlySales (YearMonthNumber);

SELECT
    monthly_sales.YearMonthNumber,
    monthly_sales.MonthYearLabel,
    monthly_sales.FinancialYearLabel,
    monthly_sales.DeliveredOrders,
    monthly_sales.ActiveCustomers,
    monthly_sales.NetUnitsSold,
    monthly_sales.NetRevenue,
    monthly_sales.GrossProfit,
    monthly_sales.AverageOrderValue,
    SUM(monthly_sales.NetRevenue) OVER
        (ORDER BY monthly_sales.YearMonthNumber ROWS UNBOUNDED PRECEDING) AS RunningNetRevenue,
    CONVERT
    (
        DECIMAL(9,4),
        (monthly_sales.NetRevenue
         - LAG(monthly_sales.NetRevenue) OVER (ORDER BY monthly_sales.YearMonthNumber))
        / NULLIF(LAG(monthly_sales.NetRevenue)
                 OVER (ORDER BY monthly_sales.YearMonthNumber), 0)
    ) AS NetRevenueMoMRate,
    CONVERT
    (
        DECIMAL(9,4),
        (monthly_sales.NetRevenue
         - LAG(monthly_sales.NetRevenue, 12) OVER (ORDER BY monthly_sales.YearMonthNumber))
        / NULLIF(LAG(monthly_sales.NetRevenue, 12)
                 OVER (ORDER BY monthly_sales.YearMonthNumber), 0)
    ) AS NetRevenueYoYRate
FROM #MonthlySales AS monthly_sales
ORDER BY monthly_sales.YearMonthNumber;

/* ============================================================================
   5. ORDER-STATUS COMPOSITION — ORDER-DATE COHORT
   ============================================================================ */

SELECT
    status_dimension.OrderStatusCode,
    status_dimension.OrderStatusName,
    COUNT_BIG(*) AS TotalOrders,
    SUM(order_demand.OrderedUnits) AS OrderedUnits,
    SUM(order_demand.InvoiceValue) AS InvoiceValue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), COUNT_BIG(*))
        / NULLIF(@TotalOrders, 0)) AS OrderShareRate
FROM #OrderDemand AS order_demand
INNER JOIN analytics.DimOrderStatus AS status_dimension
    ON status_dimension.OrderStatusKey = order_demand.OrderStatusKey
GROUP BY status_dimension.OrderStatusCode, status_dimension.OrderStatusName, status_dimension.SortOrder
ORDER BY status_dimension.SortOrder;

/* ============================================================================
   6. STORE AND GEOGRAPHIC PERFORMANCE — DELIVERED DATE
   Suitable for ranking and AOV-versus-volume scatter visuals.
   ============================================================================ */

SELECT
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_dimension.City,
    store_dimension.StateName,
    COUNT_BIG(*) AS DeliveredOrders,
    COUNT_BIG(DISTINCT delivered_order.CustomerKey) AS ActiveCustomers,
    SUM(delivered_order.NetUnitsSold) AS NetUnitsSold,
    SUM(delivered_order.NetRevenue) AS NetRevenue,
    SUM(delivered_order.GrossProfit) AS GrossProfit,
    CONVERT(DECIMAL(19,2), SUM(delivered_order.NetRevenue) / NULLIF(COUNT_BIG(*), 0)) AS AverageOrderValue,
    CONVERT(DECIMAL(9,4), SUM(delivered_order.NetRevenue) / NULLIF(@NetRevenue, 0)) AS RevenueContributionRate,
    DENSE_RANK() OVER (ORDER BY SUM(delivered_order.NetRevenue) DESC) AS RevenueRank
FROM #DeliveredOrder AS delivered_order
INNER JOIN analytics.DimStore AS store_dimension
    ON store_dimension.StoreKey = delivered_order.StoreKey
GROUP BY
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_dimension.City,
    store_dimension.StateName
ORDER BY RevenueRank, store_dimension.StoreCode;

/* ============================================================================
   7. CATEGORY AND BRAND CONTRIBUTION — DELIVERED LINE GRAIN
   Gross delivered revenue is used here; detailed refund allocation remains
   at order grain and is not duplicated across product rows.
   ============================================================================ */

;WITH ProductContribution AS
(
    SELECT
        product_dimension.CategoryName,
        product_dimension.BrandName,
        COUNT_BIG(DISTINCT delivered_line.SalesOrderID) AS DeliveredOrders,
        SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
        SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
        SUM(delivered_line.RecognizedRevenue - delivered_line.RecognizedCost) AS GrossProfitBeforeReturns
    FROM #DeliveredLine AS delivered_line
    INNER JOIN analytics.DimProduct AS product_dimension
        ON product_dimension.ProductKey = delivered_line.ProductKey
    GROUP BY product_dimension.CategoryName, product_dimension.BrandName
)
SELECT
    product_contribution.CategoryName,
    product_contribution.BrandName,
    product_contribution.DeliveredOrders,
    product_contribution.DeliveredUnits,
    product_contribution.RecognizedRevenue,
    product_contribution.GrossProfitBeforeReturns,
    CONVERT
    (
        DECIMAL(9,4),
        product_contribution.RecognizedRevenue
        / NULLIF(SUM(product_contribution.RecognizedRevenue) OVER (), 0)
    ) AS RecognizedRevenueContributionRate,
    DENSE_RANK() OVER (ORDER BY product_contribution.RecognizedRevenue DESC) AS RevenueRank
FROM ProductContribution AS product_contribution
ORDER BY RevenueRank, product_contribution.CategoryName, product_contribution.BrandName;

/* ============================================================================
   8. DISCOUNT-BAND PERFORMANCE — ORDER-DATE COHORT
   ============================================================================ */

;WITH DiscountBand AS
(
    SELECT
        order_demand.*,
        CASE
            WHEN order_demand.GrossLineValue = 0 THEN '00 No gross value'
            WHEN order_demand.DiscountValue = 0 THEN '01 No discount'
            WHEN order_demand.DiscountValue / NULLIF(order_demand.GrossLineValue, 0) < 0.05 THEN '02 Below 5%'
            WHEN order_demand.DiscountValue / NULLIF(order_demand.GrossLineValue, 0) < 0.10 THEN '03 5% to <10%'
            WHEN order_demand.DiscountValue / NULLIF(order_demand.GrossLineValue, 0) < 0.15 THEN '04 10% to <15%'
            ELSE '05 15% and above'
        END AS DiscountBand
    FROM #OrderDemand AS order_demand
)
SELECT
    discount_band.DiscountBand,
    COUNT_BIG(*) AS TotalOrders,
    SUM(discount_band.GrossLineValue) AS GrossLineValue,
    SUM(discount_band.DiscountValue) AS DiscountValue,
    SUM(discount_band.BookedOrderValue) AS BookedOrderValue,
    CONVERT(DECIMAL(9,4), SUM(discount_band.DiscountValue)
        / NULLIF(SUM(discount_band.GrossLineValue), 0)) AS EffectiveDiscountRate,
    CONVERT(DECIMAL(9,4),
        SUM(CASE WHEN discount_band.IsCancelled = 1 THEN CONVERT(DECIMAL(38,6), 1) ELSE 0 END)
        / NULLIF(COUNT_BIG(*), 0)) AS CancellationRate
FROM DiscountBand AS discount_band
GROUP BY discount_band.DiscountBand
ORDER BY discount_band.DiscountBand;

/* ============================================================================
   9. DAY-OF-WEEK DEMAND SEASONALITY — ORDER DATE
   ============================================================================ */

SELECT
    date_dimension.DayOfWeekNumber,
    date_dimension.DayName,
    date_dimension.IsWeekend,
    COUNT_BIG(*) AS TotalOrders,
    SUM(order_demand.OrderedUnits) AS OrderedUnits,
    SUM(order_demand.BookedOrderValue) AS BookedOrderValue,
    CONVERT(DECIMAL(19,2), SUM(order_demand.BookedOrderValue) / NULLIF(COUNT_BIG(*), 0)) AS AverageBookedOrderValue,
    CONVERT(DECIMAL(9,4),
        SUM(CASE WHEN order_demand.IsCancelled = 1 THEN CONVERT(DECIMAL(38,6), 1) ELSE 0 END)
        / NULLIF(COUNT_BIG(*), 0)) AS CancellationRate
FROM #OrderDemand AS order_demand
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = order_demand.OrderDateKey
GROUP BY date_dimension.DayOfWeekNumber, date_dimension.DayName, date_dimension.IsWeekend
ORDER BY date_dimension.DayOfWeekNumber;

/* ============================================================================
   10. TOP DELIVERED ORDERS
   ============================================================================ */

SELECT TOP (10)
    order_demand.OrderNumber,
    delivered_date.[Date] AS DeliveredDate,
    customer_dimension.CustomerCode,
    customer_dimension.CustomerName,
    store_dimension.StoreName,
    delivered_order.DeliveredUnits,
    delivered_order.NetUnitsSold,
    delivered_order.NetRevenue,
    delivered_order.GrossProfit,
    CONVERT(DECIMAL(9,4), delivered_order.GrossProfit
        / NULLIF(delivered_order.NetRevenue, 0)) AS GrossMarginRate
FROM #DeliveredOrder AS delivered_order
INNER JOIN #OrderDemand AS order_demand
    ON order_demand.SalesOrderID = delivered_order.SalesOrderID
INNER JOIN analytics.DimDate AS delivered_date
    ON delivered_date.DateKey = delivered_order.DeliveredDateKey
INNER JOIN analytics.DimCustomer AS customer_dimension
    ON customer_dimension.CustomerKey = delivered_order.CustomerKey
INNER JOIN analytics.DimStore AS store_dimension
    ON store_dimension.StoreKey = delivered_order.StoreKey
ORDER BY delivered_order.NetRevenue DESC, delivered_order.SalesOrderID;

/* ============================================================================
   11. SALES ANALYSIS VALIDATION
   ============================================================================ */

DECLARE @SalesValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(80) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

DECLARE @OrderSourceCount BIGINT = (SELECT COUNT_BIG(*) FROM sales.SalesOrder);
DECLARE @DeliveredSourceCount BIGINT =
(
    SELECT COUNT_BIG(*)
    FROM sales.SalesOrder AS source_order
    INNER JOIN ref.OrderStatus AS source_status
        ON source_status.OrderStatusID = source_order.OrderStatusID
    WHERE source_status.OrderStatusCode IN ('DELIVERED', 'PARTIALLY_RETURNED', 'RETURNED')
);

INSERT INTO @SalesValidation VALUES
(1, 'One analytical row per placed order',
 ABS(@OrderSourceCount - @TotalOrders),
 CASE WHEN @OrderSourceCount = @TotalOrders THEN 'PASSED' ELSE 'FAILED' END),
(2, 'One analytical row per delivered order',
 ABS(@DeliveredSourceCount - @DeliveredOrders),
 CASE WHEN @DeliveredSourceCount = @DeliveredOrders THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Order status population reconciliation',
 CASE WHEN @TotalOrders = @DeliveredOrders + @CancelledOrders
       + (SELECT COUNT_BIG(*) FROM #OrderDemand WHERE IsDelivered = 0 AND IsCancelled = 0)
       THEN 0 ELSE 1 END,
 CASE WHEN @TotalOrders = @DeliveredOrders + @CancelledOrders
       + (SELECT COUNT_BIG(*) FROM #OrderDemand WHERE IsDelivered = 0 AND IsCancelled = 0)
       THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Monthly demand totals reconcile',
 ABS(@TotalOrders - (SELECT COALESCE(SUM(TotalOrders), 0) FROM #MonthlyDemand)),
 CASE WHEN @TotalOrders = (SELECT COALESCE(SUM(TotalOrders), 0) FROM #MonthlyDemand)
      THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Monthly delivered totals reconcile',
 ABS(@DeliveredOrders - (SELECT COALESCE(SUM(DeliveredOrders), 0) FROM #MonthlySales)),
 CASE WHEN @DeliveredOrders = (SELECT COALESCE(SUM(DeliveredOrders), 0) FROM #MonthlySales)
      THEN 'PASSED' ELSE 'FAILED' END),
(6, 'Sales values are non-negative',
 (SELECT COUNT_BIG(*) FROM #DeliveredOrder
  WHERE RecognizedRevenue < 0 OR NetRevenue < 0 OR COGS < 0),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #DeliveredOrder
       WHERE RecognizedRevenue < 0 OR NetRevenue < 0 OR COGS < 0)
      THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @SalesValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @SalesValidation WHERE ValidationStatus = 'FAILED')
    THROW 51483, 'Sales analysis validation failed. Review the final validation result set.', 1;

RAISERROR('28_Sales_Analysis.sql completed successfully: sales demand and performance analyses validated.', 10, 1) WITH NOWAIT;
GO
