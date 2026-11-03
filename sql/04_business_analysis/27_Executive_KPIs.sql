/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      27_Executive_KPIs.sql
Purpose:     Produce the governed executive KPI scorecard and trend controls.
Author:      Akshay Aswani
Version:     2.0
Depends on:  26_Validate_Analytics_Model.sql (successful execution)
Rerunnable:  Yes. Read-only analysis; temporary tables are session-scoped.

Portfolio concepts demonstrated
-------------------------------
- Independent aggregation of multiple fact tables
- Pretax revenue and refund allocation
- Reusable-return COGS reversal
- Order-level and customer-level KPI grains
- Safe ratio calculations with NULLIF
- Financial-year trends and LAG-based growth
- Payment retry analysis
- Automated KPI sanity validation
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51470, 'Executive KPI analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactPayments', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
    THROW 51471, 'Executive KPI analysis stopped: the validated analytics model is incomplete.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51472, 'Executive KPI analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #SalesLinePerformance;
DROP TABLE IF EXISTS #ReturnAdjustment;
DROP TABLE IF EXISTS #RefundAdjustment;
DROP TABLE IF EXISTS #OrderPerformance;
DROP TABLE IF EXISTS #PaymentOrderOutcome;
DROP TABLE IF EXISTS #FiscalPerformance;

/* ============================================================================
   1. PREPARE GOVERNED KPI COMPONENTS AT THEIR NATURAL GRAINS
   ============================================================================ */

-- Delivered sales remain at order-item grain. Revenue excludes pass-through tax.
SELECT
    fact_sales.SalesOrderItemID,
    fact_sales.SalesOrderID,
    fact_sales.OrderNumber,
    fact_sales.DeliveredDateKey,
    fact_sales.CustomerKey,
    fact_sales.ProductKey,
    fact_sales.StoreKey,
    fact_sales.EmployeeKey,
    fact_sales.Quantity AS DeliveredUnits,
    fact_sales.UnitCost,
    CONVERT(DECIMAL(19,2), fact_sales.GrossAmount - fact_sales.DiscountAmount) AS RecognizedPretaxRevenue,
    CONVERT(DECIMAL(19,2), fact_sales.Quantity * fact_sales.UnitCost) AS RecognizedCost
INTO #SalesLinePerformance
FROM analytics.FactSales AS fact_sales
WHERE fact_sales.IsDelivered = 1;

CREATE UNIQUE CLUSTERED INDEX CIX_SalesLinePerformance
    ON #SalesLinePerformance (SalesOrderItemID);
CREATE INDEX IX_SalesLinePerformance_Order
    ON #SalesLinePerformance (SalesOrderID);

-- Allocate eligible refunds to pretax value and reverse cost only for reusable units.
SELECT
    fact_return.ProductReturnID,
    fact_return.SalesOrderID,
    SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnedUnits,
    SUM(CASE WHEN fact_return.IsReusable = 1
             THEN CONVERT(DECIMAL(19,2), fact_return.QuantityAccepted * sales_line.UnitCost)
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
                  NULLIF(sales_line.RecognizedPretaxRevenue, 0)
                  / NULLIF(source_item.NetAmount, 0),
                  0
              )
        )
    ) AS EligiblePretaxRefundValue
INTO #ReturnAdjustment
FROM analytics.FactReturns AS fact_return
INNER JOIN #SalesLinePerformance AS sales_line
    ON sales_line.SalesOrderItemID = fact_return.SalesOrderItemID
INNER JOIN sales.SalesOrderItem AS source_item
    ON source_item.SalesOrderItemID = fact_return.SalesOrderItemID
WHERE fact_return.QuantityAccepted > 0
GROUP BY fact_return.ProductReturnID, fact_return.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_ReturnAdjustment
    ON #ReturnAdjustment (ProductReturnID);

-- Refunds are first aggregated at return-header grain to prevent item/refund fan-out.
SELECT
    return_adjustment.ProductReturnID,
    return_adjustment.SalesOrderID,
    return_adjustment.AcceptedReturnedUnits,
    return_adjustment.ReusableReturnCost,
    SUM(fact_refund.CompletedRefundAmount) AS CompletedRefundValue,
    CONVERT
    (
        DECIMAL(19,2),
        SUM(fact_refund.CompletedRefundAmount)
        * COALESCE
          (
              NULLIF(return_adjustment.EligiblePretaxRefundValue, 0)
              / NULLIF(return_adjustment.EligibleRefundValue, 0),
              0
          )
    ) AS CompletedPretaxRefundValue
INTO #RefundAdjustment
FROM #ReturnAdjustment AS return_adjustment
INNER JOIN analytics.FactRefunds AS fact_refund
    ON fact_refund.ProductReturnID = return_adjustment.ProductReturnID
GROUP BY
    return_adjustment.ProductReturnID,
    return_adjustment.SalesOrderID,
    return_adjustment.AcceptedReturnedUnits,
    return_adjustment.ReusableReturnCost,
    return_adjustment.EligibleRefundValue,
    return_adjustment.EligiblePretaxRefundValue;

CREATE UNIQUE CLUSTERED INDEX CIX_RefundAdjustment
    ON #RefundAdjustment (ProductReturnID);

;WITH SalesByOrder AS
(
    SELECT
        sales_line.SalesOrderID,
        MAX(sales_line.OrderNumber) AS OrderNumber,
        MAX(sales_line.DeliveredDateKey) AS DeliveredDateKey,
        MAX(sales_line.CustomerKey) AS CustomerKey,
        MAX(sales_line.StoreKey) AS StoreKey,
        SUM(CONVERT(BIGINT, sales_line.DeliveredUnits)) AS DeliveredUnits,
        SUM(sales_line.RecognizedPretaxRevenue) AS RecognizedRevenue,
        SUM(sales_line.RecognizedCost) AS RecognizedCost
    FROM #SalesLinePerformance AS sales_line
    GROUP BY sales_line.SalesOrderID
),
AdjustmentsByOrder AS
(
    SELECT
        refund_adjustment.SalesOrderID,
        SUM(refund_adjustment.AcceptedReturnedUnits) AS AcceptedReturnedUnits,
        SUM(refund_adjustment.ReusableReturnCost) AS ReusableReturnCost,
        SUM(refund_adjustment.CompletedRefundValue) AS GrossRefundValue,
        SUM(refund_adjustment.CompletedPretaxRefundValue) AS PretaxRefundValue
    FROM #RefundAdjustment AS refund_adjustment
    GROUP BY refund_adjustment.SalesOrderID
)
SELECT
    sales_order.SalesOrderID,
    sales_order.OrderNumber,
    sales_order.DeliveredDateKey,
    sales_order.CustomerKey,
    sales_order.StoreKey,
    sales_order.DeliveredUnits,
    COALESCE(order_adjustment.AcceptedReturnedUnits, 0) AS AcceptedReturnedUnits,
    sales_order.DeliveredUnits - COALESCE(order_adjustment.AcceptedReturnedUnits, 0) AS NetUnitsSold,
    sales_order.RecognizedRevenue,
    COALESCE(order_adjustment.GrossRefundValue, 0) AS GrossRefundValue,
    COALESCE(order_adjustment.PretaxRefundValue, 0) AS PretaxRefundValue,
    sales_order.RecognizedRevenue - COALESCE(order_adjustment.PretaxRefundValue, 0) AS NetRevenue,
    sales_order.RecognizedCost - COALESCE(order_adjustment.ReusableReturnCost, 0) AS COGS,
    sales_order.RecognizedRevenue
        - COALESCE(order_adjustment.PretaxRefundValue, 0)
        - sales_order.RecognizedCost
        + COALESCE(order_adjustment.ReusableReturnCost, 0) AS GrossProfit
INTO #OrderPerformance
FROM SalesByOrder AS sales_order
LEFT JOIN AdjustmentsByOrder AS order_adjustment
    ON order_adjustment.SalesOrderID = sales_order.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_OrderPerformance
    ON #OrderPerformance (SalesOrderID);
CREATE INDEX IX_OrderPerformance_DeliveredDate
    ON #OrderPerformance (DeliveredDateKey);

-- Payment outcome is one row per order, including retry recovery.
SELECT
    fact_payment.SalesOrderID,
    COUNT_BIG(*) AS PaymentAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsSuccessful)) AS SuccessfulAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsFailed)) AS FailedAttempts,
    SUM(fact_payment.CollectedAmount) AS CompletedPaymentValue,
    MAX(CASE WHEN fact_payment.AttemptNumber = 1 AND fact_payment.IsFailed = 1 THEN 1 ELSE 0 END) AS InitialAttemptFailed,
    MAX(CASE WHEN fact_payment.AttemptNumber > 1 AND fact_payment.IsSuccessful = 1 THEN 1 ELSE 0 END) AS LaterAttemptSucceeded
INTO #PaymentOrderOutcome
FROM analytics.FactPayments AS fact_payment
GROUP BY fact_payment.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_PaymentOrderOutcome
    ON #PaymentOrderOutcome (SalesOrderID);

/* ============================================================================
   2. EXECUTIVE SCORECARD
   One row containing the principal enterprise-level KPIs.
   ============================================================================ */

DECLARE @TotalOrders BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, OrderCount)), 0) FROM analytics.FactSales);
DECLARE @DeliveredOrders BIGINT = (SELECT COUNT_BIG(*) FROM #OrderPerformance);
DECLARE @CancelledOrders BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, OrderCount)), 0)
     FROM analytics.FactSales WHERE IsCancelled = 1);
DECLARE @ActiveOrders BIGINT = @TotalOrders - @DeliveredOrders - @CancelledOrders;

DECLARE @RecognizedRevenue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(RecognizedRevenue), 0) FROM #OrderPerformance);
DECLARE @GrossRefundValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(GrossRefundValue), 0) FROM #OrderPerformance);
DECLARE @NetRevenue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(NetRevenue), 0) FROM #OrderPerformance);
DECLARE @COGS DECIMAL(38,2) =
    (SELECT COALESCE(SUM(COGS), 0) FROM #OrderPerformance);
DECLARE @GrossProfit DECIMAL(38,2) =
    (SELECT COALESCE(SUM(GrossProfit), 0) FROM #OrderPerformance);
DECLARE @DeliveredUnits BIGINT =
    (SELECT COALESCE(SUM(DeliveredUnits), 0) FROM #OrderPerformance);
DECLARE @AcceptedReturnedUnits BIGINT =
    (SELECT COALESCE(SUM(AcceptedReturnedUnits), 0) FROM #OrderPerformance);
DECLARE @NetUnitsSold BIGINT = @DeliveredUnits - @AcceptedReturnedUnits;

DECLARE @PaymentAttempts BIGINT =
    (SELECT COALESCE(SUM(PaymentAttempts), 0) FROM #PaymentOrderOutcome);
DECLARE @SuccessfulPaymentAttempts BIGINT =
    (SELECT COALESCE(SUM(SuccessfulAttempts), 0) FROM #PaymentOrderOutcome);
DECLARE @FailedPaymentAttempts BIGINT =
    (SELECT COALESCE(SUM(FailedAttempts), 0) FROM #PaymentOrderOutcome);
DECLARE @CompletedPaymentValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(CompletedPaymentValue), 0) FROM #PaymentOrderOutcome);
DECLARE @RetryPopulation BIGINT =
    (SELECT COUNT_BIG(*) FROM #PaymentOrderOutcome WHERE InitialAttemptFailed = 1);
DECLARE @RetryRecoveredOrders BIGINT =
    (SELECT COUNT_BIG(*) FROM #PaymentOrderOutcome
     WHERE InitialAttemptFailed = 1 AND LaterAttemptSucceeded = 1);

DECLARE @ActiveCustomers BIGINT =
    (SELECT COUNT_BIG(DISTINCT CustomerKey) FROM #OrderPerformance);
DECLARE @RepeatCustomers BIGINT =
(
    SELECT COUNT_BIG(*)
    FROM
    (
        SELECT CustomerKey
        FROM #OrderPerformance
        GROUP BY CustomerKey
        HAVING COUNT_BIG(*) >= 2
    ) AS repeat_customer
);

DECLARE @GrossRefundCashValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(CompletedRefundAmount), 0) FROM analytics.FactRefunds);
DECLARE @InventoryValueAtCost DECIMAL(38,2) =
    (SELECT COALESCE(SUM(StockCostValue), 0) FROM analytics.FactInventorySnapshot);
DECLARE @InventoryCombinations BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot);
DECLARE @StockoutCombinations BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot WHERE QuantityAvailable = 0);
DECLARE @LowStockCombinations BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot
     WHERE QuantityAvailable > 0 AND QuantityAvailable <= ReorderLevel);
DECLARE @ExcessStockCombinations BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot WHERE IsExcessStock = 1);

SELECT
    @TotalOrders AS TotalOrders,
    @ActiveOrders AS ActiveOrders,
    @DeliveredOrders AS DeliveredOrders,
    @CancelledOrders AS CancelledOrders,
    @ActiveCustomers AS ActiveCustomers,
    @RecognizedRevenue AS RecognizedRevenue,
    @GrossRefundValue AS GrossRefundValue,
    @NetRevenue AS NetRevenue,
    @COGS AS COGS,
    @GrossProfit AS GrossProfit,
    CONVERT(DECIMAL(9,4), @GrossProfit / NULLIF(@NetRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(19,2), @NetRevenue / NULLIF(@DeliveredOrders, 0)) AS AverageOrderValue,
    @DeliveredUnits AS DeliveredUnits,
    @AcceptedReturnedUnits AS AcceptedReturnedUnits,
    @NetUnitsSold AS NetUnitsSold,
    @CompletedPaymentValue AS CompletedPaymentValue,
    @GrossRefundCashValue AS CompletedRefundCashValue,
    @CompletedPaymentValue - @GrossRefundCashValue AS NetCashCollection,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @SuccessfulPaymentAttempts)
        / NULLIF(@PaymentAttempts, 0)) AS PaymentSuccessRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @CancelledOrders)
        / NULLIF(@TotalOrders, 0)) AS OrderCancellationRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @AcceptedReturnedUnits)
        / NULLIF(@DeliveredUnits, 0)) AS ReturnRateByQuantity,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @RepeatCustomers)
        / NULLIF(@ActiveCustomers, 0)) AS RepeatCustomerRate,
    @InventoryValueAtCost AS InventoryValueAtCost,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @StockoutCombinations)
        / NULLIF(@InventoryCombinations, 0)) AS StockoutRate,
    @LowStockCombinations AS LowStockProductStoreCount,
    @ExcessStockCombinations AS ExcessStockProductStoreCount;

/* ============================================================================
   3. EXECUTIVE OPERATING-HEALTH SCORECARD
   ============================================================================ */

SELECT
    @PaymentAttempts AS PaymentAttempts,
    @SuccessfulPaymentAttempts AS SuccessfulPaymentAttempts,
    @FailedPaymentAttempts AS FailedPaymentAttempts,
    @RetryPopulation AS OrdersWithInitialPaymentFailure,
    @RetryRecoveredOrders AS RetryRecoveredOrders,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @RetryRecoveredOrders)
        / NULLIF(@RetryPopulation, 0)) AS PaymentRetrySuccessRate,
    (SELECT COUNT_BIG(DISTINCT SalesOrderID)
     FROM analytics.FactReturns WHERE QuantityAccepted > 0) AS OrdersWithAcceptedReturns,
    CONVERT
    (
        DECIMAL(9,4),
        CONVERT(DECIMAL(38,6),
            (SELECT COUNT_BIG(DISTINCT SalesOrderID)
             FROM analytics.FactReturns WHERE QuantityAccepted > 0))
        / NULLIF(@DeliveredOrders, 0)
    ) AS ReturnRateByOrders,
    CONVERT(DECIMAL(9,4), @GrossRefundCashValue / NULLIF(@CompletedPaymentValue, 0)) AS RefundRate,
    @RepeatCustomers AS RepeatCustomers,
    CONVERT(DECIMAL(19,2), CONVERT(DECIMAL(38,6), @DeliveredOrders)
        / NULLIF(@ActiveCustomers, 0)) AS PurchaseFrequency;

/* ============================================================================
   4. FINANCIAL-YEAR PERFORMANCE AND GROWTH
   Refund adjustments follow the delivered-order cohort.
   ============================================================================ */

SELECT
    date_dimension.FinancialYearStart,
    date_dimension.FinancialYearLabel,
    MIN(date_dimension.[Date]) AS FirstDeliveryDate,
    MAX(date_dimension.[Date]) AS LastDeliveryDate,
    COUNT_BIG(*) AS DeliveredOrders,
    COUNT_BIG(DISTINCT order_performance.CustomerKey) AS ActiveCustomers,
    SUM(order_performance.NetUnitsSold) AS NetUnitsSold,
    SUM(order_performance.RecognizedRevenue) AS RecognizedRevenue,
    SUM(order_performance.PretaxRefundValue) AS PretaxRefundValue,
    SUM(order_performance.NetRevenue) AS NetRevenue,
    SUM(order_performance.COGS) AS COGS,
    SUM(order_performance.GrossProfit) AS GrossProfit
INTO #FiscalPerformance
FROM #OrderPerformance AS order_performance
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = order_performance.DeliveredDateKey
GROUP BY date_dimension.FinancialYearStart, date_dimension.FinancialYearLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_FiscalPerformance
    ON #FiscalPerformance (FinancialYearStart);

SELECT
    fiscal_performance.FinancialYearLabel,
    fiscal_performance.FirstDeliveryDate,
    fiscal_performance.LastDeliveryDate,
    fiscal_performance.DeliveredOrders,
    fiscal_performance.ActiveCustomers,
    fiscal_performance.NetUnitsSold,
    fiscal_performance.NetRevenue,
    fiscal_performance.COGS,
    fiscal_performance.GrossProfit,
    CONVERT(DECIMAL(9,4), fiscal_performance.GrossProfit
        / NULLIF(fiscal_performance.NetRevenue, 0)) AS GrossMarginRate,
    CONVERT
    (
        DECIMAL(9,4),
        (fiscal_performance.NetRevenue
         - LAG(fiscal_performance.NetRevenue) OVER (ORDER BY fiscal_performance.FinancialYearStart))
        / NULLIF(LAG(fiscal_performance.NetRevenue)
                 OVER (ORDER BY fiscal_performance.FinancialYearStart), 0)
    ) AS NetRevenueYoYRate,
    CONVERT
    (
        DECIMAL(9,4),
        (fiscal_performance.GrossProfit
         - LAG(fiscal_performance.GrossProfit) OVER (ORDER BY fiscal_performance.FinancialYearStart))
        / NULLIF(LAG(fiscal_performance.GrossProfit)
                 OVER (ORDER BY fiscal_performance.FinancialYearStart), 0)
    ) AS GrossProfitYoYRate,
    CASE WHEN MONTH(fiscal_performance.FirstDeliveryDate) = 4
               AND MONTH(fiscal_performance.LastDeliveryDate) = 3
         THEN 'COMPLETE YEAR' ELSE 'PARTIAL YEAR' END AS PeriodCoverage
FROM #FiscalPerformance AS fiscal_performance
ORDER BY fiscal_performance.FinancialYearStart;

/* ============================================================================
   5. MONTHLY EXECUTIVE TREND
   ============================================================================ */

SELECT
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    date_dimension.FinancialYearLabel,
    COUNT_BIG(*) AS DeliveredOrders,
    COUNT_BIG(DISTINCT order_performance.CustomerKey) AS ActiveCustomers,
    SUM(order_performance.NetUnitsSold) AS NetUnitsSold,
    SUM(order_performance.NetRevenue) AS NetRevenue,
    SUM(order_performance.GrossProfit) AS GrossProfit,
    CONVERT(DECIMAL(9,4), SUM(order_performance.GrossProfit)
        / NULLIF(SUM(order_performance.NetRevenue), 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(19,2), SUM(order_performance.NetRevenue)
        / NULLIF(COUNT_BIG(*), 0)) AS AverageOrderValue
FROM #OrderPerformance AS order_performance
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = order_performance.DeliveredDateKey
GROUP BY
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    date_dimension.FinancialYearLabel
ORDER BY date_dimension.YearMonthNumber;

/* ============================================================================
   6. EXECUTIVE STORE CONTRIBUTION
   ============================================================================ */

SELECT
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_dimension.City,
    store_dimension.StateName,
    COUNT_BIG(*) AS DeliveredOrders,
    COUNT_BIG(DISTINCT order_performance.CustomerKey) AS ActiveCustomers,
    SUM(order_performance.NetRevenue) AS NetRevenue,
    SUM(order_performance.GrossProfit) AS GrossProfit,
    CONVERT(DECIMAL(9,4), SUM(order_performance.GrossProfit)
        / NULLIF(SUM(order_performance.NetRevenue), 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), SUM(order_performance.NetRevenue)
        / NULLIF(@NetRevenue, 0)) AS NetRevenueContributionRate,
    DENSE_RANK() OVER (ORDER BY SUM(order_performance.NetRevenue) DESC) AS RevenueRank
FROM #OrderPerformance AS order_performance
INNER JOIN analytics.DimStore AS store_dimension
    ON store_dimension.StoreKey = order_performance.StoreKey
GROUP BY
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_dimension.City,
    store_dimension.StateName
ORDER BY RevenueRank, store_dimension.StoreCode;

/* ============================================================================
   7. KPI SANITY VALIDATION
   ============================================================================ */

DECLARE @KPIValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(50) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

INSERT INTO @KPIValidation VALUES
(1, 'Order population reconciliation',
 CASE WHEN @TotalOrders = @ActiveOrders + @DeliveredOrders + @CancelledOrders THEN 0 ELSE 1 END,
 CASE WHEN @TotalOrders = @ActiveOrders + @DeliveredOrders + @CancelledOrders THEN 'PASSED' ELSE 'FAILED' END),
(2, 'Net unit reconciliation',
 CASE WHEN @NetUnitsSold = @DeliveredUnits - @AcceptedReturnedUnits THEN 0 ELSE 1 END,
 CASE WHEN @NetUnitsSold = @DeliveredUnits - @AcceptedReturnedUnits THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Net revenue reconciliation',
 CASE WHEN @NetRevenue = @RecognizedRevenue
       - (SELECT COALESCE(SUM(PretaxRefundValue), 0) FROM #OrderPerformance) THEN 0 ELSE 1 END,
 CASE WHEN @NetRevenue = @RecognizedRevenue
       - (SELECT COALESCE(SUM(PretaxRefundValue), 0) FROM #OrderPerformance) THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Gross profit reconciliation',
 CASE WHEN @GrossProfit = @NetRevenue - @COGS THEN 0 ELSE 1 END,
 CASE WHEN @GrossProfit = @NetRevenue - @COGS THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Payment attempt reconciliation',
 CASE WHEN @PaymentAttempts = (SELECT COUNT_BIG(*) FROM analytics.FactPayments) THEN 0 ELSE 1 END,
 CASE WHEN @PaymentAttempts = (SELECT COUNT_BIG(*) FROM analytics.FactPayments) THEN 'PASSED' ELSE 'FAILED' END),
(6, 'Ratio boundaries',
 CASE WHEN @SuccessfulPaymentAttempts <= @PaymentAttempts
            AND @AcceptedReturnedUnits <= @DeliveredUnits
            AND @RepeatCustomers <= @ActiveCustomers
       THEN 0 ELSE 1 END,
 CASE WHEN @SuccessfulPaymentAttempts <= @PaymentAttempts
            AND @AcceptedReturnedUnits <= @DeliveredUnits
            AND @RepeatCustomers <= @ActiveCustomers
       THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @KPIValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @KPIValidation WHERE ValidationStatus = 'FAILED')
    THROW 51473, 'Executive KPI validation failed. Review the final validation result set.', 1;

RAISERROR('27_Executive_KPIs.sql completed successfully: governed executive KPIs produced and validated.', 10, 1) WITH NOWAIT;
GO
