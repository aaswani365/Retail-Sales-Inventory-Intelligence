/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      10_Load_Reference_Data.sql
Purpose:     Load the nine curated reference tables using stable business codes.
Author:      Akshay Aswani
Version:     2.0
Depends on:  04_Create_Constraints.sql
Rerunnable:  Yes. Existing approved codes are updated; missing codes are inserted.

Approved seed volume
--------------------
- 8 categories and 32 subcategories
- 40 fictional brands
- 8 order statuses, 6 payment methods and 7 payment statuses
- 7 return reasons and 6 return statuses
- 10 inventory movement types
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51200, 'Reference-data load stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'ref.Category', N'U') IS NULL
   OR OBJECT_ID(N'ref.InventoryMovementType', N'U') IS NULL
BEGIN
    THROW 51201, 'Reference-data load stopped: required reference tables are missing.', 1;
END;

DROP TABLE IF EXISTS #CategorySeed;
DROP TABLE IF EXISTS #SubCategorySeed;
DROP TABLE IF EXISTS #BrandSeed;
DROP TABLE IF EXISTS #OrderStatusSeed;
DROP TABLE IF EXISTS #PaymentMethodSeed;
DROP TABLE IF EXISTS #PaymentStatusSeed;
DROP TABLE IF EXISTS #ReturnReasonSeed;
DROP TABLE IF EXISTS #ReturnStatusSeed;
DROP TABLE IF EXISTS #MovementTypeSeed;

CREATE TABLE #CategorySeed
(
    CategoryCode VARCHAR(20) NOT NULL PRIMARY KEY,
    CategoryName VARCHAR(100) NOT NULL,
    Description VARCHAR(255) NOT NULL
);

INSERT INTO #CategorySeed VALUES
('ELECTRONICS', 'Electronics', 'Consumer electronics, imaging and audio products'),
('COMPUTERS', 'Computers & Accessories', 'Computers, components and peripheral devices'),
('MOBILE', 'Mobiles & Accessories', 'Mobile devices and related accessories'),
('HOME_APPL', 'Home Appliances', 'Large and small household appliances'),
('FASHION', 'Fashion', 'Clothing, footwear and fashion accessories'),
('FURNITURE', 'Furniture', 'Home and office furniture'),
('SPORTS', 'Sports & Fitness', 'Sports, fitness and outdoor products'),
('BOOKS_STAT', 'Books & Stationery', 'Books, stationery and office supplies');

CREATE TABLE #SubCategorySeed
(
    SubCategoryCode VARCHAR(20) NOT NULL PRIMARY KEY,
    CategoryCode VARCHAR(20) NOT NULL,
    SubCategoryName VARCHAR(100) NOT NULL,
    Description VARCHAR(255) NOT NULL
);

INSERT INTO #SubCategorySeed VALUES
('TELEVISIONS', 'ELECTRONICS', 'Televisions', 'LED, OLED and smart televisions'),
('AUDIO', 'ELECTRONICS', 'Audio Systems', 'Speakers, headphones and soundbars'),
('CAMERAS', 'ELECTRONICS', 'Cameras', 'Digital cameras and imaging accessories'),
('WEARABLES', 'ELECTRONICS', 'Wearables', 'Smart watches and fitness wearables'),
('LAPTOPS', 'COMPUTERS', 'Laptops', 'Business, personal and gaming laptops'),
('DESKTOPS', 'COMPUTERS', 'Desktops', 'Desktop computers and workstations'),
('MONITORS', 'COMPUTERS', 'Monitors', 'Computer monitors and displays'),
('PERIPHERALS', 'COMPUTERS', 'Computer Peripherals', 'Keyboards, mice and computer accessories'),
('SMARTPHONES', 'MOBILE', 'Smartphones', 'Android and iOS smartphones'),
('FEATURE_PHONES', 'MOBILE', 'Feature Phones', 'Essential voice and feature phones'),
('CHARGERS', 'MOBILE', 'Chargers & Cables', 'Mobile chargers, adapters and cables'),
('PHONE_CASES', 'MOBILE', 'Phone Cases', 'Protective covers and mobile cases'),
('REFRIGERATORS', 'HOME_APPL', 'Refrigerators', 'Single-door and multi-door refrigerators'),
('WASHERS', 'HOME_APPL', 'Washing Machines', 'Front-load and top-load washing machines'),
('MICROWAVES', 'HOME_APPL', 'Microwave Ovens', 'Solo, grill and convection ovens'),
('KITCHEN_APPL', 'HOME_APPL', 'Kitchen Appliances', 'Mixers, kettles and food processors'),
('MENS_CLOTHING', 'FASHION', 'Men''s Clothing', 'Casual, formal and traditional menswear'),
('WOMENS_CLOTHING', 'FASHION', 'Women''s Clothing', 'Casual, formal and traditional womenswear'),
('FOOTWEAR', 'FASHION', 'Footwear', 'Shoes, sandals and performance footwear'),
('FASHION_ACC', 'FASHION', 'Fashion Accessories', 'Bags, belts, wallets and accessories'),
('CHAIRS', 'FURNITURE', 'Chairs', 'Home, office and ergonomic chairs'),
('TABLES', 'FURNITURE', 'Tables', 'Dining, office and study tables'),
('STORAGE', 'FURNITURE', 'Storage Furniture', 'Wardrobes, cabinets and shelving'),
('BEDROOM', 'FURNITURE', 'Bedroom Furniture', 'Beds, bedside tables and dressers'),
('FITNESS_EQUIP', 'SPORTS', 'Fitness Equipment', 'Gym and home-fitness equipment'),
('SPORTSWEAR', 'SPORTS', 'Sportswear', 'Performance clothing and accessories'),
('OUTDOOR_GEAR', 'SPORTS', 'Outdoor Gear', 'Camping, hiking and outdoor products'),
('TEAM_SPORTS', 'SPORTS', 'Team Sports', 'Cricket, football and team-sport equipment'),
('BOOKS', 'BOOKS_STAT', 'Books', 'Fiction, non-fiction and academic books'),
('NOTEBOOKS', 'BOOKS_STAT', 'Notebooks & Paper', 'Notebooks, paper and writing pads'),
('WRITING', 'BOOKS_STAT', 'Writing Instruments', 'Pens, pencils and markers'),
('OFFICE_SUPPLIES', 'BOOKS_STAT', 'Office Supplies', 'Filing, desk and office supplies');

CREATE TABLE #BrandSeed
(
    BrandCode VARCHAR(20) NOT NULL PRIMARY KEY,
    BrandName VARCHAR(100) NOT NULL,
    Description VARCHAR(255) NOT NULL
);

INSERT INTO #BrandSeed VALUES
('NOVATECH', 'NovaTech', 'Fictional consumer technology brand'),
('VERTEX', 'Vertex Digital', 'Fictional digital electronics brand'),
('AURORA', 'Aurora Electronics', 'Fictional electronics and imaging brand'),
('SONIQ', 'SoniqWave', 'Fictional audio products brand'),
('PIXORA', 'Pixora', 'Fictional camera and imaging brand'),
('NEXBYTE', 'NexByte', 'Fictional personal computing brand'),
('COREVISTA', 'CoreVista', 'Fictional computing and display brand'),
('QUANTUMPC', 'Quantum PC', 'Fictional desktop and component brand'),
('BYTECRAFT', 'ByteCraft', 'Fictional computer accessories brand'),
('MOBILYNX', 'MobiLynx', 'Fictional smartphone brand'),
('ZENMOBILE', 'ZenMobile', 'Fictional mobile device brand'),
('PULSEPHONE', 'PulsePhone', 'Fictional mobile technology brand'),
('CHARGEON', 'ChargeOn', 'Fictional charging accessories brand'),
('CASECRAFT', 'CaseCraft', 'Fictional protective accessories brand'),
('HOMENOVA', 'HomeNova', 'Fictional home-appliance brand'),
('PURELIVING', 'PureLiving', 'Fictional household appliance brand'),
('KITCHENPRO', 'KitchenPro', 'Fictional kitchen-appliance brand'),
('FROSTLINE', 'FrostLine', 'Fictional refrigeration brand'),
('WASHWELL', 'WashWell', 'Fictional laundry-appliance brand'),
('URBANWEAVE', 'UrbanWeave', 'Fictional contemporary fashion brand'),
('THREADLINE', 'ThreadLine', 'Fictional clothing brand'),
('MODECRAFT', 'ModeCraft', 'Fictional fashion and accessory brand'),
('STEPWISE', 'StepWise', 'Fictional footwear brand'),
('FLEXFOOT', 'FlexFoot', 'Fictional performance footwear brand'),
('OAKNEST', 'OakNest', 'Fictional home-furniture brand'),
('ERGOWORKS', 'ErgoWorks', 'Fictional ergonomic furniture brand'),
('LIVINGFORM', 'LivingForm', 'Fictional lifestyle furniture brand'),
('SPACEWISE', 'SpaceWise', 'Fictional storage furniture brand'),
('FITPULSE', 'FitPulse', 'Fictional fitness-equipment brand'),
('ACTIVEEDGE', 'ActiveEdge', 'Fictional sportswear brand'),
('TRAILFORGE', 'TrailForge', 'Fictional outdoor-equipment brand'),
('PLAYFIELD', 'PlayField', 'Fictional team-sports brand'),
('READWELL', 'ReadWell', 'Fictional publishing and books brand'),
('PAPERTRAIL', 'PaperTrail', 'Fictional notebooks and paper brand'),
('INKFLOW', 'InkFlow', 'Fictional writing-instruments brand'),
('DESKMATE', 'DeskMate', 'Fictional office-supplies brand'),
('VALUEHUB', 'ValueHub', 'Fictional value retail brand'),
('PREMIORA', 'Premiora', 'Fictional premium retail brand'),
('ECOCHOICE', 'EcoChoice', 'Fictional sustainable products brand'),
('EVERYDAY', 'Everyday Essentials', 'Fictional everyday-products brand');

CREATE TABLE #OrderStatusSeed
(
    Code VARCHAR(30) PRIMARY KEY, Name VARCHAR(100), Description VARCHAR(255), SortOrder TINYINT
);
INSERT INTO #OrderStatusSeed VALUES
('PENDING', 'Pending', 'Order created and awaiting confirmation', 1),
('CONFIRMED', 'Confirmed', 'Order confirmed for fulfilment', 2),
('PROCESSING', 'Processing', 'Order is being prepared', 3),
('SHIPPED', 'Shipped', 'Order dispatched from the store', 4),
('DELIVERED', 'Delivered', 'Order delivered to the customer', 5),
('CANCELLED', 'Cancelled', 'Order cancelled before delivery', 6),
('PARTIALLY_RETURNED', 'Partially Returned', 'Some delivered units were accepted for return', 7),
('RETURNED', 'Returned', 'All delivered units were accepted for return', 8);

CREATE TABLE #PaymentMethodSeed
(
    Code VARCHAR(30) PRIMARY KEY, Name VARCHAR(100), Description VARCHAR(255), SortOrder TINYINT
);
INSERT INTO #PaymentMethodSeed VALUES
('CASH', 'Cash', 'Cash collected at store or delivery', 1),
('UPI', 'UPI', 'Unified Payments Interface', 2),
('CREDIT_CARD', 'Credit Card', 'Credit-card payment', 3),
('DEBIT_CARD', 'Debit Card', 'Debit-card payment', 4),
('NET_BANKING', 'Net Banking', 'Online bank-transfer payment', 5),
('WALLET', 'Digital Wallet', 'Approved digital-wallet payment', 6);

CREATE TABLE #PaymentStatusSeed
(
    Code VARCHAR(30) PRIMARY KEY, Name VARCHAR(100), Description VARCHAR(255), SortOrder TINYINT
);
INSERT INTO #PaymentStatusSeed VALUES
('INITIATED', 'Initiated', 'Payment attempt created', 1),
('PENDING', 'Pending', 'Payment confirmation is pending', 2),
('COMPLETED', 'Completed', 'Payment successfully collected', 3),
('FAILED', 'Failed', 'Payment attempt failed', 4),
('CANCELLED', 'Cancelled', 'Payment attempt cancelled', 5),
('PARTIALLY_REFUNDED', 'Partially Refunded', 'Part of the collected amount was refunded', 6),
('REFUNDED', 'Refunded', 'Collected amount was fully refunded', 7);

CREATE TABLE #ReturnReasonSeed
(
    Code VARCHAR(30) PRIMARY KEY, Name VARCHAR(100), Description VARCHAR(255), SortOrder TINYINT
);
INSERT INTO #ReturnReasonSeed VALUES
('DAMAGED', 'Damaged Product', 'Product was damaged on arrival', 1),
('DEFECTIVE', 'Defective Product', 'Product did not function as expected', 2),
('WRONG_ITEM', 'Wrong Item', 'Customer received a different item', 3),
('NOT_AS_DESCRIBED', 'Not as Described', 'Product differed materially from its description', 4),
('SIZE_OR_FIT', 'Size or Fit Issue', 'Product size or fit was unsuitable', 5),
('CUSTOMER_CHANGED_MIND', 'Customer Changed Mind', 'Customer no longer wanted the product', 6),
('OTHER', 'Other', 'Other approved return reason', 7);

CREATE TABLE #ReturnStatusSeed
(
    Code VARCHAR(30) PRIMARY KEY, Name VARCHAR(100), Description VARCHAR(255), SortOrder TINYINT
);
INSERT INTO #ReturnStatusSeed VALUES
('REQUESTED', 'Requested', 'Return request submitted', 1),
('APPROVED', 'Approved', 'Return request approved', 2),
('REJECTED', 'Rejected', 'Return request rejected', 3),
('RECEIVED', 'Received', 'Returned goods received for inspection', 4),
('REFUNDED', 'Refunded', 'Approved refund completed', 5),
('CLOSED', 'Closed', 'Return workflow closed', 6);

CREATE TABLE #MovementTypeSeed
(
    Code VARCHAR(30) PRIMARY KEY, Name VARCHAR(100), Description VARCHAR(255),
    QuantityDirection SMALLINT, RequiresReference BIT, SortOrder TINYINT
);
INSERT INTO #MovementTypeSeed VALUES
('OPENING_STOCK', 'Opening Stock', 'Initial stock loaded for a product-store combination', 1, 0, 1),
('PURCHASE_RECEIPT', 'Purchase Receipt', 'Stock received from a supplier', 1, 1, 2),
('SALE', 'Sale', 'Stock issued for a customer sale', -1, 1, 3),
('SALE_CANCELLATION', 'Sale Cancellation', 'Reserved or issued stock restored after cancellation', 1, 1, 4),
('CUSTOMER_RETURN', 'Customer Return', 'Reusable customer return restored to stock', 1, 1, 5),
('DAMAGE_WRITEOFF', 'Damage Write-off', 'Damaged stock removed from sellable inventory', -1, 1, 6),
('ADJUSTMENT_IN', 'Positive Adjustment', 'Approved positive inventory correction', 1, 1, 7),
('ADJUSTMENT_OUT', 'Negative Adjustment', 'Approved negative inventory correction', -1, 1, 8),
('TRANSFER_IN', 'Transfer In', 'Stock received from another store', 1, 1, 9),
('TRANSFER_OUT', 'Transfer Out', 'Stock sent to another store', -1, 1, 10);

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE target
    SET CategoryName = seed.CategoryName,
        Description = seed.Description,
        IsActive = 1,
        ModifiedDate = SYSDATETIME()
    FROM ref.Category AS target
    INNER JOIN #CategorySeed AS seed ON seed.CategoryCode = target.CategoryCode;

    INSERT INTO ref.Category (CategoryCode, CategoryName, Description, IsActive)
    SELECT seed.CategoryCode, seed.CategoryName, seed.Description, 1
    FROM #CategorySeed AS seed
    WHERE NOT EXISTS (SELECT 1 FROM ref.Category AS target WHERE target.CategoryCode = seed.CategoryCode);

    UPDATE target
    SET CategoryID = c.CategoryID,
        SubCategoryName = seed.SubCategoryName,
        Description = seed.Description,
        IsActive = 1,
        ModifiedDate = SYSDATETIME()
    FROM ref.SubCategory AS target
    INNER JOIN #SubCategorySeed AS seed ON seed.SubCategoryCode = target.SubCategoryCode
    INNER JOIN ref.Category AS c ON c.CategoryCode = seed.CategoryCode;

    INSERT INTO ref.SubCategory (CategoryID, SubCategoryCode, SubCategoryName, Description, IsActive)
    SELECT c.CategoryID, seed.SubCategoryCode, seed.SubCategoryName, seed.Description, 1
    FROM #SubCategorySeed AS seed
    INNER JOIN ref.Category AS c ON c.CategoryCode = seed.CategoryCode
    WHERE NOT EXISTS (SELECT 1 FROM ref.SubCategory AS target WHERE target.SubCategoryCode = seed.SubCategoryCode);

    UPDATE target
    SET BrandName = seed.BrandName,
        Description = seed.Description,
        IsActive = 1,
        ModifiedDate = SYSDATETIME()
    FROM ref.Brand AS target
    INNER JOIN #BrandSeed AS seed ON seed.BrandCode = target.BrandCode;

    INSERT INTO ref.Brand (BrandCode, BrandName, Description, IsActive)
    SELECT seed.BrandCode, seed.BrandName, seed.Description, 1
    FROM #BrandSeed AS seed
    WHERE NOT EXISTS (SELECT 1 FROM ref.Brand AS target WHERE target.BrandCode = seed.BrandCode);

    UPDATE target SET OrderStatusName = seed.Name, Description = seed.Description,
        SortOrder = seed.SortOrder, IsActive = 1
    FROM ref.OrderStatus AS target INNER JOIN #OrderStatusSeed AS seed ON seed.Code = target.OrderStatusCode;
    INSERT INTO ref.OrderStatus (OrderStatusCode, OrderStatusName, Description, SortOrder, IsActive)
    SELECT Code, Name, Description, SortOrder, 1 FROM #OrderStatusSeed AS seed
    WHERE NOT EXISTS (SELECT 1 FROM ref.OrderStatus AS target WHERE target.OrderStatusCode = seed.Code);

    UPDATE target SET PaymentMethodName = seed.Name, Description = seed.Description,
        SortOrder = seed.SortOrder, IsActive = 1
    FROM ref.PaymentMethod AS target INNER JOIN #PaymentMethodSeed AS seed ON seed.Code = target.PaymentMethodCode;
    INSERT INTO ref.PaymentMethod (PaymentMethodCode, PaymentMethodName, Description, SortOrder, IsActive)
    SELECT Code, Name, Description, SortOrder, 1 FROM #PaymentMethodSeed AS seed
    WHERE NOT EXISTS (SELECT 1 FROM ref.PaymentMethod AS target WHERE target.PaymentMethodCode = seed.Code);

    UPDATE target SET PaymentStatusName = seed.Name, Description = seed.Description,
        SortOrder = seed.SortOrder, IsActive = 1
    FROM ref.PaymentStatus AS target INNER JOIN #PaymentStatusSeed AS seed ON seed.Code = target.PaymentStatusCode;
    INSERT INTO ref.PaymentStatus (PaymentStatusCode, PaymentStatusName, Description, SortOrder, IsActive)
    SELECT Code, Name, Description, SortOrder, 1 FROM #PaymentStatusSeed AS seed
    WHERE NOT EXISTS (SELECT 1 FROM ref.PaymentStatus AS target WHERE target.PaymentStatusCode = seed.Code);

    UPDATE target SET ReturnReasonName = seed.Name, Description = seed.Description,
        SortOrder = seed.SortOrder, IsActive = 1
    FROM ref.ReturnReason AS target INNER JOIN #ReturnReasonSeed AS seed ON seed.Code = target.ReturnReasonCode;
    INSERT INTO ref.ReturnReason (ReturnReasonCode, ReturnReasonName, Description, SortOrder, IsActive)
    SELECT Code, Name, Description, SortOrder, 1 FROM #ReturnReasonSeed AS seed
    WHERE NOT EXISTS (SELECT 1 FROM ref.ReturnReason AS target WHERE target.ReturnReasonCode = seed.Code);

    UPDATE target SET ReturnStatusName = seed.Name, Description = seed.Description,
        SortOrder = seed.SortOrder, IsActive = 1
    FROM ref.ReturnStatus AS target INNER JOIN #ReturnStatusSeed AS seed ON seed.Code = target.ReturnStatusCode;
    INSERT INTO ref.ReturnStatus (ReturnStatusCode, ReturnStatusName, Description, SortOrder, IsActive)
    SELECT Code, Name, Description, SortOrder, 1 FROM #ReturnStatusSeed AS seed
    WHERE NOT EXISTS (SELECT 1 FROM ref.ReturnStatus AS target WHERE target.ReturnStatusCode = seed.Code);

    UPDATE target
    SET InventoryMovementTypeName = seed.Name,
        Description = seed.Description,
        QuantityDirection = seed.QuantityDirection,
        RequiresReference = seed.RequiresReference,
        SortOrder = seed.SortOrder,
        IsActive = 1
    FROM ref.InventoryMovementType AS target
    INNER JOIN #MovementTypeSeed AS seed ON seed.Code = target.InventoryMovementTypeCode;
    INSERT INTO ref.InventoryMovementType
        (InventoryMovementTypeCode, InventoryMovementTypeName, Description,
         QuantityDirection, RequiresReference, SortOrder, IsActive)
    SELECT Code, Name, Description, QuantityDirection, RequiresReference, SortOrder, 1
    FROM #MovementTypeSeed AS seed
    WHERE NOT EXISTS
        (SELECT 1 FROM ref.InventoryMovementType AS target WHERE target.InventoryMovementTypeCode = seed.Code);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @Validation TABLE
(
    SequenceNumber TINYINT,
    TableName SYSNAME,
    ExpectedCount INT,
    ExistingApprovedCount INT,
    TotalTableCount INT
);

INSERT INTO @Validation VALUES
(1, N'ref.Category', 8,
 (SELECT COUNT(*) FROM ref.Category WHERE CategoryCode IN (SELECT CategoryCode FROM #CategorySeed)),
 (SELECT COUNT(*) FROM ref.Category)),
(2, N'ref.SubCategory', 32,
 (SELECT COUNT(*) FROM ref.SubCategory WHERE SubCategoryCode IN (SELECT SubCategoryCode FROM #SubCategorySeed)),
 (SELECT COUNT(*) FROM ref.SubCategory)),
(3, N'ref.Brand', 40,
 (SELECT COUNT(*) FROM ref.Brand WHERE BrandCode IN (SELECT BrandCode FROM #BrandSeed)),
 (SELECT COUNT(*) FROM ref.Brand)),
(4, N'ref.OrderStatus', 8,
 (SELECT COUNT(*) FROM ref.OrderStatus WHERE OrderStatusCode IN (SELECT Code FROM #OrderStatusSeed)),
 (SELECT COUNT(*) FROM ref.OrderStatus)),
(5, N'ref.PaymentMethod', 6,
 (SELECT COUNT(*) FROM ref.PaymentMethod WHERE PaymentMethodCode IN (SELECT Code FROM #PaymentMethodSeed)),
 (SELECT COUNT(*) FROM ref.PaymentMethod)),
(6, N'ref.PaymentStatus', 7,
 (SELECT COUNT(*) FROM ref.PaymentStatus WHERE PaymentStatusCode IN (SELECT Code FROM #PaymentStatusSeed)),
 (SELECT COUNT(*) FROM ref.PaymentStatus)),
(7, N'ref.ReturnReason', 7,
 (SELECT COUNT(*) FROM ref.ReturnReason WHERE ReturnReasonCode IN (SELECT Code FROM #ReturnReasonSeed)),
 (SELECT COUNT(*) FROM ref.ReturnReason)),
(8, N'ref.ReturnStatus', 6,
 (SELECT COUNT(*) FROM ref.ReturnStatus WHERE ReturnStatusCode IN (SELECT Code FROM #ReturnStatusSeed)),
 (SELECT COUNT(*) FROM ref.ReturnStatus)),
(9, N'ref.InventoryMovementType', 10,
 (SELECT COUNT(*) FROM ref.InventoryMovementType WHERE InventoryMovementTypeCode IN (SELECT Code FROM #MovementTypeSeed)),
 (SELECT COUNT(*) FROM ref.InventoryMovementType));

IF EXISTS
(
    SELECT 1 FROM @Validation
    WHERE ExpectedCount <> ExistingApprovedCount OR ExpectedCount <> TotalTableCount
)
BEGIN
    SELECT * FROM @Validation ORDER BY SequenceNumber;
    THROW 51202, 'Reference-data validation failed: missing or unexpected reference rows exist.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM ref.SubCategory AS sc
    INNER JOIN #SubCategorySeed AS seed ON seed.SubCategoryCode = sc.SubCategoryCode
    INNER JOIN ref.Category AS c ON c.CategoryID = sc.CategoryID
    WHERE c.CategoryCode <> seed.CategoryCode
)
BEGIN
    THROW 51203, 'Reference-data validation failed: subcategory hierarchy mismatch.', 1;
END;

SELECT
    SequenceNumber,
    TableName,
    ExpectedCount,
    ExistingApprovedCount,
    TotalTableCount,
    'PASSED' AS ValidationStatus
FROM @Validation
ORDER BY SequenceNumber;

SELECT
    SUM(ExpectedCount) AS TotalExpectedRows,
    SUM(ExistingApprovedCount) AS TotalApprovedRows,
    CASE WHEN SUM(ExpectedCount) = SUM(ExistingApprovedCount) THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM @Validation;

RAISERROR('10_Load_Reference_Data.sql completed successfully: 124 curated rows validated.', 10, 1) WITH NOWAIT;
GO
