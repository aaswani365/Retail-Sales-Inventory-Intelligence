/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      01_Create_Database.sql
Purpose:     Safely create and validate the Version 2 project database.
Author:      Akshay Aswani
Version:     2.0
Depends on:  None
Rerunnable:  Yes. Creates the database only when it does not already exist.

Safety policy
-------------
- This script never drops an existing database.
- It accepts only the approved database name: RetailIntelligenceDB.
- Portfolio-friendly options are applied only when this run creates the database.
- An existing database is validated but not silently reconfigured.

Execution
---------
Run in SQLCMD mode or through 00_Run_Full_Build.sql.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"
:setvar BuildEnvironment "LOCAL"

USE [master];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE
    @DatabaseName SYSNAME = N'$(DatabaseName)',
    @BuildEnvironment VARCHAR(30) = '$(BuildEnvironment)';

IF @DatabaseName <> N'RetailIntelligenceDB'
BEGIN
    THROW 51000, 'Database creation stopped: the approved database name is RetailIntelligenceDB.', 1;
END;

IF @BuildEnvironment NOT IN ('LOCAL', 'DEV', 'TEST')
BEGIN
    THROW 51001, 'Database creation stopped: environment must be LOCAL, DEV, or TEST.', 1;
END;

IF DB_ID(@DatabaseName) IN (1, 2, 3, 4)
BEGIN
    THROW 51002, 'Database creation stopped: system databases cannot be project targets.', 1;
END;

IF OBJECT_ID('tempdb..#DatabaseBuildState') IS NOT NULL
    DROP TABLE #DatabaseBuildState;

CREATE TABLE #DatabaseBuildState
(
    DatabaseName SYSNAME NOT NULL,
    WasCreated BIT NOT NULL,
    BuildEnvironment VARCHAR(30) NOT NULL,
    ActionMessage VARCHAR(200) NOT NULL
);

IF DB_ID(@DatabaseName) IS NULL
BEGIN
    RAISERROR('Creating database %s.', 10, 1, @DatabaseName) WITH NOWAIT;

    CREATE DATABASE [RetailIntelligenceDB];

    INSERT INTO #DatabaseBuildState
    (
        DatabaseName,
        WasCreated,
        BuildEnvironment,
        ActionMessage
    )
    VALUES
    (
        @DatabaseName,
        1,
        @BuildEnvironment,
        'Database created during this execution.'
    );
END;
ELSE
BEGIN
    INSERT INTO #DatabaseBuildState
    (
        DatabaseName,
        WasCreated,
        BuildEnvironment,
        ActionMessage
    )
    VALUES
    (
        @DatabaseName,
        0,
        @BuildEnvironment,
        'Database already existed; no destructive action was taken.'
    );

    RAISERROR('Database %s already exists; validating current state.', 10, 1, @DatabaseName) WITH NOWAIT;
END;
GO

-- Apply the approved local portfolio configuration only to a database created
-- by this execution. Existing databases are reported without silent changes.
IF EXISTS
(
    SELECT 1
    FROM #DatabaseBuildState
    WHERE WasCreated = 1
)
BEGIN
    ALTER DATABASE [RetailIntelligenceDB]
        SET RECOVERY SIMPLE
        WITH NO_WAIT;

    ALTER DATABASE [RetailIntelligenceDB]
        SET PAGE_VERIFY CHECKSUM
        WITH NO_WAIT;

    ALTER DATABASE [RetailIntelligenceDB]
        SET AUTO_CLOSE OFF
        WITH NO_WAIT;

    ALTER DATABASE [RetailIntelligenceDB]
        SET AUTO_SHRINK OFF
        WITH NO_WAIT;

    ALTER DATABASE [RetailIntelligenceDB]
        SET AUTO_CREATE_STATISTICS ON;

    ALTER DATABASE [RetailIntelligenceDB]
        SET AUTO_UPDATE_STATISTICS ON;

    ALTER DATABASE [RetailIntelligenceDB]
        SET READ_COMMITTED_SNAPSHOT ON
        WITH ROLLBACK IMMEDIATE;

    ALTER DATABASE [RetailIntelligenceDB]
        SET ALLOW_SNAPSHOT_ISOLATION ON;

    RAISERROR('New database configuration applied successfully.', 10, 1) WITH NOWAIT;
END;
GO

DECLARE
    @DatabaseName SYSNAME = N'$(DatabaseName)',
    @DatabaseStateDesc NVARCHAR(60),
    @UserAccessDesc NVARCHAR(60),
    @IsReadOnly BIT;

SELECT
    @DatabaseStateDesc = d.state_desc,
    @UserAccessDesc = d.user_access_desc,
    @IsReadOnly = d.is_read_only
FROM sys.databases AS d
WHERE d.name = @DatabaseName;

IF @DatabaseStateDesc IS NULL
BEGIN
    THROW 51003, 'Database validation failed: target database was not found after creation step.', 1;
END;

IF @DatabaseStateDesc <> N'ONLINE'
BEGIN
    THROW 51004, 'Database validation failed: target database is not ONLINE.', 1;
END;

IF @UserAccessDesc <> N'MULTI_USER'
BEGIN
    THROW 51005, 'Database validation failed: target database is not in MULTI_USER mode.', 1;
END;

IF @IsReadOnly = 1
BEGIN
    THROW 51006, 'Database validation failed: target database is READ_ONLY.', 1;
END;

RAISERROR('Database state validation passed.', 10, 1) WITH NOWAIT;
GO

USE [RetailIntelligenceDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExpectedDatabaseName SYSNAME = N'$(DatabaseName)';

IF DB_NAME() <> @ExpectedDatabaseName
BEGIN
    THROW 51007, 'Database context validation failed.', 1;
END;

SELECT
    d.name AS DatabaseName,
    CASE
        WHEN s.WasCreated = 1 THEN 'CREATED'
        ELSE 'ALREADY_EXISTS'
    END AS DatabaseAction,
    s.BuildEnvironment,
    d.state_desc AS DatabaseState,
    d.user_access_desc AS UserAccess,
    d.recovery_model_desc AS RecoveryModel,
    d.page_verify_option_desc AS PageVerifyOption,
    d.snapshot_isolation_state_desc AS SnapshotIsolationState,
    d.is_read_committed_snapshot_on AS IsReadCommittedSnapshotOn,
    d.is_auto_close_on AS IsAutoCloseOn,
    d.is_auto_shrink_on AS IsAutoShrinkOn,
    d.is_auto_create_stats_on AS IsAutoCreateStatisticsOn,
    d.is_auto_update_stats_on AS IsAutoUpdateStatisticsOn,
    d.compatibility_level AS CompatibilityLevel,
    s.ActionMessage
FROM sys.databases AS d
CROSS JOIN #DatabaseBuildState AS s
WHERE d.name = @ExpectedDatabaseName;

RAISERROR('01_Create_Database.sql completed successfully.', 10, 1) WITH NOWAIT;
GO
