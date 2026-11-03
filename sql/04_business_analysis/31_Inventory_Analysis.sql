/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      31_Inventory_Analysis.sql
Purpose:     Analyze inventory position, flow, risk, turnover and sell-through.
Author:      Akshay Aswani
Version:     2.0
Depends on:  30_Product_Analysis.sql
Rerunnable:  Yes. Read-only analysis using session-scoped temporary tables.

Inventory policy
----------------
- Current stock metrics use the latest product-store snapshot.
- Historical month-end balances are reconstructed from the current snapshot
  and the immutable signed movement ledger.
- Historical estimated inventory value uses current product cost and is
  explicitly labelled as an estimate.
- Sell-through excludes customer-return inflows from approved inbound supply.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51510, 'Inventory analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventoryMovement', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimInventoryMovementType', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimProduct', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimStore', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
    THROW 51511, 'Inventory analysis stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51512, 'Inventory analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #ProductFlow;
DROP TABLE IF EXISTS #ProductInventory;
DROP TABLE IF EXISTS #ProductMonthMovement;
DROP TABLE IF EXISTS #MonthEnd;
DROP TABLE IF EXISTS #EstimatedMonthEndInventory;

DECLARE @SnapshotDateKey INT =
    (SELECT MAX(SnapshotDateKey) FROM analytics.FactInventorySnapshot);
DECLARE @SnapshotDate DATE =
    (SELECT [Date] FROM analytics.DimDate WHERE DateKey = @SnapshotDateKey);
DECLARE @FirstMovementDate DATE =
(
    SELECT MIN(date_dimension.[Date])
    FROM analytics.FactInventoryMovement AS fact_movement
    INNER JOIN analytics.DimDate AS date_dimension
        ON date_dimension.DateKey = fact_movement.MovementDateKey
);
DECLARE @AnalysisDays INT = DATEDIFF(DAY, @FirstMovementDate, @SnapshotDate) + 1;

/* ============================================================================
   1. PRODUCT FLOW, SALES COST AND RETURN REVERSALS
   ============================================================================ */

;WITH MovementByProduct AS
(
    SELECT
        fact_movement.ProductKey,
        SUM(CONVERT(BIGINT, fact_movement.InflowQuantity)) AS TotalInflowUnits,
        SUM(CONVERT(BIGINT, fact_movement.OutflowQuantity)) AS TotalOutflowUnits,
        SUM(CONVERT(BIGINT, fact_movement.SignedQuantity)) AS NetMovementUnits,
        SUM(CASE WHEN movement_type.InventoryMovementTypeCode = 'OPENING_STOCK'
                 THEN CONVERT(BIGINT, fact_movement.InflowQuantity) ELSE 0 END) AS OpeningUnits,
        SUM(CASE WHEN movement_type.InventoryMovementTypeCode IN
                      ('PURCHASE_RECEIPT', 'TRANSFER_IN', 'ADJUSTMENT_IN')
                 THEN CONVERT(BIGINT, fact_movement.InflowQuantity) ELSE 0 END) AS ApprovedInboundUnits,
        SUM(CASE WHEN movement_type.InventoryMovementTypeCode = 'SALE'
                 THEN CONVERT(BIGINT, fact_movement.OutflowQuantity) ELSE 0 END) AS SaleMovementUnits,
        SUM(CASE WHEN movement_type.InventoryMovementTypeCode = 'CUSTOMER_RETURN'
                 THEN CONVERT(BIGINT, fact_movement.InflowQuantity) ELSE 0 END) AS CustomerReturnMovementUnits,
        SUM(CASE WHEN movement_type.InventoryMovementTypeCode = 'DAMAGE_WRITEOFF'
                 THEN CONVERT(BIGINT, fact_movement.OutflowQuantity) ELSE 0 END) AS DamageWriteoffUnits,
        MAX(fact_movement.MovementDateKey) AS LastMovementDateKey
    FROM analytics.FactInventoryMovement AS fact_movement
    INNER JOIN analytics.DimInventoryMovementType AS movement_type
        ON movement_type.InventoryMovementTypeKey = fact_movement.InventoryMovementTypeKey
    GROUP BY fact_movement.ProductKey
),
SalesByProduct AS
(
    SELECT
        fact_sales.ProductKey,
        SUM(CASE WHEN fact_sales.IsDelivered = 1
                 THEN CONVERT(BIGINT, fact_sales.Quantity) ELSE 0 END) AS DeliveredUnits,
        SUM(fact_sales.RecognizedCostAmount) AS RecognizedCost
    FROM analytics.FactSales AS fact_sales
    GROUP BY fact_sales.ProductKey
),
ReturnsByProduct AS
(
    SELECT
        fact_return.ProductKey,
        SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnedUnits,
        SUM(CASE WHEN fact_return.IsReusable = 1
                 THEN CONVERT(DECIMAL(19,2), fact_return.QuantityAccepted * fact_sales.UnitCost)
                 ELSE CONVERT(DECIMAL(19,2), 0) END) AS ReusableReturnCost
    FROM analytics.FactReturns AS fact_return
    INNER JOIN analytics.FactSales AS fact_sales
        ON fact_sales.SalesOrderItemID = fact_return.SalesOrderItemID
    GROUP BY fact_return.ProductKey
)
SELECT
    product_dimension.ProductKey,
    COALESCE(product_movement.TotalInflowUnits, 0) AS TotalInflowUnits,
    COALESCE(product_movement.TotalOutflowUnits, 0) AS TotalOutflowUnits,
    COALESCE(product_movement.NetMovementUnits, 0) AS NetMovementUnits,
    COALESCE(product_movement.OpeningUnits, 0) AS OpeningUnits,
    COALESCE(product_movement.ApprovedInboundUnits, 0) AS ApprovedInboundUnits,
    COALESCE(product_movement.SaleMovementUnits, 0) AS SaleMovementUnits,
    COALESCE(product_movement.CustomerReturnMovementUnits, 0) AS CustomerReturnMovementUnits,
    COALESCE(product_movement.DamageWriteoffUnits, 0) AS DamageWriteoffUnits,
    product_movement.LastMovementDateKey,
    COALESCE(product_sales.DeliveredUnits, 0) AS DeliveredUnits,
    COALESCE(product_return.AcceptedReturnedUnits, 0) AS AcceptedReturnedUnits,
    COALESCE(product_sales.DeliveredUnits, 0) - COALESCE(product_return.AcceptedReturnedUnits, 0) AS NetUnitsSold,
    COALESCE(product_sales.RecognizedCost, 0) - COALESCE(product_return.ReusableReturnCost, 0) AS COGS
INTO #ProductFlow
FROM analytics.DimProduct AS product_dimension
LEFT JOIN MovementByProduct AS product_movement
    ON product_movement.ProductKey = product_dimension.ProductKey
LEFT JOIN SalesByProduct AS product_sales
    ON product_sales.ProductKey = product_dimension.ProductKey
LEFT JOIN ReturnsByProduct AS product_return
    ON product_return.ProductKey = product_dimension.ProductKey
WHERE product_dimension.IsUnknown = 0;

CREATE UNIQUE CLUSTERED INDEX CIX_ProductFlow ON #ProductFlow (ProductKey);

/* ============================================================================
   2. CURRENT INVENTORY BY PRODUCT
   ============================================================================ */

SELECT
    product_dimension.ProductKey,
    product_dimension.SKU,
    product_dimension.ProductName,
    product_dimension.BrandName,
    product_dimension.SubCategoryName,
    product_dimension.CategoryName,
    product_dimension.SupplierName,
    product_dimension.ReorderLevel,
    product_dimension.ExcessStockLevel,
    COUNT_BIG(fact_snapshot.InventorySnapshotFactKey) AS ProductStoreCombinationCount,
    COUNT_BIG(DISTINCT CASE WHEN fact_snapshot.InventorySnapshotFactKey IS NOT NULL
                            THEN fact_snapshot.StoreKey END) AS StockedStoreCount,
    COALESCE(SUM(CONVERT(BIGINT, fact_snapshot.QuantityOnHand)), 0) AS QuantityOnHand,
    COALESCE(SUM(CONVERT(BIGINT, fact_snapshot.QuantityReserved)), 0) AS QuantityReserved,
    COALESCE(SUM(CONVERT(BIGINT, fact_snapshot.QuantityAvailable)), 0) AS QuantityAvailable,
    COALESCE(SUM(fact_snapshot.StockCostValue), 0) AS StockCostValue,
    COALESCE(SUM(fact_snapshot.StockRetailValue), 0) AS StockRetailValue,
    COALESCE(SUM(CONVERT(BIGINT, fact_snapshot.IsOutOfStock)), 0) AS StockoutStoreCount,
    COALESCE(SUM(CASE WHEN fact_snapshot.QuantityAvailable > 0
                           AND fact_snapshot.QuantityAvailable <= fact_snapshot.ReorderLevel
                      THEN CONVERT(BIGINT, 1) ELSE 0 END), 0) AS LowStockStoreCount,
    COALESCE(SUM(CONVERT(BIGINT, fact_snapshot.IsExcessStock)), 0) AS ExcessStockStoreCount
INTO #ProductInventory
FROM analytics.DimProduct AS product_dimension
LEFT JOIN analytics.FactInventorySnapshot AS fact_snapshot
    ON fact_snapshot.ProductKey = product_dimension.ProductKey
   AND fact_snapshot.SnapshotDateKey = @SnapshotDateKey
WHERE product_dimension.IsUnknown = 0
GROUP BY
    product_dimension.ProductKey,
    product_dimension.SKU,
    product_dimension.ProductName,
    product_dimension.BrandName,
    product_dimension.SubCategoryName,
    product_dimension.CategoryName,
    product_dimension.SupplierName,
    product_dimension.ReorderLevel,
    product_dimension.ExcessStockLevel;

CREATE UNIQUE CLUSTERED INDEX CIX_ProductInventory ON #ProductInventory (ProductKey);

DECLARE @InventoryCombinations BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot WHERE SnapshotDateKey = @SnapshotDateKey);
DECLARE @StockoutCombinations BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot
     WHERE SnapshotDateKey = @SnapshotDateKey AND QuantityAvailable = 0);
DECLARE @LowStockCombinations BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot
     WHERE SnapshotDateKey = @SnapshotDateKey
       AND QuantityAvailable > 0 AND QuantityAvailable <= ReorderLevel);
DECLARE @ExcessStockCombinations BIGINT =
    (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot
     WHERE SnapshotDateKey = @SnapshotDateKey AND IsExcessStock = 1);
DECLARE @EndingInventoryCost DECIMAL(38,2) =
    (SELECT COALESCE(SUM(StockCostValue), 0) FROM analytics.FactInventorySnapshot
     WHERE SnapshotDateKey = @SnapshotDateKey);
DECLARE @TotalCOGS DECIMAL(38,2) =
    (SELECT COALESCE(SUM(COGS), 0) FROM #ProductFlow);
DECLARE @NetUnitsSold BIGINT =
    (SELECT COALESCE(SUM(NetUnitsSold), 0) FROM #ProductFlow);
DECLARE @AvailableSupplyUnits BIGINT =
    (SELECT COALESCE(SUM(OpeningUnits + ApprovedInboundUnits), 0) FROM #ProductFlow);

/* ============================================================================
   3. RECONSTRUCT ESTIMATED MONTH-END PRODUCT INVENTORY
   Current cost is used consistently for comparable estimated snapshots.
   ============================================================================ */

SELECT DISTINCT
    date_dimension.MonthEndDate,
    CONVERT(INT, CONVERT(CHAR(8), date_dimension.MonthEndDate, 112)) AS MonthEndDateKey
INTO #MonthEnd
FROM analytics.DimDate AS date_dimension
WHERE date_dimension.DateKey <> 0
  AND date_dimension.MonthEndDate BETWEEN EOMONTH(@FirstMovementDate) AND EOMONTH(@SnapshotDate);

CREATE UNIQUE CLUSTERED INDEX CIX_MonthEnd ON #MonthEnd (MonthEndDateKey);

SELECT
    fact_movement.ProductKey,
    date_dimension.MonthEndDate,
    SUM(CONVERT(BIGINT, fact_movement.SignedQuantity)) AS SignedMovementUnits
INTO #ProductMonthMovement
FROM analytics.FactInventoryMovement AS fact_movement
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = fact_movement.MovementDateKey
GROUP BY fact_movement.ProductKey, date_dimension.MonthEndDate;

CREATE UNIQUE CLUSTERED INDEX CIX_ProductMonthMovement
    ON #ProductMonthMovement (ProductKey, MonthEndDate);

;WITH ClosingProductInventory AS
(
    SELECT
        product_inventory.ProductKey,
        product_inventory.QuantityOnHand AS ClosingQuantityOnHand,
        product_dimension.CostPrice
    FROM #ProductInventory AS product_inventory
    INNER JOIN analytics.DimProduct AS product_dimension
        ON product_dimension.ProductKey = product_inventory.ProductKey
),
ProductMonthGrid AS
(
    SELECT
        closing_inventory.ProductKey,
        closing_inventory.ClosingQuantityOnHand,
        closing_inventory.CostPrice,
        month_end.MonthEndDate
    FROM ClosingProductInventory AS closing_inventory
    CROSS JOIN #MonthEnd AS month_end
)
SELECT
    product_month.MonthEndDate,
    product_month.ProductKey,
    product_month.ClosingQuantityOnHand
        - COALESCE
          (
              SUM(month_movement.SignedMovementUnits) OVER
              (
                  PARTITION BY product_month.ProductKey
                  ORDER BY product_month.MonthEndDate DESC
                  ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
              ),
              0
          ) AS EstimatedQuantityOnHand,
    CONVERT
    (
        DECIMAL(19,2),
        (product_month.ClosingQuantityOnHand
         - COALESCE
           (
               SUM(month_movement.SignedMovementUnits) OVER
               (
                   PARTITION BY product_month.ProductKey
                   ORDER BY product_month.MonthEndDate DESC
                   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
               ),
               0
           )) * product_month.CostPrice
    ) AS EstimatedInventoryCostValue
INTO #EstimatedMonthEndInventory
FROM ProductMonthGrid AS product_month
LEFT JOIN #ProductMonthMovement AS month_movement
    ON month_movement.ProductKey = product_month.ProductKey
   AND month_movement.MonthEndDate = product_month.MonthEndDate;

CREATE UNIQUE CLUSTERED INDEX CIX_EstimatedMonthEndInventory
    ON #EstimatedMonthEndInventory (MonthEndDate, ProductKey);

DECLARE @AverageMonthlyInventoryCost DECIMAL(38,2) =
(
    SELECT AVG(CONVERT(DECIMAL(38,2), monthly_inventory.InventoryCostValue))
    FROM
    (
        SELECT MonthEndDate, SUM(EstimatedInventoryCostValue) AS InventoryCostValue
        FROM #EstimatedMonthEndInventory
        GROUP BY MonthEndDate
    ) AS monthly_inventory
);

/* ============================================================================
   4. INVENTORY KPI SCORECARD
   ============================================================================ */

SELECT
    @SnapshotDate AS SnapshotDate,
    @InventoryCombinations AS ProductStoreCombinations,
    (SELECT SUM(QuantityOnHand) FROM analytics.FactInventorySnapshot
     WHERE SnapshotDateKey = @SnapshotDateKey) AS InventoryOnHandUnits,
    (SELECT SUM(QuantityReserved) FROM analytics.FactInventorySnapshot
     WHERE SnapshotDateKey = @SnapshotDateKey) AS InventoryReservedUnits,
    (SELECT SUM(QuantityAvailable) FROM analytics.FactInventorySnapshot
     WHERE SnapshotDateKey = @SnapshotDateKey) AS InventoryAvailableUnits,
    @EndingInventoryCost AS InventoryValueAtCost,
    (SELECT SUM(StockRetailValue) FROM analytics.FactInventorySnapshot
     WHERE SnapshotDateKey = @SnapshotDateKey) AS InventoryValueAtRetail,
    @StockoutCombinations AS StockoutProductStoreCount,
    @LowStockCombinations AS LowStockProductStoreCount,
    @ExcessStockCombinations AS ExcessStockProductStoreCount,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @StockoutCombinations)
        / NULLIF(@InventoryCombinations, 0)) AS StockoutRate,
    CONVERT(DECIMAL(19,4), @TotalCOGS / NULLIF(@AverageMonthlyInventoryCost, 0)) AS InventoryTurnover,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @NetUnitsSold)
        / NULLIF(@AvailableSupplyUnits, 0)) AS SellThroughRate,
    CONVERT(DECIMAL(19,2), @EndingInventoryCost
        / NULLIF(@TotalCOGS / NULLIF(@AnalysisDays, 0), 0)) AS DaysOfInventory;

/* ============================================================================
   5. STORE INVENTORY HEALTH
   ============================================================================ */

SELECT
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_dimension.City,
    store_dimension.StateName,
    COUNT_BIG(*) AS ProductCount,
    SUM(CONVERT(BIGINT, fact_snapshot.QuantityOnHand)) AS QuantityOnHand,
    SUM(CONVERT(BIGINT, fact_snapshot.QuantityReserved)) AS QuantityReserved,
    SUM(CONVERT(BIGINT, fact_snapshot.QuantityAvailable)) AS QuantityAvailable,
    SUM(fact_snapshot.StockCostValue) AS StockCostValue,
    SUM(fact_snapshot.StockRetailValue) AS StockRetailValue,
    SUM(CONVERT(BIGINT, fact_snapshot.IsOutOfStock)) AS StockoutProducts,
    SUM(CASE WHEN fact_snapshot.QuantityAvailable > 0
                  AND fact_snapshot.QuantityAvailable <= fact_snapshot.ReorderLevel
             THEN CONVERT(BIGINT, 1) ELSE 0 END) AS LowStockProducts,
    SUM(CONVERT(BIGINT, fact_snapshot.IsExcessStock)) AS ExcessStockProducts,
    CONVERT(DECIMAL(9,4), SUM(CONVERT(DECIMAL(38,6), fact_snapshot.IsOutOfStock))
        / NULLIF(COUNT_BIG(*), 0)) AS StockoutRate
FROM analytics.FactInventorySnapshot AS fact_snapshot
INNER JOIN analytics.DimStore AS store_dimension
    ON store_dimension.StoreKey = fact_snapshot.StoreKey
WHERE fact_snapshot.SnapshotDateKey = @SnapshotDateKey
GROUP BY
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    store_dimension.City,
    store_dimension.StateName
ORDER BY StockCostValue DESC;

/* ============================================================================
   6. CATEGORY INVENTORY EXPOSURE AND FLOW
   ============================================================================ */

SELECT
    product_inventory.CategoryName,
    product_inventory.SubCategoryName,
    COUNT_BIG(*) AS ProductCount,
    SUM(product_inventory.QuantityOnHand) AS QuantityOnHand,
    SUM(product_inventory.QuantityAvailable) AS QuantityAvailable,
    SUM(product_inventory.StockCostValue) AS StockCostValue,
    SUM(product_inventory.StockRetailValue) AS StockRetailValue,
    SUM(product_inventory.StockoutStoreCount) AS StockoutProductStoreCount,
    SUM(product_inventory.LowStockStoreCount) AS LowStockProductStoreCount,
    SUM(product_inventory.ExcessStockStoreCount) AS ExcessStockProductStoreCount,
    SUM(product_flow.NetUnitsSold) AS NetUnitsSold,
    SUM(product_flow.COGS) AS COGS,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), SUM(product_flow.NetUnitsSold))
        / NULLIF(SUM(product_flow.OpeningUnits + product_flow.ApprovedInboundUnits), 0)) AS SellThroughRate
FROM #ProductInventory AS product_inventory
INNER JOIN #ProductFlow AS product_flow
    ON product_flow.ProductKey = product_inventory.ProductKey
GROUP BY product_inventory.CategoryName, product_inventory.SubCategoryName
ORDER BY StockCostValue DESC;

/* ============================================================================
   7. MOVEMENT-TYPE CONTROL
   ============================================================================ */

SELECT
    movement_type.InventoryMovementTypeCode,
    movement_type.InventoryMovementTypeName,
    COUNT_BIG(*) AS MovementCount,
    SUM(CONVERT(BIGINT, fact_movement.InflowQuantity)) AS InflowUnits,
    SUM(CONVERT(BIGINT, fact_movement.OutflowQuantity)) AS OutflowUnits,
    SUM(CONVERT(BIGINT, fact_movement.SignedQuantity)) AS NetMovementUnits,
    COUNT_BIG(DISTINCT fact_movement.ProductKey) AS ProductCount,
    COUNT_BIG(DISTINCT fact_movement.StoreKey) AS StoreCount
FROM analytics.FactInventoryMovement AS fact_movement
INNER JOIN analytics.DimInventoryMovementType AS movement_type
    ON movement_type.InventoryMovementTypeKey = fact_movement.InventoryMovementTypeKey
GROUP BY
    movement_type.InventoryMovementTypeCode,
    movement_type.InventoryMovementTypeName,
    movement_type.SortOrder
ORDER BY movement_type.SortOrder;

/* ============================================================================
   8. MONTHLY INVENTORY FLOW TREND
   ============================================================================ */

SELECT
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    date_dimension.FinancialYearLabel,
    COUNT_BIG(*) AS MovementCount,
    SUM(CONVERT(BIGINT, fact_movement.InflowQuantity)) AS InflowUnits,
    SUM(CONVERT(BIGINT, fact_movement.OutflowQuantity)) AS OutflowUnits,
    SUM(CONVERT(BIGINT, fact_movement.SignedQuantity)) AS NetMovementUnits,
    SUM(CASE WHEN movement_type.InventoryMovementTypeCode = 'PURCHASE_RECEIPT'
             THEN CONVERT(BIGINT, fact_movement.InflowQuantity) ELSE 0 END) AS PurchaseReceiptUnits,
    SUM(CASE WHEN movement_type.InventoryMovementTypeCode = 'SALE'
             THEN CONVERT(BIGINT, fact_movement.OutflowQuantity) ELSE 0 END) AS SaleUnits,
    SUM(CASE WHEN movement_type.InventoryMovementTypeCode = 'CUSTOMER_RETURN'
             THEN CONVERT(BIGINT, fact_movement.InflowQuantity) ELSE 0 END) AS CustomerReturnUnits,
    SUM(CASE WHEN movement_type.InventoryMovementTypeCode = 'DAMAGE_WRITEOFF'
             THEN CONVERT(BIGINT, fact_movement.OutflowQuantity) ELSE 0 END) AS DamageWriteoffUnits
FROM analytics.FactInventoryMovement AS fact_movement
INNER JOIN analytics.DimInventoryMovementType AS movement_type
    ON movement_type.InventoryMovementTypeKey = fact_movement.InventoryMovementTypeKey
INNER JOIN analytics.DimDate AS date_dimension
    ON date_dimension.DateKey = fact_movement.MovementDateKey
GROUP BY
    date_dimension.YearMonthNumber,
    date_dimension.MonthYearLabel,
    date_dimension.FinancialYearLabel
ORDER BY date_dimension.YearMonthNumber;

/* ============================================================================
   9. ESTIMATED MONTH-END INVENTORY TREND
   ============================================================================ */

SELECT
    estimated_inventory.MonthEndDate,
    SUM(estimated_inventory.EstimatedQuantityOnHand) AS EstimatedQuantityOnHand,
    SUM(estimated_inventory.EstimatedInventoryCostValue) AS EstimatedInventoryCostValue,
    CASE WHEN SUM(estimated_inventory.EstimatedQuantityOnHand) < 0
         THEN 'REVIEW RECONSTRUCTION' ELSE 'VALID' END AS EstimateStatus
FROM #EstimatedMonthEndInventory AS estimated_inventory
GROUP BY estimated_inventory.MonthEndDate
ORDER BY estimated_inventory.MonthEndDate;

/* ============================================================================
   10. PRODUCT INVENTORY ACTION MATRIX
   ============================================================================ */

SELECT
    product_inventory.SKU,
    product_inventory.ProductName,
    product_inventory.CategoryName,
    product_inventory.SupplierName,
    product_inventory.StockedStoreCount,
    product_inventory.QuantityOnHand,
    product_inventory.QuantityAvailable,
    product_inventory.StockCostValue,
    product_inventory.StockoutStoreCount,
    product_inventory.LowStockStoreCount,
    product_inventory.ExcessStockStoreCount,
    product_flow.NetUnitsSold,
    product_flow.ApprovedInboundUnits,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), product_flow.NetUnitsSold)
        / NULLIF(product_flow.OpeningUnits + product_flow.ApprovedInboundUnits, 0)) AS SellThroughRate,
    DATEDIFF(DAY, last_movement_date.[Date], @SnapshotDate) AS DaysSinceLastMovement,
    CASE
        WHEN product_inventory.StockoutStoreCount > 0 THEN 'REPLENISH STOCKOUT LOCATIONS'
        WHEN product_inventory.LowStockStoreCount > 0 THEN 'REORDER LOW STOCK'
        WHEN product_inventory.ExcessStockStoreCount > 0
             AND DATEDIFF(DAY, last_movement_date.[Date], @SnapshotDate) > 60 THEN 'REDISTRIBUTE/PROMOTE EXCESS'
        WHEN product_inventory.QuantityOnHand > 0
             AND DATEDIFF(DAY, last_movement_date.[Date], @SnapshotDate) > 90 THEN 'REVIEW SLOW MOVING STOCK'
        ELSE 'MONITOR'
    END AS InventoryAction
FROM #ProductInventory AS product_inventory
INNER JOIN #ProductFlow AS product_flow
    ON product_flow.ProductKey = product_inventory.ProductKey
LEFT JOIN analytics.DimDate AS last_movement_date
    ON last_movement_date.DateKey = product_flow.LastMovementDateKey
ORDER BY
    CASE
        WHEN product_inventory.StockoutStoreCount > 0 THEN 1
        WHEN product_inventory.LowStockStoreCount > 0 THEN 2
        WHEN product_inventory.ExcessStockStoreCount > 0 THEN 3
        ELSE 4
    END,
    product_inventory.StockCostValue DESC;

/* ============================================================================
   11. INVENTORY ANALYSIS VALIDATION
   ============================================================================ */

DECLARE @InventoryValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(100) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

DECLARE @SnapshotOnHand BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, QuantityOnHand)), 0)
     FROM analytics.FactInventorySnapshot WHERE SnapshotDateKey = @SnapshotDateKey);
DECLARE @LedgerNetUnits BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, SignedQuantity)), 0)
     FROM analytics.FactInventoryMovement);
DECLARE @ExpectedInventoryIssuedUnits BIGINT =
(
    SELECT COALESCE(SUM(CONVERT(BIGINT, fact_sales.Quantity)), 0)
    FROM analytics.FactSales AS fact_sales
    INNER JOIN analytics.DimOrderStatus AS order_status
        ON order_status.OrderStatusKey = fact_sales.OrderStatusKey
    WHERE order_status.OrderStatusCode IN
          ('SHIPPED', 'DELIVERED', 'PARTIALLY_RETURNED', 'RETURNED')
);

INSERT INTO @InventoryValidation VALUES
(1, 'Inventory ledger reconciles to current on-hand balance',
 ABS(@SnapshotOnHand - @LedgerNetUnits),
 CASE WHEN @SnapshotOnHand = @LedgerNetUnits THEN 'PASSED' ELSE 'FAILED' END),
(2, 'Available quantity calculation is valid',
 (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot
  WHERE QuantityAvailable <> QuantityOnHand - QuantityReserved),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM analytics.FactInventorySnapshot
       WHERE QuantityAvailable <> QuantityOnHand - QuantityReserved)
      THEN 'PASSED' ELSE 'FAILED' END),
(3, 'No negative current inventory balances',
 (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot
  WHERE QuantityOnHand < 0 OR QuantityReserved < 0 OR QuantityAvailable < 0),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM analytics.FactInventorySnapshot
       WHERE QuantityOnHand < 0 OR QuantityReserved < 0 OR QuantityAvailable < 0)
      THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Product inventory totals reconcile to snapshot',
 ABS(@SnapshotOnHand - (SELECT COALESCE(SUM(QuantityOnHand), 0) FROM #ProductInventory)),
 CASE WHEN @SnapshotOnHand = (SELECT COALESCE(SUM(QuantityOnHand), 0) FROM #ProductInventory)
      THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Sale movement units reconcile to inventory-issued order units',
 ABS((SELECT COALESCE(SUM(SaleMovementUnits), 0) FROM #ProductFlow)
     - @ExpectedInventoryIssuedUnits),
 CASE WHEN (SELECT COALESCE(SUM(SaleMovementUnits), 0) FROM #ProductFlow)
              = @ExpectedInventoryIssuedUnits
      THEN 'PASSED' ELSE 'FAILED' END),
(6, 'Customer-return movements reconcile to accepted return units',
 ABS((SELECT COALESCE(SUM(CustomerReturnMovementUnits), 0) FROM #ProductFlow)
     - (SELECT COALESCE(SUM(AcceptedReturnedUnits), 0) FROM #ProductFlow)),
 CASE WHEN (SELECT COALESCE(SUM(CustomerReturnMovementUnits), 0) FROM #ProductFlow)
              = (SELECT COALESCE(SUM(AcceptedReturnedUnits), 0) FROM #ProductFlow)
      THEN 'PASSED' ELSE 'FAILED' END),
(7, 'Latest reconstructed inventory equals physical snapshot',
 ABS(@SnapshotOnHand
     - (SELECT COALESCE(SUM(EstimatedQuantityOnHand), 0)
        FROM #EstimatedMonthEndInventory WHERE MonthEndDate = EOMONTH(@SnapshotDate))),
 CASE WHEN @SnapshotOnHand =
      (SELECT COALESCE(SUM(EstimatedQuantityOnHand), 0)
       FROM #EstimatedMonthEndInventory WHERE MonthEndDate = EOMONTH(@SnapshotDate))
      THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @InventoryValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @InventoryValidation WHERE ValidationStatus = 'FAILED')
    THROW 51513, 'Inventory analysis validation failed. Review the final validation result set.', 1;

RAISERROR('31_Inventory_Analysis.sql completed successfully: inventory position, flow and turnover analyses validated.', 10, 1) WITH NOWAIT;
GO
