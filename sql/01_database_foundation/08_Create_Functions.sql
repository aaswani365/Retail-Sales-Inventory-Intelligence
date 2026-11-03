/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      08_Create_Functions.sql
Purpose:     Create a minimal set of deterministic reporting helper functions.
Author:      Akshay Aswani
Version:     2.0
Depends on:  02_Create_Schemas.sql
Rerunnable:  Yes. CREATE OR ALTER replaces definitions without dropping permissions.

Function policy
---------------
- Functions are limited to stable, reusable calendar derivations.
- Large transactional calculations remain set-based in views and procedures.
- SCHEMABINDING documents deterministic dependencies and supports reuse.
- Indian financial year begins on 1 April.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51070, 'Function creation stopped: unexpected database context.', 1;
END;

IF SCHEMA_ID(N'analytics') IS NULL
BEGIN
    THROW 51071, 'Function creation stopped: analytics schema is missing.', 1;
END;
GO

-- Example: 2024-04-01 returns FY2024-25; 2024-03-31 returns FY2023-24.
CREATE OR ALTER FUNCTION analytics.ufn_FinancialYear
(
    @CalendarDate DATE
)
RETURNS VARCHAR(9)
WITH SCHEMABINDING
AS
BEGIN
    IF @CalendarDate IS NULL
        RETURN NULL;

    DECLARE @StartYear INT =
        CASE WHEN MONTH(@CalendarDate) >= 4
             THEN YEAR(@CalendarDate)
             ELSE YEAR(@CalendarDate) - 1
        END;

    RETURN
    (
        CONCAT
        (
            'FY',
            CONVERT(CHAR(4), @StartYear),
            '-',
            RIGHT(CONVERT(CHAR(4), @StartYear + 1), 2)
        )
    );
END;
GO

-- Indian fiscal quarters: Apr-Jun Q1, Jul-Sep Q2, Oct-Dec Q3, Jan-Mar Q4.
CREATE OR ALTER FUNCTION analytics.ufn_FinancialQuarter
(
    @CalendarDate DATE
)
RETURNS CHAR(2)
WITH SCHEMABINDING
AS
BEGIN
    IF @CalendarDate IS NULL
        RETURN NULL;

    RETURN
    (
        CASE
            WHEN MONTH(@CalendarDate) BETWEEN 4 AND 6 THEN 'Q1'
            WHEN MONTH(@CalendarDate) BETWEEN 7 AND 9 THEN 'Q2'
            WHEN MONTH(@CalendarDate) BETWEEN 10 AND 12 THEN 'Q3'
            ELSE 'Q4'
        END
    );
END;
GO

-- Surrogate date key in YYYYMMDD integer form; example 2026-09-22 returns 20260922.
CREATE OR ALTER FUNCTION analytics.ufn_DateKey
(
    @CalendarDate DATE
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    IF @CalendarDate IS NULL
        RETURN NULL;

    RETURN
    (
        (YEAR(@CalendarDate) * 10000)
        + (MONTH(@CalendarDate) * 100)
        + DAY(@CalendarDate)
    );
END;
GO

DECLARE @ExpectedFunctions TABLE
(
    FunctionSequence TINYINT NOT NULL PRIMARY KEY,
    SchemaName SYSNAME NOT NULL,
    FunctionName SYSNAME NOT NULL,
    ExpectedType CHAR(2) NOT NULL,
    Purpose VARCHAR(150) NOT NULL
);

INSERT INTO @ExpectedFunctions VALUES
(1, N'analytics', N'ufn_FinancialYear', 'FN', 'Return Indian financial-year label'),
(2, N'analytics', N'ufn_FinancialQuarter', 'FN', 'Return Indian financial quarter'),
(3, N'analytics', N'ufn_DateKey', 'FN', 'Return integer date key in YYYYMMDD form');

IF EXISTS
(
    SELECT 1
    FROM @ExpectedFunctions AS ef
    WHERE OBJECT_ID(QUOTENAME(ef.SchemaName) + N'.' + QUOTENAME(ef.FunctionName), ef.ExpectedType) IS NULL
)
BEGIN
    THROW 51072, 'Function validation failed: one or more approved functions are missing.', 1;
END;

SELECT
    ef.FunctionSequence,
    ef.SchemaName,
    ef.FunctionName,
    ef.Purpose,
    sm.is_schema_bound AS IsSchemaBound,
    CASE
        WHEN o.object_id IS NOT NULL AND sm.is_schema_bound = 1 THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM @ExpectedFunctions AS ef
LEFT JOIN sys.objects AS o
    ON o.object_id = OBJECT_ID(QUOTENAME(ef.SchemaName) + N'.' + QUOTENAME(ef.FunctionName), ef.ExpectedType)
LEFT JOIN sys.sql_modules AS sm
    ON sm.object_id = o.object_id
ORDER BY ef.FunctionSequence;

SELECT
    TestDate,
    analytics.ufn_FinancialYear(TestDate) AS FinancialYear,
    analytics.ufn_FinancialQuarter(TestDate) AS FinancialQuarter,
    analytics.ufn_DateKey(TestDate) AS DateKey
FROM
(
    VALUES
        (CONVERT(DATE, '2024-03-31')),
        (CONVERT(DATE, '2024-04-01')),
        (CONVERT(DATE, '2026-09-22'))
) AS tests (TestDate)
ORDER BY TestDate;

RAISERROR('08_Create_Functions.sql completed successfully: 3 approved functions validated.', 10, 1) WITH NOWAIT;
GO
