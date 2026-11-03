/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      00_Run_Full_Build.sql
Purpose:     Execute the complete SQL Server solution in dependency order.
Author:      Akshay Aswani
Version:     2.0
Location:    sql\00_orchestration\00_Run_Full_Build.sql

Execution requirements
----------------------
1. Keep this file inside sql\00_orchestration\.
2. Preserve the approved repository folder structure.
3. Open this file in SSMS and enable Query > SQLCMD Mode.
4. Execute only in an approved LOCAL, DEV, or TEST environment.
5. The referenced scripts stop the build when a critical validation fails.

Command-line example from sql\00_orchestration
-----------------------------------------------
sqlcmd -S <server> -E -b -i 00_Run_Full_Build.sql

Important
---------
- Relative paths are based on this file being in sql\00_orchestration\.
- Do not run this master script against production.
- Do not run it merely to test path changes against an existing completed build.
- Use a fresh database or follow the reset/rerun policy documented by each script.
*/

:ON ERROR EXIT

-- The parent of 00_orchestration is the sql folder.
:setvar SqlRoot ".."
:setvar DatabaseName "RetailIntelligenceDB"
:setvar BuildEnvironment "LOCAL"
:setvar GenerationProfile "BASELINE"
:setvar RandomSeed "20260921"
:setvar PeriodStartDate "2023-07-01"
:setvar PeriodEndDate "2026-06-30"
:setvar EnableDataReset "0"

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE
    @BuildStartDate DATETIME2(0) = SYSDATETIME(),
    @DatabaseName SYSNAME = N'$(DatabaseName)',
    @BuildEnvironment VARCHAR(30) = '$(BuildEnvironment)';

IF @DatabaseName <> N'RetailIntelligenceDB'
    THROW 51000, 'Build stopped: the approved database is RetailIntelligenceDB.', 1;

IF @BuildEnvironment NOT IN ('LOCAL', 'DEV', 'TEST')
    THROW 51001, 'Build stopped: allowed environments are LOCAL, DEV, and TEST.', 1;

RAISERROR('FULL BUILD STARTED | Database=%s | Environment=%s', 10, 1,
          @DatabaseName, @BuildEnvironment) WITH NOWAIT;

SELECT
    @BuildStartDate AS BuildStartDate,
    @@SERVERNAME AS SQLServerInstance,
    CONVERT(VARCHAR(128), SERVERPROPERTY('ProductVersion')) AS SQLServerVersion,
    @DatabaseName AS TargetDatabase,
    @BuildEnvironment AS BuildEnvironment,
    '$(GenerationProfile)' AS GenerationProfile,
    '$(RandomSeed)' AS RandomSeed,
    CONVERT(DATE, '$(PeriodStartDate)') AS PeriodStartDate,
    CONVERT(DATE, '$(PeriodEndDate)') AS PeriodEndDate;
GO

-- ============================================================================
-- PHASE 1: DATABASE FOUNDATION (01-09)
-- ============================================================================

RAISERROR('PHASE 1 START: Database foundation.', 10, 1) WITH NOWAIT;
GO

:r $(SqlRoot)\01_database_foundation\01_Create_Database.sql
:r $(SqlRoot)\01_database_foundation\02_Create_Schemas.sql
:r $(SqlRoot)\01_database_foundation\03_Create_Tables.sql
:r $(SqlRoot)\01_database_foundation\04_Create_Constraints.sql
:r $(SqlRoot)\01_database_foundation\05_Create_Indexes.sql
:r $(SqlRoot)\01_database_foundation\06_Create_Operational_Views.sql
:r $(SqlRoot)\01_database_foundation\07_Create_Stored_Procedures.sql
:r $(SqlRoot)\01_database_foundation\08_Create_Functions.sql
:r $(SqlRoot)\01_database_foundation\09_Validate_Trigger_Policy.sql

RAISERROR('PHASE 1 COMPLETE: Database foundation created and validated.', 10, 1) WITH NOWAIT;
GO

-- ============================================================================
-- PHASE 2: SYNTHETIC DATA GENERATION (10-21)
-- ============================================================================

RAISERROR('PHASE 2 START: Synthetic retail data generation.', 10, 1) WITH NOWAIT;
GO

:r $(SqlRoot)\02_data_generation\10_Load_Reference_Data.sql
:r $(SqlRoot)\02_data_generation\11_Generate_Stores.sql
:r $(SqlRoot)\02_data_generation\12_Generate_Employees.sql
:r $(SqlRoot)\02_data_generation\13_Generate_Customers.sql
:r $(SqlRoot)\02_data_generation\14_Generate_Suppliers.sql
:r $(SqlRoot)\02_data_generation\15_Generate_Products.sql
:r $(SqlRoot)\02_data_generation\16_Generate_Opening_Inventory.sql
:r $(SqlRoot)\02_data_generation\17_Generate_Sales_Orders.sql
:r $(SqlRoot)\02_data_generation\18_Generate_Order_Lifecycle.sql
:r $(SqlRoot)\02_data_generation\19_Generate_Payments.sql
:r $(SqlRoot)\02_data_generation\20_Generate_Returns_Refunds.sql
:r $(SqlRoot)\02_data_generation\21_Generate_Inventory_Movements.sql

RAISERROR('PHASE 2 COMPLETE: Operational dataset generated and validated.', 10, 1) WITH NOWAIT;
GO

-- ============================================================================
-- PHASE 3: ANALYTICS MODEL (22-26)
-- ============================================================================

RAISERROR('PHASE 3 START: Dimensional analytics model.', 10, 1) WITH NOWAIT;
GO

:r $(SqlRoot)\03_analytics_model\22_Create_Analytics_Dimensions.sql
:r $(SqlRoot)\03_analytics_model\23_Create_Analytics_Facts.sql
:r $(SqlRoot)\03_analytics_model\24_Create_Analytics_Views.sql
:r $(SqlRoot)\03_analytics_model\25_Create_Analytics_Indexes.sql
:r $(SqlRoot)\03_analytics_model\26_Validate_Analytics_Model.sql

RAISERROR('PHASE 3 COMPLETE: Analytics model created and validated.', 10, 1) WITH NOWAIT;
GO

-- ============================================================================
-- PHASE 4: BUSINESS ANALYSIS (27-35)
-- These scripts are read-only analytical workloads and validation evidence.
-- ============================================================================

RAISERROR('PHASE 4 START: Business analysis.', 10, 1) WITH NOWAIT;
GO

:r $(SqlRoot)\04_business_analysis\27_Executive_KPIs.sql
:r $(SqlRoot)\04_business_analysis\28_Sales_Analysis.sql
:r $(SqlRoot)\04_business_analysis\29_Customer_Analysis.sql
:r $(SqlRoot)\04_business_analysis\30_Product_Analysis.sql
:r $(SqlRoot)\04_business_analysis\31_Inventory_Analysis.sql
:r $(SqlRoot)\04_business_analysis\32_Store_Employee_Analysis.sql
:r $(SqlRoot)\04_business_analysis\33_Returns_Payments_Analysis.sql
:r $(SqlRoot)\04_business_analysis\34_Supplier_Analysis.sql
:r $(SqlRoot)\04_business_analysis\35_Advanced_Business_Analysis.sql

RAISERROR('PHASE 4 COMPLETE: Business analysis workloads passed.', 10, 1) WITH NOWAIT;
GO

-- ============================================================================
-- PHASE 5: QUALITY, POWER BI SEMANTIC LAYER, AND DEPLOYMENT (36-40)
-- ============================================================================

RAISERROR('PHASE 5 START: Quality and deployment certification.', 10, 1) WITH NOWAIT;
GO

:r $(SqlRoot)\05_quality_deployment\36_Data_Quality_Framework.sql
:r $(SqlRoot)\05_quality_deployment\37_Performance_Benchmarking.sql
:r $(SqlRoot)\05_quality_deployment\38_PowerBI_Reporting_Views.sql
:r $(SqlRoot)\05_quality_deployment\39_PowerBI_Model_Validation.sql
:r $(SqlRoot)\05_quality_deployment\40_Deployment_Health_Check.sql

RAISERROR('PHASE 5 COMPLETE: Quality and deployment certification passed.', 10, 1) WITH NOWAIT;
GO

-- ============================================================================
-- BUILD COMPLETION SUMMARY
-- ============================================================================

USE [$(DatabaseName)];
GO

SELECT
    N'Retail Sales & Inventory Intelligence Platform' AS ProjectName,
    N'2.0' AS ProjectVersion,
    DB_NAME() AS DatabaseName,
    '$(BuildEnvironment)' AS BuildEnvironment,
    (SELECT COUNT(*) FROM sys.tables) AS UserTableCount,
    (SELECT COUNT(*) FROM sys.views) AS UserViewCount,
    (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0) AS StoredProcedureCount,
    (SELECT COUNT(*) FROM sys.indexes WHERE index_id > 0 AND is_hypothetical = 0) AS IndexCount,
    SYSDATETIME() AS BuildEndDate,
    N'PASSED' AS BuildStatus,
    N'READY FOR POWER BI AND PORTFOLIO RELEASE' AS DeploymentStatus;
GO

RAISERROR('FULL BUILD PASSED: READY FOR POWER BI AND PORTFOLIO RELEASE.', 10, 1) WITH NOWAIT;
GO
