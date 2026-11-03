/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      34_Supplier_Analysis.sql
Purpose:     Analyze supplier contribution, quality, inventory and concentration.
Author:      Akshay Aswani
Version:     2.0
Depends on:  33_Returns_Payments_Analysis.sql
Rerunnable:  Yes. Read-only analysis using session-scoped temporary tables.

Attribution limitation
----------------------
Supplier metrics use each product's current primary supplier from DimProduct.
The project does not contain effective-dated product-supplier assignments;
therefore historical results must retain this disclosure.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51540, 'Supplier analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventoryMovement', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimSupplier', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimProduct', N'U') IS NULL
    THROW 51541, 'Supplier analysis stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51542, 'Supplier analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #DeliveredSupplierLine;
DROP TABLE IF EXISTS #SupplierReturnAdjustment;
DROP TABLE IF EXISTS #SupplierPerformance;
DROP TABLE IF EXISTS #SupplierYear;

/* ============================================================================
   1. DELIVERED SALES ATTRIBUTED TO CURRENT PRIMARY SUPPLIER
   ============================================================================ */

SELECT
    fact_sales.SalesOrderItemID,
    fact_sales.SalesOrderID,
    fact_sales.DeliveredDateKey,
    fact_sales.ProductKey,
    product_dimension.SupplierID,
    fact_sales.Quantity AS DeliveredUnits,
    fact_sales.UnitCost,
    CONVERT(DECIMAL(19,2), fact_sales.GrossAmount - fact_sales.DiscountAmount) AS RecognizedRevenue,
    CONVERT(DECIMAL(19,2), fact_sales.Quantity * fact_sales.UnitCost) AS RecognizedCost
INTO #DeliveredSupplierLine
FROM analytics.FactSales AS fact_sales
INNER JOIN analytics.DimProduct AS product_dimension
    ON product_dimension.ProductKey = fact_sales.ProductKey
WHERE fact_sales.IsDelivered = 1;

CREATE UNIQUE CLUSTERED INDEX CIX_DeliveredSupplierLine
    ON #DeliveredSupplierLine (SalesOrderItemID);
CREATE INDEX IX_DeliveredSupplierLine_Supplier
    ON #DeliveredSupplierLine (SupplierID, DeliveredDateKey);

/* ============================================================================
   2. ITEM-LEVEL COMPLETED REFUND AND RETURN-COST ALLOCATION
   ============================================================================ */

;WITH ReturnItemBase AS
(
    SELECT
        fact_return.ProductReturnItemID,
        fact_return.ProductReturnID,
        fact_return.ProductKey,
        delivered_line.SupplierID,
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
    INNER JOIN #DeliveredSupplierLine AS delivered_line
        ON delivered_line.SalesOrderItemID = fact_return.SalesOrderItemID
    INNER JOIN sales.SalesOrderItem AS source_item
        ON source_item.SalesOrderItemID = fact_return.SalesOrderItemID
),
ReturnHeaderControl AS
(
    SELECT
        return_item.ProductReturnID,
        SUM(return_item.EligibleRefundValue) AS HeaderEligibleRefundValue,
        MAX(refund_header.CompletedRefundValue) AS HeaderCompletedRefundValue
    FROM ReturnItemBase AS return_item
    LEFT JOIN
    (
        SELECT ProductReturnID, SUM(CompletedRefundAmount) AS CompletedRefundValue
        FROM analytics.FactRefunds
        GROUP BY ProductReturnID
    ) AS refund_header
        ON refund_header.ProductReturnID = return_item.ProductReturnID
    GROUP BY return_item.ProductReturnID
)
SELECT
    return_item.ProductReturnItemID,
    return_item.SupplierID,
    return_item.ProductKey,
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
INTO #SupplierReturnAdjustment
FROM ReturnItemBase AS return_item
INNER JOIN ReturnHeaderControl AS return_control
    ON return_control.ProductReturnID = return_item.ProductReturnID;

CREATE UNIQUE CLUSTERED INDEX CIX_SupplierReturnAdjustment
    ON #SupplierReturnAdjustment (ProductReturnItemID);
CREATE INDEX IX_SupplierReturnAdjustment_Supplier
    ON #SupplierReturnAdjustment (SupplierID);

/* ============================================================================
   3. SUPPLIER PERFORMANCE MART
   ============================================================================ */

;WITH SupplierProducts AS
(
    SELECT
        product_dimension.SupplierID,
        COUNT_BIG(*) AS ProductCount,
        COUNT_BIG(DISTINCT product_dimension.CategoryName) AS CategoryCount
    FROM analytics.DimProduct AS product_dimension
    WHERE product_dimension.IsUnknown = 0
    GROUP BY product_dimension.SupplierID
),
SupplierSales AS
(
    SELECT
        delivered_line.SupplierID,
        COUNT_BIG(DISTINCT delivered_line.SalesOrderID) AS DeliveredOrders,
        COUNT_BIG(DISTINCT delivered_line.ProductKey) AS SellingProducts,
        SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
        SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
        SUM(delivered_line.RecognizedCost) AS RecognizedCost
    FROM #DeliveredSupplierLine AS delivered_line
    GROUP BY delivered_line.SupplierID
),
SupplierReturns AS
(
    SELECT
        return_adjustment.SupplierID,
        SUM(CONVERT(BIGINT, return_adjustment.QuantityRequested)) AS RequestedReturnUnits,
        SUM(CONVERT(BIGINT, return_adjustment.QuantityAccepted)) AS AcceptedReturnedUnits,
        SUM(CASE WHEN return_adjustment.IsReusable = 1
                 THEN CONVERT(BIGINT, return_adjustment.QuantityAccepted) ELSE 0 END) AS ReusableReturnedUnits,
        SUM(return_adjustment.ReusableReturnCost) AS ReusableReturnCost,
        SUM(return_adjustment.CompletedPretaxRefundValue) AS PretaxRefundValue
    FROM #SupplierReturnAdjustment AS return_adjustment
    GROUP BY return_adjustment.SupplierID
),
SupplierInventory AS
(
    SELECT
        product_dimension.SupplierID,
        COUNT_BIG(DISTINCT fact_snapshot.ProductKey) AS StockedProducts,
        COUNT_BIG(*) AS ProductStoreCombinations,
        SUM(CONVERT(BIGINT, fact_snapshot.QuantityOnHand)) AS QuantityOnHand,
        SUM(CONVERT(BIGINT, fact_snapshot.QuantityAvailable)) AS QuantityAvailable,
        SUM(fact_snapshot.StockCostValue) AS InventoryExposure,
        SUM(CONVERT(BIGINT, fact_snapshot.IsOutOfStock)) AS StockoutCombinations,
        SUM(CONVERT(BIGINT, fact_snapshot.IsBelowReorderLevel)) AS BelowReorderCombinations,
        SUM(CONVERT(BIGINT, fact_snapshot.IsExcessStock)) AS ExcessStockCombinations
    FROM analytics.FactInventorySnapshot AS fact_snapshot
    INNER JOIN analytics.DimProduct AS product_dimension
        ON product_dimension.ProductKey = fact_snapshot.ProductKey
    GROUP BY product_dimension.SupplierID
),
SupplierReceipts AS
(
    SELECT
        product_dimension.SupplierID,
        COUNT_BIG(*) AS PurchaseReceiptEvents,
        SUM(CONVERT(BIGINT, fact_movement.InflowQuantity)) AS PurchaseReceiptUnits
    FROM analytics.FactInventoryMovement AS fact_movement
    INNER JOIN analytics.DimInventoryMovementType AS movement_type
        ON movement_type.InventoryMovementTypeKey = fact_movement.InventoryMovementTypeKey
    INNER JOIN analytics.DimProduct AS product_dimension
        ON product_dimension.ProductKey = fact_movement.ProductKey
    WHERE movement_type.InventoryMovementTypeCode = 'PURCHASE_RECEIPT'
    GROUP BY product_dimension.SupplierID
)
SELECT
    supplier_dimension.SupplierKey,
    supplier_dimension.SupplierID,
    supplier_dimension.SupplierCode,
    supplier_dimension.SupplierName,
    supplier_dimension.City,
    supplier_dimension.StateName,
    supplier_dimension.Country,
    supplier_dimension.IsActive,
    COALESCE(supplier_product.ProductCount, 0) AS ProductCount,
    COALESCE(supplier_product.CategoryCount, 0) AS CategoryCount,
    COALESCE(supplier_sales.SellingProducts, 0) AS SellingProducts,
    COALESCE(supplier_sales.DeliveredOrders, 0) AS DeliveredOrders,
    COALESCE(supplier_sales.DeliveredUnits, 0) AS DeliveredUnits,
    COALESCE(supplier_return.RequestedReturnUnits, 0) AS RequestedReturnUnits,
    COALESCE(supplier_return.AcceptedReturnedUnits, 0) AS AcceptedReturnedUnits,
    COALESCE(supplier_return.ReusableReturnedUnits, 0) AS ReusableReturnedUnits,
    COALESCE(supplier_sales.RecognizedRevenue, 0) AS RecognizedRevenue,
    COALESCE(supplier_return.PretaxRefundValue, 0) AS PretaxRefundValue,
    COALESCE(supplier_sales.RecognizedRevenue, 0) - COALESCE(supplier_return.PretaxRefundValue, 0) AS NetRevenue,
    COALESCE(supplier_sales.RecognizedCost, 0) - COALESCE(supplier_return.ReusableReturnCost, 0) AS COGS,
    COALESCE(supplier_sales.RecognizedRevenue, 0)
        - COALESCE(supplier_return.PretaxRefundValue, 0)
        - COALESCE(supplier_sales.RecognizedCost, 0)
        + COALESCE(supplier_return.ReusableReturnCost, 0) AS GrossProfit,
    COALESCE(supplier_inventory.StockedProducts, 0) AS StockedProducts,
    COALESCE(supplier_inventory.ProductStoreCombinations, 0) AS ProductStoreCombinations,
    COALESCE(supplier_inventory.QuantityOnHand, 0) AS QuantityOnHand,
    COALESCE(supplier_inventory.QuantityAvailable, 0) AS QuantityAvailable,
    COALESCE(supplier_inventory.InventoryExposure, 0) AS InventoryExposure,
    COALESCE(supplier_inventory.StockoutCombinations, 0) AS StockoutCombinations,
    COALESCE(supplier_inventory.BelowReorderCombinations, 0) AS BelowReorderCombinations,
    COALESCE(supplier_inventory.ExcessStockCombinations, 0) AS ExcessStockCombinations,
    COALESCE(supplier_receipt.PurchaseReceiptEvents, 0) AS PurchaseReceiptEvents,
    COALESCE(supplier_receipt.PurchaseReceiptUnits, 0) AS PurchaseReceiptUnits
INTO #SupplierPerformance
FROM analytics.DimSupplier AS supplier_dimension
LEFT JOIN SupplierProducts AS supplier_product
    ON supplier_product.SupplierID = supplier_dimension.SupplierID
LEFT JOIN SupplierSales AS supplier_sales
    ON supplier_sales.SupplierID = supplier_dimension.SupplierID
LEFT JOIN SupplierReturns AS supplier_return
    ON supplier_return.SupplierID = supplier_dimension.SupplierID
LEFT JOIN SupplierInventory AS supplier_inventory
    ON supplier_inventory.SupplierID = supplier_dimension.SupplierID
LEFT JOIN SupplierReceipts AS supplier_receipt
    ON supplier_receipt.SupplierID = supplier_dimension.SupplierID
WHERE supplier_dimension.IsUnknown = 0;

CREATE UNIQUE CLUSTERED INDEX CIX_SupplierPerformance
    ON #SupplierPerformance (SupplierKey);

DECLARE @PortfolioNetRevenue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(NetRevenue), 0) FROM #SupplierPerformance);
DECLARE @PortfolioInventoryExposure DECIMAL(38,2) =
    (SELECT COALESCE(SUM(InventoryExposure), 0) FROM #SupplierPerformance);
DECLARE @PortfolioDeliveredUnits BIGINT =
    (SELECT COALESCE(SUM(DeliveredUnits), 0) FROM #SupplierPerformance);
DECLARE @PortfolioAcceptedReturns BIGINT =
    (SELECT COALESCE(SUM(AcceptedReturnedUnits), 0) FROM #SupplierPerformance);

/* ============================================================================
   4. SUPPLIER KPI SCORECARD AND RANKING
   ============================================================================ */

SELECT
    supplier_performance.SupplierCode,
    supplier_performance.SupplierName,
    supplier_performance.StateName,
    supplier_performance.ProductCount,
    supplier_performance.CategoryCount,
    supplier_performance.SellingProducts,
    supplier_performance.DeliveredOrders,
    supplier_performance.DeliveredUnits,
    supplier_performance.NetRevenue,
    supplier_performance.GrossProfit,
    CONVERT(DECIMAL(9,4), supplier_performance.GrossProfit
        / NULLIF(supplier_performance.NetRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(9,4), supplier_performance.NetRevenue
        / NULLIF(@PortfolioNetRevenue, 0)) AS SupplierRevenueContributionRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), supplier_performance.AcceptedReturnedUnits)
        / NULLIF(supplier_performance.DeliveredUnits, 0)) AS SupplierReturnRate,
    supplier_performance.InventoryExposure AS SupplierInventoryExposure,
    CONVERT(DECIMAL(9,4), supplier_performance.InventoryExposure
        / NULLIF(@PortfolioInventoryExposure, 0)) AS InventoryExposureContributionRate,
    supplier_performance.PurchaseReceiptEvents,
    supplier_performance.PurchaseReceiptUnits,
    DENSE_RANK() OVER (ORDER BY supplier_performance.NetRevenue DESC) AS RevenueRank,
    DENSE_RANK() OVER (ORDER BY supplier_performance.InventoryExposure DESC) AS InventoryExposureRank
FROM #SupplierPerformance AS supplier_performance
ORDER BY RevenueRank, supplier_performance.SupplierCode;

/* ============================================================================
   5. SUPPLIER CONCENTRATION AND CUMULATIVE CONTRIBUTION
   ============================================================================ */

;WITH SupplierContribution AS
(
    SELECT
        supplier_performance.SupplierCode,
        supplier_performance.SupplierName,
        supplier_performance.NetRevenue,
        supplier_performance.InventoryExposure,
        SUM(supplier_performance.NetRevenue) OVER
        (
            ORDER BY supplier_performance.NetRevenue DESC, supplier_performance.SupplierCode
            ROWS UNBOUNDED PRECEDING
        ) AS CumulativeNetRevenue
    FROM #SupplierPerformance AS supplier_performance
)
SELECT
    supplier_contribution.*,
    CONVERT(DECIMAL(9,4), supplier_contribution.NetRevenue
        / NULLIF(@PortfolioNetRevenue, 0)) AS RevenueContributionRate,
    CONVERT(DECIMAL(9,4), supplier_contribution.CumulativeNetRevenue
        / NULLIF(@PortfolioNetRevenue, 0)) AS CumulativeRevenueContributionRate,
    CASE
        WHEN supplier_contribution.CumulativeNetRevenue / NULLIF(@PortfolioNetRevenue, 0) <= 0.80
            THEN 'CORE SUPPLIER SET'
        ELSE 'DIVERSIFICATION TAIL'
    END AS ConcentrationClass
FROM SupplierContribution AS supplier_contribution
ORDER BY supplier_contribution.NetRevenue DESC, supplier_contribution.SupplierCode;

/* ============================================================================
   6. SUPPLIER CATEGORY MIX
   ============================================================================ */

SELECT
    supplier_dimension.SupplierCode,
    supplier_dimension.SupplierName,
    product_dimension.CategoryName,
    COUNT_BIG(DISTINCT product_dimension.ProductKey) AS ProductCount,
    COUNT_BIG(DISTINCT delivered_line.SalesOrderID) AS DeliveredOrders,
    SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
    SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
    SUM(delivered_line.RecognizedRevenue - delivered_line.RecognizedCost) AS GrossProfitBeforeReturns
FROM #DeliveredSupplierLine AS delivered_line
INNER JOIN analytics.DimProduct AS product_dimension
    ON product_dimension.ProductKey = delivered_line.ProductKey
INNER JOIN analytics.DimSupplier AS supplier_dimension
    ON supplier_dimension.SupplierID = delivered_line.SupplierID
GROUP BY
    supplier_dimension.SupplierCode,
    supplier_dimension.SupplierName,
    product_dimension.CategoryName
ORDER BY RecognizedRevenue DESC;

/* ============================================================================
   7. SUPPLIER INVENTORY RISK
   ============================================================================ */

SELECT
    supplier_performance.SupplierCode,
    supplier_performance.SupplierName,
    supplier_performance.ProductCount,
    supplier_performance.StockedProducts,
    supplier_performance.QuantityOnHand,
    supplier_performance.QuantityAvailable,
    supplier_performance.InventoryExposure,
    supplier_performance.StockoutCombinations,
    supplier_performance.BelowReorderCombinations,
    supplier_performance.ExcessStockCombinations,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), supplier_performance.StockoutCombinations)
        / NULLIF(supplier_performance.ProductStoreCombinations, 0)) AS StockoutRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), supplier_performance.BelowReorderCombinations)
        / NULLIF(supplier_performance.ProductStoreCombinations, 0)) AS BelowReorderRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), supplier_performance.ExcessStockCombinations)
        / NULLIF(supplier_performance.ProductStoreCombinations, 0)) AS ExcessStockRate
FROM #SupplierPerformance AS supplier_performance
ORDER BY supplier_performance.InventoryExposure DESC;

/* ============================================================================
   8. FINANCIAL-YEAR SUPPLIER SALES GROWTH
   ============================================================================ */

SELECT
    delivered_line.SupplierID,
    date_dimension.FinancialYearStart,
    date_dimension.FinancialYearLabel,
    SUM(CONVERT(BIGINT, delivered_line.DeliveredUnits)) AS DeliveredUnits,
    SUM(delivered_line.RecognizedRevenue) AS RecognizedRevenue,
    SUM(delivered_line.RecognizedRevenue - delivered_line.RecognizedCost) AS GrossProfitBeforeReturns
INTO #SupplierYear
FROM #DeliveredSupplierLine AS delivered_line
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = delivered_line.DeliveredDateKey
GROUP BY
    delivered_line.SupplierID,
    date_dimension.FinancialYearStart,
    date_dimension.FinancialYearLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_SupplierYear
    ON #SupplierYear (SupplierID, FinancialYearStart);

SELECT
    supplier_dimension.SupplierCode,
    supplier_dimension.SupplierName,
    supplier_year.FinancialYearLabel,
    supplier_year.DeliveredUnits,
    supplier_year.RecognizedRevenue,
    supplier_year.GrossProfitBeforeReturns,
    CONVERT
    (
        DECIMAL(9,4),
        (supplier_year.RecognizedRevenue
         - LAG(supplier_year.RecognizedRevenue) OVER
           (PARTITION BY supplier_year.SupplierID ORDER BY supplier_year.FinancialYearStart))
        / NULLIF
          (
              LAG(supplier_year.RecognizedRevenue) OVER
              (PARTITION BY supplier_year.SupplierID ORDER BY supplier_year.FinancialYearStart),
              0
          )
    ) AS RecognizedRevenueYoYRate
FROM #SupplierYear AS supplier_year
INNER JOIN analytics.DimSupplier AS supplier_dimension
    ON supplier_dimension.SupplierID = supplier_year.SupplierID
ORDER BY supplier_dimension.SupplierCode, supplier_year.FinancialYearStart;

/* ============================================================================
   9. SUPPLIER GEOGRAPHIC EXPOSURE
   ============================================================================ */

SELECT
    supplier_performance.StateName,
    supplier_performance.Country,
    COUNT_BIG(*) AS SupplierCount,
    SUM(supplier_performance.ProductCount) AS ProductCount,
    SUM(supplier_performance.NetRevenue) AS NetRevenue,
    SUM(supplier_performance.GrossProfit) AS GrossProfit,
    SUM(supplier_performance.InventoryExposure) AS InventoryExposure,
    CONVERT(DECIMAL(9,4), SUM(supplier_performance.NetRevenue)
        / NULLIF(@PortfolioNetRevenue, 0)) AS RevenueContributionRate,
    CONVERT(DECIMAL(9,4), SUM(supplier_performance.InventoryExposure)
        / NULLIF(@PortfolioInventoryExposure, 0)) AS InventoryExposureContributionRate
FROM #SupplierPerformance AS supplier_performance
GROUP BY supplier_performance.StateName, supplier_performance.Country
ORDER BY NetRevenue DESC;

/* ============================================================================
   10. SUPPLIER ACTION MATRIX
   ============================================================================ */

;WITH SupplierBenchmark AS
(
    SELECT
        AVG(CONVERT(DECIMAL(38,6), NetRevenue)) AS AverageSupplierRevenue,
        AVG(CONVERT(DECIMAL(38,6), CONVERT(DECIMAL(38,6), AcceptedReturnedUnits)
            / NULLIF(DeliveredUnits, 0))) AS AverageSupplierReturnRate,
        AVG(CONVERT(DECIMAL(38,6), InventoryExposure)) AS AverageInventoryExposure
    FROM #SupplierPerformance
    WHERE DeliveredUnits > 0
)
SELECT
    supplier_performance.SupplierCode,
    supplier_performance.SupplierName,
    supplier_performance.NetRevenue,
    supplier_performance.GrossProfit,
    supplier_performance.InventoryExposure,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), supplier_performance.AcceptedReturnedUnits)
        / NULLIF(supplier_performance.DeliveredUnits, 0)) AS SupplierReturnRate,
    CASE
        WHEN supplier_performance.DeliveredUnits = 0 THEN 'REVIEW INACTIVE ASSORTMENT'
        WHEN supplier_performance.GrossProfit <= 0 THEN 'RENEGOTIATE COST/PRICING'
        WHEN CONVERT(DECIMAL(38,6), supplier_performance.AcceptedReturnedUnits)
             / NULLIF(supplier_performance.DeliveredUnits, 0) > supplier_benchmark.AverageSupplierReturnRate
             THEN 'QUALITY IMPROVEMENT REQUIRED'
        WHEN supplier_performance.InventoryExposure > supplier_benchmark.AverageInventoryExposure
             AND supplier_performance.NetRevenue < supplier_benchmark.AverageSupplierRevenue
             THEN 'REDUCE INVENTORY EXPOSURE'
        WHEN supplier_performance.NetRevenue >= supplier_benchmark.AverageSupplierRevenue
             THEN 'STRATEGIC SUPPLIER: PROTECT'
        ELSE 'MONITOR AND DEVELOP'
    END AS SupplierAction
FROM #SupplierPerformance AS supplier_performance
CROSS JOIN SupplierBenchmark AS supplier_benchmark
ORDER BY supplier_performance.NetRevenue DESC;

/* ============================================================================
   11. SUPPLIER ANALYSIS VALIDATION
   ============================================================================ */

DECLARE @SupplierValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(110) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

DECLARE @SourceSupplierCount BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.DimSupplier WHERE IsUnknown = 0);
DECLARE @DeliveredFactUnits BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, Quantity)), 0)
     FROM analytics.FactSales WHERE IsDelivered = 1);
DECLARE @SnapshotInventoryValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(StockCostValue), 0) FROM analytics.FactInventorySnapshot);

INSERT INTO @SupplierValidation VALUES
(1, 'One performance row per supplier',
 ABS(@SourceSupplierCount - (SELECT COUNT_BIG(*) FROM #SupplierPerformance)),
 CASE WHEN @SourceSupplierCount = (SELECT COUNT_BIG(*) FROM #SupplierPerformance)
      THEN 'PASSED' ELSE 'FAILED' END),
(2, 'Delivered units reconcile to sales fact',
 ABS(@DeliveredFactUnits - @PortfolioDeliveredUnits),
 CASE WHEN @DeliveredFactUnits = @PortfolioDeliveredUnits THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Accepted returns do not exceed delivered units',
 CASE WHEN @PortfolioAcceptedReturns <= @PortfolioDeliveredUnits THEN 0 ELSE 1 END,
 CASE WHEN @PortfolioAcceptedReturns <= @PortfolioDeliveredUnits THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Supplier inventory exposure reconciles to snapshot',
 CASE WHEN @PortfolioInventoryExposure = @SnapshotInventoryValue THEN 0 ELSE 1 END,
 CASE WHEN @PortfolioInventoryExposure = @SnapshotInventoryValue THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Supplier gross profit reconciles to net revenue less COGS',
 (SELECT COUNT_BIG(*) FROM #SupplierPerformance
  WHERE GrossProfit <> NetRevenue - COGS),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM #SupplierPerformance WHERE GrossProfit <> NetRevenue - COGS)
      THEN 'PASSED' ELSE 'FAILED' END),
(6, 'All products map to a valid supplier',
 (SELECT COUNT_BIG(*) FROM analytics.DimProduct
  WHERE IsUnknown = 0 AND SupplierID <= 0),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM analytics.DimProduct WHERE IsUnknown = 0 AND SupplierID <= 0)
      THEN 'PASSED' ELSE 'FAILED' END),
(7, 'Supplier revenue totals reconcile to performance mart',
 CASE WHEN @PortfolioNetRevenue =
      (SELECT COALESCE(SUM(NetRevenue), 0) FROM #SupplierPerformance)
      THEN 0 ELSE 1 END,
 CASE WHEN @PortfolioNetRevenue =
      (SELECT COALESCE(SUM(NetRevenue), 0) FROM #SupplierPerformance)
      THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @SupplierValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @SupplierValidation WHERE ValidationStatus = 'FAILED')
    THROW 51543, 'Supplier analysis validation failed. Review the final validation result set.', 1;

RAISERROR('34_Supplier_Analysis.sql completed successfully: supplier contribution and risk analyses validated.', 10, 1) WITH NOWAIT;
GO
