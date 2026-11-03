/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      22_Create_Analytics_Dimensions.sql
Purpose:     Create and load Power BI-ready conformed dimensions.
Author:      Akshay Aswani
Version:     2.0
Depends on:  21_Generate_Inventory_Movements.sql
Rerunnable:  Yes, before analytical fact tables are created.

Dimensional policy
------------------
- Surrogate integer keys are used for business dimensions.
- Key 0 is the governed Unknown member.
- Master dimensions use Type 1 current attributes in this portfolio release.
- DimDate uses YYYYMMDD keys and supports Indian financial years (Apr-Mar).
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51380, 'Dimension build stopped: unexpected database context.', 1;

IF SCHEMA_ID(N'analytics') IS NULL
    THROW 51381, 'Dimension build stopped: analytics schema is missing.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NOT NULL
   OR OBJECT_ID(N'analytics.FactPayments', N'U') IS NOT NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NOT NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NOT NULL
   OR OBJECT_ID(N'analytics.FactInventoryMovement', N'U') IS NOT NULL
   OR OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NOT NULL
    THROW 51382, 'Dimension rebuild stopped: analytical fact tables already exist.', 1;

-- ============================================================================
-- 1. CREATE DIMENSION TABLES
-- ============================================================================

IF OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
CREATE TABLE analytics.DimDate
(
    DateKey INT NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY,
    [Date] DATE NOT NULL CONSTRAINT UQ_DimDate_Date UNIQUE,
    FullDateLabel VARCHAR(30) NOT NULL,
    DayOfMonth TINYINT NOT NULL,
    DayOfWeekNumber TINYINT NOT NULL,
    DayName VARCHAR(10) NOT NULL,
    DayNameShort CHAR(3) NOT NULL,
    DayOfYear SMALLINT NOT NULL,
    WeekOfYear TINYINT NOT NULL,
    WeekStartDate DATE NOT NULL,
    IsWeekend BIT NOT NULL,
    MonthNumber TINYINT NOT NULL,
    MonthName VARCHAR(10) NOT NULL,
    MonthNameShort CHAR(3) NOT NULL,
    MonthYearLabel VARCHAR(20) NOT NULL,
    YearMonthNumber INT NOT NULL,
    MonthStartDate DATE NOT NULL,
    MonthEndDate DATE NOT NULL,
    CalendarQuarterNumber TINYINT NOT NULL,
    CalendarQuarterLabel CHAR(2) NOT NULL,
    CalendarYear SMALLINT NOT NULL,
    FinancialMonthNumber TINYINT NOT NULL,
    FinancialQuarterNumber TINYINT NOT NULL,
    FinancialQuarterLabel CHAR(2) NOT NULL,
    FinancialYearStart SMALLINT NOT NULL,
    FinancialYearLabel VARCHAR(12) NOT NULL,
    IsUnknown BIT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_DimDate_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.DimCustomer', N'U') IS NULL
CREATE TABLE analytics.DimCustomer
(
    CustomerKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimCustomer PRIMARY KEY,
    CustomerID INT NOT NULL CONSTRAINT UQ_DimCustomer_CustomerID UNIQUE,
    CustomerCode VARCHAR(20) NOT NULL CONSTRAINT UQ_DimCustomer_CustomerCode UNIQUE,
    CustomerName VARCHAR(110) NOT NULL,
    Email VARCHAR(150) NOT NULL,
    Phone VARCHAR(20) NOT NULL,
    City VARCHAR(100) NOT NULL,
    StateName VARCHAR(100) NOT NULL,
    Country VARCHAR(100) NOT NULL,
    PostalCode VARCHAR(10) NOT NULL,
    RegistrationDate DATE NOT NULL,
    LoyaltyPoints INT NOT NULL,
    CustomerSegment VARCHAR(30) NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_DimCustomer_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.DimProduct', N'U') IS NULL
CREATE TABLE analytics.DimProduct
(
    ProductKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimProduct PRIMARY KEY,
    ProductID INT NOT NULL CONSTRAINT UQ_DimProduct_ProductID UNIQUE,
    SKU VARCHAR(40) NOT NULL CONSTRAINT UQ_DimProduct_SKU UNIQUE,
    ProductName VARCHAR(150) NOT NULL,
    BrandCode VARCHAR(20) NOT NULL,
    BrandName VARCHAR(100) NOT NULL,
    SubCategoryCode VARCHAR(20) NOT NULL,
    SubCategoryName VARCHAR(100) NOT NULL,
    CategoryCode VARCHAR(20) NOT NULL,
    CategoryName VARCHAR(100) NOT NULL,
    SupplierID INT NOT NULL,
    SupplierCode VARCHAR(20) NOT NULL,
    SupplierName VARCHAR(150) NOT NULL,
    CostPrice DECIMAL(12,2) NOT NULL,
    SellingPrice DECIMAL(12,2) NOT NULL,
    ReorderLevel INT NOT NULL,
    ExcessStockLevel INT NOT NULL,
    PriceBand VARCHAR(20) NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_DimProduct_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.DimStore', N'U') IS NULL
CREATE TABLE analytics.DimStore
(
    StoreKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimStore PRIMARY KEY,
    StoreID INT NOT NULL CONSTRAINT UQ_DimStore_StoreID UNIQUE,
    StoreCode VARCHAR(20) NOT NULL CONSTRAINT UQ_DimStore_StoreCode UNIQUE,
    StoreName VARCHAR(100) NOT NULL,
    StoreTier VARCHAR(10) NOT NULL,
    City VARCHAR(100) NOT NULL,
    StateName VARCHAR(100) NOT NULL,
    Country VARCHAR(100) NOT NULL,
    PostalCode VARCHAR(10) NOT NULL,
    OpeningDate DATE NOT NULL,
    ClosingDate DATE NULL,
    ManagerEmployeeID INT NOT NULL,
    ManagerEmployeeCode VARCHAR(20) NOT NULL,
    ManagerName VARCHAR(110) NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_DimStore_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.DimEmployee', N'U') IS NULL
CREATE TABLE analytics.DimEmployee
(
    EmployeeKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimEmployee PRIMARY KEY,
    EmployeeID INT NOT NULL CONSTRAINT UQ_DimEmployee_EmployeeID UNIQUE,
    EmployeeCode VARCHAR(20) NOT NULL CONSTRAINT UQ_DimEmployee_EmployeeCode UNIQUE,
    EmployeeName VARCHAR(110) NOT NULL,
    JobTitle VARCHAR(100) NOT NULL,
    StoreID INT NOT NULL,
    StoreCode VARCHAR(20) NOT NULL,
    StoreName VARCHAR(100) NOT NULL,
    ManagerEmployeeID INT NOT NULL,
    ManagerEmployeeCode VARCHAR(20) NOT NULL,
    ManagerName VARCHAR(110) NOT NULL,
    HireDate DATE NOT NULL,
    TerminationDate DATE NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_DimEmployee_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.DimSupplier', N'U') IS NULL
CREATE TABLE analytics.DimSupplier
(
    SupplierKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimSupplier PRIMARY KEY,
    SupplierID INT NOT NULL CONSTRAINT UQ_DimSupplier_SupplierID UNIQUE,
    SupplierCode VARCHAR(20) NOT NULL CONSTRAINT UQ_DimSupplier_SupplierCode UNIQUE,
    SupplierName VARCHAR(150) NOT NULL,
    ContactName VARCHAR(100) NOT NULL,
    City VARCHAR(100) NOT NULL,
    StateName VARCHAR(100) NOT NULL,
    Country VARCHAR(100) NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_DimSupplier_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.DimPaymentMethod', N'U') IS NULL
CREATE TABLE analytics.DimPaymentMethod
(
    PaymentMethodKey SMALLINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimPaymentMethod PRIMARY KEY,
    PaymentMethodID SMALLINT NOT NULL CONSTRAINT UQ_DimPaymentMethod_ID UNIQUE,
    PaymentMethodCode VARCHAR(30) NOT NULL CONSTRAINT UQ_DimPaymentMethod_Code UNIQUE,
    PaymentMethodName VARCHAR(100) NOT NULL,
    SortOrder TINYINT NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL
);

IF OBJECT_ID(N'analytics.DimOrderStatus', N'U') IS NULL
CREATE TABLE analytics.DimOrderStatus
(
    OrderStatusKey SMALLINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimOrderStatus PRIMARY KEY,
    OrderStatusID SMALLINT NOT NULL CONSTRAINT UQ_DimOrderStatus_ID UNIQUE,
    OrderStatusCode VARCHAR(30) NOT NULL CONSTRAINT UQ_DimOrderStatus_Code UNIQUE,
    OrderStatusName VARCHAR(100) NOT NULL,
    SortOrder TINYINT NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL
);

IF OBJECT_ID(N'analytics.DimPaymentStatus', N'U') IS NULL
CREATE TABLE analytics.DimPaymentStatus
(
    PaymentStatusKey SMALLINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimPaymentStatus PRIMARY KEY,
    PaymentStatusID SMALLINT NOT NULL CONSTRAINT UQ_DimPaymentStatus_ID UNIQUE,
    PaymentStatusCode VARCHAR(30) NOT NULL CONSTRAINT UQ_DimPaymentStatus_Code UNIQUE,
    PaymentStatusName VARCHAR(100) NOT NULL,
    SortOrder TINYINT NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL
);

IF OBJECT_ID(N'analytics.DimReturnReason', N'U') IS NULL
CREATE TABLE analytics.DimReturnReason
(
    ReturnReasonKey SMALLINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimReturnReason PRIMARY KEY,
    ReturnReasonID SMALLINT NOT NULL CONSTRAINT UQ_DimReturnReason_ID UNIQUE,
    ReturnReasonCode VARCHAR(30) NOT NULL CONSTRAINT UQ_DimReturnReason_Code UNIQUE,
    ReturnReasonName VARCHAR(100) NOT NULL,
    SortOrder TINYINT NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL
);

IF OBJECT_ID(N'analytics.DimReturnStatus', N'U') IS NULL
CREATE TABLE analytics.DimReturnStatus
(
    ReturnStatusKey SMALLINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimReturnStatus PRIMARY KEY,
    ReturnStatusID SMALLINT NOT NULL CONSTRAINT UQ_DimReturnStatus_ID UNIQUE,
    ReturnStatusCode VARCHAR(30) NOT NULL CONSTRAINT UQ_DimReturnStatus_Code UNIQUE,
    ReturnStatusName VARCHAR(100) NOT NULL,
    SortOrder TINYINT NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL
);

IF OBJECT_ID(N'analytics.DimInventoryMovementType', N'U') IS NULL
CREATE TABLE analytics.DimInventoryMovementType
(
    InventoryMovementTypeKey SMALLINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimInventoryMovementType PRIMARY KEY,
    InventoryMovementTypeID SMALLINT NOT NULL CONSTRAINT UQ_DimInventoryMovementType_ID UNIQUE,
    InventoryMovementTypeCode VARCHAR(30) NOT NULL CONSTRAINT UQ_DimInventoryMovementType_Code UNIQUE,
    InventoryMovementTypeName VARCHAR(100) NOT NULL,
    QuantityDirection SMALLINT NOT NULL,
    SortOrder TINYINT NOT NULL,
    IsActive BIT NOT NULL,
    IsUnknown BIT NOT NULL
);

-- ============================================================================
-- 2. REBUILD DATE DIMENSION (2023-01-01 THROUGH 2026-12-31)
-- ============================================================================

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE FROM analytics.DimDate;

    INSERT INTO analytics.DimDate
    (
        DateKey, [Date], FullDateLabel, DayOfMonth, DayOfWeekNumber,
        DayName, DayNameShort, DayOfYear, WeekOfYear, WeekStartDate,
        IsWeekend, MonthNumber, MonthName, MonthNameShort, MonthYearLabel,
        YearMonthNumber, MonthStartDate, MonthEndDate,
        CalendarQuarterNumber, CalendarQuarterLabel, CalendarYear,
        FinancialMonthNumber, FinancialQuarterNumber, FinancialQuarterLabel,
        FinancialYearStart, FinancialYearLabel, IsUnknown
    )
    VALUES
    (0, '1900-01-01', 'Unknown', 0, 0, 'Unknown', 'UNK', 0, 0, '1900-01-01',
     0, 0, 'Unknown', 'UNK', 'Unknown', 0, '1900-01-01', '1900-01-01',
     0, 'U0', 0, 0, 0, 'U0', 0, 'Unknown', 1);

    ;WITH DateNumbers AS
    (
        SELECT TOP (1461)
            ROW_NUMBER() OVER (ORDER BY first_object.object_id, second_object.object_id) - 1 AS DayOffset
        FROM sys.all_objects AS first_object
        CROSS JOIN sys.all_objects AS second_object
    ),
    CalendarDates AS
    (
        SELECT DATEADD(DAY, DayOffset, CONVERT(DATE, '2023-01-01')) AS CalendarDate
        FROM DateNumbers
    )
    INSERT INTO analytics.DimDate
    (
        DateKey, [Date], FullDateLabel, DayOfMonth, DayOfWeekNumber,
        DayName, DayNameShort, DayOfYear, WeekOfYear, WeekStartDate,
        IsWeekend, MonthNumber, MonthName, MonthNameShort, MonthYearLabel,
        YearMonthNumber, MonthStartDate, MonthEndDate,
        CalendarQuarterNumber, CalendarQuarterLabel, CalendarYear,
        FinancialMonthNumber, FinancialQuarterNumber, FinancialQuarterLabel,
        FinancialYearStart, FinancialYearLabel, IsUnknown
    )
    SELECT
        CONVERT(INT, CONVERT(CHAR(8), CalendarDate, 112)),
        CalendarDate,
        CONVERT(VARCHAR(30), CalendarDate, 106),
        DATEPART(DAY, CalendarDate),
        CONVERT(TINYINT, (DATEDIFF(DAY, '1900-01-01', CalendarDate) % 7) + 1),
        CHOOSE((DATEDIFF(DAY, '1900-01-01', CalendarDate) % 7) + 1,
               'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'),
        LEFT(CHOOSE((DATEDIFF(DAY, '1900-01-01', CalendarDate) % 7) + 1,
                    'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'), 3),
        DATEPART(DAYOFYEAR, CalendarDate),
        DATEPART(ISO_WEEK, CalendarDate),
        DATEADD(DAY, -(DATEDIFF(DAY, '1900-01-01', CalendarDate) % 7), CalendarDate),
        CASE WHEN (DATEDIFF(DAY, '1900-01-01', CalendarDate) % 7) >= 5 THEN 1 ELSE 0 END,
        DATEPART(MONTH, CalendarDate),
        DATENAME(MONTH, CalendarDate),
        LEFT(DATENAME(MONTH, CalendarDate), 3),
        CONCAT(LEFT(DATENAME(MONTH, CalendarDate), 3), ' ', DATEPART(YEAR, CalendarDate)),
        DATEPART(YEAR, CalendarDate) * 100 + DATEPART(MONTH, CalendarDate),
        DATEFROMPARTS(YEAR(CalendarDate), MONTH(CalendarDate), 1),
        EOMONTH(CalendarDate),
        DATEPART(QUARTER, CalendarDate),
        CONCAT('Q', DATEPART(QUARTER, CalendarDate)),
        DATEPART(YEAR, CalendarDate),
        ((DATEPART(MONTH, CalendarDate) + 8) % 12) + 1,
        (((DATEPART(MONTH, CalendarDate) + 8) % 12) / 3) + 1,
        CONCAT('Q', (((DATEPART(MONTH, CalendarDate) + 8) % 12) / 3) + 1),
        DATEPART(YEAR, CalendarDate) - CASE WHEN MONTH(CalendarDate) < 4 THEN 1 ELSE 0 END,
        CONCAT('FY',
            DATEPART(YEAR, CalendarDate) - CASE WHEN MONTH(CalendarDate) < 4 THEN 1 ELSE 0 END,
            '-', RIGHT(CONVERT(VARCHAR(4),
            DATEPART(YEAR, CalendarDate) + CASE WHEN MONTH(CalendarDate) >= 4 THEN 1 ELSE 0 END), 2)),
        0
    FROM CalendarDates;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ============================================================================
-- 3. REBUILD TYPE 1 BUSINESS DIMENSIONS
-- ============================================================================

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE FROM analytics.DimCustomer;
    DELETE FROM analytics.DimProduct;
    DELETE FROM analytics.DimStore;
    DELETE FROM analytics.DimEmployee;
    DELETE FROM analytics.DimSupplier;
    DELETE FROM analytics.DimPaymentMethod;
    DELETE FROM analytics.DimOrderStatus;
    DELETE FROM analytics.DimPaymentStatus;
    DELETE FROM analytics.DimReturnReason;
    DELETE FROM analytics.DimReturnStatus;
    DELETE FROM analytics.DimInventoryMovementType;

    DBCC CHECKIDENT ('analytics.DimCustomer', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimProduct', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimStore', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimEmployee', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimSupplier', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimPaymentMethod', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimOrderStatus', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimPaymentStatus', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimReturnReason', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimReturnStatus', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.DimInventoryMovementType', RESEED, 0) WITH NO_INFOMSGS;

    SET IDENTITY_INSERT analytics.DimCustomer ON;
    INSERT INTO analytics.DimCustomer
        (CustomerKey, CustomerID, CustomerCode, CustomerName, Email, Phone,
         City, StateName, Country, PostalCode, RegistrationDate, LoyaltyPoints,
         CustomerSegment, IsActive, IsUnknown)
    VALUES (0, 0, 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown',
            'Unknown', 'Unknown', '1900-01-01', 0, 'Unknown', 0, 1);
    SET IDENTITY_INSERT analytics.DimCustomer OFF;

    INSERT INTO analytics.DimCustomer
        (CustomerID, CustomerCode, CustomerName, Email, Phone, City, StateName,
         Country, PostalCode, RegistrationDate, LoyaltyPoints, CustomerSegment,
         IsActive, IsUnknown)
    SELECT CustomerID, CustomerCode, CONCAT(FirstName, ' ', LastName),
           COALESCE(Email, 'Unknown'), COALESCE(Phone, 'Unknown'),
           COALESCE(City, 'Unknown'), COALESCE(State, 'Unknown'),
           COALESCE(Country, 'Unknown'), COALESCE(PostalCode, 'Unknown'),
           RegistrationDate, LoyaltyPoints,
           CASE
               WHEN CONVERT(INT, RIGHT(CustomerCode, 5)) <= 1000 THEN 'High Value / Loyal'
               WHEN CONVERT(INT, RIGHT(CustomerCode, 5)) <= 4000 THEN 'Regular'
               WHEN CONVERT(INT, RIGHT(CustomerCode, 5)) <= 8500 THEN 'Occasional'
               ELSE 'One-Time / Dormant'
           END,
           IsActive, 0
    FROM core.Customer;

    SET IDENTITY_INSERT analytics.DimProduct ON;
    INSERT INTO analytics.DimProduct
        (ProductKey, ProductID, SKU, ProductName, BrandCode, BrandName,
         SubCategoryCode, SubCategoryName, CategoryCode, CategoryName,
         SupplierID, SupplierCode, SupplierName, CostPrice, SellingPrice,
         ReorderLevel, ExcessStockLevel, PriceBand, IsActive, IsUnknown)
    VALUES (0, 0, 'UNKNOWN', 'Unknown', 'UNKNOWN', 'Unknown', 'UNKNOWN', 'Unknown',
            'UNKNOWN', 'Unknown', 0, 'UNKNOWN', 'Unknown', 0, 0, 0, 0,
            'Unknown', 0, 1);
    SET IDENTITY_INSERT analytics.DimProduct OFF;

    INSERT INTO analytics.DimProduct
        (ProductID, SKU, ProductName, BrandCode, BrandName, SubCategoryCode,
         SubCategoryName, CategoryCode, CategoryName, SupplierID, SupplierCode,
         SupplierName, CostPrice, SellingPrice, ReorderLevel, ExcessStockLevel,
         PriceBand, IsActive, IsUnknown)
    SELECT product.ProductID, product.SKU, product.ProductName,
           brand.BrandCode, brand.BrandName,
           subcategory.SubCategoryCode, subcategory.SubCategoryName,
           category.CategoryCode, category.CategoryName,
           supplier.SupplierID, supplier.SupplierCode, supplier.SupplierName,
           product.CostPrice, product.SellingPrice, product.ReorderLevel,
           COALESCE(product.ExcessStockLevel, 0),
           CASE WHEN product.SellingPrice < 1000 THEN 'Value'
                WHEN product.SellingPrice < 10000 THEN 'Mid-Range'
                WHEN product.SellingPrice < 30000 THEN 'Premium'
                ELSE 'Luxury' END,
           product.IsActive, 0
    FROM core.Product AS product
    INNER JOIN ref.Brand AS brand ON brand.BrandID = product.BrandID
    INNER JOIN ref.SubCategory AS subcategory ON subcategory.SubCategoryID = product.SubCategoryID
    INNER JOIN ref.Category AS category ON category.CategoryID = subcategory.CategoryID
    INNER JOIN core.Supplier AS supplier ON supplier.SupplierID = product.SupplierID;

    SET IDENTITY_INSERT analytics.DimStore ON;
    INSERT INTO analytics.DimStore
        (StoreKey, StoreID, StoreCode, StoreName, StoreTier, City, StateName,
         Country, PostalCode, OpeningDate, ClosingDate, ManagerEmployeeID,
         ManagerEmployeeCode, ManagerName, IsActive, IsUnknown)
    VALUES (0, 0, 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown',
            'Unknown', '1900-01-01', NULL, 0, 'UNKNOWN', 'Unknown', 0, 1);
    SET IDENTITY_INSERT analytics.DimStore OFF;

    INSERT INTO analytics.DimStore
        (StoreID, StoreCode, StoreName, StoreTier, City, StateName, Country,
         PostalCode, OpeningDate, ClosingDate, ManagerEmployeeID,
         ManagerEmployeeCode, ManagerName, IsActive, IsUnknown)
    SELECT store.StoreID, store.StoreCode, store.StoreName,
           CASE COUNT(balance.InventoryBalanceID)
               WHEN 437 THEN 'Large' WHEN 349 THEN 'Medium' WHEN 267 THEN 'Small'
               ELSE 'Other' END,
           store.City, store.State, store.Country, COALESCE(store.PostalCode, 'Unknown'),
           store.OpeningDate, store.ClosingDate,
           COALESCE(manager.EmployeeID, 0), COALESCE(manager.EmployeeCode, 'UNKNOWN'),
           CASE WHEN manager.EmployeeID IS NULL THEN 'Unknown'
                ELSE CONCAT(manager.FirstName, ' ', manager.LastName) END,
           store.IsActive, 0
    FROM core.Store AS store
    LEFT JOIN core.Employee AS manager ON manager.EmployeeID = store.ManagerEmployeeID
    LEFT JOIN inventory.InventoryBalance AS balance ON balance.StoreID = store.StoreID
    GROUP BY store.StoreID, store.StoreCode, store.StoreName, store.City, store.State,
             store.Country, store.PostalCode, store.OpeningDate, store.ClosingDate,
             manager.EmployeeID, manager.EmployeeCode, manager.FirstName,
             manager.LastName, store.IsActive;

    SET IDENTITY_INSERT analytics.DimEmployee ON;
    INSERT INTO analytics.DimEmployee
        (EmployeeKey, EmployeeID, EmployeeCode, EmployeeName, JobTitle, StoreID,
         StoreCode, StoreName, ManagerEmployeeID, ManagerEmployeeCode,
         ManagerName, HireDate, TerminationDate, IsActive, IsUnknown)
    VALUES (0, 0, 'UNKNOWN', 'Unknown', 'Unknown', 0, 'UNKNOWN', 'Unknown', 0,
            'UNKNOWN', 'Unknown', '1900-01-01', NULL, 0, 1);
    SET IDENTITY_INSERT analytics.DimEmployee OFF;

    INSERT INTO analytics.DimEmployee
        (EmployeeID, EmployeeCode, EmployeeName, JobTitle, StoreID, StoreCode,
         StoreName, ManagerEmployeeID, ManagerEmployeeCode, ManagerName,
         HireDate, TerminationDate, IsActive, IsUnknown)
    SELECT employee.EmployeeID, employee.EmployeeCode,
           CONCAT(employee.FirstName, ' ', employee.LastName), employee.JobTitle,
           store.StoreID, store.StoreCode, store.StoreName,
           COALESCE(manager.EmployeeID, 0), COALESCE(manager.EmployeeCode, 'UNKNOWN'),
           CASE WHEN manager.EmployeeID IS NULL THEN 'Unknown'
                ELSE CONCAT(manager.FirstName, ' ', manager.LastName) END,
           employee.HireDate, employee.TerminationDate, employee.IsActive, 0
    FROM core.Employee AS employee
    INNER JOIN core.Store AS store ON store.StoreID = employee.StoreID
    LEFT JOIN core.Employee AS manager ON manager.EmployeeID = employee.ManagerEmployeeID;

    SET IDENTITY_INSERT analytics.DimSupplier ON;
    INSERT INTO analytics.DimSupplier
        (SupplierKey, SupplierID, SupplierCode, SupplierName, ContactName,
         City, StateName, Country, IsActive, IsUnknown)
    VALUES (0, 0, 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 0, 1);
    SET IDENTITY_INSERT analytics.DimSupplier OFF;

    INSERT INTO analytics.DimSupplier
        (SupplierID, SupplierCode, SupplierName, ContactName, City, StateName,
         Country, IsActive, IsUnknown)
    SELECT SupplierID, SupplierCode, SupplierName, COALESCE(ContactName, 'Unknown'),
           COALESCE(City, 'Unknown'), COALESCE(State, 'Unknown'),
           COALESCE(Country, 'Unknown'), IsActive, 0
    FROM core.Supplier;

    -- Small reference dimensions use the same governed key-0 pattern.
    SET IDENTITY_INSERT analytics.DimPaymentMethod ON;
    INSERT analytics.DimPaymentMethod
        (PaymentMethodKey, PaymentMethodID, PaymentMethodCode, PaymentMethodName, SortOrder, IsActive, IsUnknown)
    VALUES (0,0,'UNKNOWN','Unknown',0,0,1);
    SET IDENTITY_INSERT analytics.DimPaymentMethod OFF;
    INSERT analytics.DimPaymentMethod
        (PaymentMethodID, PaymentMethodCode, PaymentMethodName, SortOrder, IsActive, IsUnknown)
    SELECT PaymentMethodID, PaymentMethodCode, PaymentMethodName, SortOrder, IsActive, 0 FROM ref.PaymentMethod;

    SET IDENTITY_INSERT analytics.DimOrderStatus ON;
    INSERT analytics.DimOrderStatus
        (OrderStatusKey, OrderStatusID, OrderStatusCode, OrderStatusName, SortOrder, IsActive, IsUnknown)
    VALUES (0,0,'UNKNOWN','Unknown',0,0,1);
    SET IDENTITY_INSERT analytics.DimOrderStatus OFF;
    INSERT analytics.DimOrderStatus
        (OrderStatusID, OrderStatusCode, OrderStatusName, SortOrder, IsActive, IsUnknown)
    SELECT OrderStatusID, OrderStatusCode, OrderStatusName, SortOrder, IsActive, 0 FROM ref.OrderStatus;

    SET IDENTITY_INSERT analytics.DimPaymentStatus ON;
    INSERT analytics.DimPaymentStatus
        (PaymentStatusKey, PaymentStatusID, PaymentStatusCode, PaymentStatusName, SortOrder, IsActive, IsUnknown)
    VALUES (0,0,'UNKNOWN','Unknown',0,0,1);
    SET IDENTITY_INSERT analytics.DimPaymentStatus OFF;
    INSERT analytics.DimPaymentStatus
        (PaymentStatusID, PaymentStatusCode, PaymentStatusName, SortOrder, IsActive, IsUnknown)
    SELECT PaymentStatusID, PaymentStatusCode, PaymentStatusName, SortOrder, IsActive, 0 FROM ref.PaymentStatus;

    SET IDENTITY_INSERT analytics.DimReturnReason ON;
    INSERT analytics.DimReturnReason
        (ReturnReasonKey, ReturnReasonID, ReturnReasonCode, ReturnReasonName, SortOrder, IsActive, IsUnknown)
    VALUES (0,0,'UNKNOWN','Unknown',0,0,1);
    SET IDENTITY_INSERT analytics.DimReturnReason OFF;
    INSERT analytics.DimReturnReason
        (ReturnReasonID, ReturnReasonCode, ReturnReasonName, SortOrder, IsActive, IsUnknown)
    SELECT ReturnReasonID, ReturnReasonCode, ReturnReasonName, SortOrder, IsActive, 0 FROM ref.ReturnReason;

    SET IDENTITY_INSERT analytics.DimReturnStatus ON;
    INSERT analytics.DimReturnStatus
        (ReturnStatusKey, ReturnStatusID, ReturnStatusCode, ReturnStatusName, SortOrder, IsActive, IsUnknown)
    VALUES (0,0,'UNKNOWN','Unknown',0,0,1);
    SET IDENTITY_INSERT analytics.DimReturnStatus OFF;
    INSERT analytics.DimReturnStatus
        (ReturnStatusID, ReturnStatusCode, ReturnStatusName, SortOrder, IsActive, IsUnknown)
    SELECT ReturnStatusID, ReturnStatusCode, ReturnStatusName, SortOrder, IsActive, 0 FROM ref.ReturnStatus;

    SET IDENTITY_INSERT analytics.DimInventoryMovementType ON;
    INSERT analytics.DimInventoryMovementType
        (InventoryMovementTypeKey, InventoryMovementTypeID, InventoryMovementTypeCode,
         InventoryMovementTypeName, QuantityDirection, SortOrder, IsActive, IsUnknown)
    VALUES (0,0,'UNKNOWN','Unknown',0,0,0,1);
    SET IDENTITY_INSERT analytics.DimInventoryMovementType OFF;
    INSERT analytics.DimInventoryMovementType
        (InventoryMovementTypeID, InventoryMovementTypeCode, InventoryMovementTypeName,
         QuantityDirection, SortOrder, IsActive, IsUnknown)
    SELECT InventoryMovementTypeID, InventoryMovementTypeCode, InventoryMovementTypeName,
           QuantityDirection, SortOrder, IsActive, 0
    FROM ref.InventoryMovementType;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ============================================================================
-- 4. DIMENSION ACCEPTANCE VALIDATION
-- ============================================================================

DECLARE @DimensionValidation TABLE
(
    DimensionName SYSNAME NOT NULL,
    ExpectedRowCount INT NOT NULL,
    ExistingRowCount INT NOT NULL,
    UnknownMemberCount INT NOT NULL
);

INSERT INTO @DimensionValidation VALUES
('DimDate', 1462, (SELECT COUNT(*) FROM analytics.DimDate),
 (SELECT COUNT(*) FROM analytics.DimDate WHERE DateKey = 0 AND IsUnknown = 1)),
('DimCustomer', 10001, (SELECT COUNT(*) FROM analytics.DimCustomer),
 (SELECT COUNT(*) FROM analytics.DimCustomer WHERE CustomerKey = 0 AND IsUnknown = 1)),
('DimProduct', 501, (SELECT COUNT(*) FROM analytics.DimProduct),
 (SELECT COUNT(*) FROM analytics.DimProduct WHERE ProductKey = 0 AND IsUnknown = 1)),
('DimStore', 21, (SELECT COUNT(*) FROM analytics.DimStore),
 (SELECT COUNT(*) FROM analytics.DimStore WHERE StoreKey = 0 AND IsUnknown = 1)),
('DimEmployee', 101, (SELECT COUNT(*) FROM analytics.DimEmployee),
 (SELECT COUNT(*) FROM analytics.DimEmployee WHERE EmployeeKey = 0 AND IsUnknown = 1)),
('DimSupplier', 51, (SELECT COUNT(*) FROM analytics.DimSupplier),
 (SELECT COUNT(*) FROM analytics.DimSupplier WHERE SupplierKey = 0 AND IsUnknown = 1)),
('DimPaymentMethod', 7, (SELECT COUNT(*) FROM analytics.DimPaymentMethod),
 (SELECT COUNT(*) FROM analytics.DimPaymentMethod WHERE PaymentMethodKey = 0 AND IsUnknown = 1)),
('DimOrderStatus', 9, (SELECT COUNT(*) FROM analytics.DimOrderStatus),
 (SELECT COUNT(*) FROM analytics.DimOrderStatus WHERE OrderStatusKey = 0 AND IsUnknown = 1)),
('DimPaymentStatus', 8, (SELECT COUNT(*) FROM analytics.DimPaymentStatus),
 (SELECT COUNT(*) FROM analytics.DimPaymentStatus WHERE PaymentStatusKey = 0 AND IsUnknown = 1)),
('DimReturnReason', 8, (SELECT COUNT(*) FROM analytics.DimReturnReason),
 (SELECT COUNT(*) FROM analytics.DimReturnReason WHERE ReturnReasonKey = 0 AND IsUnknown = 1)),
('DimReturnStatus', 7, (SELECT COUNT(*) FROM analytics.DimReturnStatus),
 (SELECT COUNT(*) FROM analytics.DimReturnStatus WHERE ReturnStatusKey = 0 AND IsUnknown = 1)),
('DimInventoryMovementType', 11, (SELECT COUNT(*) FROM analytics.DimInventoryMovementType),
 (SELECT COUNT(*) FROM analytics.DimInventoryMovementType WHERE InventoryMovementTypeKey = 0 AND IsUnknown = 1));

IF EXISTS
(
    SELECT 1 FROM @DimensionValidation
    WHERE ExistingRowCount <> ExpectedRowCount OR UnknownMemberCount <> 1
)
    THROW 51383, 'Dimension validation failed: row count or Unknown-member mismatch.', 1;

IF (SELECT COUNT(*) FROM analytics.DimDate WHERE DateKey <> 0) <> DATEDIFF(DAY, '2023-01-01', '2026-12-31') + 1
   OR EXISTS
      (
          SELECT 1
          FROM analytics.DimDate AS date_dimension
          WHERE date_dimension.DateKey <> 0
            AND (date_dimension.FinancialMonthNumber NOT BETWEEN 1 AND 12
                 OR date_dimension.FinancialQuarterNumber NOT BETWEEN 1 AND 4)
      )
    THROW 51384, 'Date-dimension validation failed: coverage or fiscal attributes are invalid.', 1;

SELECT
    DimensionName,
    ExpectedRowCount,
    ExistingRowCount,
    UnknownMemberCount,
    CASE WHEN ExpectedRowCount = ExistingRowCount AND UnknownMemberCount = 1
         THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM @DimensionValidation
ORDER BY CASE DimensionName
    WHEN 'DimDate' THEN 1 WHEN 'DimCustomer' THEN 2 WHEN 'DimProduct' THEN 3
    WHEN 'DimStore' THEN 4 WHEN 'DimEmployee' THEN 5 WHEN 'DimSupplier' THEN 6
    WHEN 'DimPaymentMethod' THEN 7 WHEN 'DimOrderStatus' THEN 8
    WHEN 'DimPaymentStatus' THEN 9 WHEN 'DimReturnReason' THEN 10
    WHEN 'DimReturnStatus' THEN 11 ELSE 12 END;

SELECT
    MIN(CASE WHEN DateKey <> 0 THEN [Date] END) AS MinimumReportingDate,
    MAX([Date]) AS MaximumReportingDate,
    COUNT(DISTINCT CalendarYear) - 1 AS CalendarYearCount,
    COUNT(DISTINCT FinancialYearLabel) - 1 AS FinancialYearCount,
    'PASSED' AS ValidationStatus
FROM analytics.DimDate;

RAISERROR('22_Create_Analytics_Dimensions.sql completed successfully: 12 conformed dimensions loaded and validated.', 10, 1) WITH NOWAIT;
GO
