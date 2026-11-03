/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      26_Validate_Analytics_Model.sql
Purpose:     Execute the acceptance gate for the Power BI analytical model.
Author:      Akshay Aswani
Version:     2.0
Depends on:  22_Create_Analytics_Dimensions.sql
             23_Create_Analytics_Facts.sql
             24_Create_Analytics_Views.sql
             25_Create_Analytics_Indexes.sql
Rerunnable:  Yes. Each execution creates a new auditable validation run.

Validation coverage
-------------------
1. Required analytics objects
2. Dimension row counts, unknown members and date continuity
3. Source-to-fact row counts and declared fact grains
4. Required dimension-key resolution and trusted foreign keys
5. Financial and inventory reconciliations
6. Derived-column and business-rule consistency
7. Power BI view grain preservation
8. Approved analytics indexes
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51460, 'Analytics validation stopped: unexpected database context.', 1;

IF SCHEMA_ID(N'analytics') IS NULL
   OR SCHEMA_ID(N'audit') IS NULL
   OR OBJECT_ID(N'audit.ValidationRun', N'U') IS NULL
   OR OBJECT_ID(N'audit.ValidationResult', N'U') IS NULL
    THROW 51461, 'Analytics validation stopped: required schemas or audit tables are missing.', 1;

DECLARE @RunStartDate DATETIME2(0) = SYSDATETIME();
DECLARE @ValidationRunID BIGINT;

INSERT INTO audit.ValidationRun
(
    RunStartDate, RunEndDate, EnvironmentName, OverallStatus,
    TotalTests, PassedTests, FailedTests, Remarks
)
VALUES
(
    @RunStartDate, NULL, 'LOCAL', 'RUNNING', 0, 0, 0,
    'Analytics model acceptance validation initiated by script 26.'
);

SET @ValidationRunID = SCOPE_IDENTITY();

DECLARE @Results TABLE
(
    TestSequence SMALLINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TestCode VARCHAR(50) NOT NULL,
    TestCategory VARCHAR(30) NOT NULL,
    TestName VARCHAR(200) NOT NULL,
    Severity VARCHAR(10) NOT NULL,
    ExpectedValue VARCHAR(100) NULL,
    ActualValue VARCHAR(100) NULL,
    ExceptionCount BIGINT NOT NULL,
    TestStatus VARCHAR(10) NOT NULL,
    DiagnosticMessage VARCHAR(1000) NULL
);

BEGIN TRY
    /* ======================================================================
       1. OBJECT INVENTORY
       ====================================================================== */
    DECLARE @RequiredTables TABLE (ObjectName SYSNAME PRIMARY KEY);
    INSERT INTO @RequiredTables (ObjectName) VALUES
    ('DimDate'), ('DimCustomer'), ('DimProduct'), ('DimStore'),
    ('DimEmployee'), ('DimSupplier'), ('DimPaymentMethod'),
    ('DimOrderStatus'), ('DimPaymentStatus'), ('DimReturnReason'),
    ('DimReturnStatus'), ('DimInventoryMovementType'),
    ('FactSales'), ('FactPayments'), ('FactReturns'), ('FactRefunds'),
    ('FactInventoryMovement'), ('FactInventorySnapshot');

    DECLARE @MissingTableCount BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM @RequiredTables AS required_table
        WHERE OBJECT_ID(N'analytics.' + QUOTENAME(required_table.ObjectName), N'U') IS NULL
    );

    INSERT INTO @Results VALUES
    ('AM-OBJ-001', 'OBJECTS', 'Required analytical tables exist', 'CRITICAL',
     '18', CONVERT(VARCHAR(100), 18 - @MissingTableCount), @MissingTableCount,
     CASE WHEN @MissingTableCount = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Twelve dimensions and six facts are required.');

    DECLARE @RequiredViews TABLE (ObjectName SYSNAME PRIMARY KEY);
    INSERT INTO @RequiredViews (ObjectName) VALUES
    ('vw_SalesDetail'), ('vw_PaymentDetail'), ('vw_ReturnDetail'),
    ('vw_RefundDetail'), ('vw_InventoryMovementDetail'), ('vw_CurrentInventory'),
    ('vw_ExecutiveKPIControl'), ('vw_MonthlySalesControl'),
    ('vw_StorePerformanceControl'), ('vw_ProductPerformanceControl');

    DECLARE @MissingViewCount BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM @RequiredViews AS required_view
        WHERE OBJECT_ID(N'analytics.' + QUOTENAME(required_view.ObjectName), N'V') IS NULL
    );

    INSERT INTO @Results VALUES
    ('AM-OBJ-002', 'OBJECTS', 'Required Power BI views exist', 'CRITICAL',
     '10', CONVERT(VARCHAR(100), 10 - @MissingViewCount), @MissingViewCount,
     CASE WHEN @MissingViewCount = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Six detail views and four control views are required.');

    IF @MissingTableCount > 0 OR @MissingViewCount > 0
        THROW 51462, 'Analytics validation stopped: required analytics objects are missing.', 1;

    /* ======================================================================
       2. DIMENSION ACCEPTANCE
       ====================================================================== */
    DECLARE @DimensionControl TABLE
    (
        DimensionName SYSNAME PRIMARY KEY,
        ExpectedRows BIGINT NOT NULL,
        ActualRows BIGINT NOT NULL,
        UnknownRows BIGINT NOT NULL
    );

    INSERT INTO @DimensionControl VALUES
    ('DimDate', 1462, (SELECT COUNT_BIG(*) FROM analytics.DimDate),
     (SELECT COUNT_BIG(*) FROM analytics.DimDate WHERE DateKey = 0 AND IsUnknown = 1)),
    ('DimCustomer', 10001, (SELECT COUNT_BIG(*) FROM analytics.DimCustomer),
     (SELECT COUNT_BIG(*) FROM analytics.DimCustomer WHERE CustomerKey = 0 AND IsUnknown = 1)),
    ('DimProduct', 501, (SELECT COUNT_BIG(*) FROM analytics.DimProduct),
     (SELECT COUNT_BIG(*) FROM analytics.DimProduct WHERE ProductKey = 0 AND IsUnknown = 1)),
    ('DimStore', 21, (SELECT COUNT_BIG(*) FROM analytics.DimStore),
     (SELECT COUNT_BIG(*) FROM analytics.DimStore WHERE StoreKey = 0 AND IsUnknown = 1)),
    ('DimEmployee', 101, (SELECT COUNT_BIG(*) FROM analytics.DimEmployee),
     (SELECT COUNT_BIG(*) FROM analytics.DimEmployee WHERE EmployeeKey = 0 AND IsUnknown = 1)),
    ('DimSupplier', 51, (SELECT COUNT_BIG(*) FROM analytics.DimSupplier),
     (SELECT COUNT_BIG(*) FROM analytics.DimSupplier WHERE SupplierKey = 0 AND IsUnknown = 1)),
    ('DimPaymentMethod', 7, (SELECT COUNT_BIG(*) FROM analytics.DimPaymentMethod),
     (SELECT COUNT_BIG(*) FROM analytics.DimPaymentMethod WHERE PaymentMethodKey = 0 AND IsUnknown = 1)),
    ('DimOrderStatus', 9, (SELECT COUNT_BIG(*) FROM analytics.DimOrderStatus),
     (SELECT COUNT_BIG(*) FROM analytics.DimOrderStatus WHERE OrderStatusKey = 0 AND IsUnknown = 1)),
    ('DimPaymentStatus', 8, (SELECT COUNT_BIG(*) FROM analytics.DimPaymentStatus),
     (SELECT COUNT_BIG(*) FROM analytics.DimPaymentStatus WHERE PaymentStatusKey = 0 AND IsUnknown = 1)),
    ('DimReturnReason', 8, (SELECT COUNT_BIG(*) FROM analytics.DimReturnReason),
     (SELECT COUNT_BIG(*) FROM analytics.DimReturnReason WHERE ReturnReasonKey = 0 AND IsUnknown = 1)),
    ('DimReturnStatus', 7, (SELECT COUNT_BIG(*) FROM analytics.DimReturnStatus),
     (SELECT COUNT_BIG(*) FROM analytics.DimReturnStatus WHERE ReturnStatusKey = 0 AND IsUnknown = 1)),
    ('DimInventoryMovementType', 11, (SELECT COUNT_BIG(*) FROM analytics.DimInventoryMovementType),
     (SELECT COUNT_BIG(*) FROM analytics.DimInventoryMovementType WHERE InventoryMovementTypeKey = 0 AND IsUnknown = 1));

    DECLARE @DimensionCountFailures BIGINT =
        (SELECT COUNT_BIG(*) FROM @DimensionControl WHERE ExpectedRows <> ActualRows);
    DECLARE @UnknownMemberFailures BIGINT =
        (SELECT COUNT_BIG(*) FROM @DimensionControl WHERE UnknownRows <> 1);

    INSERT INTO @Results VALUES
    ('AM-DIM-001', 'DIMENSIONS', 'Approved dimension row counts', 'CRITICAL',
     '12 dimensions matched',
     CONCAT(12 - @DimensionCountFailures, ' dimensions matched'),
     @DimensionCountFailures,
     CASE WHEN @DimensionCountFailures = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Dimension counts must match the approved source population plus one unknown member.'),
    ('AM-DIM-002', 'DIMENSIONS', 'One unknown member per dimension', 'CRITICAL',
     '12', CONVERT(VARCHAR(100), 12 - @UnknownMemberFailures),
     @UnknownMemberFailures,
     CASE WHEN @UnknownMemberFailures = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'The zero surrogate key supports safe handling of optional or unknown relationships.');

    DECLARE @DateExceptions BIGINT =
    (
        SELECT
            CASE WHEN COUNT_BIG(*) = 1461
                       AND MIN([Date]) = CONVERT(DATE, '2023-01-01')
                       AND MAX([Date]) = CONVERT(DATE, '2026-12-31')
                       AND COUNT_BIG(DISTINCT [Date]) = 1461
                 THEN 0 ELSE 1 END
        FROM analytics.DimDate
        WHERE DateKey <> 0
    );

    INSERT INTO @Results VALUES
    ('AM-DIM-003', 'DIMENSIONS', 'Date dimension is continuous and complete', 'CRITICAL',
     '2023-01-01 to 2026-12-31; 1461 dates',
     CONCAT(CONVERT(VARCHAR(10), (SELECT MIN([Date]) FROM analytics.DimDate WHERE DateKey <> 0), 120),
            ' to ', CONVERT(VARCHAR(10), (SELECT MAX([Date]) FROM analytics.DimDate WHERE DateKey <> 0), 120),
            '; ', (SELECT COUNT_BIG(*) FROM analytics.DimDate WHERE DateKey <> 0), ' dates'),
     @DateExceptions,
     CASE WHEN @DateExceptions = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'A continuous date dimension is required for reliable Power BI time intelligence.');

    /* ======================================================================
       3. FACT ROW COUNTS AND GRAINS
       ====================================================================== */
    DECLARE @FactControl TABLE
    (
        FactName SYSNAME PRIMARY KEY,
        DeclaredGrain VARCHAR(100) NOT NULL,
        SourceRows BIGINT NOT NULL,
        FactRows BIGINT NOT NULL,
        DuplicateRows BIGINT NOT NULL
    );

    INSERT INTO @FactControl VALUES
    ('FactSales', 'One row per sales-order item',
     (SELECT COUNT_BIG(*) FROM sales.SalesOrderItem),
     (SELECT COUNT_BIG(*) FROM analytics.FactSales),
     (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT SalesOrderItemID) FROM analytics.FactSales)),
    ('FactPayments', 'One row per payment attempt',
     (SELECT COUNT_BIG(*) FROM sales.Payment),
     (SELECT COUNT_BIG(*) FROM analytics.FactPayments),
     (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT PaymentID) FROM analytics.FactPayments)),
    ('FactReturns', 'One row per returned order item',
     (SELECT COUNT_BIG(*) FROM sales.ProductReturnItem),
     (SELECT COUNT_BIG(*) FROM analytics.FactReturns),
     (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT ProductReturnItemID) FROM analytics.FactReturns)),
    ('FactRefunds', 'One row per refund event',
     (SELECT COUNT_BIG(*) FROM sales.Refund),
     (SELECT COUNT_BIG(*) FROM analytics.FactRefunds),
     (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT RefundID) FROM analytics.FactRefunds)),
    ('FactInventoryMovement', 'One row per inventory movement',
     (SELECT COUNT_BIG(*) FROM inventory.InventoryMovement),
     (SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement),
     (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT InventoryMovementID) FROM analytics.FactInventoryMovement)),
    ('FactInventorySnapshot', 'One row per snapshot date-product-store',
     (SELECT COUNT_BIG(*) FROM inventory.InventoryBalance),
     (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot),
     (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(SnapshotDateKey, '|', ProductKey, '|', StoreKey))
      FROM analytics.FactInventorySnapshot));

    DECLARE @FactCountFailures BIGINT =
        (SELECT COUNT_BIG(*) FROM @FactControl WHERE SourceRows <> FactRows);
    DECLARE @FactGrainExceptions BIGINT =
        (SELECT COALESCE(SUM(DuplicateRows), 0) FROM @FactControl);

    INSERT INTO @Results VALUES
    ('AM-FACT-001', 'FACTS', 'Source-to-fact row counts reconcile', 'CRITICAL',
     '6 facts matched', CONCAT(6 - @FactCountFailures, ' facts matched'),
     @FactCountFailures,
     CASE WHEN @FactCountFailures = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Every operational source row must appear exactly once in its analytical fact.'),
    ('AM-FACT-002', 'FACTS', 'Declared fact grains are unique', 'CRITICAL',
     '0 duplicate rows', CONCAT(@FactGrainExceptions, ' duplicate rows'),
     @FactGrainExceptions,
     CASE WHEN @FactGrainExceptions = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Duplicate business keys would inflate Power BI measures.');

    /* ======================================================================
       4. RELATIONSHIP AND KEY QUALITY
       ====================================================================== */
    DECLARE @UnresolvedRequiredKeys BIGINT =
    (
        SELECT COUNT_BIG(*) FROM analytics.FactSales
        WHERE OrderDateKey = 0 OR CustomerKey = 0 OR ProductKey = 0
           OR StoreKey = 0 OR EmployeeKey = 0 OR OrderStatusKey = 0
    ) +
    (
        SELECT COUNT_BIG(*) FROM analytics.FactPayments
        WHERE PaymentDateKey = 0 OR CustomerKey = 0 OR StoreKey = 0
           OR PaymentMethodKey = 0 OR PaymentStatusKey = 0 OR OrderStatusKey = 0
    ) +
    (
        SELECT COUNT_BIG(*) FROM analytics.FactReturns
        WHERE RequestDateKey = 0 OR CustomerKey = 0 OR ProductKey = 0 OR StoreKey = 0
           OR EmployeeKey = 0 OR ReturnReasonKey = 0 OR ReturnStatusKey = 0 OR OrderStatusKey = 0
    ) +
    (
        SELECT COUNT_BIG(*) FROM analytics.FactRefunds
        WHERE RefundDateKey = 0 OR CustomerKey = 0 OR StoreKey = 0
           OR PaymentMethodKey = 0 OR PaymentStatusKey = 0 OR OrderStatusKey = 0
    ) +
    (
        SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement
        WHERE MovementDateKey = 0 OR ProductKey = 0 OR StoreKey = 0
           OR InventoryMovementTypeKey = 0
    ) +
    (
        SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot
        WHERE SnapshotDateKey = 0 OR ProductKey = 0 OR StoreKey = 0
    );

    INSERT INTO @Results VALUES
    ('AM-REL-001', 'RELATIONSHIPS', 'Required dimension keys are resolved', 'CRITICAL',
     '0 unresolved rows', CONCAT(@UnresolvedRequiredKeys, ' unresolved rows'),
     @UnresolvedRequiredKeys,
     CASE WHEN @UnresolvedRequiredKeys = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Zero is permitted only for optional role-playing dates and optional movement employees.');

    DECLARE @UntrustedForeignKeys BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sys.foreign_keys AS foreign_key
        INNER JOIN sys.tables AS parent_table ON parent_table.object_id = foreign_key.parent_object_id
        INNER JOIN sys.schemas AS parent_schema ON parent_schema.schema_id = parent_table.schema_id
        WHERE parent_schema.name = N'analytics'
          AND parent_table.name LIKE N'Fact%'
          AND (foreign_key.is_disabled = 1 OR foreign_key.is_not_trusted = 1)
    );

    INSERT INTO @Results VALUES
    ('AM-REL-002', 'RELATIONSHIPS', 'Fact foreign keys are enabled and trusted', 'CRITICAL',
     '0 unusable foreign keys', CONCAT(@UntrustedForeignKeys, ' unusable foreign keys'),
     @UntrustedForeignKeys,
     CASE WHEN @UntrustedForeignKeys = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Trusted relationships protect model integrity and help SQL Server optimization.');

    /* ======================================================================
       5. VALUE RECONCILIATION
       ====================================================================== */
    DECLARE @SourceSalesValue DECIMAL(38,2) =
        (SELECT COALESCE(SUM(NetAmount), 0) FROM sales.SalesOrderItem);
    DECLARE @FactSalesValue DECIMAL(38,2) =
        (SELECT COALESCE(SUM(NetAmount), 0) FROM analytics.FactSales);
    DECLARE @SourcePaymentValue DECIMAL(38,2) =
        (SELECT COALESCE(SUM(Amount), 0) FROM sales.Payment);
    DECLARE @FactPaymentValue DECIMAL(38,2) =
        (SELECT COALESCE(SUM(Amount), 0) FROM analytics.FactPayments);
    DECLARE @SourceRefundValue DECIMAL(38,2) =
        (SELECT COALESCE(SUM(RefundAmount), 0) FROM sales.Refund);
    DECLARE @FactRefundValue DECIMAL(38,2) =
        (SELECT COALESCE(SUM(RefundAmount), 0) FROM analytics.FactRefunds);
    DECLARE @SourceSignedUnits BIGINT =
        (SELECT COALESCE(SUM(CONVERT(BIGINT, Quantity) * QuantityDirection), 0)
         FROM inventory.InventoryMovement);
    DECLARE @FactSignedUnits BIGINT =
        (SELECT COALESCE(SUM(CONVERT(BIGINT, SignedQuantity)), 0)
         FROM analytics.FactInventoryMovement);

    INSERT INTO @Results VALUES
    ('AM-REC-001', 'RECONCILIATION', 'Sales value reconciles to source', 'CRITICAL',
     CONVERT(VARCHAR(100), @SourceSalesValue), CONVERT(VARCHAR(100), @FactSalesValue),
     CASE WHEN @SourceSalesValue = @FactSalesValue THEN 0 ELSE 1 END,
     CASE WHEN @SourceSalesValue = @FactSalesValue THEN 'PASSED' ELSE 'FAILED' END,
     'FactSales.NetAmount must reconcile exactly to SalesOrderItem.NetAmount.'),
    ('AM-REC-002', 'RECONCILIATION', 'Payment value reconciles to source', 'CRITICAL',
     CONVERT(VARCHAR(100), @SourcePaymentValue), CONVERT(VARCHAR(100), @FactPaymentValue),
     CASE WHEN @SourcePaymentValue = @FactPaymentValue THEN 0 ELSE 1 END,
     CASE WHEN @SourcePaymentValue = @FactPaymentValue THEN 'PASSED' ELSE 'FAILED' END,
     'FactPayments.Amount must reconcile exactly to Payment.Amount.'),
    ('AM-REC-003', 'RECONCILIATION', 'Refund value reconciles to source', 'CRITICAL',
     CONVERT(VARCHAR(100), @SourceRefundValue), CONVERT(VARCHAR(100), @FactRefundValue),
     CASE WHEN @SourceRefundValue = @FactRefundValue THEN 0 ELSE 1 END,
     CASE WHEN @SourceRefundValue = @FactRefundValue THEN 'PASSED' ELSE 'FAILED' END,
     'FactRefunds.RefundAmount must reconcile exactly to Refund.RefundAmount.'),
    ('AM-REC-004', 'RECONCILIATION', 'Signed inventory units reconcile to source', 'CRITICAL',
     CONVERT(VARCHAR(100), @SourceSignedUnits), CONVERT(VARCHAR(100), @FactSignedUnits),
     CASE WHEN @SourceSignedUnits = @FactSignedUnits THEN 0 ELSE 1 END,
     CASE WHEN @SourceSignedUnits = @FactSignedUnits THEN 'PASSED' ELSE 'FAILED' END,
     'SignedQuantity must equal Quantity multiplied by QuantityDirection.');

    /* ======================================================================
       6. DERIVED BUSINESS RULES
       ====================================================================== */
    DECLARE @SalesCalculationExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM analytics.FactSales AS fact_sales
        WHERE fact_sales.CostAmount <> CONVERT(DECIMAL(14,2), fact_sales.Quantity * fact_sales.UnitCost)
           OR fact_sales.GrossProfitAmount <> fact_sales.NetAmount - fact_sales.CostAmount
           OR fact_sales.LineCount <> 1
    );

    DECLARE @PaymentFlagExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM analytics.FactPayments AS fact_payment
        WHERE fact_payment.AttemptCount <> 1
           OR CONVERT(INT, fact_payment.IsSuccessful)
              + CONVERT(INT, fact_payment.IsFailed)
              + CONVERT(INT, fact_payment.IsPending) > 1
           OR fact_payment.CollectedAmount < 0
           OR fact_payment.CollectedAmount > fact_payment.Amount
    );

    DECLARE @ReturnCalculationExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM analytics.FactReturns AS fact_return
        WHERE fact_return.QuantityRejected < 0
           OR fact_return.QuantityRejected <> fact_return.QuantityRequested - fact_return.QuantityAccepted
           OR fact_return.QuantityAccepted > fact_return.QuantityRequested
           OR fact_return.ReturnLineCount <> 1
    );

    DECLARE @InventoryCalculationExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM analytics.FactInventoryMovement AS fact_movement
        WHERE fact_movement.SignedQuantity <> fact_movement.Quantity * fact_movement.QuantityDirection
           OR fact_movement.InflowQuantity <> CASE WHEN fact_movement.QuantityDirection = 1 THEN fact_movement.Quantity ELSE 0 END
           OR fact_movement.OutflowQuantity <> CASE WHEN fact_movement.QuantityDirection = -1 THEN fact_movement.Quantity ELSE 0 END
    ) +
    (
        SELECT COUNT_BIG(*)
        FROM analytics.FactInventorySnapshot AS fact_snapshot
        WHERE fact_snapshot.QuantityOnHand < 0
           OR fact_snapshot.QuantityReserved < 0
           OR fact_snapshot.QuantityReserved > fact_snapshot.QuantityOnHand
           OR fact_snapshot.QuantityAvailable <> fact_snapshot.QuantityOnHand - fact_snapshot.QuantityReserved
           OR fact_snapshot.SnapshotRowCount <> 1
    );

    INSERT INTO @Results VALUES
    ('AM-RULE-001', 'BUSINESS RULES', 'Sales calculations are consistent', 'CRITICAL',
     '0 exceptions', CONCAT(@SalesCalculationExceptions, ' exceptions'),
     @SalesCalculationExceptions,
     CASE WHEN @SalesCalculationExceptions = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Cost, profit and additive line-count columns are checked.'),
    ('AM-RULE-002', 'BUSINESS RULES', 'Payment flags and collected values are consistent', 'CRITICAL',
     '0 exceptions', CONCAT(@PaymentFlagExceptions, ' exceptions'),
     @PaymentFlagExceptions,
     CASE WHEN @PaymentFlagExceptions = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Payment outcome flags must not overlap and collected value cannot exceed attempted value.'),
    ('AM-RULE-003', 'BUSINESS RULES', 'Return quantities are consistent', 'CRITICAL',
     '0 exceptions', CONCAT(@ReturnCalculationExceptions, ' exceptions'),
     @ReturnCalculationExceptions,
     CASE WHEN @ReturnCalculationExceptions = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Accepted and rejected quantities must reconcile to requested quantity.'),
    ('AM-RULE-004', 'BUSINESS RULES', 'Inventory calculations are consistent', 'CRITICAL',
     '0 exceptions', CONCAT(@InventoryCalculationExceptions, ' exceptions'),
     @InventoryCalculationExceptions,
     CASE WHEN @InventoryCalculationExceptions = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Movement signs and snapshot availability are independently recalculated.');

    /* ======================================================================
       7. POWER BI VIEW GRAINS
       ====================================================================== */
    DECLARE @ViewControl TABLE
    (
        ViewName SYSNAME PRIMARY KEY,
        ExpectedRows BIGINT NOT NULL,
        ActualRows BIGINT NOT NULL
    );

    INSERT INTO @ViewControl VALUES
    ('vw_SalesDetail', (SELECT COUNT_BIG(*) FROM analytics.FactSales),
     (SELECT COUNT_BIG(*) FROM analytics.vw_SalesDetail)),
    ('vw_PaymentDetail', (SELECT COUNT_BIG(*) FROM analytics.FactPayments),
     (SELECT COUNT_BIG(*) FROM analytics.vw_PaymentDetail)),
    ('vw_ReturnDetail', (SELECT COUNT_BIG(*) FROM analytics.FactReturns),
     (SELECT COUNT_BIG(*) FROM analytics.vw_ReturnDetail)),
    ('vw_RefundDetail', (SELECT COUNT_BIG(*) FROM analytics.FactRefunds),
     (SELECT COUNT_BIG(*) FROM analytics.vw_RefundDetail)),
    ('vw_InventoryMovementDetail', (SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement),
     (SELECT COUNT_BIG(*) FROM analytics.vw_InventoryMovementDetail)),
    ('vw_CurrentInventory', (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot),
     (SELECT COUNT_BIG(*) FROM analytics.vw_CurrentInventory)),
    ('vw_ExecutiveKPIControl', 1,
     (SELECT COUNT_BIG(*) FROM analytics.vw_ExecutiveKPIControl)),
    ('vw_MonthlySalesControl',
     (SELECT COUNT_BIG(DISTINCT date_dimension.YearMonthNumber)
      FROM analytics.FactSales AS fact_sales
      INNER JOIN analytics.DimDate AS date_dimension ON date_dimension.DateKey = fact_sales.OrderDateKey),
     (SELECT COUNT_BIG(*) FROM analytics.vw_MonthlySalesControl)),
    ('vw_StorePerformanceControl',
     (SELECT COUNT_BIG(DISTINCT StoreKey) FROM analytics.FactSales),
     (SELECT COUNT_BIG(*) FROM analytics.vw_StorePerformanceControl)),
    ('vw_ProductPerformanceControl',
     (SELECT COUNT_BIG(DISTINCT ProductKey) FROM analytics.FactSales),
     (SELECT COUNT_BIG(*) FROM analytics.vw_ProductPerformanceControl));

    DECLARE @ViewGrainFailures BIGINT =
        (SELECT COUNT_BIG(*) FROM @ViewControl WHERE ExpectedRows <> ActualRows);

    INSERT INTO @Results VALUES
    ('AM-VIEW-001', 'VIEWS', 'Power BI views preserve declared grains', 'CRITICAL',
     '10 views matched', CONCAT(10 - @ViewGrainFailures, ' views matched'),
     @ViewGrainFailures,
     CASE WHEN @ViewGrainFailures = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'Detail views must not create fan-out; control views must preserve their reporting grain.');

    /* ======================================================================
       8. APPROVED ANALYTICS INDEXES
       ====================================================================== */
    DECLARE @ApprovedIndexes TABLE (IndexName SYSNAME PRIMARY KEY);
    INSERT INTO @ApprovedIndexes VALUES
    ('IX_DimDate_YearMonthNumber'),
    ('IX_DimDate_FinancialYear_Month'),
    ('IX_DimCustomer_Segment_State_City'),
    ('IX_DimProduct_Category_Brand'),
    ('IX_DimProduct_SupplierID'),
    ('IX_DimStore_Tier_State_City'),
    ('IX_DimEmployee_Store_JobTitle'),
    ('IX_FactSales_OrderDateKey'),
    ('IX_FactSales_DeliveredDateKey'),
    ('IX_FactSales_ProductKey_OrderDateKey'),
    ('IX_FactSales_StoreKey_OrderDateKey'),
    ('IX_FactSales_CustomerKey_OrderDateKey'),
    ('IX_FactSales_OrderStatusKey_OrderDateKey'),
    ('IX_FactPayments_Date_Status'),
    ('IX_FactPayments_Method_Date'),
    ('IX_FactPayments_SalesOrder_Attempt'),
    ('IX_FactPayments_FailedAttempts'),
    ('IX_FactReturns_RequestDate_Reason'),
    ('IX_FactReturns_Product_RequestDate'),
    ('IX_FactReturns_Store_RequestDate'),
    ('IX_FactReturns_Accepted'),
    ('IX_FactRefunds_Date_Status'),
    ('IX_FactRefunds_Store_Date'),
    ('IX_FactInventoryMovement_Date_Type'),
    ('IX_FactInventoryMovement_Product_Store_Date'),
    ('IX_FactInventoryMovement_ReferenceNumber'),
    ('IX_FactInventorySnapshot_Date_Store'),
    ('IX_FactInventorySnapshot_Product_Date'),
    ('IX_FactInventorySnapshot_BelowReorder'),
    ('IX_FactInventorySnapshot_ExcessStock');

    DECLARE @IndexFailures BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM @ApprovedIndexes AS approved_index
        LEFT JOIN
        (
            SELECT index_catalogue.name, index_catalogue.is_disabled, index_catalogue.is_hypothetical
            FROM sys.indexes AS index_catalogue
            INNER JOIN sys.tables AS table_catalogue
                ON table_catalogue.object_id = index_catalogue.object_id
            INNER JOIN sys.schemas AS schema_catalogue
                ON schema_catalogue.schema_id = table_catalogue.schema_id
            WHERE schema_catalogue.name = N'analytics'
        ) AS existing_index
            ON existing_index.name = approved_index.IndexName
        WHERE existing_index.name IS NULL
           OR existing_index.is_disabled = 1
           OR existing_index.is_hypothetical = 1
    );

    INSERT INTO @Results VALUES
    ('AM-IDX-001', 'INDEXES', 'Approved analytics indexes are usable', 'CRITICAL',
     '30', CONVERT(VARCHAR(100), 30 - @IndexFailures), @IndexFailures,
     CASE WHEN @IndexFailures = 0 THEN 'PASSED' ELSE 'FAILED' END,
     'All reporting indexes must exist, be enabled and be non-hypothetical.');

    /* ======================================================================
       9. PERSIST RESULTS AND CLOSE THE RUN
       ====================================================================== */
    INSERT INTO audit.ValidationResult
    (
        ValidationRunID, TestCode, TestName, Severity, ExpectedValue,
        ActualValue, ExceptionCount, TestStatus, ExecutedDate, DiagnosticMessage
    )
    SELECT
        @ValidationRunID, result.TestCode, result.TestName, result.Severity,
        result.ExpectedValue, result.ActualValue, result.ExceptionCount,
        result.TestStatus, SYSDATETIME(),
        CONCAT('[', result.TestCategory, '] ', result.DiagnosticMessage)
    FROM @Results AS result;

    DECLARE @TotalTests INT = (SELECT COUNT(*) FROM @Results);
    DECLARE @PassedTests INT = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'PASSED');
    DECLARE @FailedTests INT = @TotalTests - @PassedTests;
    DECLARE @OverallStatus VARCHAR(10) =
        CASE WHEN @FailedTests = 0 THEN 'PASSED' ELSE 'FAILED' END;

    UPDATE audit.ValidationRun
    SET RunEndDate = SYSDATETIME(),
        OverallStatus = @OverallStatus,
        TotalTests = @TotalTests,
        PassedTests = @PassedTests,
        FailedTests = @FailedTests,
        Remarks = CASE WHEN @FailedTests = 0
                       THEN 'Analytics model accepted for business-analysis scripts and Power BI.'
                       ELSE 'Analytics model rejected. Review failed tests before continuing.' END
    WHERE ValidationRunID = @ValidationRunID;

    SELECT
        TestSequence, TestCode, TestCategory, TestName, Severity,
        ExpectedValue, ActualValue, ExceptionCount, TestStatus,
        DiagnosticMessage
    FROM @Results
    ORDER BY TestSequence;

    SELECT
        @ValidationRunID AS ValidationRunID,
        @RunStartDate AS RunStartDate,
        SYSDATETIME() AS RunEndDate,
        @TotalTests AS TotalTests,
        @PassedTests AS PassedTests,
        @FailedTests AS FailedTests,
        @OverallStatus AS OverallStatus;

    SELECT DimensionName, ExpectedRows, ActualRows, UnknownRows,
           CASE WHEN ExpectedRows = ActualRows AND UnknownRows = 1
                THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
    FROM @DimensionControl
    ORDER BY DimensionName;

    SELECT FactName, DeclaredGrain, SourceRows, FactRows, DuplicateRows,
           CASE WHEN SourceRows = FactRows AND DuplicateRows = 0
                THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
    FROM @FactControl
    ORDER BY FactName;

    SELECT ViewName, ExpectedRows, ActualRows,
           CASE WHEN ExpectedRows = ActualRows THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
    FROM @ViewControl
    ORDER BY ViewName;

    IF @FailedTests > 0
        THROW 51463, 'Analytics model validation failed. Review the returned failed tests and audit.ValidationResult.', 1;

    RAISERROR('26_Validate_Analytics_Model.sql completed successfully: analytics model accepted for Power BI.', 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH
    IF EXISTS
    (
        SELECT 1
        FROM audit.ValidationRun
        WHERE ValidationRunID = @ValidationRunID
          AND OverallStatus = 'RUNNING'
    )
    BEGIN
        UPDATE audit.ValidationRun
        SET RunEndDate = SYSDATETIME(),
            OverallStatus = 'FAILED',
            TotalTests = (SELECT COUNT(*) FROM @Results),
            PassedTests = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'PASSED'),
            FailedTests = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'FAILED'),
            Remarks = LEFT(CONCAT('Validation execution error: ', ERROR_MESSAGE()), 500)
        WHERE ValidationRunID = @ValidationRunID;
    END;

    THROW;
END CATCH;
GO
