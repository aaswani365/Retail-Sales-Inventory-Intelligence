/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      30_Product_Analysis.sql
Purpose:     Analyze product sales, profitability, returns and portfolio value.
Author:      Akshay Aswani
Version:     2.0
Depends on:  29_Customer_Analysis.sql
Rerunnable:  Yes. Read-only analysis using session-scoped temporary tables.

Metric policy
-------------
- Delivered product lines use delivered date.
- Revenue excludes pass-through tax.
- Completed refunds are allocated to return items by eligible refund share.
- Reusable accepted returns reverse transaction-time product cost.
- Product return rate uses accepted returned units / delivered units.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51500, 'Product analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimProduct', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
    THROW 51501, 'Product analysis stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51502, 'Product analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #DeliveredProductLine;
DROP TABLE IF EXISTS #ReturnItemAdjustment;
DROP TABLE IF EXISTS #ProductPerformance;
DROP TABLE IF EXISTS #ProductYear;
DROP TABLE IF EXISTS #ProductABC;

/* ============================================================================
   1. DELIVERED PRODUCT LINES
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
    fact_sales.UnitPrice,
    CONVERT(DECIMAL(19,2), fact_sales.GrossAmount - fact_sales.DiscountAmount) AS RecognizedRevenue,
    CONVERT(DECIMAL(19,2), fact_sales.Quantity * fact_sales.UnitCost) AS RecognizedCost
INTO #DeliveredProductLine
FROM analytics.FactSales AS fact_sales
WHERE fact_sales.IsDelivered = 1;

CREATE UNIQUE CLUSTERED INDEX CIX_DeliveredProductLine
    ON #DeliveredProductLine (SalesOrderItemID);
CREATE INDEX IX_DeliveredProductLine_ProductDate
    ON #DeliveredProductLine (ProductKey, DeliveredDateKey);

/* ============================================================================
   2. ITEM-LEVEL RETURN AND COMPLETED-REFUND ALLOCATION
   ============================================================================ */

;WITH ReturnItemBase AS
(
    SELECT
        fact_return.ProductReturnItemID,
        fact_return.ProductReturnID,
        fact_return.SalesOrderItemID,
        fact_return.ProductKey,
        fact_return.ReturnReasonKey,
        fact_return.QuantityRequested,
        fact_return.QuantityAccepted,
        fact_return.IsReusable,
        delivered_line.UnitCost,
        CONVERT(DECIMAL(19,2), fact_return.EligibleRefundAmount) AS EligibleRefundValue,
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
        ) AS EligiblePretaxRefundValue
    FROM analytics.FactReturns AS fact_return
    INNER JOIN #DeliveredProductLine AS delivered_line
        ON delivered_line.SalesOrderItemID = fact_return.SalesOrderItemID
    INNER JOIN sales.SalesOrderItem AS source_item
        ON source_item.SalesOrderItemID = fact_return.SalesOrderItemID
),
ReturnHeaderControl AS
(
    SELECT
        return_item.ProductReturnID,
        SUM(return_item.EligibleRefundValue) AS HeaderEligibleRefundValue,
        MAX(fact_refund.CompletedRefundAmount) AS HeaderCompletedRefundValue
    FROM ReturnItemBase AS return_item
    LEFT JOIN
    (
        SELECT ProductReturnID, SUM(CompletedRefundAmount) AS CompletedRefundAmount
        FROM analytics.FactRefunds
        GROUP BY ProductReturnID
    ) AS fact_refund
        ON fact_refund.ProductReturnID = return_item.ProductReturnID
    GROUP BY return_item.ProductReturnID
)
SELECT
    return_item.ProductReturnItemID,
    return_item.ProductReturnID,
    return_item.SalesOrderItemID,
    return_item.ProductKey,
    return_item.ReturnReasonKey,
    return_item.QuantityRequested,
    return_item.QuantityAccepted,
    return_item.IsReusable,
    CASE WHEN return_item.IsReusable = 1
         THEN CONVERT(DECIMAL(19,2), return_item.QuantityAccepted * return_item.UnitCost)
         ELSE CONVERT(DECIMAL(19,2), 0) END AS ReusableReturnCost,
    CONVERT
    (
        DECIMAL(19,2),
        COALESCE(return_control.HeaderCompletedRefundValue, 0)
        * COALESCE
          (
              NULLIF(return_item.EligiblePretaxRefundValue, 0)
              / NULLIF(return_control.HeaderEligibleRefundValue, 0),
              0
          )
    ) AS CompletedPretaxRefundValue
INTO #ReturnItemAdjustment
FROM ReturnItemBase AS return_item
INNER JOIN ReturnHeaderControl AS return_control
    ON return_control.ProductReturnID = return_item.ProductReturnID;

CREATE UNIQUE CLUSTERED INDEX CIX_ReturnItemAdjustment
    ON #ReturnItemAdjustment (ProductReturnItemID);
CREATE INDEX IX_ReturnItemAdjustment_Product
    ON #ReturnItemAdjustment (ProductKey);

/* ============================================================================
   3. PRODUCT PERFORMANCE MART — ONE ROW PER PRODUCT
   ============================================================================ */

;WITH SalesByProduct AS
(
    SELECT
        delivered_line.ProductKey,
        COUNT_BIG(*) AS DeliveredLineCount,
        COUNT_BIG(DISTINCT delivered_line.SalesOrderID) AS DeliveredOrders,
        COUNT_BIG(DISTINCT delivered_line.CustomerKey) AS ActiveCustomers,
        COUNT_BIG(DISTINCT delivered_line.StoreKey) AS SellingStores,
        SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
        SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
        SUM(delivered_line.RecognizedCost) AS RecognizedCost,
        SUM(CONVERT(DECIMAL(38,6), delivered_line.DeliveredUnits * delivered_line.UnitPrice))
            / NULLIF(SUM(delivered_line.DeliveredUnits), 0) AS WeightedAverageSellingPrice
    FROM #DeliveredProductLine AS delivered_line
    GROUP BY delivered_line.ProductKey
),
ReturnsByProduct AS
(
    SELECT
        return_adjustment.ProductKey,
        COUNT_BIG(*) AS ReturnedLineCount,
        SUM(CONVERT(BIGINT, return_adjustment.QuantityRequested)) AS RequestedReturnUnits,
        SUM(CONVERT(BIGINT, return_adjustment.QuantityAccepted)) AS AcceptedReturnedUnits,
        SUM(CASE WHEN return_adjustment.IsReusable = 1
                 THEN CONVERT(BIGINT, return_adjustment.QuantityAccepted) ELSE 0 END) AS ReusableReturnedUnits,
        SUM(return_adjustment.ReusableReturnCost) AS ReusableReturnCost,
        SUM(return_adjustment.CompletedPretaxRefundValue) AS PretaxRefundValue
    FROM #ReturnItemAdjustment AS return_adjustment
    GROUP BY return_adjustment.ProductKey
)
SELECT
    product_dimension.ProductKey,
    product_dimension.SKU,
    product_dimension.ProductName,
    product_dimension.BrandName,
    product_dimension.SubCategoryName,
    product_dimension.CategoryName,
    product_dimension.SupplierName,
    product_dimension.PriceBand,
    product_dimension.CostPrice AS CurrentCostPrice,
    product_dimension.SellingPrice AS CurrentSellingPrice,
    COALESCE(product_sales.DeliveredLineCount, 0) AS DeliveredLineCount,
    COALESCE(product_sales.DeliveredOrders, 0) AS DeliveredOrders,
    COALESCE(product_sales.ActiveCustomers, 0) AS ActiveCustomers,
    COALESCE(product_sales.SellingStores, 0) AS SellingStores,
    COALESCE(product_sales.DeliveredUnits, 0) AS DeliveredUnits,
    COALESCE(product_return.RequestedReturnUnits, 0) AS RequestedReturnUnits,
    COALESCE(product_return.AcceptedReturnedUnits, 0) AS AcceptedReturnedUnits,
    COALESCE(product_return.ReusableReturnedUnits, 0) AS ReusableReturnedUnits,
    COALESCE(product_sales.DeliveredUnits, 0) - COALESCE(product_return.AcceptedReturnedUnits, 0) AS NetUnitsSold,
    COALESCE(product_sales.RecognizedRevenue, 0) AS RecognizedRevenue,
    COALESCE(product_return.PretaxRefundValue, 0) AS PretaxRefundValue,
    COALESCE(product_sales.RecognizedRevenue, 0) - COALESCE(product_return.PretaxRefundValue, 0) AS NetRevenue,
    COALESCE(product_sales.RecognizedCost, 0) - COALESCE(product_return.ReusableReturnCost, 0) AS COGS,
    COALESCE(product_sales.RecognizedRevenue, 0)
        - COALESCE(product_return.PretaxRefundValue, 0)
        - COALESCE(product_sales.RecognizedCost, 0)
        + COALESCE(product_return.ReusableReturnCost, 0) AS GrossProfit,
    COALESCE(product_sales.WeightedAverageSellingPrice, 0) AS WeightedAverageSellingPrice
INTO #ProductPerformance
FROM analytics.DimProduct AS product_dimension
LEFT JOIN SalesByProduct AS product_sales
    ON product_sales.ProductKey = product_dimension.ProductKey
LEFT JOIN ReturnsByProduct AS product_return
    ON product_return.ProductKey = product_dimension.ProductKey
WHERE product_dimension.IsUnknown = 0;

CREATE UNIQUE CLUSTERED INDEX CIX_ProductPerformance
    ON #ProductPerformance (ProductKey);

DECLARE @PortfolioNetRevenue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(NetRevenue), 0) FROM #ProductPerformance);
DECLARE @PortfolioGrossProfit DECIMAL(38,2) =
    (SELECT COALESCE(SUM(GrossProfit), 0) FROM #ProductPerformance);
DECLARE @PortfolioDeliveredUnits BIGINT =
    (SELECT COALESCE(SUM(DeliveredUnits), 0) FROM #ProductPerformance);
DECLARE @PortfolioAcceptedReturns BIGINT =
    (SELECT COALESCE(SUM(AcceptedReturnedUnits), 0) FROM #ProductPerformance);

/* ============================================================================
   4. PRODUCT KPI SCORECARD
   ============================================================================ */

SELECT
    COUNT_BIG(*) AS TotalProducts,
    SUM(CASE WHEN DeliveredUnits > 0 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS SellingProducts,
    SUM(CASE WHEN DeliveredUnits = 0 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS ProductsWithoutDeliveredSales,
    @PortfolioDeliveredUnits AS DeliveredUnits,
    @PortfolioAcceptedReturns AS AcceptedReturnedUnits,
    @PortfolioDeliveredUnits - @PortfolioAcceptedReturns AS NetUnitsSold,
    @PortfolioNetRevenue AS NetRevenue,
    SUM(COGS) AS COGS,
    @PortfolioGrossProfit AS GrossProfit,
    CONVERT(DECIMAL(9,4), @PortfolioGrossProfit / NULLIF(@PortfolioNetRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @PortfolioAcceptedReturns)
        / NULLIF(@PortfolioDeliveredUnits, 0)) AS ProductReturnRate
FROM #ProductPerformance;

/* ============================================================================
   5. PRODUCT RANKING AND CONTRIBUTION
   ============================================================================ */

SELECT
    product_performance.SKU,
    product_performance.ProductName,
    product_performance.BrandName,
    product_performance.CategoryName,
    product_performance.PriceBand,
    product_performance.DeliveredOrders,
    product_performance.ActiveCustomers,
    product_performance.DeliveredUnits,
    product_performance.NetUnitsSold,
    product_performance.NetRevenue,
    product_performance.GrossProfit,
    CONVERT(DECIMAL(9,4), product_performance.GrossProfit
        / NULLIF(product_performance.NetRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), product_performance.AcceptedReturnedUnits)
        / NULLIF(product_performance.DeliveredUnits, 0)) AS ProductReturnRate,
    CONVERT(DECIMAL(9,4), product_performance.NetRevenue
        / NULLIF(@PortfolioNetRevenue, 0)) AS NetRevenueContributionRate,
    DENSE_RANK() OVER (ORDER BY product_performance.NetRevenue DESC) AS RevenueRank,
    DENSE_RANK() OVER (ORDER BY product_performance.GrossProfit DESC) AS ProfitRank
FROM #ProductPerformance AS product_performance
ORDER BY RevenueRank, product_performance.SKU;

/* ============================================================================
   6. CATEGORY, SUBCATEGORY AND BRAND PERFORMANCE
   ============================================================================ */

SELECT
    product_performance.CategoryName,
    product_performance.SubCategoryName,
    product_performance.BrandName,
    COUNT_BIG(*) AS ProductCount,
    SUM(CASE WHEN product_performance.DeliveredUnits > 0 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS SellingProductCount,
    SUM(product_performance.DeliveredOrders) AS DeliveredOrders,
    SUM(product_performance.DeliveredUnits) AS DeliveredUnits,
    SUM(product_performance.NetUnitsSold) AS NetUnitsSold,
    SUM(product_performance.NetRevenue) AS NetRevenue,
    SUM(product_performance.GrossProfit) AS GrossProfit,
    CONVERT(DECIMAL(9,4), SUM(product_performance.GrossProfit)
        / NULLIF(SUM(product_performance.NetRevenue), 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), SUM(product_performance.AcceptedReturnedUnits))
        / NULLIF(SUM(product_performance.DeliveredUnits), 0)) AS ProductReturnRate,
    CONVERT(DECIMAL(9,4), SUM(product_performance.NetRevenue)
        / NULLIF(@PortfolioNetRevenue, 0)) AS RevenueContributionRate
FROM #ProductPerformance AS product_performance
GROUP BY
    product_performance.CategoryName,
    product_performance.SubCategoryName,
    product_performance.BrandName
ORDER BY NetRevenue DESC;

/* ============================================================================
   7. ABC / PARETO PRODUCT CLASSIFICATION
   A = cumulative 0-80%, B = next 15%, C = remaining 5% of net revenue.
   ============================================================================ */

;WITH RevenueRunning AS
(
    SELECT
        product_performance.*,
        SUM(product_performance.NetRevenue) OVER
        (
            ORDER BY product_performance.NetRevenue DESC, product_performance.ProductKey
            ROWS UNBOUNDED PRECEDING
        ) AS CumulativeNetRevenue
    FROM #ProductPerformance AS product_performance
    WHERE product_performance.NetRevenue > 0
)
SELECT
    revenue_running.*,
    CONVERT(DECIMAL(9,4), revenue_running.CumulativeNetRevenue
        / NULLIF(@PortfolioNetRevenue, 0)) AS CumulativeRevenueRate,
    CASE
        WHEN revenue_running.CumulativeNetRevenue / NULLIF(@PortfolioNetRevenue, 0) <= 0.80 THEN 'A - Core Revenue'
        WHEN revenue_running.CumulativeNetRevenue / NULLIF(@PortfolioNetRevenue, 0) <= 0.95 THEN 'B - Growth Portfolio'
        ELSE 'C - Long Tail'
    END AS ABCClass
INTO #ProductABC
FROM RevenueRunning AS revenue_running;

CREATE UNIQUE CLUSTERED INDEX CIX_ProductABC ON #ProductABC (ProductKey);

SELECT
    product_abc.ABCClass,
    COUNT_BIG(*) AS ProductCount,
    SUM(product_abc.NetUnitsSold) AS NetUnitsSold,
    SUM(product_abc.NetRevenue) AS NetRevenue,
    SUM(product_abc.GrossProfit) AS GrossProfit,
    CONVERT(DECIMAL(9,4), SUM(product_abc.NetRevenue)
        / NULLIF(@PortfolioNetRevenue, 0)) AS RevenueContributionRate
FROM #ProductABC AS product_abc
GROUP BY product_abc.ABCClass
ORDER BY product_abc.ABCClass;

/* ============================================================================
   8. PRICE-BAND PERFORMANCE
   ============================================================================ */

SELECT
    product_performance.PriceBand,
    COUNT_BIG(*) AS ProductCount,
    SUM(CASE WHEN product_performance.DeliveredUnits > 0 THEN CONVERT(BIGINT, 1) ELSE 0 END) AS SellingProducts,
    SUM(product_performance.DeliveredOrders) AS DeliveredOrders,
    SUM(product_performance.NetUnitsSold) AS NetUnitsSold,
    SUM(product_performance.NetRevenue) AS NetRevenue,
    SUM(product_performance.GrossProfit) AS GrossProfit,
    CONVERT(DECIMAL(19,2), SUM(product_performance.NetRevenue)
        / NULLIF(SUM(product_performance.DeliveredOrders), 0)) AS RevenuePerDeliveredOrder,
    CONVERT(DECIMAL(9,4), SUM(product_performance.GrossProfit)
        / NULLIF(SUM(product_performance.NetRevenue), 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), SUM(product_performance.AcceptedReturnedUnits))
        / NULLIF(SUM(product_performance.DeliveredUnits), 0)) AS ProductReturnRate
FROM #ProductPerformance AS product_performance
GROUP BY product_performance.PriceBand
ORDER BY MIN(product_performance.CurrentSellingPrice);

/* ============================================================================
   9. RETURN REASON BY PRODUCT CATEGORY
   ============================================================================ */

SELECT
    product_dimension.CategoryName,
    return_reason.ReturnReasonCode,
    return_reason.ReturnReasonName,
    COUNT_BIG(*) AS ReturnedLineCount,
    SUM(CONVERT(BIGINT, return_adjustment.QuantityRequested)) AS RequestedReturnUnits,
    SUM(CONVERT(BIGINT, return_adjustment.QuantityAccepted)) AS AcceptedReturnedUnits,
    SUM(return_adjustment.CompletedPretaxRefundValue) AS CompletedPretaxRefundValue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6),
        SUM(return_adjustment.QuantityAccepted))
        / NULLIF(SUM(return_adjustment.QuantityRequested), 0)) AS AcceptanceRate
FROM #ReturnItemAdjustment AS return_adjustment
INNER JOIN analytics.DimProduct AS product_dimension
    ON product_dimension.ProductKey = return_adjustment.ProductKey
INNER JOIN analytics.DimReturnReason AS return_reason
    ON return_reason.ReturnReasonKey = return_adjustment.ReturnReasonKey
GROUP BY
    product_dimension.CategoryName,
    return_reason.ReturnReasonCode,
    return_reason.ReturnReasonName
ORDER BY AcceptedReturnedUnits DESC;

/* ============================================================================
   10. FINANCIAL-YEAR PRODUCT GROWTH
   ============================================================================ */

SELECT
    delivered_line.ProductKey,
    date_dimension.FinancialYearStart,
    date_dimension.FinancialYearLabel,
    SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
    SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue
INTO #ProductYear
FROM #DeliveredProductLine AS delivered_line
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = delivered_line.DeliveredDateKey
GROUP BY
    delivered_line.ProductKey,
    date_dimension.FinancialYearStart,
    date_dimension.FinancialYearLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_ProductYear
    ON #ProductYear (ProductKey, FinancialYearStart);

SELECT
    product_dimension.SKU,
    product_dimension.ProductName,
    product_year.FinancialYearLabel,
    product_year.DeliveredUnits,
    product_year.RecognizedRevenue,
    CONVERT
    (
        DECIMAL(9,4),
        (product_year.RecognizedRevenue
         - LAG(product_year.RecognizedRevenue) OVER
           (PARTITION BY product_year.ProductKey ORDER BY product_year.FinancialYearStart))
        / NULLIF
          (
              LAG(product_year.RecognizedRevenue) OVER
              (PARTITION BY product_year.ProductKey ORDER BY product_year.FinancialYearStart),
              0
          )
    ) AS RecognizedRevenueYoYRate
FROM #ProductYear AS product_year
INNER JOIN analytics.DimProduct AS product_dimension
    ON product_dimension.ProductKey = product_year.ProductKey
ORDER BY product_dimension.SKU, product_year.FinancialYearStart;

/* ============================================================================
   11. PRODUCT PORTFOLIO ACTION MATRIX
   Descriptive recommendations; not an automated purchasing decision.
   ============================================================================ */

SELECT
    product_performance.SKU,
    product_performance.ProductName,
    product_performance.CategoryName,
    product_performance.DeliveredUnits,
    product_performance.NetRevenue,
    product_performance.GrossProfit,
    CONVERT(DECIMAL(9,4), product_performance.GrossProfit
        / NULLIF(product_performance.NetRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), product_performance.AcceptedReturnedUnits)
        / NULLIF(product_performance.DeliveredUnits, 0)) AS ProductReturnRate,
    COALESCE(product_abc.ABCClass, 'D - No Revenue') AS ABCClass,
    CASE
        WHEN product_performance.DeliveredUnits = 0 THEN 'REVIEW ASSORTMENT'
        WHEN product_abc.ABCClass = 'A - Core Revenue'
             AND product_performance.GrossProfit > 0
             AND CONVERT(DECIMAL(38,6), product_performance.AcceptedReturnedUnits)
                 / NULLIF(product_performance.DeliveredUnits, 0) < 0.10 THEN 'PROTECT AND REPLENISH'
        WHEN product_performance.GrossProfit <= 0 THEN 'PRICING/COST REVIEW'
        WHEN CONVERT(DECIMAL(38,6), product_performance.AcceptedReturnedUnits)
             / NULLIF(product_performance.DeliveredUnits, 0) >= 0.10 THEN 'QUALITY/RETURN REVIEW'
        WHEN product_abc.ABCClass = 'C - Long Tail' THEN 'RATIONALIZE OR PROMOTE'
        ELSE 'MONITOR'
    END AS PortfolioAction
FROM #ProductPerformance AS product_performance
LEFT JOIN #ProductABC AS product_abc
    ON product_abc.ProductKey = product_performance.ProductKey
ORDER BY
    CASE
        WHEN product_performance.DeliveredUnits = 0 THEN 1
        WHEN product_performance.GrossProfit <= 0 THEN 2
        WHEN CONVERT(DECIMAL(38,6), product_performance.AcceptedReturnedUnits)
             / NULLIF(product_performance.DeliveredUnits, 0) >= 0.10 THEN 3
        ELSE 4
    END,
    product_performance.NetRevenue DESC;

/* ============================================================================
   12. PRODUCT ANALYSIS VALIDATION
   ============================================================================ */

DECLARE @ProductValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(100) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

DECLARE @SourceProducts BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.DimProduct WHERE IsUnknown = 0);
DECLARE @FactDeliveredUnits BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, Quantity)), 0)
     FROM analytics.FactSales WHERE IsDelivered = 1);

INSERT INTO @ProductValidation VALUES
(1, 'One performance row per product',
 ABS(@SourceProducts - (SELECT COUNT_BIG(*) FROM #ProductPerformance)),
 CASE WHEN @SourceProducts = (SELECT COUNT_BIG(*) FROM #ProductPerformance)
      THEN 'PASSED' ELSE 'FAILED' END),
(2, 'Delivered units reconcile to sales fact',
 ABS(@FactDeliveredUnits - @PortfolioDeliveredUnits),
 CASE WHEN @FactDeliveredUnits = @PortfolioDeliveredUnits THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Accepted returns do not exceed delivered units',
 (SELECT COUNT_BIG(*) FROM #ProductPerformance
  WHERE AcceptedReturnedUnits > DeliveredUnits),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #ProductPerformance WHERE AcceptedReturnedUnits > DeliveredUnits)
      THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Net units are correctly calculated',
 (SELECT COUNT_BIG(*) FROM #ProductPerformance
  WHERE NetUnitsSold <> DeliveredUnits - AcceptedReturnedUnits),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #ProductPerformance
       WHERE NetUnitsSold <> DeliveredUnits - AcceptedReturnedUnits)
      THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Gross profit reconciles to net revenue less COGS',
 (SELECT COUNT_BIG(*) FROM #ProductPerformance
  WHERE GrossProfit <> NetRevenue - COGS),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #ProductPerformance WHERE GrossProfit <> NetRevenue - COGS)
      THEN 'PASSED' ELSE 'FAILED' END),
(6, 'ABC classification covers all revenue-generating products',
 ABS((SELECT COUNT_BIG(*) FROM #ProductPerformance WHERE NetRevenue > 0)
     - (SELECT COUNT_BIG(*) FROM #ProductABC)),
 CASE WHEN (SELECT COUNT_BIG(*) FROM #ProductPerformance WHERE NetRevenue > 0)
              = (SELECT COUNT_BIG(*) FROM #ProductABC)
      THEN 'PASSED' ELSE 'FAILED' END),
(7, 'Revenue contribution reconciles to portfolio total',
 CASE WHEN @PortfolioNetRevenue = (SELECT COALESCE(SUM(NetRevenue), 0) FROM #ProductPerformance)
      THEN 0 ELSE 1 END,
 CASE WHEN @PortfolioNetRevenue = (SELECT COALESCE(SUM(NetRevenue), 0) FROM #ProductPerformance)
      THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @ProductValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @ProductValidation WHERE ValidationStatus = 'FAILED')
    THROW 51503, 'Product analysis validation failed. Review the final validation result set.', 1;

RAISERROR('30_Product_Analysis.sql completed successfully: product profitability and portfolio analyses validated.', 10, 1) WITH NOWAIT;
GO
