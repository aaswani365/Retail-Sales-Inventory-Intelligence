/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      25_Create_Analytics_Indexes.sql
Purpose:     Create targeted analytical indexes for Power BI and SQL workloads.
Author:      Akshay Aswani
Version:     2.0
Depends on:  24_Create_Analytics_Views.sql
Rerunnable:  Yes. Existing approved indexes are skipped.

Index strategy
--------------
- Date-leading indexes support incremental refresh and time slicing.
- Dimension-key indexes support star-schema joins and drilldowns.
- Filtered indexes target payment failures, accepted returns and stock alerts.
- Existing PK and UNIQUE constraint indexes are not duplicated.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51440, 'Analytics-index build stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactPayments', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventoryMovement', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
    THROW 51441, 'Analytics-index build stopped: one or more fact tables are missing.', 1;

DROP TABLE IF EXISTS #AnalyticsIndexBuild;

CREATE TABLE #AnalyticsIndexBuild
(
    IndexSequence TINYINT NOT NULL PRIMARY KEY,
    IndexGroup VARCHAR(30) NOT NULL,
    SchemaName SYSNAME NOT NULL,
    TableName SYSNAME NOT NULL,
    IndexName SYSNAME NOT NULL,
    CreateStatement NVARCHAR(MAX) NOT NULL
);

INSERT INTO #AnalyticsIndexBuild VALUES
-- Dimension navigation and sort paths.
(1, 'DIMENSION', N'analytics', N'DimDate', N'IX_DimDate_YearMonthNumber',
 N'CREATE INDEX IX_DimDate_YearMonthNumber ON analytics.DimDate (YearMonthNumber, DateKey) INCLUDE (MonthYearLabel, CalendarYear, CalendarQuarterLabel);'),
(2, 'DIMENSION', N'analytics', N'DimDate', N'IX_DimDate_FinancialYear_Month',
 N'CREATE INDEX IX_DimDate_FinancialYear_Month ON analytics.DimDate (FinancialYearStart, FinancialMonthNumber, DateKey) INCLUDE (FinancialYearLabel, FinancialQuarterLabel);'),
(3, 'DIMENSION', N'analytics', N'DimCustomer', N'IX_DimCustomer_Segment_State_City',
 N'CREATE INDEX IX_DimCustomer_Segment_State_City ON analytics.DimCustomer (CustomerSegment, StateName, City) INCLUDE (CustomerCode, CustomerName, IsActive);'),
(4, 'DIMENSION', N'analytics', N'DimProduct', N'IX_DimProduct_Category_Brand',
 N'CREATE INDEX IX_DimProduct_Category_Brand ON analytics.DimProduct (CategoryName, SubCategoryName, BrandName) INCLUDE (SKU, ProductName, SupplierName, PriceBand, IsActive);'),
(5, 'DIMENSION', N'analytics', N'DimProduct', N'IX_DimProduct_SupplierID',
 N'CREATE INDEX IX_DimProduct_SupplierID ON analytics.DimProduct (SupplierID, ProductKey) INCLUDE (SKU, ProductName, CategoryName, BrandName);'),
(6, 'DIMENSION', N'analytics', N'DimStore', N'IX_DimStore_Tier_State_City',
 N'CREATE INDEX IX_DimStore_Tier_State_City ON analytics.DimStore (StoreTier, StateName, City) INCLUDE (StoreCode, StoreName, IsActive);'),
(7, 'DIMENSION', N'analytics', N'DimEmployee', N'IX_DimEmployee_Store_JobTitle',
 N'CREATE INDEX IX_DimEmployee_Store_JobTitle ON analytics.DimEmployee (StoreID, JobTitle) INCLUDE (EmployeeCode, EmployeeName, ManagerName, IsActive);'),

-- Sales fact: time intelligence and contribution analysis.
(8, 'SALES', N'analytics', N'FactSales', N'IX_FactSales_OrderDateKey',
 N'CREATE INDEX IX_FactSales_OrderDateKey ON analytics.FactSales (OrderDateKey) INCLUDE (OrderCount, Quantity, NetAmount, RecognizedRevenueAmount, RecognizedCostAmount, RecognizedGrossProfitAmount);'),
(9, 'SALES', N'analytics', N'FactSales', N'IX_FactSales_DeliveredDateKey',
 N'CREATE INDEX IX_FactSales_DeliveredDateKey ON analytics.FactSales (DeliveredDateKey) INCLUDE (ProductKey, StoreKey, Quantity, RecognizedRevenueAmount, RecognizedGrossProfitAmount) WHERE DeliveredDateKey <> 0;'),
(10, 'SALES', N'analytics', N'FactSales', N'IX_FactSales_ProductKey_OrderDateKey',
 N'CREATE INDEX IX_FactSales_ProductKey_OrderDateKey ON analytics.FactSales (ProductKey, OrderDateKey) INCLUDE (SalesOrderID, OrderCount, Quantity, RecognizedRevenueAmount, RecognizedCostAmount, RecognizedGrossProfitAmount);'),
(11, 'SALES', N'analytics', N'FactSales', N'IX_FactSales_StoreKey_OrderDateKey',
 N'CREATE INDEX IX_FactSales_StoreKey_OrderDateKey ON analytics.FactSales (StoreKey, OrderDateKey) INCLUDE (EmployeeKey, OrderCount, Quantity, RecognizedRevenueAmount, RecognizedGrossProfitAmount);'),
(12, 'SALES', N'analytics', N'FactSales', N'IX_FactSales_CustomerKey_OrderDateKey',
 N'CREATE INDEX IX_FactSales_CustomerKey_OrderDateKey ON analytics.FactSales (CustomerKey, OrderDateKey) INCLUDE (SalesOrderID, OrderCount, Quantity, RecognizedRevenueAmount);'),
(13, 'SALES', N'analytics', N'FactSales', N'IX_FactSales_OrderStatusKey_OrderDateKey',
 N'CREATE INDEX IX_FactSales_OrderStatusKey_OrderDateKey ON analytics.FactSales (OrderStatusKey, OrderDateKey) INCLUDE (OrderCount, Quantity, NetAmount, IsDelivered, IsCancelled, IsReturned);'),

-- Payment fact: channel, outcome and retry analysis.
(14, 'PAYMENT', N'analytics', N'FactPayments', N'IX_FactPayments_Date_Status',
 N'CREATE INDEX IX_FactPayments_Date_Status ON analytics.FactPayments (PaymentDateKey, PaymentStatusKey) INCLUDE (PaymentMethodKey, AttemptCount, Amount, CollectedAmount, IsSuccessful, IsFailed);'),
(15, 'PAYMENT', N'analytics', N'FactPayments', N'IX_FactPayments_Method_Date',
 N'CREATE INDEX IX_FactPayments_Method_Date ON analytics.FactPayments (PaymentMethodKey, PaymentDateKey) INCLUDE (PaymentStatusKey, AttemptCount, Amount, CollectedAmount);'),
(16, 'PAYMENT', N'analytics', N'FactPayments', N'IX_FactPayments_SalesOrder_Attempt',
 N'CREATE INDEX IX_FactPayments_SalesOrder_Attempt ON analytics.FactPayments (SalesOrderID, AttemptNumber) INCLUDE (PaymentStatusKey, PaymentMethodKey, Amount, CollectedAmount);'),
(17, 'PAYMENT', N'analytics', N'FactPayments', N'IX_FactPayments_FailedAttempts',
 N'CREATE INDEX IX_FactPayments_FailedAttempts ON analytics.FactPayments (PaymentDateKey, PaymentMethodKey) INCLUDE (SalesOrderID, AttemptNumber, Amount, FailureReason) WHERE IsFailed = 1;'),

-- Return and refund fact access paths.
(18, 'RETURN', N'analytics', N'FactReturns', N'IX_FactReturns_RequestDate_Reason',
 N'CREATE INDEX IX_FactReturns_RequestDate_Reason ON analytics.FactReturns (RequestDateKey, ReturnReasonKey) INCLUDE (ProductKey, StoreKey, QuantityRequested, QuantityAccepted, EligibleRefundAmount, IsReusable);'),
(19, 'RETURN', N'analytics', N'FactReturns', N'IX_FactReturns_Product_RequestDate',
 N'CREATE INDEX IX_FactReturns_Product_RequestDate ON analytics.FactReturns (ProductKey, RequestDateKey) INCLUDE (ReturnReasonKey, QuantityRequested, QuantityAccepted, EligibleRefundAmount);'),
(20, 'RETURN', N'analytics', N'FactReturns', N'IX_FactReturns_Store_RequestDate',
 N'CREATE INDEX IX_FactReturns_Store_RequestDate ON analytics.FactReturns (StoreKey, RequestDateKey) INCLUDE (ReturnReasonKey, QuantityRequested, QuantityAccepted, EligibleRefundAmount);'),
(21, 'RETURN', N'analytics', N'FactReturns', N'IX_FactReturns_Accepted',
 N'CREATE INDEX IX_FactReturns_Accepted ON analytics.FactReturns (ReceivedDateKey, ReturnReasonKey) INCLUDE (ProductKey, StoreKey, QuantityAccepted, EligibleRefundAmount, IsReusable) WHERE IsAccepted = 1;'),
(22, 'REFUND', N'analytics', N'FactRefunds', N'IX_FactRefunds_Date_Status',
 N'CREATE INDEX IX_FactRefunds_Date_Status ON analytics.FactRefunds (RefundDateKey, RefundStatus) INCLUDE (StoreKey, PaymentMethodKey, RefundCount, RefundAmount, CompletedRefundAmount);'),
(23, 'REFUND', N'analytics', N'FactRefunds', N'IX_FactRefunds_Store_Date',
 N'CREATE INDEX IX_FactRefunds_Store_Date ON analytics.FactRefunds (StoreKey, RefundDateKey) INCLUDE (RefundStatus, RefundCount, RefundAmount, CompletedRefundAmount);'),

-- Inventory flow and stock-alert paths.
(24, 'INVENTORY', N'analytics', N'FactInventoryMovement', N'IX_FactInventoryMovement_Date_Type',
 N'CREATE INDEX IX_FactInventoryMovement_Date_Type ON analytics.FactInventoryMovement (MovementDateKey, InventoryMovementTypeKey) INCLUDE (ProductKey, StoreKey, SignedQuantity, InflowQuantity, OutflowQuantity);'),
(25, 'INVENTORY', N'analytics', N'FactInventoryMovement', N'IX_FactInventoryMovement_Product_Store_Date',
 N'CREATE INDEX IX_FactInventoryMovement_Product_Store_Date ON analytics.FactInventoryMovement (ProductKey, StoreKey, MovementDateKey) INCLUDE (InventoryMovementTypeKey, SignedQuantity, ReferenceNumber);'),
(26, 'INVENTORY', N'analytics', N'FactInventoryMovement', N'IX_FactInventoryMovement_ReferenceNumber',
 N'CREATE INDEX IX_FactInventoryMovement_ReferenceNumber ON analytics.FactInventoryMovement (ReferenceNumber) INCLUDE (MovementDateKey, ProductKey, StoreKey, InventoryMovementTypeKey, SignedQuantity);'),
(27, 'INVENTORY', N'analytics', N'FactInventorySnapshot', N'IX_FactInventorySnapshot_Date_Store',
 N'CREATE INDEX IX_FactInventorySnapshot_Date_Store ON analytics.FactInventorySnapshot (SnapshotDateKey, StoreKey) INCLUDE (ProductKey, QuantityOnHand, QuantityReserved, QuantityAvailable, StockCostValue, StockRetailValue);'),
(28, 'INVENTORY', N'analytics', N'FactInventorySnapshot', N'IX_FactInventorySnapshot_Product_Date',
 N'CREATE INDEX IX_FactInventorySnapshot_Product_Date ON analytics.FactInventorySnapshot (ProductKey, SnapshotDateKey) INCLUDE (StoreKey, QuantityOnHand, QuantityAvailable, StockCostValue, IsBelowReorderLevel, IsExcessStock);'),
(29, 'INVENTORY', N'analytics', N'FactInventorySnapshot', N'IX_FactInventorySnapshot_BelowReorder',
 N'CREATE INDEX IX_FactInventorySnapshot_BelowReorder ON analytics.FactInventorySnapshot (SnapshotDateKey, StoreKey, ProductKey) INCLUDE (QuantityOnHand, QuantityAvailable, ReorderLevel, StockCostValue) WHERE IsBelowReorderLevel = 1;'),
(30, 'INVENTORY', N'analytics', N'FactInventorySnapshot', N'IX_FactInventorySnapshot_ExcessStock',
 N'CREATE INDEX IX_FactInventorySnapshot_ExcessStock ON analytics.FactInventorySnapshot (SnapshotDateKey, StoreKey, ProductKey) INCLUDE (QuantityOnHand, ExcessStockLevel, StockCostValue) WHERE IsExcessStock = 1;');

IF (SELECT COUNT(*) FROM #AnalyticsIndexBuild) <> 30
    THROW 51442, 'Analytics-index manifest is incomplete.', 1;

DECLARE @IndexSequence TINYINT = 1;
DECLARE @SchemaName SYSNAME;
DECLARE @TableName SYSNAME;
DECLARE @IndexName SYSNAME;
DECLARE @CreateStatement NVARCHAR(MAX);

WHILE @IndexSequence <= 30
BEGIN
    SELECT
        @SchemaName = SchemaName,
        @TableName = TableName,
        @IndexName = IndexName,
        @CreateStatement = CreateStatement
    FROM #AnalyticsIndexBuild
    WHERE IndexSequence = @IndexSequence;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes AS index_catalogue
        INNER JOIN sys.tables AS table_catalogue
            ON table_catalogue.object_id = index_catalogue.object_id
        INNER JOIN sys.schemas AS schema_catalogue
            ON schema_catalogue.schema_id = table_catalogue.schema_id
        WHERE schema_catalogue.name = @SchemaName
          AND table_catalogue.name = @TableName
          AND index_catalogue.name = @IndexName
    )
    BEGIN
        EXEC sys.sp_executesql @CreateStatement;
    END;

    SET @IndexSequence += 1;
END;

-- ============================================================================
-- INDEX ACCEPTANCE VALIDATION
-- ============================================================================

;WITH ApprovedIndexes AS
(
    SELECT
        build.IndexGroup,
        build.SchemaName,
        build.TableName,
        build.IndexName,
        CASE WHEN index_catalogue.index_id IS NULL THEN 0 ELSE 1 END AS ExistsFlag,
        COALESCE(index_catalogue.is_disabled, 0) AS IsDisabled,
        COALESCE(index_catalogue.is_hypothetical, 0) AS IsHypothetical,
        CASE WHEN index_catalogue.has_filter = 1 THEN 1 ELSE 0 END AS IsFiltered
    FROM #AnalyticsIndexBuild AS build
    LEFT JOIN sys.schemas AS schema_catalogue
        ON schema_catalogue.name = build.SchemaName
    LEFT JOIN sys.tables AS table_catalogue
        ON table_catalogue.schema_id = schema_catalogue.schema_id
       AND table_catalogue.name = build.TableName
    LEFT JOIN sys.indexes AS index_catalogue
        ON index_catalogue.object_id = table_catalogue.object_id
       AND index_catalogue.name = build.IndexName
)
SELECT
    IndexGroup,
    COUNT(*) AS ExpectedIndexCount,
    SUM(ExistsFlag) AS ExistingIndexCount,
    SUM(IsFiltered) AS FilteredIndexCount,
    SUM(IsDisabled) AS DisabledIndexCount,
    SUM(IsHypothetical) AS HypotheticalIndexCount,
    CASE WHEN COUNT(*) = SUM(ExistsFlag)
               AND SUM(IsDisabled) = 0
               AND SUM(IsHypothetical) = 0
         THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM ApprovedIndexes
GROUP BY IndexGroup
ORDER BY CASE IndexGroup WHEN 'DIMENSION' THEN 1 WHEN 'SALES' THEN 2
         WHEN 'PAYMENT' THEN 3 WHEN 'RETURN' THEN 4 WHEN 'REFUND' THEN 5 ELSE 6 END;

IF EXISTS
(
    SELECT 1
    FROM #AnalyticsIndexBuild AS build
    LEFT JOIN sys.schemas AS schema_catalogue ON schema_catalogue.name = build.SchemaName
    LEFT JOIN sys.tables AS table_catalogue
        ON table_catalogue.schema_id = schema_catalogue.schema_id
       AND table_catalogue.name = build.TableName
    LEFT JOIN sys.indexes AS index_catalogue
        ON index_catalogue.object_id = table_catalogue.object_id
       AND index_catalogue.name = build.IndexName
    WHERE index_catalogue.index_id IS NULL
       OR index_catalogue.is_disabled = 1
       OR index_catalogue.is_hypothetical = 1
)
    THROW 51443, 'Analytics-index validation failed: a required index is missing or unusable.', 1;

SELECT
    COUNT(*) AS ApprovedAnalyticsIndexCount,
    SUM(CASE WHEN index_catalogue.has_filter = 1 THEN 1 ELSE 0 END) AS FilteredIndexCount,
    'PASSED' AS ValidationStatus
FROM #AnalyticsIndexBuild AS build
INNER JOIN sys.schemas AS schema_catalogue ON schema_catalogue.name = build.SchemaName
INNER JOIN sys.tables AS table_catalogue
    ON table_catalogue.schema_id = schema_catalogue.schema_id
   AND table_catalogue.name = build.TableName
INNER JOIN sys.indexes AS index_catalogue
    ON index_catalogue.object_id = table_catalogue.object_id
   AND index_catalogue.name = build.IndexName;

RAISERROR('25_Create_Analytics_Indexes.sql completed successfully: 30 analytical indexes validated.', 10, 1) WITH NOWAIT;
GO
