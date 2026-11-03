/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      32_Store_Employee_Analysis.sql
Purpose:     Analyze store and order-processing employee performance.
Author:      Akshay Aswani
Version:     2.0
Depends on:  31_Inventory_Analysis.sql
Rerunnable:  Yes. Read-only analysis using session-scoped temporary tables.

Interpretation policy
---------------------
- Store attribution uses the fulfilling store on the sales order.
- Employee attribution uses the order-processing employee.
- Employee rankings show operational attribution, not sole causation of sales.
- Demand and cancellations use order date; realized performance uses delivery date.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51520, 'Store and employee analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimStore', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimEmployee', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
    THROW 51521, 'Store and employee analysis stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51522, 'Store and employee analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #OrderDemand;
DROP TABLE IF EXISTS #DeliveredLine;
DROP TABLE IF EXISTS #OrderAdjustment;
DROP TABLE IF EXISTS #DeliveredOrder;
DROP TABLE IF EXISTS #StorePerformance;
DROP TABLE IF EXISTS #EmployeePerformance;

/* ============================================================================
   1. ORDER-DEMAND GRAIN
   ============================================================================ */

SELECT
    fact_sales.SalesOrderID,
    MAX(fact_sales.OrderNumber) AS OrderNumber,
    MAX(fact_sales.OrderDateKey) AS OrderDateKey,
    MAX(fact_sales.StoreKey) AS StoreKey,
    MAX(fact_sales.EmployeeKey) AS EmployeeKey,
    MAX(fact_sales.CustomerKey) AS CustomerKey,
    MAX(CONVERT(TINYINT, fact_sales.IsDelivered)) AS IsDelivered,
    MAX(CONVERT(TINYINT, fact_sales.IsCancelled)) AS IsCancelled,
    SUM(CONVERT(BIGINT, fact_sales.Quantity)) AS OrderedUnits,
    SUM(CASE WHEN fact_sales.IsCancelled = 0
             THEN CONVERT(DECIMAL(19,2), fact_sales.NetAmount) ELSE 0 END) AS BookedOrderValue
INTO #OrderDemand
FROM analytics.FactSales AS fact_sales
GROUP BY fact_sales.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_StoreOrderDemand ON #OrderDemand (SalesOrderID);
CREATE INDEX IX_StoreOrderDemand_StoreEmployee ON #OrderDemand (StoreKey, EmployeeKey);

/* ============================================================================
   2. DELIVERED LINES AND ORDER-LEVEL RETURN ADJUSTMENTS
   ============================================================================ */

SELECT
    fact_sales.SalesOrderItemID,
    fact_sales.SalesOrderID,
    fact_sales.DeliveredDateKey,
    fact_sales.StoreKey,
    fact_sales.EmployeeKey,
    fact_sales.CustomerKey,
    fact_sales.Quantity AS DeliveredUnits,
    fact_sales.UnitCost,
    CONVERT(DECIMAL(19,2), fact_sales.GrossAmount - fact_sales.DiscountAmount) AS RecognizedRevenue,
    CONVERT(DECIMAL(19,2), fact_sales.Quantity * fact_sales.UnitCost) AS RecognizedCost
INTO #DeliveredLine
FROM analytics.FactSales AS fact_sales
WHERE fact_sales.IsDelivered = 1;

CREATE UNIQUE CLUSTERED INDEX CIX_StoreDeliveredLine ON #DeliveredLine (SalesOrderItemID);
CREATE INDEX IX_StoreDeliveredLine_Order ON #DeliveredLine (SalesOrderID);

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
INTO #OrderAdjustment
FROM ReturnRefund AS return_refund
GROUP BY return_refund.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_StoreOrderAdjustment ON #OrderAdjustment (SalesOrderID);

;WITH DeliveredOrderBase AS
(
    SELECT
        delivered_line.SalesOrderID,
        MAX(delivered_line.DeliveredDateKey) AS DeliveredDateKey,
        MAX(delivered_line.StoreKey) AS StoreKey,
        MAX(delivered_line.EmployeeKey) AS EmployeeKey,
        MAX(delivered_line.CustomerKey) AS CustomerKey,
        SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
        SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
        SUM(delivered_line.RecognizedCost) AS RecognizedCost
    FROM #DeliveredLine AS delivered_line
    GROUP BY delivered_line.SalesOrderID
)
SELECT
    delivered_order.SalesOrderID,
    delivered_order.DeliveredDateKey,
    delivered_order.StoreKey,
    delivered_order.EmployeeKey,
    delivered_order.CustomerKey,
    delivered_order.DeliveredUnits,
    delivered_order.DeliveredUnits - COALESCE(order_adjustment.AcceptedReturnedUnits, 0) AS NetUnitsSold,
    delivered_order.RecognizedRevenue - COALESCE(order_adjustment.PretaxRefundValue, 0) AS NetRevenue,
    delivered_order.RecognizedCost - COALESCE(order_adjustment.ReusableReturnCost, 0) AS COGS,
    delivered_order.RecognizedRevenue
        - COALESCE(order_adjustment.PretaxRefundValue, 0)
        - delivered_order.RecognizedCost
        + COALESCE(order_adjustment.ReusableReturnCost, 0) AS GrossProfit
INTO #DeliveredOrder
FROM DeliveredOrderBase AS delivered_order
LEFT JOIN #OrderAdjustment AS order_adjustment
    ON order_adjustment.SalesOrderID = delivered_order.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_StoreDeliveredOrder ON #DeliveredOrder (SalesOrderID);
CREATE INDEX IX_StoreDeliveredOrder_StoreEmployee ON #DeliveredOrder (StoreKey, EmployeeKey);

/* ============================================================================
   3. STORE PERFORMANCE MART
   ============================================================================ */

;WITH StoreDemand AS
(
    SELECT
        order_demand.StoreKey,
        COUNT_BIG(*) AS TotalOrders,
        SUM(CASE WHEN order_demand.IsCancelled = 1 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS CancelledOrders,
        SUM(order_demand.OrderedUnits) AS OrderedUnits,
        SUM(order_demand.BookedOrderValue) AS BookedOrderValue
    FROM #OrderDemand AS order_demand
    GROUP BY order_demand.StoreKey
),
StoreSales AS
(
    SELECT
        delivered_order.StoreKey,
        COUNT_BIG(*) AS DeliveredOrders,
        COUNT_BIG(DISTINCT delivered_order.CustomerKey) AS ActiveCustomers,
        SUM(delivered_order.NetUnitsSold) AS NetUnitsSold,
        SUM(delivered_order.NetRevenue) AS NetRevenue,
        SUM(delivered_order.COGS) AS COGS,
        SUM(delivered_order.GrossProfit) AS GrossProfit
    FROM #DeliveredOrder AS delivered_order
    GROUP BY delivered_order.StoreKey
),
StoreWorkforce AS
(
    SELECT
        employee_dimension.StoreID,
        COUNT_BIG(*) AS EmployeeCount,
        SUM(CASE WHEN employee_dimension.IsActive = 1 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS ActiveEmployeeCount
    FROM analytics.DimEmployee AS employee_dimension
    WHERE employee_dimension.IsUnknown = 0
    GROUP BY employee_dimension.StoreID
)
SELECT
    store_dimension.StoreKey,
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_dimension.City,
    store_dimension.StateName,
    store_dimension.ManagerEmployeeCode,
    store_dimension.ManagerName,
    COALESCE(store_workforce.EmployeeCount, 0) AS EmployeeCount,
    COALESCE(store_workforce.ActiveEmployeeCount, 0) AS ActiveEmployeeCount,
    COALESCE(store_demand.TotalOrders, 0) AS TotalOrders,
    COALESCE(store_demand.CancelledOrders, 0) AS CancelledOrders,
    COALESCE(store_sales.DeliveredOrders, 0) AS DeliveredOrders,
    COALESCE(store_sales.ActiveCustomers, 0) AS ActiveCustomers,
    COALESCE(store_sales.NetUnitsSold, 0) AS NetUnitsSold,
    COALESCE(store_demand.BookedOrderValue, 0) AS BookedOrderValue,
    COALESCE(store_sales.NetRevenue, 0) AS NetRevenue,
    COALESCE(store_sales.COGS, 0) AS COGS,
    COALESCE(store_sales.GrossProfit, 0) AS GrossProfit
INTO #StorePerformance
FROM analytics.DimStore AS store_dimension
LEFT JOIN StoreDemand AS store_demand
    ON store_demand.StoreKey = store_dimension.StoreKey
LEFT JOIN StoreSales AS store_sales
    ON store_sales.StoreKey = store_dimension.StoreKey
LEFT JOIN StoreWorkforce AS store_workforce
    ON store_workforce.StoreID = store_dimension.StoreID
WHERE store_dimension.IsUnknown = 0;

CREATE UNIQUE CLUSTERED INDEX CIX_StorePerformance ON #StorePerformance (StoreKey);

DECLARE @TotalNetRevenue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(NetRevenue), 0) FROM #StorePerformance);
DECLARE @TotalDeliveredOrders BIGINT =
    (SELECT COALESCE(SUM(DeliveredOrders), 0) FROM #StorePerformance);

/* ============================================================================
   4. STORE SCORECARD AND RANKING
   ============================================================================ */

SELECT
    store_performance.StoreCode,
    store_performance.StoreName,
    store_performance.StoreTier,
    store_performance.City,
    store_performance.StateName,
    store_performance.ManagerName,
    store_performance.ActiveEmployeeCount,
    store_performance.TotalOrders,
    store_performance.DeliveredOrders,
    store_performance.CancelledOrders,
    store_performance.ActiveCustomers,
    store_performance.NetUnitsSold,
    store_performance.NetRevenue AS StoreNetRevenue,
    store_performance.GrossProfit,
    CONVERT(DECIMAL(9,4), store_performance.GrossProfit
        / NULLIF(store_performance.NetRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(19,2), store_performance.NetRevenue
        / NULLIF(store_performance.DeliveredOrders, 0)) AS AverageOrderValue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), store_performance.CancelledOrders)
        / NULLIF(store_performance.TotalOrders, 0)) AS CancellationRate,
    CONVERT(DECIMAL(19,2), store_performance.NetRevenue
        / NULLIF(store_performance.ActiveEmployeeCount, 0)) AS RevenuePerEmployee,
    CONVERT(DECIMAL(19,2), CONVERT(DECIMAL(38,6), store_performance.DeliveredOrders)
        / NULLIF(store_performance.ActiveEmployeeCount, 0)) AS OrdersPerEmployee,
    CONVERT(DECIMAL(9,4), store_performance.NetRevenue
        / NULLIF(@TotalNetRevenue, 0)) AS RevenueContributionRate,
    DENSE_RANK() OVER (ORDER BY store_performance.NetRevenue DESC) AS RevenueRank,
    DENSE_RANK() OVER (ORDER BY store_performance.GrossProfit DESC) AS ProfitRank
FROM #StorePerformance AS store_performance
ORDER BY RevenueRank, store_performance.StoreCode;

/* ============================================================================
   5. STORE TIER AND STATE BENCHMARKS
   ============================================================================ */

SELECT
    store_performance.StoreTier,
    store_performance.StateName,
    COUNT_BIG(*) AS StoreCount,
    SUM(store_performance.ActiveEmployeeCount) AS ActiveEmployees,
    SUM(store_performance.TotalOrders) AS TotalOrders,
    SUM(store_performance.DeliveredOrders) AS DeliveredOrders,
    SUM(store_performance.CancelledOrders) AS CancelledOrders,
    SUM(store_performance.NetRevenue) AS NetRevenue,
    SUM(store_performance.GrossProfit) AS GrossProfit,
    CONVERT(DECIMAL(19,2), SUM(store_performance.NetRevenue)
        / NULLIF(COUNT_BIG(*), 0)) AS RevenuePerStore,
    CONVERT(DECIMAL(19,2), SUM(store_performance.NetRevenue)
        / NULLIF(SUM(store_performance.ActiveEmployeeCount), 0)) AS RevenuePerEmployee,
    CONVERT(DECIMAL(9,4), SUM(store_performance.GrossProfit)
        / NULLIF(SUM(store_performance.NetRevenue), 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), SUM(store_performance.CancelledOrders))
        / NULLIF(SUM(store_performance.TotalOrders), 0)) AS CancellationRate
FROM #StorePerformance AS store_performance
GROUP BY store_performance.StoreTier, store_performance.StateName
ORDER BY NetRevenue DESC;

/* ============================================================================
   6. EMPLOYEE PERFORMANCE MART AND RANKING
   ============================================================================ */

;WITH EmployeeDemand AS
(
    SELECT
        order_demand.EmployeeKey,
        COUNT_BIG(*) AS TotalOrders,
        SUM(CASE WHEN order_demand.IsCancelled = 1 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS CancelledOrders
    FROM #OrderDemand AS order_demand
    GROUP BY order_demand.EmployeeKey
),
EmployeeSales AS
(
    SELECT
        delivered_order.EmployeeKey,
        COUNT_BIG(*) AS DeliveredOrders,
        COUNT_BIG(DISTINCT delivered_order.CustomerKey) AS ActiveCustomers,
        SUM(delivered_order.NetUnitsSold) AS NetUnitsSold,
        SUM(delivered_order.NetRevenue) AS NetRevenue,
        SUM(delivered_order.GrossProfit) AS GrossProfit
    FROM #DeliveredOrder AS delivered_order
    GROUP BY delivered_order.EmployeeKey
)
SELECT
    employee_dimension.EmployeeKey,
    employee_dimension.EmployeeCode,
    employee_dimension.EmployeeName,
    employee_dimension.JobTitle,
    employee_dimension.StoreCode,
    employee_dimension.StoreName,
    employee_dimension.ManagerName,
    employee_dimension.HireDate,
    employee_dimension.IsActive,
    COALESCE(employee_demand.TotalOrders, 0) AS TotalOrders,
    COALESCE(employee_demand.CancelledOrders, 0) AS CancelledOrders,
    COALESCE(employee_sales.DeliveredOrders, 0) AS DeliveredOrders,
    COALESCE(employee_sales.ActiveCustomers, 0) AS ActiveCustomers,
    COALESCE(employee_sales.NetUnitsSold, 0) AS NetUnitsSold,
    COALESCE(employee_sales.NetRevenue, 0) AS NetRevenue,
    COALESCE(employee_sales.GrossProfit, 0) AS GrossProfit
INTO #EmployeePerformance
FROM analytics.DimEmployee AS employee_dimension
LEFT JOIN EmployeeDemand AS employee_demand
    ON employee_demand.EmployeeKey = employee_dimension.EmployeeKey
LEFT JOIN EmployeeSales AS employee_sales
    ON employee_sales.EmployeeKey = employee_dimension.EmployeeKey
WHERE employee_dimension.IsUnknown = 0;

CREATE UNIQUE CLUSTERED INDEX CIX_EmployeePerformance
    ON #EmployeePerformance (EmployeeKey);

SELECT
    employee_performance.EmployeeCode,
    employee_performance.EmployeeName,
    employee_performance.JobTitle,
    employee_performance.StoreName,
    employee_performance.ManagerName,
    employee_performance.IsActive,
    employee_performance.TotalOrders,
    employee_performance.DeliveredOrders,
    employee_performance.CancelledOrders,
    employee_performance.ActiveCustomers,
    employee_performance.NetUnitsSold,
    employee_performance.NetRevenue AS AttributedNetRevenue,
    employee_performance.GrossProfit AS AttributedGrossProfit,
    CONVERT(DECIMAL(19,2), employee_performance.NetRevenue
        / NULLIF(employee_performance.DeliveredOrders, 0)) AS AverageOrderValue,
    CONVERT(DECIMAL(9,4), employee_performance.GrossProfit
        / NULLIF(employee_performance.NetRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), employee_performance.CancelledOrders)
        / NULLIF(employee_performance.TotalOrders, 0)) AS CancellationRate,
    DENSE_RANK() OVER
        (PARTITION BY employee_performance.StoreName ORDER BY employee_performance.NetRevenue DESC) AS StoreRevenueRank,
    DENSE_RANK() OVER (ORDER BY employee_performance.NetRevenue DESC) AS EnterpriseRevenueRank
FROM #EmployeePerformance AS employee_performance
ORDER BY EnterpriseRevenueRank, employee_performance.EmployeeCode;

/* ============================================================================
   7. JOB-TITLE WORKFORCE NORMALIZATION
   ============================================================================ */

SELECT
    employee_performance.JobTitle,
    COUNT_BIG(*) AS EmployeeCount,
    SUM(CASE WHEN employee_performance.IsActive = 1 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS ActiveEmployeeCount,
    SUM(employee_performance.DeliveredOrders) AS DeliveredOrders,
    SUM(employee_performance.NetRevenue) AS AttributedNetRevenue,
    SUM(employee_performance.GrossProfit) AS AttributedGrossProfit,
    CONVERT(DECIMAL(19,2), SUM(employee_performance.NetRevenue)
        / NULLIF(SUM(CASE WHEN employee_performance.IsActive = 1 THEN 1 ELSE 0 END), 0)) AS RevenuePerActiveEmployee,
    CONVERT(DECIMAL(19,2), CONVERT(DECIMAL(38,6), SUM(employee_performance.DeliveredOrders))
        / NULLIF(SUM(CASE WHEN employee_performance.IsActive = 1 THEN 1 ELSE 0 END), 0)) AS OrdersPerActiveEmployee
FROM #EmployeePerformance AS employee_performance
GROUP BY employee_performance.JobTitle
ORDER BY AttributedNetRevenue DESC;

/* ============================================================================
   8. MONTHLY STORE LEADERBOARD
   ============================================================================ */

;WITH MonthlyStore AS
(
    SELECT
        date_dimension.YearMonthNumber,
        date_dimension.MonthYearLabel,
        store_dimension.StoreCode,
        store_dimension.StoreName,
        COUNT_BIG(*) AS DeliveredOrders,
        SUM(delivered_order.NetRevenue) AS NetRevenue,
        SUM(delivered_order.GrossProfit) AS GrossProfit
    FROM #DeliveredOrder AS delivered_order
    INNER JOIN analytics.DimDate AS date_dimension
        ON date_dimension.DateKey = delivered_order.DeliveredDateKey
    INNER JOIN analytics.DimStore AS store_dimension
        ON store_dimension.StoreKey = delivered_order.StoreKey
    GROUP BY
        date_dimension.YearMonthNumber,
        date_dimension.MonthYearLabel,
        store_dimension.StoreCode,
        store_dimension.StoreName
)
SELECT
    monthly_store.YearMonthNumber,
    monthly_store.MonthYearLabel,
    monthly_store.StoreCode,
    monthly_store.StoreName,
    monthly_store.DeliveredOrders,
    monthly_store.NetRevenue,
    monthly_store.GrossProfit,
    DENSE_RANK() OVER
        (PARTITION BY monthly_store.YearMonthNumber ORDER BY monthly_store.NetRevenue DESC) AS MonthlyRevenueRank
FROM MonthlyStore AS monthly_store
ORDER BY monthly_store.YearMonthNumber, MonthlyRevenueRank, monthly_store.StoreCode;

/* ============================================================================
   9. FULFILLMENT SPEED BY STORE
   ============================================================================ */

SELECT
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    COUNT_BIG(*) AS DeliveredOrders,
    CONVERT(DECIMAL(19,2), AVG(CONVERT(DECIMAL(19,2),
        DATEDIFF(MINUTE, source_order.OrderDate, source_order.DeliveredDate))) / 1440.0) AS AverageDeliveryDays,
    CONVERT(DECIMAL(19,2), AVG(CONVERT(DECIMAL(19,2),
        DATEDIFF(MINUTE, source_order.OrderDate, source_order.ConfirmedDate))) / 60.0) AS AverageConfirmationHours,
    MIN(source_order.DeliveredDate) AS FirstDeliveryDate,
    MAX(source_order.DeliveredDate) AS LatestDeliveryDate
FROM sales.SalesOrder AS source_order
INNER JOIN ref.OrderStatus AS source_status
    ON source_status.OrderStatusID = source_order.OrderStatusID
INNER JOIN analytics.DimStore AS store_dimension
    ON store_dimension.StoreID = source_order.StoreID
WHERE source_status.OrderStatusCode IN ('DELIVERED', 'PARTIALLY_RETURNED', 'RETURNED')
GROUP BY store_dimension.StoreCode, store_dimension.StoreName, store_dimension.StoreTier
ORDER BY AverageDeliveryDays, store_dimension.StoreCode;

/* ============================================================================
   10. STORE ACTION MATRIX
   ============================================================================ */

;WITH StoreBenchmarks AS
(
    SELECT
        AVG(CONVERT(DECIMAL(38,6), NetRevenue)) AS AverageStoreRevenue,
        AVG(CONVERT(DECIMAL(38,6), GrossProfit / NULLIF(NetRevenue, 0))) AS AverageStoreMargin,
        AVG(CONVERT(DECIMAL(38,6), CONVERT(DECIMAL(38,6), CancelledOrders)
            / NULLIF(TotalOrders, 0))) AS AverageCancellationRate
    FROM #StorePerformance
)
SELECT
    store_performance.StoreCode,
    store_performance.StoreName,
    store_performance.StoreTier,
    store_performance.NetRevenue,
    store_performance.GrossProfit,
    CONVERT(DECIMAL(9,4), store_performance.GrossProfit
        / NULLIF(store_performance.NetRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), store_performance.CancelledOrders)
        / NULLIF(store_performance.TotalOrders, 0)) AS CancellationRate,
    CASE
        WHEN store_performance.NetRevenue >= store_benchmark.AverageStoreRevenue
             AND store_performance.GrossProfit / NULLIF(store_performance.NetRevenue, 0)
                 >= store_benchmark.AverageStoreMargin THEN 'LEADER: PROTECT AND SCALE'
        WHEN store_performance.NetRevenue >= store_benchmark.AverageStoreRevenue THEN 'HIGH REVENUE: IMPROVE MARGIN'
        WHEN CONVERT(DECIMAL(38,6), store_performance.CancelledOrders)
             / NULLIF(store_performance.TotalOrders, 0) > store_benchmark.AverageCancellationRate
             THEN 'REDUCE CANCELLATIONS'
        ELSE 'GROW DEMAND AND PRODUCTIVITY'
    END AS StoreAction
FROM #StorePerformance AS store_performance
CROSS JOIN StoreBenchmarks AS store_benchmark
ORDER BY store_performance.NetRevenue DESC;

/* ============================================================================
   11. STORE AND EMPLOYEE VALIDATION
   ============================================================================ */

DECLARE @StoreEmployeeValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(100) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

DECLARE @SourceStoreCount BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.DimStore WHERE IsUnknown = 0);
DECLARE @SourceEmployeeCount BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.DimEmployee WHERE IsUnknown = 0);
DECLARE @DeliveredFactOrders BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, OrderCount)), 0)
     FROM analytics.FactSales WHERE IsDelivered = 1);

INSERT INTO @StoreEmployeeValidation VALUES
(1, 'One performance row per store',
 ABS(@SourceStoreCount - (SELECT COUNT_BIG(*) FROM #StorePerformance)),
 CASE WHEN @SourceStoreCount = (SELECT COUNT_BIG(*) FROM #StorePerformance)
      THEN 'PASSED' ELSE 'FAILED' END),
(2, 'One performance row per employee',
 ABS(@SourceEmployeeCount - (SELECT COUNT_BIG(*) FROM #EmployeePerformance)),
 CASE WHEN @SourceEmployeeCount = (SELECT COUNT_BIG(*) FROM #EmployeePerformance)
      THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Delivered orders reconcile to fact',
 ABS(@DeliveredFactOrders - @TotalDeliveredOrders),
 CASE WHEN @DeliveredFactOrders = @TotalDeliveredOrders THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Employee delivered orders reconcile to store totals',
 ABS(@TotalDeliveredOrders
     - (SELECT COALESCE(SUM(DeliveredOrders), 0) FROM #EmployeePerformance)),
 CASE WHEN @TotalDeliveredOrders =
      (SELECT COALESCE(SUM(DeliveredOrders), 0) FROM #EmployeePerformance)
      THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Employee revenue reconciles to store revenue',
 CASE WHEN @TotalNetRevenue =
      (SELECT COALESCE(SUM(NetRevenue), 0) FROM #EmployeePerformance)
      THEN 0 ELSE 1 END,
 CASE WHEN @TotalNetRevenue =
      (SELECT COALESCE(SUM(NetRevenue), 0) FROM #EmployeePerformance)
      THEN 'PASSED' ELSE 'FAILED' END),
(6, 'Store order populations are valid',
 (SELECT COUNT_BIG(*) FROM #StorePerformance
  WHERE DeliveredOrders + CancelledOrders > TotalOrders),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #StorePerformance
       WHERE DeliveredOrders + CancelledOrders > TotalOrders)
      THEN 'PASSED' ELSE 'FAILED' END),
(7, 'Store gross profit reconciles to revenue less COGS',
 (SELECT COUNT_BIG(*) FROM #StorePerformance
  WHERE GrossProfit <> NetRevenue - COGS),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #StorePerformance WHERE GrossProfit <> NetRevenue - COGS)
      THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @StoreEmployeeValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @StoreEmployeeValidation WHERE ValidationStatus = 'FAILED')
    THROW 51523, 'Store and employee analysis validation failed. Review the final validation result set.', 1;

RAISERROR('32_Store_Employee_Analysis.sql completed successfully: store and employee performance analyses validated.', 10, 1) WITH NOWAIT;
GO
