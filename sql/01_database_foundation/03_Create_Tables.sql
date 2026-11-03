/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      03_Create_Tables.sql
Purpose:     Create the 25 approved operational and audit tables.
Author:      Akshay Aswani
Version:     2.0
Depends on:  02_Create_Schemas.sql
Rerunnable:  Yes. Missing tables are created; existing tables are preserved.

Design boundary
---------------
- This script creates columns, nullability and identity properties only.
- PK, FK, UQ, CK and DF constraints are added by 04_Create_Constraints.sql.
- Indexes are added by 05_Create_Indexes.sql.
- Existing tables are never dropped or silently altered.
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
    THROW 51020, 'Table creation stopped: unexpected database context.', 1;
END;

IF @ExpectedDatabaseName <> N'RetailIntelligenceDB'
BEGIN
    THROW 51021, 'Table creation stopped: the approved database name is RetailIntelligenceDB.', 1;
END;

IF EXISTS
(
    SELECT required.SchemaName
    FROM
    (
        VALUES
            (N'ref'),
            (N'core'),
            (N'sales'),
            (N'inventory'),
            (N'audit'),
            (N'analytics')
    ) AS required (SchemaName)
    LEFT JOIN sys.schemas AS s
        ON s.name = required.SchemaName
    WHERE s.schema_id IS NULL
)
BEGIN
    THROW 51022, 'Table creation stopped: one or more required schemas are missing.', 1;
END;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- ========================================================================
    -- REFERENCE TABLES (9)
    -- ========================================================================

    IF OBJECT_ID(N'ref.Category', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.Category
        (
            CategoryID INT IDENTITY(1,1) NOT NULL,
            CategoryCode VARCHAR(20) NOT NULL,
            CategoryName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'ref.SubCategory', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.SubCategory
        (
            SubCategoryID INT IDENTITY(1,1) NOT NULL,
            CategoryID INT NOT NULL,
            SubCategoryCode VARCHAR(20) NOT NULL,
            SubCategoryName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'ref.Brand', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.Brand
        (
            BrandID INT IDENTITY(1,1) NOT NULL,
            BrandCode VARCHAR(20) NOT NULL,
            BrandName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'ref.OrderStatus', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.OrderStatus
        (
            OrderStatusID SMALLINT IDENTITY(1,1) NOT NULL,
            OrderStatusCode VARCHAR(30) NOT NULL,
            OrderStatusName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            SortOrder TINYINT NOT NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL
        );
    END;

    IF OBJECT_ID(N'ref.PaymentMethod', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.PaymentMethod
        (
            PaymentMethodID SMALLINT IDENTITY(1,1) NOT NULL,
            PaymentMethodCode VARCHAR(30) NOT NULL,
            PaymentMethodName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            SortOrder TINYINT NOT NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL
        );
    END;

    IF OBJECT_ID(N'ref.PaymentStatus', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.PaymentStatus
        (
            PaymentStatusID SMALLINT IDENTITY(1,1) NOT NULL,
            PaymentStatusCode VARCHAR(30) NOT NULL,
            PaymentStatusName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            SortOrder TINYINT NOT NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL
        );
    END;

    IF OBJECT_ID(N'ref.ReturnReason', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.ReturnReason
        (
            ReturnReasonID SMALLINT IDENTITY(1,1) NOT NULL,
            ReturnReasonCode VARCHAR(30) NOT NULL,
            ReturnReasonName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            SortOrder TINYINT NOT NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL
        );
    END;

    IF OBJECT_ID(N'ref.ReturnStatus', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.ReturnStatus
        (
            ReturnStatusID SMALLINT IDENTITY(1,1) NOT NULL,
            ReturnStatusCode VARCHAR(30) NOT NULL,
            ReturnStatusName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            SortOrder TINYINT NOT NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL
        );
    END;

    IF OBJECT_ID(N'ref.InventoryMovementType', N'U') IS NULL
    BEGIN
        CREATE TABLE ref.InventoryMovementType
        (
            InventoryMovementTypeID SMALLINT IDENTITY(1,1) NOT NULL,
            InventoryMovementTypeCode VARCHAR(30) NOT NULL,
            InventoryMovementTypeName VARCHAR(100) NOT NULL,
            Description VARCHAR(255) NULL,
            QuantityDirection SMALLINT NOT NULL,
            RequiresReference BIT NOT NULL,
            SortOrder TINYINT NOT NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL
        );
    END;

    -- ========================================================================
    -- CORE MASTER TABLES (5)
    -- ========================================================================

    IF OBJECT_ID(N'core.Store', N'U') IS NULL
    BEGIN
        CREATE TABLE core.Store
        (
            StoreID INT IDENTITY(1,1) NOT NULL,
            StoreCode VARCHAR(20) NOT NULL,
            StoreName VARCHAR(100) NOT NULL,
            ManagerEmployeeID INT NULL,
            AddressLine VARCHAR(255) NOT NULL,
            City VARCHAR(100) NOT NULL,
            State VARCHAR(100) NOT NULL,
            PostalCode VARCHAR(10) NULL,
            Country VARCHAR(100) NOT NULL,
            Phone VARCHAR(20) NULL,
            OpeningDate DATE NOT NULL,
            ClosingDate DATE NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'core.Employee', N'U') IS NULL
    BEGIN
        CREATE TABLE core.Employee
        (
            EmployeeID INT IDENTITY(1,1) NOT NULL,
            EmployeeCode VARCHAR(20) NOT NULL,
            StoreID INT NOT NULL,
            ManagerEmployeeID INT NULL,
            FirstName VARCHAR(50) NOT NULL,
            LastName VARCHAR(50) NOT NULL,
            Email VARCHAR(150) NULL,
            Phone VARCHAR(20) NULL,
            JobTitle VARCHAR(100) NOT NULL,
            Salary DECIMAL(12,2) NOT NULL,
            HireDate DATE NOT NULL,
            TerminationDate DATE NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'core.Customer', N'U') IS NULL
    BEGIN
        CREATE TABLE core.Customer
        (
            CustomerID INT IDENTITY(1,1) NOT NULL,
            CustomerCode VARCHAR(20) NOT NULL,
            FirstName VARCHAR(50) NOT NULL,
            LastName VARCHAR(50) NOT NULL,
            Email VARCHAR(150) NULL,
            Phone VARCHAR(20) NULL,
            AddressLine VARCHAR(255) NULL,
            City VARCHAR(100) NULL,
            State VARCHAR(100) NULL,
            PostalCode VARCHAR(10) NULL,
            Country VARCHAR(100) NULL,
            RegistrationDate DATE NOT NULL,
            LoyaltyPoints INT NOT NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'core.Supplier', N'U') IS NULL
    BEGIN
        CREATE TABLE core.Supplier
        (
            SupplierID INT IDENTITY(1,1) NOT NULL,
            SupplierCode VARCHAR(20) NOT NULL,
            SupplierName VARCHAR(150) NOT NULL,
            ContactName VARCHAR(100) NULL,
            Email VARCHAR(150) NULL,
            Phone VARCHAR(20) NULL,
            AddressLine VARCHAR(255) NULL,
            City VARCHAR(100) NULL,
            State VARCHAR(100) NULL,
            PostalCode VARCHAR(10) NULL,
            Country VARCHAR(100) NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'core.Product', N'U') IS NULL
    BEGIN
        CREATE TABLE core.Product
        (
            ProductID INT IDENTITY(1,1) NOT NULL,
            SKU VARCHAR(40) NOT NULL,
            ProductName VARCHAR(150) NOT NULL,
            SubCategoryID INT NOT NULL,
            BrandID INT NOT NULL,
            SupplierID INT NOT NULL,
            CostPrice DECIMAL(12,2) NOT NULL,
            SellingPrice DECIMAL(12,2) NOT NULL,
            ReorderLevel INT NOT NULL,
            ExcessStockLevel INT NULL,
            Barcode VARCHAR(50) NULL,
            Description VARCHAR(500) NULL,
            IsActive BIT NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    -- ========================================================================
    -- SALES TRANSACTION TABLES (7)
    -- ========================================================================

    IF OBJECT_ID(N'sales.SalesOrder', N'U') IS NULL
    BEGIN
        CREATE TABLE sales.SalesOrder
        (
            SalesOrderID BIGINT IDENTITY(1,1) NOT NULL,
            OrderNumber VARCHAR(25) NOT NULL,
            CustomerID INT NOT NULL,
            StoreID INT NOT NULL,
            EmployeeID INT NOT NULL,
            OrderStatusID SMALLINT NOT NULL,
            OrderDate DATETIME2(0) NOT NULL,
            ConfirmedDate DATETIME2(0) NULL,
            ShippedDate DATETIME2(0) NULL,
            DeliveredDate DATETIME2(0) NULL,
            CancelledDate DATETIME2(0) NULL,
            SubtotalAmount DECIMAL(14,2) NOT NULL,
            DiscountAmount DECIMAL(14,2) NOT NULL,
            TaxAmount DECIMAL(14,2) NOT NULL,
            NetAmount DECIMAL(14,2) NOT NULL,
            Remarks VARCHAR(500) NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'sales.SalesOrderItem', N'U') IS NULL
    BEGIN
        CREATE TABLE sales.SalesOrderItem
        (
            SalesOrderItemID BIGINT IDENTITY(1,1) NOT NULL,
            SalesOrderID BIGINT NOT NULL,
            ProductID INT NOT NULL,
            Quantity INT NOT NULL,
            UnitCost DECIMAL(12,2) NOT NULL,
            UnitPrice DECIMAL(12,2) NOT NULL,
            GrossAmount DECIMAL(14,2) NOT NULL,
            DiscountAmount DECIMAL(14,2) NOT NULL,
            TaxRate DECIMAL(5,2) NOT NULL,
            TaxAmount DECIMAL(14,2) NOT NULL,
            NetAmount DECIMAL(14,2) NOT NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'sales.OrderStatusHistory', N'U') IS NULL
    BEGIN
        CREATE TABLE sales.OrderStatusHistory
        (
            OrderStatusHistoryID BIGINT IDENTITY(1,1) NOT NULL,
            SalesOrderID BIGINT NOT NULL,
            FromOrderStatusID SMALLINT NULL,
            ToOrderStatusID SMALLINT NOT NULL,
            StatusChangedDate DATETIME2(0) NOT NULL,
            ChangedByEmployeeID INT NULL,
            ChangeReason VARCHAR(255) NULL,
            CreatedDate DATETIME2(0) NOT NULL
        );
    END;

    IF OBJECT_ID(N'sales.Payment', N'U') IS NULL
    BEGIN
        CREATE TABLE sales.Payment
        (
            PaymentID BIGINT IDENTITY(1,1) NOT NULL,
            SalesOrderID BIGINT NOT NULL,
            PaymentMethodID SMALLINT NOT NULL,
            PaymentStatusID SMALLINT NOT NULL,
            AttemptNumber SMALLINT NOT NULL,
            PaymentDate DATETIME2(0) NOT NULL,
            Amount DECIMAL(14,2) NOT NULL,
            TransactionReference VARCHAR(100) NULL,
            FailureReason VARCHAR(255) NULL,
            Remarks VARCHAR(255) NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'sales.ProductReturn', N'U') IS NULL
    BEGIN
        CREATE TABLE sales.ProductReturn
        (
            ProductReturnID BIGINT IDENTITY(1,1) NOT NULL,
            ReturnNumber VARCHAR(25) NOT NULL,
            SalesOrderID BIGINT NOT NULL,
            ReturnStatusID SMALLINT NOT NULL,
            RequestDate DATETIME2(0) NOT NULL,
            ApprovedDate DATETIME2(0) NULL,
            ReceivedDate DATETIME2(0) NULL,
            ClosedDate DATETIME2(0) NULL,
            Remarks VARCHAR(500) NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'sales.ProductReturnItem', N'U') IS NULL
    BEGIN
        CREATE TABLE sales.ProductReturnItem
        (
            ProductReturnItemID BIGINT IDENTITY(1,1) NOT NULL,
            ProductReturnID BIGINT NOT NULL,
            SalesOrderItemID BIGINT NOT NULL,
            ReturnReasonID SMALLINT NOT NULL,
            QuantityRequested INT NOT NULL,
            QuantityAccepted INT NOT NULL,
            EligibleRefundAmount DECIMAL(14,2) NOT NULL,
            IsReusable BIT NULL,
            InspectionNotes VARCHAR(500) NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'sales.Refund', N'U') IS NULL
    BEGIN
        CREATE TABLE sales.Refund
        (
            RefundID BIGINT IDENTITY(1,1) NOT NULL,
            PaymentID BIGINT NOT NULL,
            ProductReturnID BIGINT NOT NULL,
            RefundDate DATETIME2(0) NOT NULL,
            RefundAmount DECIMAL(14,2) NOT NULL,
            RefundReference VARCHAR(100) NULL,
            RefundStatus VARCHAR(20) NOT NULL,
            Remarks VARCHAR(255) NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    -- ========================================================================
    -- INVENTORY TABLES (2)
    -- ========================================================================

    IF OBJECT_ID(N'inventory.InventoryBalance', N'U') IS NULL
    BEGIN
        CREATE TABLE inventory.InventoryBalance
        (
            InventoryBalanceID BIGINT IDENTITY(1,1) NOT NULL,
            ProductID INT NOT NULL,
            StoreID INT NOT NULL,
            QuantityOnHand INT NOT NULL,
            QuantityReserved INT NOT NULL,
            LastMovementDate DATETIME2(0) NULL,
            LastRestockedDate DATETIME2(0) NULL,
            CreatedDate DATETIME2(0) NOT NULL,
            ModifiedDate DATETIME2(0) NULL
        );
    END;

    IF OBJECT_ID(N'inventory.InventoryMovement', N'U') IS NULL
    BEGIN
        CREATE TABLE inventory.InventoryMovement
        (
            InventoryMovementID BIGINT IDENTITY(1,1) NOT NULL,
            ProductID INT NOT NULL,
            StoreID INT NOT NULL,
            InventoryMovementTypeID SMALLINT NOT NULL,
            MovementDate DATETIME2(0) NOT NULL,
            Quantity INT NOT NULL,
            QuantityDirection SMALLINT NOT NULL,
            SalesOrderItemID BIGINT NULL,
            ProductReturnItemID BIGINT NULL,
            ReferenceNumber VARCHAR(50) NULL,
            Reason VARCHAR(255) NULL,
            CreatedByEmployeeID INT NULL,
            CreatedDate DATETIME2(0) NOT NULL
        );
    END;

    -- ========================================================================
    -- AUDIT TABLES (2)
    -- ========================================================================

    IF OBJECT_ID(N'audit.ValidationRun', N'U') IS NULL
    BEGIN
        CREATE TABLE audit.ValidationRun
        (
            ValidationRunID BIGINT IDENTITY(1,1) NOT NULL,
            RunStartDate DATETIME2(0) NOT NULL,
            RunEndDate DATETIME2(0) NULL,
            EnvironmentName VARCHAR(30) NOT NULL,
            OverallStatus VARCHAR(10) NOT NULL,
            TotalTests INT NOT NULL,
            PassedTests INT NOT NULL,
            FailedTests INT NOT NULL,
            Remarks VARCHAR(500) NULL
        );
    END;

    IF OBJECT_ID(N'audit.ValidationResult', N'U') IS NULL
    BEGIN
        CREATE TABLE audit.ValidationResult
        (
            ValidationResultID BIGINT IDENTITY(1,1) NOT NULL,
            ValidationRunID BIGINT NOT NULL,
            TestCode VARCHAR(50) NOT NULL,
            TestName VARCHAR(200) NOT NULL,
            Severity VARCHAR(10) NOT NULL,
            ExpectedValue VARCHAR(100) NULL,
            ActualValue VARCHAR(100) NULL,
            ExceptionCount BIGINT NOT NULL,
            TestStatus VARCHAR(10) NOT NULL,
            ExecutedDate DATETIME2(0) NOT NULL,
            DiagnosticMessage VARCHAR(1000) NULL
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

-- ============================================================================
-- TABLE-INVENTORY VALIDATION
-- Detailed column/type validation is implemented in 20_Validate_Schema.sql.
-- ============================================================================

DECLARE @RequiredTables TABLE
(
    SchemaName SYSNAME NOT NULL,
    TableName SYSNAME NOT NULL,
    ExpectedSequence TINYINT NOT NULL,
    PRIMARY KEY (SchemaName, TableName)
);

INSERT INTO @RequiredTables
(
    SchemaName,
    TableName,
    ExpectedSequence
)
VALUES
    (N'ref',       N'Category',                  1),
    (N'ref',       N'SubCategory',               2),
    (N'ref',       N'Brand',                     3),
    (N'ref',       N'OrderStatus',               4),
    (N'ref',       N'PaymentMethod',             5),
    (N'ref',       N'PaymentStatus',             6),
    (N'ref',       N'ReturnReason',              7),
    (N'ref',       N'ReturnStatus',              8),
    (N'ref',       N'InventoryMovementType',     9),
    (N'core',      N'Store',                    10),
    (N'core',      N'Employee',                 11),
    (N'core',      N'Customer',                 12),
    (N'core',      N'Supplier',                 13),
    (N'core',      N'Product',                  14),
    (N'sales',     N'SalesOrder',               15),
    (N'sales',     N'SalesOrderItem',           16),
    (N'sales',     N'OrderStatusHistory',       17),
    (N'sales',     N'Payment',                  18),
    (N'sales',     N'ProductReturn',            19),
    (N'sales',     N'ProductReturnItem',        20),
    (N'sales',     N'Refund',                   21),
    (N'inventory', N'InventoryBalance',         22),
    (N'inventory', N'InventoryMovement',        23),
    (N'audit',     N'ValidationRun',            24),
    (N'audit',     N'ValidationResult',         25);

DECLARE @MissingTableCount INT;

SELECT
    @MissingTableCount = COUNT(*)
FROM @RequiredTables AS rt
LEFT JOIN sys.schemas AS s
    ON s.name = rt.SchemaName
LEFT JOIN sys.tables AS t
    ON t.schema_id = s.schema_id
   AND t.name = rt.TableName
WHERE t.object_id IS NULL;

IF @MissingTableCount > 0
BEGIN
    SELECT
        rt.SchemaName,
        rt.TableName
    FROM @RequiredTables AS rt
    LEFT JOIN sys.schemas AS s
        ON s.name = rt.SchemaName
    LEFT JOIN sys.tables AS t
        ON t.schema_id = s.schema_id
       AND t.name = rt.TableName
    WHERE t.object_id IS NULL
    ORDER BY
        rt.ExpectedSequence;

    THROW 51023, 'Table creation validation failed: one or more required tables are missing.', 1;
END;

SELECT
    rt.ExpectedSequence,
    rt.SchemaName,
    rt.TableName,
    COUNT(c.column_id) AS ColumnCount,
    SUM(CASE WHEN c.is_identity = 1 THEN 1 ELSE 0 END) AS IdentityColumnCount,
    SUM(CASE WHEN c.is_nullable = 0 THEN 1 ELSE 0 END) AS RequiredColumnCount,
    SUM(CASE WHEN c.is_nullable = 1 THEN 1 ELSE 0 END) AS NullableColumnCount,
    'PASSED' AS TableExistsStatus
FROM @RequiredTables AS rt
INNER JOIN sys.schemas AS s
    ON s.name = rt.SchemaName
INNER JOIN sys.tables AS t
    ON t.schema_id = s.schema_id
   AND t.name = rt.TableName
INNER JOIN sys.columns AS c
    ON c.object_id = t.object_id
GROUP BY
    rt.ExpectedSequence,
    rt.SchemaName,
    rt.TableName
ORDER BY
    rt.ExpectedSequence;

RAISERROR('03_Create_Tables.sql completed successfully: 25 required tables validated.', 10, 1) WITH NOWAIT;
GO
