/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      35_Advanced_Business_Analysis.sql
Purpose:     Demonstrate advanced SQL for strategic business investigation.
Author:      Akshay Aswani
Version:     2.0
Depends on:  34_Supplier_Analysis.sql
Rerunnable:  Yes. Read-only analysis using session-scoped temporary tables.

Advanced techniques
-------------------
- Market-basket association rules: support, confidence and lift
- Pareto / cumulative contribution analysis
- Rolling averages and statistical anomaly flags
- Window-based financial-year growth decomposition
- Store-category opportunity-gap analysis
- Product performance quadrants
- Rolling run-rate indicators (not predictive ML forecasts)
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51550, 'Advanced business analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactPayments', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimProduct', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimCustomer', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimStore', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
    THROW 51551, 'Advanced business analysis stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51552, 'Advanced business analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #DeliveredLine;
DROP TABLE IF EXISTS #DeliveredOrder;
DROP TABLE IF EXISTS #ProductPerformance;
DROP TABLE IF EXISTS #MonthlyPerformance;
DROP TABLE IF EXISTS #BasketProduct;
DROP TABLE IF EXISTS #ProductPair;
DROP TABLE IF EXISTS #StoreFinancialYear;

/* ============================================================================
   1. CONTROLLED DELIVERED-SALES BASE
   Revenue below is pretax recognized revenue before completed-refund adjustment.
   ============================================================================ */

SELECT
    fact_sales.SalesOrderItemID,
    fact_sales.SalesOrderID,
    fact_sales.DeliveredDateKey,
    fact_sales.CustomerKey,
    fact_sales.ProductKey,
    fact_sales.StoreKey,
    fact_sales.Quantity AS DeliveredUnits,
    CONVERT(DECIMAL(19,2), fact_sales.GrossAmount - fact_sales.DiscountAmount) AS RecognizedRevenue,
    CONVERT(DECIMAL(19,2), fact_sales.Quantity * fact_sales.UnitCost) AS RecognizedCost,
    CONVERT(DECIMAL(19,2),
        fact_sales.GrossAmount - fact_sales.DiscountAmount
        - fact_sales.Quantity * fact_sales.UnitCost) AS GrossProfitBeforeReturns
INTO #DeliveredLine
FROM analytics.FactSales AS fact_sales
WHERE fact_sales.IsDelivered = 1;

CREATE UNIQUE CLUSTERED INDEX CIX_AdvancedDeliveredLine
    ON #DeliveredLine (SalesOrderItemID);
CREATE INDEX IX_AdvancedDeliveredLine_OrderProduct
    ON #DeliveredLine (SalesOrderID, ProductKey);
CREATE INDEX IX_AdvancedDeliveredLine_DateStore
    ON #DeliveredLine (DeliveredDateKey, StoreKey);

SELECT
    delivered_line.SalesOrderID,
    MAX(delivered_line.DeliveredDateKey) AS DeliveredDateKey,
    MAX(delivered_line.CustomerKey) AS CustomerKey,
    MAX(delivered_line.StoreKey) AS StoreKey,
    COUNT_BIG(*) AS BasketLineCount,
    COUNT_BIG(DISTINCT delivered_line.ProductKey) AS DistinctProductCount,
    SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
    SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
    SUM(delivered_line.GrossProfitBeforeReturns) AS GrossProfitBeforeReturns
INTO #DeliveredOrder
FROM #DeliveredLine AS delivered_line
GROUP BY delivered_line.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_AdvancedDeliveredOrder
    ON #DeliveredOrder (SalesOrderID);

DECLARE @DeliveredOrders BIGINT = (SELECT COUNT_BIG(*) FROM #DeliveredOrder);
DECLARE @TotalRecognizedRevenue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(RecognizedRevenue), 0) FROM #DeliveredOrder);

/* ============================================================================
   2. MARKET-BASKET PRODUCT ASSOCIATION RULES
   ============================================================================ */

SELECT DISTINCT
    delivered_line.SalesOrderID,
    delivered_line.ProductKey
INTO #BasketProduct
FROM #DeliveredLine AS delivered_line;

CREATE UNIQUE CLUSTERED INDEX CIX_BasketProduct
    ON #BasketProduct (SalesOrderID, ProductKey);
CREATE INDEX IX_BasketProduct_Product
    ON #BasketProduct (ProductKey, SalesOrderID);

SELECT
    basket_a.ProductKey AS ProductAKey,
    basket_b.ProductKey AS ProductBKey,
    COUNT_BIG(*) AS PairOrderCount
INTO #ProductPair
FROM #BasketProduct AS basket_a
INNER JOIN #BasketProduct AS basket_b
    ON basket_b.SalesOrderID = basket_a.SalesOrderID
   AND basket_b.ProductKey > basket_a.ProductKey
GROUP BY basket_a.ProductKey, basket_b.ProductKey;

CREATE UNIQUE CLUSTERED INDEX CIX_ProductPair
    ON #ProductPair (ProductAKey, ProductBKey);

;WITH ProductOrderCount AS
(
    SELECT ProductKey, COUNT_BIG(*) AS ProductOrderCount
    FROM #BasketProduct
    GROUP BY ProductKey
)
SELECT TOP (50)
    product_a.SKU AS ProductASKU,
    product_a.ProductName AS ProductAName,
    product_b.SKU AS ProductBSKU,
    product_b.ProductName AS ProductBName,
    product_pair.PairOrderCount,
    product_a_count.ProductOrderCount AS ProductAOrders,
    product_b_count.ProductOrderCount AS ProductBOrders,
    CONVERT(DECIMAL(9,6), CONVERT(DECIMAL(38,10), product_pair.PairOrderCount)
        / NULLIF(@DeliveredOrders, 0)) AS SupportRate,
    CONVERT(DECIMAL(9,6), CONVERT(DECIMAL(38,10), product_pair.PairOrderCount)
        / NULLIF(product_a_count.ProductOrderCount, 0)) AS ConfidenceAToB,
    CONVERT(DECIMAL(9,6), CONVERT(DECIMAL(38,10), product_pair.PairOrderCount)
        / NULLIF(product_b_count.ProductOrderCount, 0)) AS ConfidenceBToA,
    CONVERT
    (
        DECIMAL(19,6),
        (CONVERT(DECIMAL(38,10), product_pair.PairOrderCount) / NULLIF(@DeliveredOrders, 0))
        / NULLIF
          (
              (CONVERT(DECIMAL(38,10), product_a_count.ProductOrderCount) / NULLIF(@DeliveredOrders, 0))
              * (CONVERT(DECIMAL(38,10), product_b_count.ProductOrderCount) / NULLIF(@DeliveredOrders, 0)),
              0
          )
    ) AS Lift
FROM #ProductPair AS product_pair
INNER JOIN ProductOrderCount AS product_a_count
    ON product_a_count.ProductKey = product_pair.ProductAKey
INNER JOIN ProductOrderCount AS product_b_count
    ON product_b_count.ProductKey = product_pair.ProductBKey
INNER JOIN analytics.DimProduct AS product_a
    ON product_a.ProductKey = product_pair.ProductAKey
INNER JOIN analytics.DimProduct AS product_b
    ON product_b.ProductKey = product_pair.ProductBKey
WHERE product_pair.PairOrderCount >= 20
ORDER BY Lift DESC, product_pair.PairOrderCount DESC;

/* ============================================================================
   3. CATEGORY MARKET-BASKET ASSOCIATION
   ============================================================================ */

;WITH BasketCategory AS
(
    SELECT DISTINCT
        basket_product.SalesOrderID,
        product_dimension.CategoryName
    FROM #BasketProduct AS basket_product
    INNER JOIN analytics.DimProduct AS product_dimension
        ON product_dimension.ProductKey = basket_product.ProductKey
),
CategoryOrderCount AS
(
    SELECT CategoryName, COUNT_BIG(*) AS CategoryOrders
    FROM BasketCategory
    GROUP BY CategoryName
),
CategoryPair AS
(
    SELECT
        category_a.CategoryName AS CategoryA,
        category_b.CategoryName AS CategoryB,
        COUNT_BIG(*) AS PairOrders
    FROM BasketCategory AS category_a
    INNER JOIN BasketCategory AS category_b
        ON category_b.SalesOrderID = category_a.SalesOrderID
       AND category_b.CategoryName > category_a.CategoryName
    GROUP BY category_a.CategoryName, category_b.CategoryName
)
SELECT
    category_pair.CategoryA,
    category_pair.CategoryB,
    category_pair.PairOrders,
    CONVERT(DECIMAL(9,6), CONVERT(DECIMAL(38,10), category_pair.PairOrders)
        / NULLIF(@DeliveredOrders, 0)) AS SupportRate,
    CONVERT(DECIMAL(9,6), CONVERT(DECIMAL(38,10), category_pair.PairOrders)
        / NULLIF(category_a_count.CategoryOrders, 0)) AS ConfidenceAToB,
    CONVERT
    (
        DECIMAL(19,6),
        (CONVERT(DECIMAL(38,10), category_pair.PairOrders) / NULLIF(@DeliveredOrders, 0))
        / NULLIF
          (
              (CONVERT(DECIMAL(38,10), category_a_count.CategoryOrders) / NULLIF(@DeliveredOrders, 0))
              * (CONVERT(DECIMAL(38,10), category_b_count.CategoryOrders) / NULLIF(@DeliveredOrders, 0)),
              0
          )
    ) AS Lift
FROM CategoryPair AS category_pair
INNER JOIN CategoryOrderCount AS category_a_count
    ON category_a_count.CategoryName = category_pair.CategoryA
INNER JOIN CategoryOrderCount AS category_b_count
    ON category_b_count.CategoryName = category_pair.CategoryB
ORDER BY Lift DESC, category_pair.PairOrders DESC;

/* ============================================================================
   4. CUSTOMER REVENUE PARETO ANALYSIS
   ============================================================================ */

;WITH CustomerValue AS
(
    SELECT
        delivered_order.CustomerKey,
        COUNT_BIG(*) AS DeliveredOrders,
        SUM(delivered_order.RecognizedRevenue) AS RecognizedRevenue
    FROM #DeliveredOrder AS delivered_order
    GROUP BY delivered_order.CustomerKey
),
CustomerRunning AS
(
    SELECT
        customer_value.*,
        ROW_NUMBER() OVER
            (ORDER BY customer_value.RecognizedRevenue DESC, customer_value.CustomerKey) AS CustomerRank,
        COUNT_BIG(*) OVER () AS ActiveCustomerCount,
        SUM(customer_value.RecognizedRevenue) OVER
        (
            ORDER BY customer_value.RecognizedRevenue DESC, customer_value.CustomerKey
            ROWS UNBOUNDED PRECEDING
        ) AS CumulativeRevenue
    FROM CustomerValue AS customer_value
)
SELECT
    customer_dimension.CustomerCode,
    customer_dimension.CustomerName,
    customer_dimension.CustomerSegment,
    customer_running.CustomerRank,
    customer_running.ActiveCustomerCount,
    customer_running.DeliveredOrders,
    customer_running.RecognizedRevenue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), customer_running.CustomerRank)
        / NULLIF(customer_running.ActiveCustomerCount, 0)) AS CumulativeCustomerRate,
    CONVERT(DECIMAL(9,4), customer_running.CumulativeRevenue
        / NULLIF(@TotalRecognizedRevenue, 0)) AS CumulativeRevenueRate,
    CASE WHEN customer_running.CumulativeRevenue / NULLIF(@TotalRecognizedRevenue, 0) <= 0.80
         THEN 'TOP REVENUE COHORT' ELSE 'REMAINING COHORT' END AS ParetoClass
FROM CustomerRunning AS customer_running
INNER JOIN analytics.DimCustomer AS customer_dimension
    ON customer_dimension.CustomerKey = customer_running.CustomerKey
ORDER BY customer_running.CustomerRank;

/* ============================================================================
   5. PRODUCT PARETO AND PERFORMANCE QUADRANTS
   ============================================================================ */

;WITH SalesByProduct AS
(
    SELECT
        delivered_line.ProductKey,
        COUNT_BIG(DISTINCT delivered_line.SalesOrderID) AS DeliveredOrders,
        SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
        SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
        SUM(delivered_line.GrossProfitBeforeReturns) AS GrossProfitBeforeReturns
    FROM #DeliveredLine AS delivered_line
    GROUP BY delivered_line.ProductKey
),
ReturnsByProduct AS
(
    SELECT
        fact_return.ProductKey,
        SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnedUnits
    FROM analytics.FactReturns AS fact_return
    GROUP BY fact_return.ProductKey
)
SELECT
    product_dimension.ProductKey,
    product_dimension.SKU,
    product_dimension.ProductName,
    product_dimension.CategoryName,
    COALESCE(product_sales.DeliveredOrders, 0) AS DeliveredOrders,
    COALESCE(product_sales.DeliveredUnits, 0) AS DeliveredUnits,
    COALESCE(product_return.AcceptedReturnedUnits, 0) AS AcceptedReturnedUnits,
    COALESCE(product_sales.RecognizedRevenue, 0) AS RecognizedRevenue,
    COALESCE(product_sales.GrossProfitBeforeReturns, 0) AS GrossProfitBeforeReturns
INTO #ProductPerformance
FROM analytics.DimProduct AS product_dimension
LEFT JOIN SalesByProduct AS product_sales
    ON product_sales.ProductKey = product_dimension.ProductKey
LEFT JOIN ReturnsByProduct AS product_return
    ON product_return.ProductKey = product_dimension.ProductKey
WHERE product_dimension.IsUnknown = 0;

CREATE UNIQUE CLUSTERED INDEX CIX_AdvancedProductPerformance
    ON #ProductPerformance (ProductKey);

;WITH ProductBenchmark AS
(
    SELECT
        AVG(CONVERT(DECIMAL(38,6), RecognizedRevenue)) AS AverageRevenue,
        AVG(CONVERT(DECIMAL(38,6), GrossProfitBeforeReturns
            / NULLIF(RecognizedRevenue, 0))) AS AverageMargin,
        AVG(CONVERT(DECIMAL(38,6), CONVERT(DECIMAL(38,6), AcceptedReturnedUnits)
            / NULLIF(DeliveredUnits, 0))) AS AverageReturnRate
    FROM #ProductPerformance
    WHERE DeliveredUnits > 0
)
SELECT
    product_performance.SKU,
    product_performance.ProductName,
    product_performance.CategoryName,
    product_performance.DeliveredUnits,
    product_performance.RecognizedRevenue,
    product_performance.GrossProfitBeforeReturns,
    CONVERT(DECIMAL(9,4), product_performance.GrossProfitBeforeReturns
        / NULLIF(product_performance.RecognizedRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), product_performance.AcceptedReturnedUnits)
        / NULLIF(product_performance.DeliveredUnits, 0)) AS ProductReturnRate,
    CASE
        WHEN product_performance.RecognizedRevenue >= product_benchmark.AverageRevenue
             AND product_performance.GrossProfitBeforeReturns
                 / NULLIF(product_performance.RecognizedRevenue, 0) >= product_benchmark.AverageMargin
             THEN 'STAR: HIGH REVENUE / HIGH MARGIN'
        WHEN product_performance.RecognizedRevenue >= product_benchmark.AverageRevenue
             THEN 'VOLUME DRIVER: IMPROVE MARGIN'
        WHEN product_performance.GrossProfitBeforeReturns
             / NULLIF(product_performance.RecognizedRevenue, 0) >= product_benchmark.AverageMargin
             THEN 'NICHE PROFIT: GROW DEMAND'
        WHEN product_performance.DeliveredUnits = 0 THEN 'NO SALES: REVIEW ASSORTMENT'
        ELSE 'LOW VALUE: RATIONALIZE'
    END AS PerformanceQuadrant,
    CASE WHEN CONVERT(DECIMAL(38,6), product_performance.AcceptedReturnedUnits)
                   / NULLIF(product_performance.DeliveredUnits, 0) > product_benchmark.AverageReturnRate
         THEN 'ABOVE-AVERAGE RETURN RISK' ELSE 'NORMAL RETURN RISK' END AS ReturnRiskFlag
FROM #ProductPerformance AS product_performance
CROSS JOIN ProductBenchmark AS product_benchmark
ORDER BY product_performance.RecognizedRevenue DESC;

/* ============================================================================
   6. MONTHLY ROLLING TREND AND ANOMALY DETECTION
   An anomaly is outside two prior-six-month standard deviations.
   ============================================================================ */

SELECT
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    COUNT_BIG(DISTINCT delivered_line.SalesOrderID) AS DeliveredOrders,
    SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
    SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
    SUM(delivered_line.GrossProfitBeforeReturns) AS GrossProfitBeforeReturns
INTO #MonthlyPerformance
FROM #DeliveredLine AS delivered_line
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = delivered_line.DeliveredDateKey
GROUP BY date_dimension.YearMonthNumber, date_dimension.MonthYearLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_AdvancedMonthlyPerformance
    ON #MonthlyPerformance (YearMonthNumber);

;WITH RollingControl AS
(
    SELECT
        monthly_performance.*,
        AVG(CONVERT(DECIMAL(38,6), monthly_performance.RecognizedRevenue)) OVER
        (
            ORDER BY monthly_performance.YearMonthNumber
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS PriorSixMonthAverage,
        STDEV(CONVERT(FLOAT, monthly_performance.RecognizedRevenue)) OVER
        (
            ORDER BY monthly_performance.YearMonthNumber
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS PriorSixMonthStdDev,
        AVG(CONVERT(DECIMAL(38,6), monthly_performance.RecognizedRevenue)) OVER
        (
            ORDER BY monthly_performance.YearMonthNumber
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS ThreeMonthRevenueRunRate
    FROM #MonthlyPerformance AS monthly_performance
)
SELECT
    rolling_control.YearMonthNumber,
    rolling_control.MonthYearLabel,
    rolling_control.DeliveredOrders,
    rolling_control.DeliveredUnits,
    rolling_control.RecognizedRevenue,
    rolling_control.GrossProfitBeforeReturns,
    rolling_control.ThreeMonthRevenueRunRate,
    rolling_control.PriorSixMonthAverage,
    rolling_control.PriorSixMonthStdDev,
    CONVERT(DECIMAL(19,4),
        (rolling_control.RecognizedRevenue - rolling_control.PriorSixMonthAverage)
        / NULLIF(rolling_control.PriorSixMonthStdDev, 0)) AS RevenueZScore,
    CASE
        WHEN rolling_control.PriorSixMonthStdDev IS NULL THEN 'INSUFFICIENT HISTORY'
        WHEN rolling_control.RecognizedRevenue
             > rolling_control.PriorSixMonthAverage + 2 * rolling_control.PriorSixMonthStdDev THEN 'HIGH ANOMALY'
        WHEN rolling_control.RecognizedRevenue
             < rolling_control.PriorSixMonthAverage - 2 * rolling_control.PriorSixMonthStdDev THEN 'LOW ANOMALY'
        ELSE 'NORMAL'
    END AS AnomalyFlag
FROM RollingControl AS rolling_control
ORDER BY rolling_control.YearMonthNumber;

/* ============================================================================
   7. STORE FINANCIAL-YEAR GROWTH DECOMPOSITION
   ============================================================================ */

SELECT
    delivered_line.StoreKey,
    date_dimension.FinancialYearStart,
    date_dimension.FinancialYearLabel,
    COUNT_BIG(DISTINCT delivered_line.SalesOrderID) AS DeliveredOrders,
    SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
    SUM(delivered_line.GrossProfitBeforeReturns) AS GrossProfitBeforeReturns
INTO #StoreFinancialYear
FROM #DeliveredLine AS delivered_line
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = delivered_line.DeliveredDateKey
GROUP BY
    delivered_line.StoreKey,
    date_dimension.FinancialYearStart,
    date_dimension.FinancialYearLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_StoreFinancialYear
    ON #StoreFinancialYear (StoreKey, FinancialYearStart);

;WITH StoreGrowth AS
(
    SELECT
        store_year.*,
        LAG(store_year.RecognizedRevenue) OVER
            (PARTITION BY store_year.StoreKey ORDER BY store_year.FinancialYearStart) AS PriorYearRevenue,
        LAG(store_year.GrossProfitBeforeReturns) OVER
            (PARTITION BY store_year.StoreKey ORDER BY store_year.FinancialYearStart) AS PriorYearProfit
    FROM #StoreFinancialYear AS store_year
)
SELECT
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_growth.FinancialYearLabel,
    store_growth.DeliveredOrders,
    store_growth.RecognizedRevenue,
    store_growth.RecognizedRevenue - store_growth.PriorYearRevenue AS RevenueGrowthValue,
    CONVERT(DECIMAL(9,4),
        (store_growth.RecognizedRevenue - store_growth.PriorYearRevenue)
        / NULLIF(store_growth.PriorYearRevenue, 0)) AS RevenueGrowthRate,
    store_growth.GrossProfitBeforeReturns - store_growth.PriorYearProfit AS ProfitGrowthValue,
    CONVERT(DECIMAL(9,4),
        (store_growth.GrossProfitBeforeReturns - store_growth.PriorYearProfit)
        / NULLIF(store_growth.PriorYearProfit, 0)) AS ProfitGrowthRate,
    CONVERT(DECIMAL(9,4),
        (store_growth.RecognizedRevenue - store_growth.PriorYearRevenue)
        / NULLIF
          (
              SUM(store_growth.RecognizedRevenue - store_growth.PriorYearRevenue) OVER
                  (PARTITION BY store_growth.FinancialYearStart),
              0
          )) AS EnterpriseGrowthContributionRate
FROM StoreGrowth AS store_growth
INNER JOIN analytics.DimStore AS store_dimension
    ON store_dimension.StoreKey = store_growth.StoreKey
ORDER BY store_growth.FinancialYearStart, RevenueGrowthValue DESC;

/* ============================================================================
   8. STORE-CATEGORY OPPORTUNITY GAP
   Compares category revenue per store against the category's store average.
   ============================================================================ */

;WITH StoreCategory AS
(
    SELECT
        delivered_line.StoreKey,
        product_dimension.CategoryName,
        SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
        SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits
    FROM #DeliveredLine AS delivered_line
    INNER JOIN analytics.DimProduct AS product_dimension
        ON product_dimension.ProductKey = delivered_line.ProductKey
    GROUP BY delivered_line.StoreKey, product_dimension.CategoryName
),
StoreCategoryBenchmark AS
(
    SELECT
        store_category.*,
        AVG(CONVERT(DECIMAL(38,6), store_category.RecognizedRevenue)) OVER
            (PARTITION BY store_category.CategoryName) AS CategoryAverageStoreRevenue
    FROM StoreCategory AS store_category
)
SELECT
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_category.CategoryName,
    store_category.DeliveredUnits,
    store_category.RecognizedRevenue,
    store_category.CategoryAverageStoreRevenue,
    store_category.CategoryAverageStoreRevenue - store_category.RecognizedRevenue AS RevenueOpportunityGap,
    CONVERT(DECIMAL(9,4), store_category.RecognizedRevenue
        / NULLIF(store_category.CategoryAverageStoreRevenue, 0)) AS PerformanceToCategoryAverageRate,
    CASE
        WHEN store_category.RecognizedRevenue < store_category.CategoryAverageStoreRevenue * 0.75
            THEN 'HIGH OPPORTUNITY GAP'
        WHEN store_category.RecognizedRevenue < store_category.CategoryAverageStoreRevenue
            THEN 'MODERATE OPPORTUNITY GAP'
        ELSE 'AT/ABOVE CATEGORY AVERAGE'
    END AS OpportunityFlag
FROM StoreCategoryBenchmark AS store_category
INNER JOIN analytics.DimStore AS store_dimension
    ON store_dimension.StoreKey = store_category.StoreKey
ORDER BY RevenueOpportunityGap DESC;

/* ============================================================================
   9. INVENTORY-REVENUE MISALIGNMENT
   ============================================================================ */

;WITH ProductInventory AS
(
    SELECT ProductKey, SUM(StockCostValue) AS InventoryExposure
    FROM analytics.FactInventorySnapshot
    GROUP BY ProductKey
),
PortfolioControl AS
(
    SELECT
        SUM(product_performance.RecognizedRevenue) AS PortfolioRevenue,
        SUM(product_inventory.InventoryExposure) AS PortfolioInventory
    FROM #ProductPerformance AS product_performance
    INNER JOIN ProductInventory AS product_inventory
        ON product_inventory.ProductKey = product_performance.ProductKey
)
SELECT
    product_performance.SKU,
    product_performance.ProductName,
    product_performance.CategoryName,
    product_performance.RecognizedRevenue,
    product_inventory.InventoryExposure,
    CONVERT(DECIMAL(9,4), product_performance.RecognizedRevenue
        / NULLIF(portfolio_control.PortfolioRevenue, 0)) AS RevenueShareRate,
    CONVERT(DECIMAL(9,4), product_inventory.InventoryExposure
        / NULLIF(portfolio_control.PortfolioInventory, 0)) AS InventoryShareRate,
    CONVERT(DECIMAL(9,4),
        product_inventory.InventoryExposure / NULLIF(portfolio_control.PortfolioInventory, 0)
        - product_performance.RecognizedRevenue / NULLIF(portfolio_control.PortfolioRevenue, 0)) AS ExposureMinusRevenueShare,
    CASE
        WHEN product_inventory.InventoryExposure / NULLIF(portfolio_control.PortfolioInventory, 0)
             > product_performance.RecognizedRevenue / NULLIF(portfolio_control.PortfolioRevenue, 0) * 1.50
            THEN 'OVER-EXPOSED INVENTORY'
        WHEN product_performance.RecognizedRevenue / NULLIF(portfolio_control.PortfolioRevenue, 0)
             > product_inventory.InventoryExposure / NULLIF(portfolio_control.PortfolioInventory, 0) * 1.50
            THEN 'POTENTIAL UNDER-STOCK RISK'
        ELSE 'BALANCED'
    END AS AlignmentFlag
FROM #ProductPerformance AS product_performance
INNER JOIN ProductInventory AS product_inventory
    ON product_inventory.ProductKey = product_performance.ProductKey
CROSS JOIN PortfolioControl AS portfolio_control
ORDER BY ExposureMinusRevenueShare DESC;

/* ============================================================================
   10. ADVANCED ANALYSIS VALIDATION
   ============================================================================ */

DECLARE @AdvancedValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(110) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

DECLARE @FactDeliveredOrders BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, OrderCount)), 0)
     FROM analytics.FactSales WHERE IsDelivered = 1);
DECLARE @FactDeliveredLines BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactSales WHERE IsDelivered = 1);

INSERT INTO @AdvancedValidation VALUES
(1, 'Delivered order grain reconciliation',
 ABS(@FactDeliveredOrders - @DeliveredOrders),
 CASE WHEN @FactDeliveredOrders = @DeliveredOrders THEN 'PASSED' ELSE 'FAILED' END),
(2, 'Delivered line grain reconciliation',
 ABS(@FactDeliveredLines - (SELECT COUNT_BIG(*) FROM #DeliveredLine)),
 CASE WHEN @FactDeliveredLines = (SELECT COUNT_BIG(*) FROM #DeliveredLine)
      THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Basket contains unique order-product combinations',
 (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(SalesOrderID, '|', ProductKey))
  FROM #BasketProduct),
 CASE WHEN (SELECT COUNT_BIG(*) FROM #BasketProduct)
              = (SELECT COUNT_BIG(DISTINCT CONCAT(SalesOrderID, '|', ProductKey)) FROM #BasketProduct)
      THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Product pairs are ordered and unique',
 (SELECT COUNT_BIG(*) FROM #ProductPair WHERE ProductAKey >= ProductBKey),
 CASE WHEN NOT EXISTS (SELECT 1 FROM #ProductPair WHERE ProductAKey >= ProductBKey)
      THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Monthly revenue reconciles to delivered revenue',
 CASE WHEN @TotalRecognizedRevenue =
      (SELECT COALESCE(SUM(RecognizedRevenue), 0) FROM #MonthlyPerformance)
      THEN 0 ELSE 1 END,
 CASE WHEN @TotalRecognizedRevenue =
      (SELECT COALESCE(SUM(RecognizedRevenue), 0) FROM #MonthlyPerformance)
      THEN 'PASSED' ELSE 'FAILED' END),
(6, 'Product performance covers all known products',
 ABS((SELECT COUNT_BIG(*) FROM analytics.DimProduct WHERE IsUnknown = 0)
     - (SELECT COUNT_BIG(*) FROM #ProductPerformance)),
 CASE WHEN (SELECT COUNT_BIG(*) FROM analytics.DimProduct WHERE IsUnknown = 0)
              = (SELECT COUNT_BIG(*) FROM #ProductPerformance)
      THEN 'PASSED' ELSE 'FAILED' END),
(7, 'Association-rule rates are bounded by valid order populations',
 (SELECT COUNT_BIG(*) FROM #ProductPair
  WHERE PairOrderCount <= 0 OR PairOrderCount > @DeliveredOrders),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #ProductPair
       WHERE PairOrderCount <= 0 OR PairOrderCount > @DeliveredOrders)
      THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @AdvancedValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @AdvancedValidation WHERE ValidationStatus = 'FAILED')
    THROW 51553, 'Advanced business analysis validation failed. Review the final validation result set.', 1;

RAISERROR('35_Advanced_Business_Analysis.sql completed successfully: strategic advanced-SQL analyses validated.', 10, 1) WITH NOWAIT;
GO
