/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      11_Generate_Stores.sql
Purpose:     Generate 20 deterministic synthetic stores across India.
Author:      Akshay Aswani
Version:     2.0
Depends on:  10_Load_Reference_Data.sql
Rerunnable:  Yes. Existing store codes are updated; missing stores are inserted.

Geographic design
-----------------
- North: 6 stores
- West:  6 stores
- South: 5 stores
- East/Central: 3 stores

All names, addresses and phone numbers are synthetic portfolio data.
ManagerEmployeeID remains unchanged/null until 12_Generate_Employees.sql.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51210, 'Store generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'core.Store', N'U') IS NULL
BEGIN
    THROW 51211, 'Store generation stopped: core.Store is missing.', 1;
END;

DROP TABLE IF EXISTS #StoreSeed;

CREATE TABLE #StoreSeed
(
    StoreCode VARCHAR(20) NOT NULL PRIMARY KEY,
    StoreName VARCHAR(100) NOT NULL UNIQUE,
    Region VARCHAR(20) NOT NULL,
    AddressLine VARCHAR(255) NOT NULL,
    City VARCHAR(100) NOT NULL,
    StateName VARCHAR(100) NOT NULL,
    PostalCode VARCHAR(10) NOT NULL,
    Phone VARCHAR(20) NOT NULL,
    OpeningDate DATE NOT NULL
);

INSERT INTO #StoreSeed
(
    StoreCode, StoreName, Region, AddressLine, City,
    StateName, PostalCode, Phone, OpeningDate
)
VALUES
-- North (6)
('STR-JAI-01', 'Retail Intelligence Jaipur Central', 'North', '101 Market Square, C-Scheme', 'Jaipur', 'Rajasthan', '302001', '+91-141-4001001', '2016-04-15'),
('STR-DEL-01', 'Retail Intelligence Delhi North', 'North', '202 Commerce Avenue, Rohini', 'Delhi', 'Delhi', '110085', '+91-11-40010002', '2015-08-21'),
('STR-GGN-01', 'Retail Intelligence Gurugram', 'North', '303 Business Park, Sector 29', 'Gurugram', 'Haryana', '122009', '+91-124-4001003', '2017-02-10'),
('STR-NOI-01', 'Retail Intelligence Noida', 'North', '404 Retail Boulevard, Sector 18', 'Noida', 'Uttar Pradesh', '201301', '+91-120-4001004', '2017-11-03'),
('STR-CHD-01', 'Retail Intelligence Chandigarh', 'North', '505 City Plaza, Sector 22', 'Chandigarh', 'Chandigarh', '160022', '+91-172-4001005', '2018-06-18'),
('STR-LKO-01', 'Retail Intelligence Lucknow', 'North', '606 Heritage Road, Gomti Nagar', 'Lucknow', 'Uttar Pradesh', '226010', '+91-522-4001006', '2019-01-25'),

-- West (6)
('STR-AHM-01', 'Retail Intelligence Ahmedabad', 'West', '107 Riverfront Arcade, Ashram Road', 'Ahmedabad', 'Gujarat', '380009', '+91-79-40010007', '2015-10-12'),
('STR-MUM-01', 'Retail Intelligence Mumbai West', 'West', '208 Metro Mall Road, Andheri', 'Mumbai', 'Maharashtra', '400053', '+91-22-40010008', '2014-05-09'),
('STR-PUN-01', 'Retail Intelligence Pune', 'West', '309 Innovation Street, Baner', 'Pune', 'Maharashtra', '411045', '+91-20-40010009', '2016-09-16'),
('STR-SUR-01', 'Retail Intelligence Surat', 'West', '410 Textile Avenue, Vesu', 'Surat', 'Gujarat', '395007', '+91-261-4001010', '2018-03-23'),
('STR-VAD-01', 'Retail Intelligence Vadodara', 'West', '511 Garden Plaza, Alkapuri', 'Vadodara', 'Gujarat', '390007', '+91-265-4001011', '2019-07-05'),
('STR-IND-01', 'Retail Intelligence Indore', 'West', '612 Central Boulevard, Vijay Nagar', 'Indore', 'Madhya Pradesh', '452010', '+91-731-4001012', '2020-02-14'),

-- South (5)
('STR-BLR-01', 'Retail Intelligence Bengaluru', 'South', '113 Tech Park Road, Koramangala', 'Bengaluru', 'Karnataka', '560034', '+91-80-40010013', '2014-11-28'),
('STR-HYD-01', 'Retail Intelligence Hyderabad', 'South', '214 Lake View Avenue, Hitech City', 'Hyderabad', 'Telangana', '500081', '+91-40-40010014', '2016-01-08'),
('STR-CHE-01', 'Retail Intelligence Chennai', 'South', '315 Marina Commerce Road, T Nagar', 'Chennai', 'Tamil Nadu', '600017', '+91-44-40010015', '2016-12-19'),
('STR-KOC-01', 'Retail Intelligence Kochi', 'South', '416 Harbour Plaza, Edappally', 'Kochi', 'Kerala', '682024', '+91-484-4001016', '2019-04-26'),
('STR-CBE-01', 'Retail Intelligence Coimbatore', 'South', '517 Green Avenue, RS Puram', 'Coimbatore', 'Tamil Nadu', '641002', '+91-422-4001017', '2020-09-11'),

-- East and Central (3)
('STR-KOL-01', 'Retail Intelligence Kolkata', 'East/Central', '118 Park Avenue, Salt Lake', 'Kolkata', 'West Bengal', '700091', '+91-33-40010018', '2015-06-30'),
('STR-BBI-01', 'Retail Intelligence Bhubaneswar', 'East/Central', '219 Temple City Road, Jayadev Vihar', 'Bhubaneswar', 'Odisha', '751013', '+91-674-4001019', '2019-10-18'),
('STR-RPR-01', 'Retail Intelligence Raipur', 'East/Central', '320 Central Market Road, Telibandha', 'Raipur', 'Chhattisgarh', '492001', '+91-771-4001020', '2021-03-12');

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE target
    SET StoreName = seed.StoreName,
        AddressLine = seed.AddressLine,
        City = seed.City,
        State = seed.StateName,
        PostalCode = seed.PostalCode,
        Country = 'India',
        Phone = seed.Phone,
        OpeningDate = seed.OpeningDate,
        ClosingDate = NULL,
        IsActive = 1,
        ModifiedDate = SYSDATETIME()
    FROM core.Store AS target
    INNER JOIN #StoreSeed AS seed
        ON seed.StoreCode = target.StoreCode;

    INSERT INTO core.Store
    (
        StoreCode, StoreName, ManagerEmployeeID, AddressLine,
        City, State, PostalCode, Country, Phone,
        OpeningDate, ClosingDate, IsActive
    )
    SELECT
        seed.StoreCode, seed.StoreName, NULL, seed.AddressLine,
        seed.City, seed.StateName, seed.PostalCode, 'India', seed.Phone,
        seed.OpeningDate, NULL, 1
    FROM #StoreSeed AS seed
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM core.Store AS target
        WHERE target.StoreCode = seed.StoreCode
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @ApprovedStoreCount INT =
(
    SELECT COUNT(*)
    FROM core.Store
    WHERE StoreCode IN (SELECT StoreCode FROM #StoreSeed)
);

DECLARE @TotalStoreCount INT = (SELECT COUNT(*) FROM core.Store);

IF @ApprovedStoreCount <> 20 OR @TotalStoreCount <> 20
BEGIN
    THROW 51212, 'Store validation failed: expected exactly 20 approved stores.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM core.Store AS s
    INNER JOIN #StoreSeed AS seed ON seed.StoreCode = s.StoreCode
    WHERE s.StoreName <> seed.StoreName
       OR s.City <> seed.City
       OR s.State <> seed.StateName
       OR s.Country <> 'India'
       OR s.OpeningDate <> seed.OpeningDate
       OR s.IsActive <> 1
       OR s.ClosingDate IS NOT NULL
)
BEGIN
    THROW 51213, 'Store validation failed: one or more store attributes differ from the approved seed.', 1;
END;

SELECT
    seed.Region,
    COUNT(*) AS ExpectedStoreCount,
    COUNT(s.StoreID) AS ExistingStoreCount,
    CASE WHEN COUNT(*) = COUNT(s.StoreID) THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM #StoreSeed AS seed
LEFT JOIN core.Store AS s ON s.StoreCode = seed.StoreCode
GROUP BY seed.Region
ORDER BY
    CASE seed.Region
        WHEN 'North' THEN 1
        WHEN 'West' THEN 2
        WHEN 'South' THEN 3
        ELSE 4
    END;

SELECT
    @ApprovedStoreCount AS ApprovedStoreCount,
    @TotalStoreCount AS TotalStoreCount,
    COUNT(DISTINCT City) AS CityCount,
    COUNT(DISTINCT State) AS StateCount,
    MIN(OpeningDate) AS EarliestOpeningDate,
    MAX(OpeningDate) AS LatestOpeningDate,
    CASE WHEN @ApprovedStoreCount = 20 AND @TotalStoreCount = 20 THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM core.Store;

RAISERROR('11_Generate_Stores.sql completed successfully: 20 synthetic stores validated.', 10, 1) WITH NOWAIT;
GO
