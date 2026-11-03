/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      14_Generate_Suppliers.sql
Purpose:     Generate 50 deterministic synthetic suppliers.
Author:      Akshay Aswani
Version:     2.0
Depends on:  13_Generate_Customers.sql
Rerunnable:  Yes. Stable supplier codes are updated; missing rows are inserted.

Supplier groups used by later product generation
------------------------------------------------
- SUP001-SUP010: Strategic (20% of suppliers; about 50% of products)
- SUP011-SUP035: Standard  (50% of suppliers; about 40% of products)
- SUP036-SUP050: Niche     (30% of suppliers; about 10% of products)

All company names, contacts, emails, phones, and addresses are fictional.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51240, 'Supplier generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'core.Supplier', N'U') IS NULL
BEGIN
    THROW 51241, 'Supplier generation stopped: core.Supplier is missing.', 1;
END;

DROP TABLE IF EXISTS #FirstName;
DROP TABLE IF EXISTS #LastName;
DROP TABLE IF EXISTS #Location;
DROP TABLE IF EXISTS #SupplierSeed;

CREATE TABLE #FirstName
(
    NameNumber TINYINT NOT NULL PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL
);

INSERT INTO #FirstName (NameNumber, FirstName) VALUES
(1,'Aarav'),(2,'Aditi'),(3,'Arjun'),(4,'Ananya'),(5,'Dev'),
(6,'Diya'),(7,'Ishaan'),(8,'Ishita'),(9,'Kabir'),(10,'Kavya'),
(11,'Manav'),(12,'Meera'),(13,'Nakul'),(14,'Naina'),(15,'Rohan'),
(16,'Riya'),(17,'Samar'),(18,'Sanya'),(19,'Vihaan'),(20,'Zoya');

CREATE TABLE #LastName
(
    NameNumber TINYINT NOT NULL PRIMARY KEY,
    LastName VARCHAR(50) NOT NULL
);

INSERT INTO #LastName (NameNumber, LastName) VALUES
(1,'Ahuja'),(2,'Bajaj'),(3,'Batra'),(4,'Chawla'),(5,'Desai'),
(6,'Gupta'),(7,'Iyer'),(8,'Jain'),(9,'Kapoor'),(10,'Khanna'),
(11,'Malhotra'),(12,'Mehta'),(13,'Nair'),(14,'Patel'),(15,'Rao'),
(16,'Saxena'),(17,'Shah'),(18,'Sharma'),(19,'Sinha'),(20,'Verma');

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

CREATE TABLE #SupplierSeed
(
    SupplierNumber INT NOT NULL PRIMARY KEY,
    SupplierCode VARCHAR(20) NOT NULL UNIQUE,
    SupplierGroup VARCHAR(20) NOT NULL,
    SupplierName VARCHAR(150) NOT NULL UNIQUE,
    ContactName VARCHAR(100) NULL,
    Email VARCHAR(150) NULL,
    Phone VARCHAR(20) NULL,
    AddressLine VARCHAR(255) NOT NULL,
    City VARCHAR(100) NOT NULL,
    StateName VARCHAR(100) NOT NULL,
    PostalCode VARCHAR(10) NOT NULL,
    Country VARCHAR(100) NOT NULL,
    IsActive BIT NOT NULL
);

;WITH Tens AS
(
    SELECT Digit
    FROM (VALUES (0),(1),(2),(3),(4)) AS values_list (Digit)
),
Ones AS
(
    SELECT Digit
    FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)) AS values_list (Digit)
),
SupplierNumbers AS
(
    SELECT (t.Digit * 10) + o.Digit AS SupplierNumber
    FROM Tens AS t
    CROSS JOIN Ones AS o
),
SupplierAttributes AS
(
    SELECT
        SupplierNumber,
        ((SupplierNumber * 7 - 1) % 20) + 1 AS FirstNameNumber,
        ((SupplierNumber * 13 - 1) % 20) + 1 AS LastNameNumber,
        ((SupplierNumber * 17 - 1) % 20) + 1 AS LocationNumber
    FROM SupplierNumbers
)
INSERT INTO #SupplierSeed
(
    SupplierNumber, SupplierCode, SupplierGroup, SupplierName,
    ContactName, Email, Phone, AddressLine,
    City, StateName, PostalCode, Country, IsActive
)
SELECT
    attributes.SupplierNumber,
    CONCAT('SUP', RIGHT(CONCAT('000', attributes.SupplierNumber), 3)),
    CASE
        WHEN attributes.SupplierNumber <= 10 THEN 'Strategic'
        WHEN attributes.SupplierNumber <= 35 THEN 'Standard'
        ELSE 'Niche'
    END,
    CONCAT(
        CASE
            WHEN attributes.SupplierNumber <= 10 THEN 'Apex Strategic Distribution '
            WHEN attributes.SupplierNumber <= 35 THEN 'Meridian Standard Supply '
            ELSE 'NicheCraft Specialty Goods '
        END,
        RIGHT(CONCAT('00', attributes.SupplierNumber), 2)
    ),
    CASE
        WHEN attributes.SupplierNumber % 17 = 0 THEN NULL
        ELSE CONCAT(first_name.FirstName, ' ', last_name.LastName)
    END,
    CASE
        WHEN attributes.SupplierNumber % 13 = 0 THEN NULL
        ELSE CONCAT(
            'contact', RIGHT(CONCAT('000', attributes.SupplierNumber), 3),
            '@supplier.retailintelligence.example'
        )
    END,
    CASE
        WHEN attributes.SupplierNumber % 19 = 0 THEN NULL
        ELSE CONCAT(
            '+91-',
            CONVERT(VARCHAR(10), CONVERT(BIGINT, 6000000000) + attributes.SupplierNumber)
        )
    END,
    CONCAT(
        CONVERT(VARCHAR(10), 100 + attributes.SupplierNumber),
        ' Synthetic Industrial Estate, Zone ',
        CONVERT(VARCHAR(10), 1 + (attributes.SupplierNumber % 8))
    ),
    location.City,
    location.StateName,
    location.PostalCode,
    'India',
    CASE WHEN attributes.SupplierNumber IN (49, 50) THEN 0 ELSE 1 END
FROM SupplierAttributes AS attributes
INNER JOIN #FirstName AS first_name
    ON first_name.NameNumber = attributes.FirstNameNumber
INNER JOIN #LastName AS last_name
    ON last_name.NameNumber = attributes.LastNameNumber
INNER JOIN #Location AS location
    ON location.LocationNumber = attributes.LocationNumber;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE target
    SET SupplierName = seed.SupplierName,
        ContactName = seed.ContactName,
        Email = seed.Email,
        Phone = seed.Phone,
        AddressLine = seed.AddressLine,
        City = seed.City,
        State = seed.StateName,
        PostalCode = seed.PostalCode,
        Country = seed.Country,
        IsActive = seed.IsActive,
        ModifiedDate = SYSDATETIME()
    FROM core.Supplier AS target
    INNER JOIN #SupplierSeed AS seed
        ON seed.SupplierCode = target.SupplierCode;

    INSERT INTO core.Supplier
    (
        SupplierCode, SupplierName, ContactName, Email, Phone,
        AddressLine, City, State, PostalCode, Country, IsActive
    )
    SELECT
        seed.SupplierCode, seed.SupplierName, seed.ContactName, seed.Email, seed.Phone,
        seed.AddressLine, seed.City, seed.StateName, seed.PostalCode, seed.Country,
        seed.IsActive
    FROM #SupplierSeed AS seed
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM core.Supplier AS target
        WHERE target.SupplierCode = seed.SupplierCode
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @ApprovedSupplierCount INT =
(
    SELECT COUNT(*)
    FROM core.Supplier
    WHERE SupplierCode IN (SELECT SupplierCode FROM #SupplierSeed)
);

DECLARE @TotalSupplierCount INT = (SELECT COUNT(*) FROM core.Supplier);

IF @ApprovedSupplierCount <> 50 OR @TotalSupplierCount <> 50
BEGIN
    THROW 51242, 'Supplier validation failed: expected exactly 50 approved suppliers.', 1;
END;

IF EXISTS
(
    SELECT SupplierName
    FROM core.Supplier
    GROUP BY SupplierName
    HAVING COUNT(*) > 1
)
BEGIN
    THROW 51243, 'Supplier validation failed: duplicate supplier name detected.', 1;
END;

IF EXISTS
(
    SELECT Email
    FROM core.Supplier
    WHERE Email IS NOT NULL
    GROUP BY Email
    HAVING COUNT(*) > 1
)
BEGIN
    THROW 51244, 'Supplier validation failed: duplicate populated email detected.', 1;
END;

IF (SELECT COUNT(*) FROM core.Supplier WHERE IsActive = 0) <> 2
   OR EXISTS
   (
       SELECT 1
       FROM core.Supplier
       WHERE Country <> 'India'
          OR City IS NULL
          OR State IS NULL
          OR PostalCode IS NULL
   )
BEGIN
    THROW 51245, 'Supplier validation failed: activity or geography distribution differs from design.', 1;
END;

SELECT
    seed.SupplierGroup,
    COUNT(*) AS ExpectedSupplierCount,
    COUNT(supplier.SupplierID) AS ExistingSupplierCount,
    SUM(CASE WHEN supplier.IsActive = 1 THEN 1 ELSE 0 END) AS ActiveSupplierCount,
    SUM(CASE WHEN supplier.IsActive = 0 THEN 1 ELSE 0 END) AS InactiveSupplierCount,
    CASE WHEN COUNT(*) = COUNT(supplier.SupplierID) THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM #SupplierSeed AS seed
LEFT JOIN core.Supplier AS supplier
    ON supplier.SupplierCode = seed.SupplierCode
GROUP BY seed.SupplierGroup
ORDER BY MIN(seed.SupplierNumber);

SELECT
    @ApprovedSupplierCount AS ApprovedSupplierCount,
    @TotalSupplierCount AS TotalSupplierCount,
    COUNT(DISTINCT City) AS CityCount,
    COUNT(DISTINCT State) AS StateCount,
    SUM(CASE WHEN ContactName IS NULL THEN 1 ELSE 0 END) AS MissingContactCount,
    SUM(CASE WHEN Email IS NULL THEN 1 ELSE 0 END) AS MissingEmailCount,
    SUM(CASE WHEN Phone IS NULL THEN 1 ELSE 0 END) AS MissingPhoneCount,
    SUM(CASE WHEN IsActive = 1 THEN 1 ELSE 0 END) AS ActiveSupplierCount,
    SUM(CASE WHEN IsActive = 0 THEN 1 ELSE 0 END) AS InactiveSupplierCount,
    CASE
        WHEN @ApprovedSupplierCount = 50
         AND @TotalSupplierCount = 50
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM core.Supplier;

RAISERROR('14_Generate_Suppliers.sql completed successfully: 50 synthetic suppliers validated.', 10, 1) WITH NOWAIT;
GO
