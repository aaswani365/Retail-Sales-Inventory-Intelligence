/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      15_Generate_Products.sql
Purpose:     Generate 500 deterministic products with realistic commercial attributes.
Author:      Akshay Aswani
Version:     2.0
Depends on:  14_Generate_Suppliers.sql
Rerunnable:  Yes. Stable SKUs are updated; missing rows are inserted.

Portfolio design
----------------
- Demand bands: 100 high, 250 medium, 150 low.
- Supplier concentration: 250 strategic, 200 standard, 50 niche products.
- Ten products (2%) are intentional, identifiable loss leaders.
- Fifteen products are inactive and excluded from later transaction generation.
- All product names, SKUs, barcodes, descriptions, and prices are synthetic.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51250, 'Product generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'core.Product', N'U') IS NULL
   OR OBJECT_ID(N'core.Supplier', N'U') IS NULL
   OR OBJECT_ID(N'ref.Category', N'U') IS NULL
   OR OBJECT_ID(N'ref.SubCategory', N'U') IS NULL
   OR OBJECT_ID(N'ref.Brand', N'U') IS NULL
BEGIN
    THROW 51251, 'Product generation stopped: one or more required tables are missing.', 1;
END;

IF (SELECT COUNT(*) FROM ref.Category WHERE IsActive = 1) <> 8
   OR (SELECT COUNT(*) FROM ref.SubCategory WHERE IsActive = 1) <> 32
   OR (SELECT COUNT(*) FROM ref.Brand WHERE IsActive = 1) <> 40
   OR (SELECT COUNT(*) FROM core.Supplier) <> 50
BEGIN
    THROW 51252, 'Product generation stopped: approved reference or supplier counts are missing.', 1;
END;

DROP TABLE IF EXISTS #BrandChoice;
DROP TABLE IF EXISTS #ProductSeed;

CREATE TABLE #BrandChoice
(
    CategoryCode VARCHAR(20) NOT NULL,
    ChoiceNumber TINYINT NOT NULL,
    BrandCode VARCHAR(20) NOT NULL,
    PRIMARY KEY (CategoryCode, ChoiceNumber)
);

INSERT INTO #BrandChoice (CategoryCode, ChoiceNumber, BrandCode) VALUES
('ELECTRONICS',1,'NOVATECH'),('ELECTRONICS',2,'VERTEX'),('ELECTRONICS',3,'AURORA'),('ELECTRONICS',4,'SONIQ'),
('ELECTRONICS',5,'PIXORA'),('ELECTRONICS',6,'VALUEHUB'),('ELECTRONICS',7,'PREMIORA'),('ELECTRONICS',8,'ECOCHOICE'),
('COMPUTERS',1,'NEXBYTE'),('COMPUTERS',2,'COREVISTA'),('COMPUTERS',3,'QUANTUMPC'),('COMPUTERS',4,'BYTECRAFT'),
('COMPUTERS',5,'NOVATECH'),('COMPUTERS',6,'VALUEHUB'),('COMPUTERS',7,'PREMIORA'),('COMPUTERS',8,'EVERYDAY'),
('MOBILE',1,'MOBILYNX'),('MOBILE',2,'ZENMOBILE'),('MOBILE',3,'PULSEPHONE'),('MOBILE',4,'CHARGEON'),
('MOBILE',5,'CASECRAFT'),('MOBILE',6,'VALUEHUB'),('MOBILE',7,'PREMIORA'),('MOBILE',8,'ECOCHOICE'),
('HOME_APPL',1,'HOMENOVA'),('HOME_APPL',2,'PURELIVING'),('HOME_APPL',3,'KITCHENPRO'),('HOME_APPL',4,'FROSTLINE'),
('HOME_APPL',5,'WASHWELL'),('HOME_APPL',6,'VALUEHUB'),('HOME_APPL',7,'PREMIORA'),('HOME_APPL',8,'EVERYDAY'),
('FASHION',1,'URBANWEAVE'),('FASHION',2,'THREADLINE'),('FASHION',3,'MODECRAFT'),('FASHION',4,'STEPWISE'),
('FASHION',5,'FLEXFOOT'),('FASHION',6,'VALUEHUB'),('FASHION',7,'PREMIORA'),('FASHION',8,'ECOCHOICE'),
('FURNITURE',1,'OAKNEST'),('FURNITURE',2,'ERGOWORKS'),('FURNITURE',3,'LIVINGFORM'),('FURNITURE',4,'SPACEWISE'),
('FURNITURE',5,'VALUEHUB'),('FURNITURE',6,'PREMIORA'),('FURNITURE',7,'ECOCHOICE'),('FURNITURE',8,'EVERYDAY'),
('SPORTS',1,'FITPULSE'),('SPORTS',2,'ACTIVEEDGE'),('SPORTS',3,'TRAILFORGE'),('SPORTS',4,'PLAYFIELD'),
('SPORTS',5,'VALUEHUB'),('SPORTS',6,'PREMIORA'),('SPORTS',7,'ECOCHOICE'),('SPORTS',8,'EVERYDAY'),
('BOOKS_STAT',1,'READWELL'),('BOOKS_STAT',2,'PAPERTRAIL'),('BOOKS_STAT',3,'INKFLOW'),('BOOKS_STAT',4,'DESKMATE'),
('BOOKS_STAT',5,'VALUEHUB'),('BOOKS_STAT',6,'PREMIORA'),('BOOKS_STAT',7,'ECOCHOICE'),('BOOKS_STAT',8,'EVERYDAY');

CREATE TABLE #ProductSeed
(
    ProductNumber INT NOT NULL PRIMARY KEY,
    SKU VARCHAR(40) NOT NULL UNIQUE,
    ProductName VARCHAR(150) NOT NULL,
    CategoryCode VARCHAR(20) NOT NULL,
    SubCategoryCode VARCHAR(20) NOT NULL,
    BrandCode VARCHAR(20) NOT NULL,
    SupplierCode VARCHAR(20) NOT NULL,
    SupplierGroup VARCHAR(20) NOT NULL,
    DemandBand VARCHAR(20) NOT NULL,
    CostPrice DECIMAL(12,2) NOT NULL,
    SellingPrice DECIMAL(12,2) NOT NULL,
    ReorderLevel INT NOT NULL,
    ExcessStockLevel INT NOT NULL,
    Barcode VARCHAR(50) NULL,
    Description VARCHAR(500) NOT NULL,
    IsLossLeader BIT NOT NULL,
    IsActive BIT NOT NULL
);

;WITH Digits AS
(
    SELECT Digit
    FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS values_list (Digit)
),
Numbers AS
(
    SELECT TOP (500)
        CONVERT(INT, ROW_NUMBER() OVER (ORDER BY d3.Digit, d2.Digit, d1.Digit)) AS ProductNumber
    FROM Digits AS d1
    CROSS JOIN Digits AS d2
    CROSS JOIN Digits AS d3
),
RankedSubCategories AS
(
    SELECT
        subcategory.SubCategoryID,
        subcategory.SubCategoryCode,
        subcategory.SubCategoryName,
        category.CategoryCode,
        ROW_NUMBER() OVER (ORDER BY subcategory.SubCategoryCode) AS SubCategoryNumber
    FROM ref.SubCategory AS subcategory
    INNER JOIN ref.Category AS category
        ON category.CategoryID = subcategory.CategoryID
    WHERE subcategory.IsActive = 1
      AND category.IsActive = 1
),
Assignments AS
(
    SELECT
        numbers.ProductNumber,
        subcategory.CategoryCode,
        subcategory.SubCategoryCode,
        subcategory.SubCategoryName,
        brand_choice.BrandCode,
        CASE
            WHEN numbers.ProductNumber <= 250
                THEN CONCAT('SUP', RIGHT(CONCAT('000', 1 + ((numbers.ProductNumber - 1) % 10)), 3))
            WHEN numbers.ProductNumber <= 450
                THEN CONCAT('SUP', RIGHT(CONCAT('000', 11 + ((numbers.ProductNumber - 251) % 25)), 3))
            ELSE CONCAT('SUP', RIGHT(CONCAT('000', 36 + ((numbers.ProductNumber - 451) % 13)), 3))
        END AS SupplierCode,
        CASE
            WHEN numbers.ProductNumber <= 250 THEN 'Strategic'
            WHEN numbers.ProductNumber <= 450 THEN 'Standard'
            ELSE 'Niche'
        END AS SupplierGroup,
        CASE
            WHEN numbers.ProductNumber <= 100 THEN 'High Demand'
            WHEN numbers.ProductNumber <= 350 THEN 'Medium Demand'
            ELSE 'Low Demand'
        END AS DemandBand
    FROM Numbers AS numbers
    INNER JOIN RankedSubCategories AS subcategory
        ON subcategory.SubCategoryNumber = ((numbers.ProductNumber - 1) % 32) + 1
    INNER JOIN #BrandChoice AS brand_choice
        ON brand_choice.CategoryCode = subcategory.CategoryCode
       AND brand_choice.ChoiceNumber =
           ((((numbers.ProductNumber - 1) / 32) + (numbers.ProductNumber * 7) - 1) % 8) + 1
),
BasePricing AS
(
    SELECT
        assignments.*,
        CONVERT(DECIMAL(12,2),
            CASE assignments.CategoryCode
                WHEN 'ELECTRONICS' THEN 5000 + ((assignments.ProductNumber * 977) % 60000)
                WHEN 'COMPUTERS'   THEN 12000 + ((assignments.ProductNumber * 1237) % 80000)
                WHEN 'MOBILE'      THEN 800 + ((assignments.ProductNumber * 853) % 65000)
                WHEN 'HOME_APPL'   THEN 3000 + ((assignments.ProductNumber * 719) % 50000)
                WHEN 'FASHION'     THEN 300 + ((assignments.ProductNumber * 113) % 5000)
                WHEN 'FURNITURE'   THEN 1500 + ((assignments.ProductNumber * 479) % 30000)
                WHEN 'SPORTS'      THEN 250 + ((assignments.ProductNumber * 337) % 20000)
                ELSE 80 + ((assignments.ProductNumber * 67) % 2000)
            END
        ) AS UnroundedCost
    FROM Assignments AS assignments
),
CommercialPricing AS
(
    SELECT
        pricing.*,
        CONVERT(DECIMAL(12,2), ROUND(pricing.UnroundedCost, -1)) AS CostPrice,
        CONVERT(DECIMAL(6,4), 1.18 + ((pricing.ProductNumber % 18) / 100.0)) AS StandardMarkup
    FROM BasePricing AS pricing
)
INSERT INTO #ProductSeed
(
    ProductNumber, SKU, ProductName, CategoryCode, SubCategoryCode,
    BrandCode, SupplierCode, SupplierGroup, DemandBand,
    CostPrice, SellingPrice, ReorderLevel, ExcessStockLevel,
    Barcode, Description, IsLossLeader, IsActive
)
SELECT
    pricing.ProductNumber,
    CONCAT('SKU-', RIGHT(CONCAT('00000', pricing.ProductNumber), 5)),
    CONCAT(brand.BrandName, ' ', pricing.SubCategoryName, ' Series ',
           RIGHT(CONCAT('000', pricing.ProductNumber), 3)),
    pricing.CategoryCode,
    pricing.SubCategoryCode,
    pricing.BrandCode,
    pricing.SupplierCode,
    pricing.SupplierGroup,
    pricing.DemandBand,
    pricing.CostPrice,
    CONVERT(DECIMAL(12,2),
        CASE
            WHEN pricing.ProductNumber % 50 = 0
                THEN pricing.CostPrice
                     - CASE WHEN pricing.CostPrice >= 1000 THEN 100 ELSE 10 END
            ELSE ROUND(pricing.CostPrice * pricing.StandardMarkup, -1)
        END
    ),
    CASE pricing.DemandBand
        WHEN 'High Demand' THEN 40 + (pricing.ProductNumber % 21)
        WHEN 'Medium Demand' THEN 20 + (pricing.ProductNumber % 21)
        ELSE 5 + (pricing.ProductNumber % 16)
    END,
    (CASE pricing.DemandBand
        WHEN 'High Demand' THEN 40 + (pricing.ProductNumber % 21)
        WHEN 'Medium Demand' THEN 20 + (pricing.ProductNumber % 21)
        ELSE 5 + (pricing.ProductNumber % 16)
     END * 3) + (pricing.ProductNumber % 20),
    CASE
        WHEN pricing.ProductNumber % 25 = 0 THEN NULL
        ELSE CONCAT('890', RIGHT(CONCAT('000000000', pricing.ProductNumber), 9))
    END,
    CONCAT(
        'Synthetic ', pricing.DemandBand, ' portfolio product in ',
        pricing.SubCategoryName,
        CASE WHEN pricing.ProductNumber % 50 = 0 THEN '; controlled loss-leader pricing.'
             ELSE '; standard positive-margin pricing.' END
    ),
    CASE WHEN pricing.ProductNumber % 50 = 0 THEN 1 ELSE 0 END,
    CASE WHEN pricing.ProductNumber > 485 THEN 0 ELSE 1 END
FROM CommercialPricing AS pricing
INNER JOIN ref.Brand AS brand
    ON brand.BrandCode = pricing.BrandCode;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE target
    SET ProductName = seed.ProductName,
        SubCategoryID = subcategory.SubCategoryID,
        BrandID = brand.BrandID,
        SupplierID = supplier.SupplierID,
        CostPrice = seed.CostPrice,
        SellingPrice = seed.SellingPrice,
        ReorderLevel = seed.ReorderLevel,
        ExcessStockLevel = seed.ExcessStockLevel,
        Barcode = seed.Barcode,
        Description = seed.Description,
        IsActive = seed.IsActive,
        ModifiedDate = SYSDATETIME()
    FROM core.Product AS target
    INNER JOIN #ProductSeed AS seed ON seed.SKU = target.SKU
    INNER JOIN ref.SubCategory AS subcategory ON subcategory.SubCategoryCode = seed.SubCategoryCode
    INNER JOIN ref.Brand AS brand ON brand.BrandCode = seed.BrandCode
    INNER JOIN core.Supplier AS supplier ON supplier.SupplierCode = seed.SupplierCode;

    INSERT INTO core.Product
    (
        SKU, ProductName, SubCategoryID, BrandID, SupplierID,
        CostPrice, SellingPrice, ReorderLevel, ExcessStockLevel,
        Barcode, Description, IsActive
    )
    SELECT
        seed.SKU, seed.ProductName, subcategory.SubCategoryID, brand.BrandID, supplier.SupplierID,
        seed.CostPrice, seed.SellingPrice, seed.ReorderLevel, seed.ExcessStockLevel,
        seed.Barcode, seed.Description, seed.IsActive
    FROM #ProductSeed AS seed
    INNER JOIN ref.SubCategory AS subcategory ON subcategory.SubCategoryCode = seed.SubCategoryCode
    INNER JOIN ref.Brand AS brand ON brand.BrandCode = seed.BrandCode
    INNER JOIN core.Supplier AS supplier ON supplier.SupplierCode = seed.SupplierCode
    WHERE NOT EXISTS
    (
        SELECT 1 FROM core.Product AS target WHERE target.SKU = seed.SKU
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @ApprovedProductCount INT =
(
    SELECT COUNT(*)
    FROM core.Product
    WHERE SKU IN (SELECT SKU FROM #ProductSeed)
);

DECLARE @TotalProductCount INT = (SELECT COUNT(*) FROM core.Product);

IF @ApprovedProductCount <> 500 OR @TotalProductCount <> 500
    THROW 51253, 'Product validation failed: expected exactly 500 approved products.', 1;

IF EXISTS
(
    SELECT 1
    FROM core.Product AS product
    INNER JOIN core.Supplier AS supplier ON supplier.SupplierID = product.SupplierID
    WHERE product.IsActive = 1 AND supplier.IsActive = 0
)
    THROW 51254, 'Product validation failed: active product assigned to inactive supplier.', 1;

IF EXISTS
(
    SELECT 1
    FROM core.Product
    WHERE CostPrice <= 0
       OR SellingPrice <= 0
       OR ReorderLevel < 0
       OR ExcessStockLevel < ReorderLevel
)
    THROW 51255, 'Product validation failed: invalid price or stock threshold.', 1;

IF EXISTS
(
    SELECT 1
    FROM core.Product AS product
    INNER JOIN #ProductSeed AS seed ON seed.SKU = product.SKU
    WHERE (seed.IsLossLeader = 1 AND product.SellingPrice >= product.CostPrice)
       OR (seed.IsLossLeader = 0 AND product.SellingPrice <= product.CostPrice)
)
    THROW 51256, 'Product validation failed: margin policy differs from design.', 1;

IF (SELECT COUNT(*) FROM #ProductSeed WHERE IsLossLeader = 1) <> 10
   OR (SELECT COUNT(*) FROM core.Product WHERE IsActive = 0) <> 15
   OR (SELECT COUNT(*) FROM core.Product WHERE Barcode IS NULL) <> 20
BEGIN
    THROW 51257, 'Product validation failed: loss-leader, activity, or barcode distribution differs from design.', 1;
END;

SELECT
    seed.DemandBand,
    COUNT(*) AS ProductCount,
    SUM(CASE WHEN product.IsActive = 1 THEN 1 ELSE 0 END) AS ActiveProductCount,
    MIN(product.SellingPrice) AS MinimumSellingPrice,
    MAX(product.SellingPrice) AS MaximumSellingPrice,
    'PASSED' AS ValidationStatus
FROM #ProductSeed AS seed
INNER JOIN core.Product AS product ON product.SKU = seed.SKU
GROUP BY seed.DemandBand
ORDER BY MIN(seed.ProductNumber);

SELECT
    seed.SupplierGroup,
    COUNT(*) AS ProductCount,
    COUNT(DISTINCT product.SupplierID) AS SupplierCount,
    CAST(100.0 * COUNT(*) / @TotalProductCount AS DECIMAL(5,2)) AS ProductSharePercent,
    'PASSED' AS ValidationStatus
FROM #ProductSeed AS seed
INNER JOIN core.Product AS product ON product.SKU = seed.SKU
GROUP BY seed.SupplierGroup
ORDER BY MIN(seed.ProductNumber);

SELECT
    @ApprovedProductCount AS ApprovedProductCount,
    @TotalProductCount AS TotalProductCount,
    COUNT(DISTINCT category.CategoryID) AS CategoryCount,
    COUNT(DISTINCT product.SubCategoryID) AS SubCategoryCount,
    COUNT(DISTINCT product.BrandID) AS BrandCount,
    COUNT(DISTINCT product.SupplierID) AS SupplierCount,
    SUM(CASE WHEN seed.IsLossLeader = 1 THEN 1 ELSE 0 END) AS LossLeaderCount,
    SUM(CASE WHEN product.IsActive = 1 THEN 1 ELSE 0 END) AS ActiveProductCount,
    SUM(CASE WHEN product.IsActive = 0 THEN 1 ELSE 0 END) AS InactiveProductCount,
    CASE
        WHEN @ApprovedProductCount = 500
         AND @TotalProductCount = 500
         AND COUNT(DISTINCT category.CategoryID) = 8
         AND COUNT(DISTINCT product.SubCategoryID) = 32
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM core.Product AS product
INNER JOIN #ProductSeed AS seed ON seed.SKU = product.SKU
INNER JOIN ref.SubCategory AS subcategory ON subcategory.SubCategoryID = product.SubCategoryID
INNER JOIN ref.Category AS category ON category.CategoryID = subcategory.CategoryID;

RAISERROR('15_Generate_Products.sql completed successfully: 500 synthetic products validated.', 10, 1) WITH NOWAIT;
GO
