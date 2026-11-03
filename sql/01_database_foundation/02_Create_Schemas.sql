/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      02_Create_Schemas.sql
Purpose:     Create and validate the six approved Version 2 database schemas.
Author:      Akshay Aswani
Version:     2.0
Depends on:  01_Create_Database.sql
Rerunnable:  Yes. Existing approved schemas are preserved and validated.

Approved schemas
----------------
ref        Controlled classifications, statuses and movement types
core       Master business entities
sales      Orders, payments, returns and refunds
inventory  Inventory balances and movement events
audit      Validation execution history
analytics  Power BI-ready dimensions, facts and reporting objects
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExpectedDatabaseName SYSNAME = N'$(DatabaseName)';

IF DB_NAME() <> @ExpectedDatabaseName
BEGIN
    THROW 51010, 'Schema creation stopped: unexpected database context.', 1;
END;

IF @ExpectedDatabaseName <> N'RetailIntelligenceDB'
BEGIN
    THROW 51011, 'Schema creation stopped: the approved database name is RetailIntelligenceDB.', 1;
END;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'ref') IS NULL
        EXEC(N'CREATE SCHEMA [ref] AUTHORIZATION [dbo];');

    IF SCHEMA_ID(N'core') IS NULL
        EXEC(N'CREATE SCHEMA [core] AUTHORIZATION [dbo];');

    IF SCHEMA_ID(N'sales') IS NULL
        EXEC(N'CREATE SCHEMA [sales] AUTHORIZATION [dbo];');

    IF SCHEMA_ID(N'inventory') IS NULL
        EXEC(N'CREATE SCHEMA [inventory] AUTHORIZATION [dbo];');

    IF SCHEMA_ID(N'audit') IS NULL
        EXEC(N'CREATE SCHEMA [audit] AUTHORIZATION [dbo];');

    IF SCHEMA_ID(N'analytics') IS NULL
        EXEC(N'CREATE SCHEMA [analytics] AUTHORIZATION [dbo];');

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

DECLARE @RequiredSchemas TABLE
(
    SchemaName SYSNAME NOT NULL PRIMARY KEY,
    SchemaPurpose VARCHAR(200) NOT NULL
);

INSERT INTO @RequiredSchemas
(
    SchemaName,
    SchemaPurpose
)
VALUES
    (N'ref',       'Controlled classifications, statuses and movement types'),
    (N'core',      'Stores, employees, customers, suppliers and products'),
    (N'sales',     'Orders, status history, payments, returns and refunds'),
    (N'inventory', 'Current inventory balances and immutable movement events'),
    (N'audit',     'Validation runs, results and quality evidence'),
    (N'analytics', 'Power BI-ready dimensions, facts and reporting objects');

DECLARE
    @MissingSchemaCount INT,
    @IncorrectOwnerCount INT;

SELECT
    @MissingSchemaCount = COUNT(*)
FROM @RequiredSchemas AS rs
LEFT JOIN sys.schemas AS s
    ON s.name = rs.SchemaName
WHERE s.schema_id IS NULL;

IF @MissingSchemaCount > 0
BEGIN
    SELECT
        rs.SchemaName AS MissingSchema
    FROM @RequiredSchemas AS rs
    LEFT JOIN sys.schemas AS s
        ON s.name = rs.SchemaName
    WHERE s.schema_id IS NULL
    ORDER BY
        rs.SchemaName;

    THROW 51012, 'Schema validation failed: one or more required schemas are missing.', 1;
END;

SELECT
    @IncorrectOwnerCount = COUNT(*)
FROM @RequiredSchemas AS rs
INNER JOIN sys.schemas AS s
    ON s.name = rs.SchemaName
INNER JOIN sys.database_principals AS dp
    ON dp.principal_id = s.principal_id
WHERE dp.name <> N'dbo';

IF @IncorrectOwnerCount > 0
BEGIN
    SELECT
        rs.SchemaName,
        dp.name AS ActualOwner,
        N'dbo' AS ExpectedOwner
    FROM @RequiredSchemas AS rs
    INNER JOIN sys.schemas AS s
        ON s.name = rs.SchemaName
    INNER JOIN sys.database_principals AS dp
        ON dp.principal_id = s.principal_id
    WHERE dp.name <> N'dbo'
    ORDER BY
        rs.SchemaName;

    THROW 51013, 'Schema validation failed: one or more required schemas are not owned by dbo.', 1;
END;

SELECT
    rs.SchemaName,
    rs.SchemaPurpose,
    s.schema_id AS SchemaID,
    dp.name AS SchemaOwner,
    COUNT(o.object_id) AS CurrentObjectCount,
    CASE
        WHEN s.schema_id IS NOT NULL AND dp.name = N'dbo' THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM @RequiredSchemas AS rs
INNER JOIN sys.schemas AS s
    ON s.name = rs.SchemaName
INNER JOIN sys.database_principals AS dp
    ON dp.principal_id = s.principal_id
LEFT JOIN sys.objects AS o
    ON o.schema_id = s.schema_id
   AND o.is_ms_shipped = 0
GROUP BY
    rs.SchemaName,
    rs.SchemaPurpose,
    s.schema_id,
    dp.name
ORDER BY
    CASE rs.SchemaName
        WHEN N'ref' THEN 1
        WHEN N'core' THEN 2
        WHEN N'sales' THEN 3
        WHEN N'inventory' THEN 4
        WHEN N'audit' THEN 5
        WHEN N'analytics' THEN 6
        ELSE 99
    END;

RAISERROR('02_Create_Schemas.sql completed successfully: 6 required schemas validated.', 10, 1) WITH NOWAIT;
GO
