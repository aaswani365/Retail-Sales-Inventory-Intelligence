/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      40_Deployment_Health_Check.sql
Purpose:     Execute the final database deployment and portfolio-readiness gate.
Author:      Akshay Aswani
Version:     2.0
Depends on:  39_PowerBI_Model_Validation.sql
Rerunnable:  Yes. Each execution creates a new auditable health-check run.

Deployment coverage
-------------------
- Database state and approved SQL Server options
- Required schemas and application objects
- Enabled/trusted constraints and indexes
- Operational and analytical data populations
- Analytics and Power BI acceptance history
- Database storage and deployment manifest
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51600, 'Deployment health check stopped: unexpected database context.', 1;

IF OBJECT_ID(N'audit.ValidationRun', N'U') IS NULL
   OR OBJECT_ID(N'audit.ValidationResult', N'U') IS NULL
    THROW 51601, 'Deployment health check stopped: audit framework is missing.', 1;

DECLARE @ValidationRunID BIGINT;

INSERT INTO audit.ValidationRun
(
    RunStartDate, RunEndDate, EnvironmentName, OverallStatus,
    TotalTests, PassedTests, FailedTests, Remarks
)
VALUES
(
    SYSDATETIME(), NULL, 'LOCAL', 'Running', 0, 0, 0,
    'Final deployment health check initiated by script 40.'
);

SET @ValidationRunID = SCOPE_IDENTITY();

DECLARE @Results TABLE
(
    TestSequence SMALLINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TestCode VARCHAR(50) NOT NULL UNIQUE,
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
       1. DATABASE CONFIGURATION
       ====================================================================== */
    DECLARE @DatabaseStateExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sys.databases
        WHERE name = DB_NAME()
          AND (state_desc <> 'ONLINE' OR user_access_desc <> 'MULTI_USER')
    );

    INSERT INTO @Results VALUES
    ('DEP-DB-001', 'DATABASE', 'Database is online with multi-user access', 'Critical',
     'ONLINE / MULTI_USER',
     (SELECT CONCAT(state_desc, ' / ', user_access_desc) FROM sys.databases WHERE name = DB_NAME()),
     @DatabaseStateExceptions,
     CASE WHEN @DatabaseStateExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'The reporting database must be available to SQL Server and Power BI clients.');

    DECLARE @CompatibilityExceptions BIGINT =
    (
        SELECT COUNT_BIG(*) FROM sys.databases
        WHERE name = DB_NAME() AND compatibility_level < 160
    );

    INSERT INTO @Results VALUES
    ('DEP-DB-002', 'DATABASE', 'Database compatibility level supports SQL Server 2022', 'High',
     '>=160',
     (SELECT CONVERT(VARCHAR(10), compatibility_level) FROM sys.databases WHERE name = DB_NAME()),
     @CompatibilityExceptions,
     CASE WHEN @CompatibilityExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Compatibility level 160 is the approved project baseline.');

    DECLARE @DatabaseOptionExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sys.databases
        WHERE name = DB_NAME()
          AND (page_verify_option_desc <> 'CHECKSUM'
               OR snapshot_isolation_state_desc <> 'ON'
               OR is_read_committed_snapshot_on <> 1
               OR is_auto_close_on <> 0
               OR is_auto_shrink_on <> 0
               OR is_auto_create_stats_on <> 1
               OR is_auto_update_stats_on <> 1)
    );

    INSERT INTO @Results VALUES
    ('DEP-DB-003', 'DATABASE', 'Approved reliability and statistics options are enabled', 'Critical',
     '0 configuration exceptions', CONCAT(@DatabaseOptionExceptions, ' configuration exceptions'),
     @DatabaseOptionExceptions,
     CASE WHEN @DatabaseOptionExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'CHECKSUM, snapshot isolation and automatic statistics are required; auto-close and auto-shrink are disabled.');

    /* ======================================================================
       2. REQUIRED SCHEMAS AND OBJECTS
       ====================================================================== */
    DECLARE @RequiredSchemas TABLE (SchemaName SYSNAME NOT NULL PRIMARY KEY);
    INSERT INTO @RequiredSchemas VALUES
        ('ref'), ('core'), ('sales'), ('inventory'), ('audit'), ('analytics');

    DECLARE @MissingSchemas BIGINT =
    (
        SELECT COUNT_BIG(*) FROM @RequiredSchemas
        WHERE SCHEMA_ID(SchemaName) IS NULL
    );

    INSERT INTO @Results VALUES
    ('DEP-OBJ-001', 'OBJECTS', 'All approved business schemas exist', 'Critical',
     '6 schemas', CONCAT(6 - @MissingSchemas, ' schemas'), @MissingSchemas,
     CASE WHEN @MissingSchemas = 0 THEN 'Passed' ELSE 'Failed' END,
     'Reference, core, sales, inventory, audit and analytics schemas are required.');

    DECLARE @RequiredTables TABLE
    (
        SchemaName SYSNAME NOT NULL,
        TableName SYSNAME NOT NULL,
        PRIMARY KEY (SchemaName, TableName)
    );

    INSERT INTO @RequiredTables VALUES
    ('ref','Category'), ('ref','SubCategory'), ('ref','Brand'),
    ('ref','OrderStatus'), ('ref','PaymentMethod'), ('ref','PaymentStatus'),
    ('ref','ReturnReason'), ('ref','ReturnStatus'), ('ref','InventoryMovementType'),
    ('core','Store'), ('core','Employee'), ('core','Customer'), ('core','Supplier'), ('core','Product'),
    ('sales','SalesOrder'), ('sales','SalesOrderItem'), ('sales','OrderStatusHistory'),
    ('sales','Payment'), ('sales','ProductReturn'), ('sales','ProductReturnItem'), ('sales','Refund'),
    ('inventory','InventoryBalance'), ('inventory','InventoryMovement'),
    ('audit','ValidationRun'), ('audit','ValidationResult');

    DECLARE @MissingOperationalTables BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM @RequiredTables
        WHERE OBJECT_ID(QUOTENAME(SchemaName) + N'.' + QUOTENAME(TableName), N'U') IS NULL
    );

    INSERT INTO @Results VALUES
    ('DEP-OBJ-002', 'OBJECTS', 'All 25 operational and audit tables exist', 'Critical',
     '25 tables', CONCAT(25 - @MissingOperationalTables, ' tables'), @MissingOperationalTables,
     CASE WHEN @MissingOperationalTables = 0 THEN 'Passed' ELSE 'Failed' END,
     'The normalized operational layer and audit framework must be complete.');

    DECLARE @RequiredAnalyticsTables TABLE (TableName SYSNAME NOT NULL PRIMARY KEY);
    INSERT INTO @RequiredAnalyticsTables VALUES
    ('DimDate'), ('DimCustomer'), ('DimProduct'), ('DimStore'), ('DimEmployee'), ('DimSupplier'),
    ('DimPaymentMethod'), ('DimOrderStatus'), ('DimPaymentStatus'), ('DimReturnReason'),
    ('DimReturnStatus'), ('DimInventoryMovementType'), ('FactSales'), ('FactPayments'),
    ('FactReturns'), ('FactRefunds'), ('FactInventoryMovement'), ('FactInventorySnapshot');

    DECLARE @MissingAnalyticsTables BIGINT =
    (
        SELECT COUNT_BIG(*) FROM @RequiredAnalyticsTables
        WHERE OBJECT_ID(N'analytics.' + QUOTENAME(TableName), N'U') IS NULL
    );

    INSERT INTO @Results VALUES
    ('DEP-OBJ-003', 'OBJECTS', 'All analytical dimensions and facts exist', 'Critical',
     '18 tables', CONCAT(18 - @MissingAnalyticsTables, ' tables'), @MissingAnalyticsTables,
     CASE WHEN @MissingAnalyticsTables = 0 THEN 'Passed' ELSE 'Failed' END,
     'The approved star schema contains twelve dimensions and six facts.');

    DECLARE @RequiredPowerBIViews TABLE (ViewName SYSNAME NOT NULL PRIMARY KEY);
    INSERT INTO @RequiredPowerBIViews VALUES
    ('pbi_ExecutiveSummary'), ('pbi_SalesTrend'), ('pbi_StorePerformance'),
    ('pbi_ProductPerformance'), ('pbi_CustomerPerformance'), ('pbi_InventoryPosition'),
    ('pbi_ReturnsPerformance'), ('pbi_PaymentPerformance');

    DECLARE @MissingPowerBIViews BIGINT =
    (
        SELECT COUNT_BIG(*) FROM @RequiredPowerBIViews
        WHERE OBJECT_ID(N'analytics.' + QUOTENAME(ViewName), N'V') IS NULL
    );

    INSERT INTO @Results VALUES
    ('DEP-OBJ-004', 'OBJECTS', 'All Power BI semantic views exist', 'Critical',
     '8 views', CONCAT(8 - @MissingPowerBIViews, ' views'), @MissingPowerBIViews,
     CASE WHEN @MissingPowerBIViews = 0 THEN 'Passed' ELSE 'Failed' END,
     'The eight-page dashboard semantic layer must be complete.');

    DECLARE @RequiredProgrammability TABLE
    (
        SchemaName SYSNAME NOT NULL,
        ObjectName SYSNAME NOT NULL,
        ObjectType CHAR(2) NOT NULL,
        PRIMARY KEY (SchemaName, ObjectName)
    );

    INSERT INTO @RequiredProgrammability VALUES
    ('sales','usp_RecalculateOrderTotals','P'),
    ('sales','usp_ChangeOrderStatus','P'),
    ('sales','usp_RecordPayment','P'),
    ('inventory','usp_PostInventoryMovement','P'),
    ('sales','usp_RecordRefund','P'),
    ('audit','usp_RecordValidationResult','P'),
    ('audit','usp_CompleteValidationRun','P'),
    ('analytics','ufn_FinancialYear','FN'),
    ('analytics','ufn_FinancialQuarter','FN'),
    ('analytics','ufn_DateKey','FN');

    DECLARE @MissingProgrammabilityObjects BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM @RequiredProgrammability
        WHERE OBJECT_ID(QUOTENAME(SchemaName) + N'.' + QUOTENAME(ObjectName), ObjectType) IS NULL
    );

    INSERT INTO @Results VALUES
    ('DEP-OBJ-005', 'OBJECTS', 'Approved procedures and functions exist', 'Critical',
     '10 objects', CONCAT(10 - @MissingProgrammabilityObjects, ' objects'), @MissingProgrammabilityObjects,
     CASE WHEN @MissingProgrammabilityObjects = 0 THEN 'Passed' ELSE 'Failed' END,
     'Seven controlled procedures and three analytics functions are required.');

    /* ======================================================================
       3. CONSTRAINT AND INDEX HEALTH
       ====================================================================== */
    DECLARE @ForeignKeyExceptions BIGINT =
    (
        SELECT COUNT_BIG(*) FROM sys.foreign_keys
        WHERE is_disabled = 1 OR is_not_trusted = 1
    );

    INSERT INTO @Results VALUES
    ('DEP-INT-001', 'INTEGRITY', 'Foreign keys are enabled and trusted', 'Critical',
     '0 exceptions', CONCAT(@ForeignKeyExceptions, ' exceptions'), @ForeignKeyExceptions,
     CASE WHEN @ForeignKeyExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Disabled or untrusted foreign keys invalidate deployment readiness.');

    DECLARE @CheckConstraintExceptions BIGINT =
    (
        SELECT COUNT_BIG(*) FROM sys.check_constraints
        WHERE is_disabled = 1 OR is_not_trusted = 1
    );

    INSERT INTO @Results VALUES
    ('DEP-INT-002', 'INTEGRITY', 'Check constraints are enabled and trusted', 'Critical',
     '0 exceptions', CONCAT(@CheckConstraintExceptions, ' exceptions'), @CheckConstraintExceptions,
     CASE WHEN @CheckConstraintExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Trusted checks preserve approved business rules.');

    DECLARE @IndexExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sys.indexes AS object_index
        INNER JOIN sys.tables AS object_table ON object_table.object_id = object_index.object_id
        WHERE object_table.is_ms_shipped = 0
          AND object_index.index_id > 0
          AND (object_index.is_disabled = 1 OR object_index.is_hypothetical = 1)
    );

    INSERT INTO @Results VALUES
    ('DEP-PER-001', 'PERFORMANCE', 'Portfolio indexes are enabled and physical', 'Critical',
     '0 exceptions', CONCAT(@IndexExceptions, ' exceptions'), @IndexExceptions,
     CASE WHEN @IndexExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Disabled and hypothetical indexes cannot support portfolio workloads.');

    DECLARE @HeapCount BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sys.tables AS object_table
        WHERE object_table.is_ms_shipped = 0
          AND NOT EXISTS
          (
              SELECT 1 FROM sys.indexes AS object_index
              WHERE object_index.object_id = object_table.object_id
                AND object_index.type = 1
          )
    );

    INSERT INTO @Results VALUES
    ('DEP-PER-002', 'PERFORMANCE', 'Portfolio tables use clustered storage', 'High',
     '0 heaps', CONCAT(@HeapCount, ' heaps'), @HeapCount,
     CASE WHEN @HeapCount = 0 THEN 'Passed' ELSE 'Failed' END,
     'Every project table is expected to have a clustered primary-key or clustered index.');

    /* ======================================================================
       4. DATA POPULATIONS
       ====================================================================== */
    DECLARE @EmptyOperationalPopulations BIGINT =
        CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM core.Customer) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM core.Product) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM core.Store) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM sales.SalesOrder) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM sales.SalesOrderItem) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM sales.Payment) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM inventory.InventoryMovement) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM inventory.InventoryBalance) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('DEP-DAT-001', 'DATA', 'Core operational populations contain data', 'Critical',
     '0 empty populations', CONCAT(@EmptyOperationalPopulations, ' empty populations'),
     @EmptyOperationalPopulations,
     CASE WHEN @EmptyOperationalPopulations = 0 THEN 'Passed' ELSE 'Failed' END,
     'Eight essential operational populations are checked.');

    DECLARE @EmptyFactPopulations BIGINT =
        CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM analytics.FactSales) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM analytics.FactPayments) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM analytics.FactReturns) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM analytics.FactRefunds) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM analytics.FactInventoryMovement) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM analytics.FactInventorySnapshot) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('DEP-DAT-002', 'DATA', 'All analytical facts contain data', 'Critical',
     '0 empty facts', CONCAT(@EmptyFactPopulations, ' empty facts'), @EmptyFactPopulations,
     CASE WHEN @EmptyFactPopulations = 0 THEN 'Passed' ELSE 'Failed' END,
     'All six facts must be populated before Power BI deployment.');

    /* ======================================================================
       5. VALIDATION HISTORY
       ====================================================================== */
    DECLARE @AnalyticsAcceptanceMissing BIGINT = CASE WHEN EXISTS
    (
        SELECT 1 FROM audit.ValidationRun
        WHERE OverallStatus = 'Passed' AND Remarks LIKE 'Analytics model accepted%'
    ) THEN 0 ELSE 1 END;

    INSERT INTO @Results VALUES
    ('DEP-AUD-001', 'AUDIT', 'Analytics model acceptance is recorded', 'Critical',
     'Passed run found', CASE WHEN @AnalyticsAcceptanceMissing = 0 THEN 'Passed run found' ELSE 'Not found' END,
     @AnalyticsAcceptanceMissing,
     CASE WHEN @AnalyticsAcceptanceMissing = 0 THEN 'Passed' ELSE 'Failed' END,
     'Script 26 acceptance must remain in the validation history.');

    DECLARE @DataQualityAcceptanceMissing BIGINT = CASE WHEN EXISTS
    (
        SELECT 1 FROM audit.ValidationRun
        WHERE OverallStatus = 'Passed' AND Remarks LIKE 'Data-quality framework passed:%'
    ) THEN 0 ELSE 1 END;

    INSERT INTO @Results VALUES
    ('DEP-AUD-002', 'AUDIT', 'End-to-end data-quality acceptance is recorded', 'Critical',
     'Passed run found', CASE WHEN @DataQualityAcceptanceMissing = 0 THEN 'Passed run found' ELSE 'Not found' END,
     @DataQualityAcceptanceMissing,
     CASE WHEN @DataQualityAcceptanceMissing = 0 THEN 'Passed' ELSE 'Failed' END,
     'Script 36 acceptance must remain in the validation history.');

    DECLARE @PowerBIAcceptanceMissing BIGINT = CASE WHEN EXISTS
    (
        SELECT 1 FROM audit.ValidationRun
        WHERE OverallStatus = 'Passed' AND Remarks LIKE 'Power BI model accepted:%'
    ) THEN 0 ELSE 1 END;

    INSERT INTO @Results VALUES
    ('DEP-AUD-003', 'AUDIT', 'Power BI model acceptance is recorded', 'Critical',
     'Passed run found', CASE WHEN @PowerBIAcceptanceMissing = 0 THEN 'Passed run found' ELSE 'Not found' END,
     @PowerBIAcceptanceMissing,
     CASE WHEN @PowerBIAcceptanceMissing = 0 THEN 'Passed' ELSE 'Failed' END,
     'Script 39 acceptance is required before deployment.');

    /* ======================================================================
       6. PERSIST, SUMMARIZE AND FINALIZE
       ====================================================================== */
    INSERT INTO audit.ValidationResult
    (
        ValidationRunID, TestCode, TestName, Severity, ExpectedValue,
        ActualValue, ExceptionCount, TestStatus, ExecutedDate, DiagnosticMessage
    )
    SELECT
        @ValidationRunID, TestCode, TestName, Severity, ExpectedValue,
        ActualValue, ExceptionCount, TestStatus, SYSDATETIME(),
        CONCAT('[', TestCategory, '] ', DiagnosticMessage)
    FROM @Results;

    DECLARE @TotalTests INT = (SELECT COUNT(*) FROM @Results);
    DECLARE @PassedTests INT = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'Passed');
    DECLARE @FailedTests INT = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'Failed');

    UPDATE audit.ValidationRun
    SET RunEndDate = SYSDATETIME(),
        OverallStatus = CASE WHEN @FailedTests = 0 THEN 'Passed' ELSE 'Failed' END,
        TotalTests = @TotalTests,
        PassedTests = @PassedTests,
        FailedTests = @FailedTests,
        Remarks = CASE WHEN @FailedTests = 0
                       THEN 'Deployment health check passed: database and Power BI semantic layer are portfolio-ready.'
                       ELSE 'Deployment health check failed: review script 40 validation results.' END
    WHERE ValidationRunID = @ValidationRunID;

    SELECT
        TestSequence, TestCode, TestCategory, TestName, Severity,
        ExpectedValue, ActualValue, ExceptionCount, TestStatus, DiagnosticMessage
    FROM @Results
    ORDER BY TestSequence;

    SELECT
        database_file.name AS LogicalFileName,
        database_file.type_desc AS FileType,
        CONVERT(DECIMAL(12,2), database_file.size * 8.0 / 1024) AS AllocatedMB,
        CASE WHEN database_file.max_size = -1 THEN 'UNLIMITED'
             ELSE CONVERT(VARCHAR(30), CONVERT(DECIMAL(12,2), database_file.max_size * 8.0 / 1024)) END AS MaximumMB,
        CASE WHEN database_file.is_percent_growth = 1
             THEN CONCAT(database_file.growth, '%')
             ELSE CONCAT(CONVERT(DECIMAL(12,2), database_file.growth * 8.0 / 1024), ' MB') END AS GrowthSetting
    FROM sys.database_files AS database_file
    ORDER BY database_file.type;

    SELECT
        DB_NAME() AS DatabaseName,
        @@SERVERNAME AS SQLServerInstance,
        CONVERT(VARCHAR(30), SERVERPROPERTY('ProductVersion')) AS ProductVersion,
        CONVERT(VARCHAR(100), SERVERPROPERTY('Edition')) AS Edition,
        (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()) AS CompatibilityLevel,
        (SELECT COUNT_BIG(*) FROM sys.tables WHERE is_ms_shipped = 0) AS UserTableCount,
        (SELECT COUNT_BIG(*) FROM sys.views WHERE is_ms_shipped = 0) AS UserViewCount,
        (SELECT COUNT_BIG(*) FROM sys.procedures WHERE is_ms_shipped = 0) AS StoredProcedureCount,
        (SELECT COUNT_BIG(*) FROM sys.indexes AS object_index
         INNER JOIN sys.tables AS object_table ON object_table.object_id = object_index.object_id
         WHERE object_table.is_ms_shipped = 0 AND object_index.index_id > 0) AS IndexCount,
        @TotalTests AS HealthCheckCount,
        @PassedTests AS PassedHealthChecks,
        @FailedTests AS FailedHealthChecks,
        CASE WHEN @FailedTests = 0 THEN 'READY FOR POWER BI AND PORTFOLIO RELEASE'
             ELSE 'NOT READY - CORRECT FAILED HEALTH CHECKS' END AS DeploymentStatus;

    SELECT
        ValidationRunID, RunStartDate, RunEndDate, EnvironmentName,
        OverallStatus, TotalTests, PassedTests, FailedTests, Remarks
    FROM audit.ValidationRun
    WHERE ValidationRunID = @ValidationRunID;

    IF @FailedTests > 0
        THROW 51602, 'Deployment health check failed. Review the final result sets before release.', 1;

    RAISERROR('40_Deployment_Health_Check.sql completed successfully: project is ready for Power BI and portfolio release.', 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH
    IF EXISTS
    (
        SELECT 1 FROM audit.ValidationRun
        WHERE ValidationRunID = @ValidationRunID AND OverallStatus = 'Running'
    )
    BEGIN
        UPDATE audit.ValidationRun
        SET RunEndDate = SYSDATETIME(),
            OverallStatus = 'Failed',
            TotalTests = (SELECT COUNT(*) FROM @Results),
            PassedTests = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'Passed'),
            FailedTests = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'Failed'),
            Remarks = LEFT(CONCAT('Deployment health-check execution error: ', ERROR_MESSAGE()), 500)
        WHERE ValidationRunID = @ValidationRunID;
    END;

    THROW;
END CATCH;
GO
