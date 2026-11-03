/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      13_Generate_Customers.sql
Purpose:     Generate 10,000 deterministic synthetic customer profiles.
Author:      Akshay Aswani
Version:     2.0
Depends on:  12_Generate_Employees.sql
Rerunnable:  Yes. Stable customer codes are updated; missing rows are inserted.

Behavior bands used by later transaction scripts
------------------------------------------------
- CUS00001-CUS01000: High Value / Loyal (10%)
- CUS01001-CUS04000: Regular (30%)
- CUS04001-CUS08500: Occasional (45%)
- CUS08501-CUS10000: One-Time / Dormant (15%)

Privacy and modeling notes
--------------------------
- All names, emails, phones, and addresses are fictional portfolio data.
- Controlled nulls support data-quality and Unknown-member reporting.
- Loyalty points begin at zero and will be recalculated after sales generation.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51230, 'Customer generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'core.Customer', N'U') IS NULL
BEGIN
    THROW 51231, 'Customer generation stopped: core.Customer is missing.', 1;
END;

DROP TABLE IF EXISTS #FirstName;
DROP TABLE IF EXISTS #LastName;
DROP TABLE IF EXISTS #Location;
DROP TABLE IF EXISTS #CustomerSeed;

CREATE TABLE #FirstName
(
    NameNumber TINYINT NOT NULL PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL
);

INSERT INTO #FirstName (NameNumber, FirstName) VALUES
(1,'Aarav'),(2,'Aditi'),(3,'Advait'),(4,'Ananya'),(5,'Arjun'),
(6,'Avni'),(7,'Dev'),(8,'Diya'),(9,'Ishaan'),(10,'Ishita'),
(11,'Kabir'),(12,'Kavya'),(13,'Manav'),(14,'Meera'),(15,'Nakul'),
(16,'Naina'),(17,'Rohan'),(18,'Riya'),(19,'Samar'),(20,'Sanya'),
(21,'Tanish'),(22,'Tara'),(23,'Vihaan'),(24,'Vriti'),(25,'Zoya');

CREATE TABLE #LastName
(
    NameNumber TINYINT NOT NULL PRIMARY KEY,
    LastName VARCHAR(50) NOT NULL
);

INSERT INTO #LastName (NameNumber, LastName) VALUES
(1,'Ahuja'),(2,'Bajaj'),(3,'Batra'),(4,'Chawla'),(5,'Desai'),
(6,'Gupta'),(7,'Iyer'),(8,'Jain'),(9,'Kapoor'),(10,'Khanna'),
(11,'Malhotra'),(12,'Mehta'),(13,'Nair'),(14,'Patel'),(15,'Rao'),
(16,'Saxena'),(17,'Shah'),(18,'Sharma'),(19,'Sinha'),(20,'Verma'),
(21,'Arora'),(22,'Bose'),(23,'Kulkarni'),(24,'Menon'),(25,'Reddy');

CREATE TABLE #Location
(
    LocationNumber TINYINT NOT NULL PRIMARY KEY,
    City VARCHAR(100) NOT NULL,
    StateName VARCHAR(100) NOT NULL,
    PostalCode VARCHAR(10) NOT NULL
);

INSERT INTO #Location (LocationNumber, City, StateName, PostalCode) VALUES
(1,'Jaipur','Rajasthan','302001'),
(2,'Delhi','Delhi','110085'),
(3,'Gurugram','Haryana','122009'),
(4,'Noida','Uttar Pradesh','201301'),
(5,'Chandigarh','Chandigarh','160022'),
(6,'Lucknow','Uttar Pradesh','226010'),
(7,'Ahmedabad','Gujarat','380009'),
(8,'Mumbai','Maharashtra','400053'),
(9,'Pune','Maharashtra','411045'),
(10,'Surat','Gujarat','395007'),
(11,'Vadodara','Gujarat','390007'),
(12,'Indore','Madhya Pradesh','452010'),
(13,'Bengaluru','Karnataka','560034'),
(14,'Hyderabad','Telangana','500081'),
(15,'Chennai','Tamil Nadu','600017'),
(16,'Kochi','Kerala','682024'),
(17,'Coimbatore','Tamil Nadu','641002'),
(18,'Kolkata','West Bengal','700091'),
(19,'Bhubaneswar','Odisha','751013'),
(20,'Raipur','Chhattisgarh','492001');

CREATE TABLE #CustomerSeed
(
    CustomerNumber INT NOT NULL PRIMARY KEY,
    CustomerCode VARCHAR(20) NOT NULL UNIQUE,
    BehaviorSegment VARCHAR(30) NOT NULL,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(150) NULL,
    Phone VARCHAR(20) NULL,
    AddressLine VARCHAR(255) NULL,
    City VARCHAR(100) NULL,
    StateName VARCHAR(100) NULL,
    PostalCode VARCHAR(10) NULL,
    Country VARCHAR(100) NULL,
    RegistrationDate DATE NOT NULL,
    LoyaltyPoints INT NOT NULL,
    IsActive BIT NOT NULL
);

;WITH Digits AS
(
    SELECT Digit
    FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS values_list (Digit)
),
Numbers AS
(
    SELECT TOP (10000)
        ROW_NUMBER() OVER
        (
            ORDER BY d4.Digit, d3.Digit, d2.Digit, d1.Digit
        ) AS CustomerNumber
    FROM Digits AS d1
    CROSS JOIN Digits AS d2
    CROSS JOIN Digits AS d3
    CROSS JOIN Digits AS d4
),
CustomerAttributes AS
(
    SELECT
        CONVERT(INT, n.CustomerNumber) AS CustomerNumber,
        ((CONVERT(INT, n.CustomerNumber) * 7 - 1) % 25) + 1 AS FirstNameNumber,
        ((CONVERT(INT, n.CustomerNumber) * 13 - 1) % 25) + 1 AS LastNameNumber,
        ((CONVERT(INT, n.CustomerNumber) * 17 - 1) % 20) + 1 AS LocationNumber
    FROM Numbers AS n
)
INSERT INTO #CustomerSeed
(
    CustomerNumber, CustomerCode, BehaviorSegment, FirstName, LastName,
    Email, Phone, AddressLine, City, StateName, PostalCode, Country,
    RegistrationDate, LoyaltyPoints, IsActive
)
SELECT
    a.CustomerNumber,
    CONCAT('CUS', RIGHT(CONCAT('00000', a.CustomerNumber), 5)),
    CASE
        WHEN a.CustomerNumber <= 1000 THEN 'High Value / Loyal'
        WHEN a.CustomerNumber <= 4000 THEN 'Regular'
        WHEN a.CustomerNumber <= 8500 THEN 'Occasional'
        ELSE 'One-Time / Dormant'
    END,
    first_name.FirstName,
    last_name.LastName,
    CASE
        WHEN a.CustomerNumber % 20 = 0 THEN NULL
        ELSE CONCAT(
            LOWER(first_name.FirstName), '.', LOWER(last_name.LastName),
            RIGHT(CONCAT('00000', a.CustomerNumber), 5),
            '@retailintelligence.example'
        )
    END,
    CASE
        WHEN a.CustomerNumber % 25 = 0 THEN NULL
        ELSE CONCAT('+91-', CONVERT(VARCHAR(10), CONVERT(BIGINT, 8000000000) + a.CustomerNumber))
    END,
    CASE
        WHEN a.CustomerNumber % 50 = 0 THEN NULL
        ELSE CONCAT(
            CONVERT(VARCHAR(10), 10 + (a.CustomerNumber % 890)),
            ' Synthetic Residency, Ward ',
            CONVERT(VARCHAR(10), 1 + (a.CustomerNumber % 40))
        )
    END,
    CASE WHEN a.CustomerNumber % 50 = 0 THEN NULL ELSE location.City END,
    CASE WHEN a.CustomerNumber % 50 = 0 THEN NULL ELSE location.StateName END,
    CASE WHEN a.CustomerNumber % 50 = 0 THEN NULL ELSE location.PostalCode END,
    CASE WHEN a.CustomerNumber % 50 = 0 THEN NULL ELSE 'India' END,
    DATEADD
    (
        DAY,
        (a.CustomerNumber * 37) % 1551,
        CONVERT(DATE, '2022-01-01')
    ),
    0,
    CASE WHEN a.CustomerNumber > 9500 THEN 0 ELSE 1 END
FROM CustomerAttributes AS a
INNER JOIN #FirstName AS first_name
    ON first_name.NameNumber = a.FirstNameNumber
INNER JOIN #LastName AS last_name
    ON last_name.NameNumber = a.LastNameNumber
INNER JOIN #Location AS location
    ON location.LocationNumber = a.LocationNumber;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE target
    SET FirstName = seed.FirstName,
        LastName = seed.LastName,
        Email = seed.Email,
        Phone = seed.Phone,
        AddressLine = seed.AddressLine,
        City = seed.City,
        State = seed.StateName,
        PostalCode = seed.PostalCode,
        Country = seed.Country,
        RegistrationDate = seed.RegistrationDate,
        LoyaltyPoints = seed.LoyaltyPoints,
        IsActive = seed.IsActive,
        ModifiedDate = SYSDATETIME()
    FROM core.Customer AS target
    INNER JOIN #CustomerSeed AS seed
        ON seed.CustomerCode = target.CustomerCode;

    INSERT INTO core.Customer
    (
        CustomerCode, FirstName, LastName, Email, Phone,
        AddressLine, City, State, PostalCode, Country,
        RegistrationDate, LoyaltyPoints, IsActive
    )
    SELECT
        seed.CustomerCode, seed.FirstName, seed.LastName, seed.Email, seed.Phone,
        seed.AddressLine, seed.City, seed.StateName, seed.PostalCode, seed.Country,
        seed.RegistrationDate, seed.LoyaltyPoints, seed.IsActive
    FROM #CustomerSeed AS seed
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM core.Customer AS target
        WHERE target.CustomerCode = seed.CustomerCode
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @ApprovedCustomerCount INT =
(
    SELECT COUNT(*)
    FROM core.Customer
    WHERE CustomerCode IN (SELECT CustomerCode FROM #CustomerSeed)
);

DECLARE @TotalCustomerCount INT = (SELECT COUNT(*) FROM core.Customer);

IF @ApprovedCustomerCount <> 10000 OR @TotalCustomerCount <> 10000
BEGIN
    THROW 51232, 'Customer validation failed: expected exactly 10,000 approved customers.', 1;
END;

IF EXISTS
(
    SELECT Email
    FROM core.Customer
    WHERE Email IS NOT NULL
    GROUP BY Email
    HAVING COUNT(*) > 1
)
BEGIN
    THROW 51233, 'Customer validation failed: duplicate populated email detected.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM core.Customer
    WHERE LoyaltyPoints < 0
       OR RegistrationDate < '2022-01-01'
       OR RegistrationDate > '2026-03-31'
)
BEGIN
    THROW 51234, 'Customer validation failed: invalid loyalty points or registration date.', 1;
END;

IF (SELECT COUNT(*) FROM core.Customer WHERE Email IS NULL) <> 500
   OR (SELECT COUNT(*) FROM core.Customer WHERE Phone IS NULL) <> 400
   OR (SELECT COUNT(*) FROM core.Customer WHERE City IS NULL) <> 200
   OR (SELECT COUNT(*) FROM core.Customer WHERE IsActive = 0) <> 500
BEGIN
    THROW 51235, 'Customer validation failed: controlled-null or activity distribution differs from design.', 1;
END;

SELECT
    seed.BehaviorSegment,
    COUNT(*) AS ExpectedCustomerCount,
    COUNT(customer.CustomerID) AS ExistingCustomerCount,
    SUM(CASE WHEN customer.IsActive = 1 THEN 1 ELSE 0 END) AS ActiveCustomerCount,
    SUM(CASE WHEN customer.IsActive = 0 THEN 1 ELSE 0 END) AS InactiveCustomerCount,
    CASE WHEN COUNT(*) = COUNT(customer.CustomerID) THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM #CustomerSeed AS seed
LEFT JOIN core.Customer AS customer
    ON customer.CustomerCode = seed.CustomerCode
GROUP BY seed.BehaviorSegment
ORDER BY MIN(seed.CustomerNumber);

SELECT
    @ApprovedCustomerCount AS ApprovedCustomerCount,
    @TotalCustomerCount AS TotalCustomerCount,
    COUNT(DISTINCT City) AS PopulatedCityCount,
    SUM(CASE WHEN Email IS NULL THEN 1 ELSE 0 END) AS MissingEmailCount,
    SUM(CASE WHEN Phone IS NULL THEN 1 ELSE 0 END) AS MissingPhoneCount,
    SUM(CASE WHEN City IS NULL THEN 1 ELSE 0 END) AS MissingGeographyCount,
    SUM(CASE WHEN IsActive = 1 THEN 1 ELSE 0 END) AS ActiveCustomerCount,
    SUM(CASE WHEN IsActive = 0 THEN 1 ELSE 0 END) AS InactiveCustomerCount,
    MIN(RegistrationDate) AS EarliestRegistrationDate,
    MAX(RegistrationDate) AS LatestRegistrationDate,
    CASE
        WHEN @ApprovedCustomerCount = 10000
         AND @TotalCustomerCount = 10000
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM core.Customer;

RAISERROR('13_Generate_Customers.sql completed successfully: 10,000 synthetic customers validated.', 10, 1) WITH NOWAIT;
GO
