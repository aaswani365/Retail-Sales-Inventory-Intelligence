/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      12_Generate_Employees.sql
Purpose:     Generate 100 synthetic employees and valid store hierarchies.
Author:      Akshay Aswani
Version:     2.0
Depends on:  11_Generate_Stores.sql
Rerunnable:  Yes. Stable employee codes are updated; missing rows are inserted.

Approved role mix
-----------------
- Store Manager:          20
- Senior Sales Associate: 20
- Sales Associate:        45
- Inventory Coordinator:  15

Every store receives five employees and exactly one store manager.
All people and contact details are fictional portfolio data.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51220, 'Employee generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'core.Employee', N'U') IS NULL OR OBJECT_ID(N'core.Store', N'U') IS NULL
BEGIN
    THROW 51221, 'Employee generation stopped: required core tables are missing.', 1;
END;

IF (SELECT COUNT(*) FROM core.Store) <> 20
BEGIN
    THROW 51222, 'Employee generation stopped: exactly 20 stores are required.', 1;
END;

DROP TABLE IF EXISTS #FirstName;
DROP TABLE IF EXISTS #LastName;
DROP TABLE IF EXISTS #EmployeeSeed;

CREATE TABLE #FirstName (NameNumber TINYINT PRIMARY KEY, FirstName VARCHAR(50) NOT NULL);
INSERT INTO #FirstName VALUES
(1,'Aarav'),(2,'Aditi'),(3,'Arjun'),(4,'Ananya'),(5,'Dev'),
(6,'Diya'),(7,'Ishaan'),(8,'Ishita'),(9,'Kabir'),(10,'Kavya'),
(11,'Manav'),(12,'Meera'),(13,'Nakul'),(14,'Naina'),(15,'Rohan'),
(16,'Riya'),(17,'Samar'),(18,'Sanya'),(19,'Vihaan'),(20,'Zara');

CREATE TABLE #LastName (NameNumber TINYINT PRIMARY KEY, LastName VARCHAR(50) NOT NULL);
INSERT INTO #LastName VALUES
(1,'Ahuja'),(2,'Bajaj'),(3,'Batra'),(4,'Chawla'),(5,'Desai'),
(6,'Gupta'),(7,'Iyer'),(8,'Jain'),(9,'Kapoor'),(10,'Khanna'),
(11,'Malhotra'),(12,'Mehta'),(13,'Nair'),(14,'Patel'),(15,'Rao'),
(16,'Saxena'),(17,'Shah'),(18,'Sharma'),(19,'Sinha'),(20,'Verma');

CREATE TABLE #EmployeeSeed
(
    EmployeeNumber INT NOT NULL PRIMARY KEY,
    EmployeeCode VARCHAR(20) NOT NULL UNIQUE,
    StoreCode VARCHAR(20) NOT NULL,
    StoreSlot TINYINT NOT NULL,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(150) NOT NULL,
    Phone VARCHAR(20) NOT NULL,
    JobTitle VARCHAR(100) NOT NULL,
    Salary DECIMAL(12,2) NOT NULL,
    HireDate DATE NOT NULL,
    TerminationDate DATE NULL,
    IsActive BIT NOT NULL
);

;WITH RankedStores AS
(
    SELECT
        StoreCode,
        OpeningDate,
        ROW_NUMBER() OVER (ORDER BY StoreCode) AS StoreNumber
    FROM core.Store
),
Slots AS
(
    SELECT StoreSlot
    FROM (VALUES (1), (2), (3), (4), (5)) AS value_list (StoreSlot)
),
EmployeeNumbers AS
(
    SELECT
        rs.StoreCode,
        rs.OpeningDate,
        rs.StoreNumber,
        slots.StoreSlot,
        CONVERT(INT, ((rs.StoreNumber - 1) * 5) + slots.StoreSlot) AS EmployeeNumber
    FROM RankedStores AS rs
    CROSS JOIN Slots AS slots
)
INSERT INTO #EmployeeSeed
(
    EmployeeNumber, EmployeeCode, StoreCode, StoreSlot,
    FirstName, LastName, Email, Phone, JobTitle,
    Salary, HireDate, TerminationDate, IsActive
)
SELECT
    numbers.EmployeeNumber,
    CONCAT('EMP', RIGHT(CONCAT('0000', numbers.EmployeeNumber), 4)),
    numbers.StoreCode,
    numbers.StoreSlot,
    first_name.FirstName,
    last_name.LastName,
    CONCAT(LOWER(first_name.FirstName), '.', LOWER(last_name.LastName),
           RIGHT(CONCAT('0000', numbers.EmployeeNumber), 4), '@retailintelligence.example'),
    CONCAT('+91-', CONVERT(VARCHAR(10), CONVERT(BIGINT, 7000000000) + numbers.EmployeeNumber)),
    CASE
        WHEN numbers.StoreSlot = 1 THEN 'Store Manager'
        WHEN numbers.StoreSlot = 2 THEN 'Senior Sales Associate'
        WHEN numbers.StoreSlot IN (3, 4) THEN 'Sales Associate'
        WHEN numbers.StoreNumber <= 5 THEN 'Sales Associate'
        ELSE 'Inventory Coordinator'
    END,
    CONVERT(DECIMAL(12,2),
        CASE
            WHEN numbers.StoreSlot = 1 THEN 900000 + (numbers.StoreNumber * 5000)
            WHEN numbers.StoreSlot = 2 THEN 600000 + (numbers.StoreNumber * 3000)
            WHEN numbers.StoreSlot IN (3, 4) OR numbers.StoreNumber <= 5
                THEN 420000 + (numbers.StoreNumber * 2000) + (numbers.StoreSlot * 1500)
            ELSE 500000 + (numbers.StoreNumber * 2000)
        END),
    DATEADD(DAY, 30 + ((numbers.EmployeeNumber * 17) % 720), numbers.OpeningDate),
    CASE
        WHEN numbers.EmployeeNumber IN (3, 14, 23, 34, 43, 54, 63, 74)
        THEN CONVERT(DATE, DATEADD(DAY, 1100 + numbers.EmployeeNumber, numbers.OpeningDate))
        ELSE NULL
    END,
    CASE WHEN numbers.EmployeeNumber IN (3, 14, 23, 34, 43, 54, 63, 74) THEN 0 ELSE 1 END
FROM EmployeeNumbers AS numbers
INNER JOIN #FirstName AS first_name
    ON first_name.NameNumber = ((numbers.EmployeeNumber - 1) % 20) + 1
INNER JOIN #LastName AS last_name
    ON last_name.NameNumber = (((numbers.EmployeeNumber * 7) - 1) % 20) + 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Phase 1: create/update employee attributes without hierarchy references.
    UPDATE target
    SET StoreID = s.StoreID,
        FirstName = seed.FirstName,
        LastName = seed.LastName,
        Email = seed.Email,
        Phone = seed.Phone,
        JobTitle = seed.JobTitle,
        Salary = seed.Salary,
        HireDate = seed.HireDate,
        TerminationDate = seed.TerminationDate,
        IsActive = seed.IsActive,
        ModifiedDate = SYSDATETIME()
    FROM core.Employee AS target
    INNER JOIN #EmployeeSeed AS seed ON seed.EmployeeCode = target.EmployeeCode
    INNER JOIN core.Store AS s ON s.StoreCode = seed.StoreCode;

    INSERT INTO core.Employee
    (
        EmployeeCode, StoreID, ManagerEmployeeID, FirstName, LastName,
        Email, Phone, JobTitle, Salary, HireDate, TerminationDate, IsActive
    )
    SELECT
        seed.EmployeeCode, s.StoreID, NULL, seed.FirstName, seed.LastName,
        seed.Email, seed.Phone, seed.JobTitle, seed.Salary,
        seed.HireDate, seed.TerminationDate, seed.IsActive
    FROM #EmployeeSeed AS seed
    INNER JOIN core.Store AS s ON s.StoreCode = seed.StoreCode
    WHERE NOT EXISTS
    (
        SELECT 1 FROM core.Employee AS target
        WHERE target.EmployeeCode = seed.EmployeeCode
    );

    -- Phase 2: managers have no manager; every other employee reports to the manager of the same store.
    UPDATE employee
    SET ManagerEmployeeID = CASE WHEN seed.StoreSlot = 1 THEN NULL ELSE manager.EmployeeID END,
        ModifiedDate = SYSDATETIME()
    FROM core.Employee AS employee
    INNER JOIN #EmployeeSeed AS seed ON seed.EmployeeCode = employee.EmployeeCode
    INNER JOIN #EmployeeSeed AS manager_seed
        ON manager_seed.StoreCode = seed.StoreCode
       AND manager_seed.StoreSlot = 1
    INNER JOIN core.Employee AS manager
        ON manager.EmployeeCode = manager_seed.EmployeeCode;

    -- Phase 3: resolve the deferred Store -> Employee circular relationship.
    UPDATE store
    SET ManagerEmployeeID = manager.EmployeeID,
        ModifiedDate = SYSDATETIME()
    FROM core.Store AS store
    INNER JOIN #EmployeeSeed AS manager_seed
        ON manager_seed.StoreCode = store.StoreCode
       AND manager_seed.StoreSlot = 1
    INNER JOIN core.Employee AS manager
        ON manager.EmployeeCode = manager_seed.EmployeeCode;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @ApprovedEmployeeCount INT =
(
    SELECT COUNT(*)
    FROM core.Employee
    WHERE EmployeeCode IN (SELECT EmployeeCode FROM #EmployeeSeed)
);

DECLARE @TotalEmployeeCount INT = (SELECT COUNT(*) FROM core.Employee);

IF @ApprovedEmployeeCount <> 100 OR @TotalEmployeeCount <> 100
    THROW 51223, 'Employee validation failed: expected exactly 100 approved employees.', 1;

IF EXISTS
(
    SELECT 1
    FROM core.Employee AS e
    INNER JOIN core.Employee AS manager ON manager.EmployeeID = e.ManagerEmployeeID
    WHERE e.StoreID <> manager.StoreID OR e.EmployeeID = manager.EmployeeID
)
    THROW 51224, 'Employee validation failed: invalid cross-store or self-manager relationship.', 1;

IF EXISTS
(
    SELECT 1
    FROM core.Store AS s
    LEFT JOIN core.Employee AS manager ON manager.EmployeeID = s.ManagerEmployeeID
    WHERE manager.EmployeeID IS NULL
       OR manager.StoreID <> s.StoreID
       OR manager.JobTitle <> 'Store Manager'
       OR manager.IsActive <> 1
)
    THROW 51225, 'Employee validation failed: one or more stores lack a valid active manager.', 1;

IF EXISTS
(
    SELECT 1 FROM core.Employee
    WHERE (IsActive = 1 AND TerminationDate IS NOT NULL)
       OR (IsActive = 0 AND TerminationDate IS NULL)
       OR (TerminationDate IS NOT NULL AND TerminationDate < HireDate)
)
    THROW 51226, 'Employee validation failed: invalid active or employment-date combination.', 1;

SELECT
    JobTitle,
    COUNT(*) AS EmployeeCount,
    SUM(CASE WHEN IsActive = 1 THEN 1 ELSE 0 END) AS ActiveEmployeeCount,
    SUM(CASE WHEN IsActive = 0 THEN 1 ELSE 0 END) AS InactiveEmployeeCount,
    MIN(Salary) AS MinimumSalary,
    MAX(Salary) AS MaximumSalary,
    'PASSED' AS ValidationStatus
FROM core.Employee
GROUP BY JobTitle
ORDER BY
    CASE JobTitle
        WHEN 'Store Manager' THEN 1
        WHEN 'Senior Sales Associate' THEN 2
        WHEN 'Sales Associate' THEN 3
        ELSE 4
    END;

SELECT
    @ApprovedEmployeeCount AS ApprovedEmployeeCount,
    @TotalEmployeeCount AS TotalEmployeeCount,
    COUNT(DISTINCT StoreID) AS StoreCount,
    SUM(CASE WHEN ManagerEmployeeID IS NULL THEN 1 ELSE 0 END) AS TopLevelManagerCount,
    SUM(CASE WHEN IsActive = 1 THEN 1 ELSE 0 END) AS ActiveEmployeeCount,
    SUM(CASE WHEN IsActive = 0 THEN 1 ELSE 0 END) AS InactiveEmployeeCount,
    CASE
        WHEN @ApprovedEmployeeCount = 100
         AND @TotalEmployeeCount = 100
         AND COUNT(DISTINCT StoreID) = 20
         AND SUM(CASE WHEN ManagerEmployeeID IS NULL THEN 1 ELSE 0 END) = 20
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM core.Employee;

RAISERROR('12_Generate_Employees.sql completed successfully: 100 synthetic employees validated.', 10, 1) WITH NOWAIT;
GO
