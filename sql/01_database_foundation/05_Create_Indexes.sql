/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      05_Create_Indexes.sql
Purpose:     Create the approved filtered-unique and operational indexes.
Author:      Akshay Aswani
Version:     2.0
Depends on:  04_Create_Constraints.sql
Rerunnable:  Yes. Existing correctly named indexes are preserved.

Design principles
-----------------
- Primary-key and unique-constraint indexes are not duplicated.
- Nullable business identifiers use filtered unique indexes.
- Composite keys follow the leading columns used by joins and reporting filters.
- INCLUDE columns cover recurring analytical outputs without widening index keys.
- Columnstore and speculative tuning indexes are deferred until workload testing.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

DECLARE @ExpectedDatabaseName SYSNAME = N'$(DatabaseName)';

IF DB_NAME() <> @ExpectedDatabaseName
BEGIN
    THROW 51040, 'Index creation stopped: unexpected database context.', 1;
END;

IF @ExpectedDatabaseName <> N'RetailIntelligenceDB'
BEGIN
    THROW 51041, 'Index creation stopped: the approved database name is RetailIntelligenceDB.', 1;
END;

IF OBJECT_ID(N'core.Product', N'U') IS NULL
   OR OBJECT_ID(N'sales.SalesOrder', N'U') IS NULL
   OR OBJECT_ID(N'inventory.InventoryMovement', N'U') IS NULL
BEGIN
    THROW 51042, 'Index creation stopped: required tables are missing. Run scripts 03 and 04 first.', 1;
END;
GO

-- A failed attempt can leave a local temporary table in the same SSMS session.
DROP TABLE IF EXISTS #IndexBuild;

CREATE TABLE #IndexBuild
(
    IndexSequence SMALLINT NOT NULL PRIMARY KEY,
    IndexGroup VARCHAR(30) NOT NULL,
    ObjectSchema SYSNAME NOT NULL,
    ObjectName SYSNAME NOT NULL,
    IndexName SYSNAME NOT NULL,
    ExpectedUnique BIT NOT NULL,
    ExpectedFiltered BIT NOT NULL,
    CreateStatement NVARCHAR(MAX) NOT NULL,
    UNIQUE (ObjectSchema, ObjectName, IndexName)
);

-- Nullable alternate keys: multiple NULL values are allowed, populated values are unique.
INSERT INTO #IndexBuild
(
    IndexSequence, IndexGroup, ObjectSchema, ObjectName, IndexName,
    ExpectedUnique, ExpectedFiltered, CreateStatement
)
VALUES
(1, 'FILTERED UNIQUE', N'core', N'Employee', N'UX_Employee_Email', 1, 1,
 N'CREATE UNIQUE NONCLUSTERED INDEX UX_Employee_Email ON core.Employee (Email) WHERE Email IS NOT NULL;'),
(2, 'FILTERED UNIQUE', N'core', N'Customer', N'UX_Customer_Email', 1, 1,
 N'CREATE UNIQUE NONCLUSTERED INDEX UX_Customer_Email ON core.Customer (Email) WHERE Email IS NOT NULL;'),
(3, 'FILTERED UNIQUE', N'core', N'Supplier', N'UX_Supplier_Email', 1, 1,
 N'CREATE UNIQUE NONCLUSTERED INDEX UX_Supplier_Email ON core.Supplier (Email) WHERE Email IS NOT NULL;'),
(4, 'FILTERED UNIQUE', N'core', N'Product', N'UX_Product_Barcode', 1, 1,
 N'CREATE UNIQUE NONCLUSTERED INDEX UX_Product_Barcode ON core.Product (Barcode) WHERE Barcode IS NOT NULL;'),
(5, 'FILTERED UNIQUE', N'sales', N'Payment', N'UX_Payment_TransactionReference', 1, 1,
 N'CREATE UNIQUE NONCLUSTERED INDEX UX_Payment_TransactionReference ON sales.Payment (TransactionReference) WHERE TransactionReference IS NOT NULL;'),
(6, 'FILTERED UNIQUE', N'sales', N'Refund', N'UX_Refund_RefundReference', 1, 1,
 N'CREATE UNIQUE NONCLUSTERED INDEX UX_Refund_RefundReference ON sales.Refund (RefundReference) WHERE RefundReference IS NOT NULL;');

-- Core/master access paths.
INSERT INTO #IndexBuild VALUES
(20, 'CORE ACCESS', N'core', N'Employee', N'IX_Employee_StoreID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_Employee_StoreID ON core.Employee (StoreID) INCLUDE (EmployeeCode, FirstName, LastName, JobTitle, IsActive);'),
(21, 'CORE ACCESS', N'core', N'Customer', N'IX_Customer_RegistrationDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_Customer_RegistrationDate ON core.Customer (RegistrationDate) INCLUDE (CustomerCode, City, State, LoyaltyPoints, IsActive);'),
(22, 'CORE ACCESS', N'core', N'Product', N'IX_Product_SubCategoryID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_Product_SubCategoryID ON core.Product (SubCategoryID) INCLUDE (SKU, ProductName, BrandID, SupplierID, SellingPrice, IsActive);'),
(23, 'CORE ACCESS', N'core', N'Product', N'IX_Product_BrandID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_Product_BrandID ON core.Product (BrandID) INCLUDE (SKU, ProductName, SubCategoryID, SupplierID, SellingPrice, IsActive);'),
(24, 'CORE ACCESS', N'core', N'Product', N'IX_Product_SupplierID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_Product_SupplierID ON core.Product (SupplierID) INCLUDE (SKU, ProductName, SubCategoryID, BrandID, CostPrice, SellingPrice, IsActive);');

-- Sales lifecycle and recurring reporting access paths.
INSERT INTO #IndexBuild VALUES
(40, 'SALES REPORTING', N'sales', N'SalesOrder', N'IX_SalesOrder_OrderDate_OrderStatusID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_SalesOrder_OrderDate_OrderStatusID ON sales.SalesOrder (OrderDate, OrderStatusID) INCLUDE (CustomerID, StoreID, EmployeeID, NetAmount);'),
(41, 'SALES REPORTING', N'sales', N'SalesOrder', N'IX_SalesOrder_CustomerID_OrderDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_SalesOrder_CustomerID_OrderDate ON sales.SalesOrder (CustomerID, OrderDate) INCLUDE (OrderStatusID, StoreID, NetAmount);'),
(42, 'SALES REPORTING', N'sales', N'SalesOrder', N'IX_SalesOrder_StoreID_OrderDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_SalesOrder_StoreID_OrderDate ON sales.SalesOrder (StoreID, OrderDate) INCLUDE (OrderStatusID, EmployeeID, NetAmount);'),
(43, 'SALES REPORTING', N'sales', N'SalesOrder', N'IX_SalesOrder_EmployeeID_OrderDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_SalesOrder_EmployeeID_OrderDate ON sales.SalesOrder (EmployeeID, OrderDate) INCLUDE (OrderStatusID, StoreID, NetAmount);'),
(44, 'SALES REPORTING', N'sales', N'SalesOrderItem', N'IX_SalesOrderItem_ProductID_SalesOrderID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_SalesOrderItem_ProductID_SalesOrderID ON sales.SalesOrderItem (ProductID, SalesOrderID) INCLUDE (Quantity, UnitCost, UnitPrice, DiscountAmount, TaxAmount, NetAmount);'),
(45, 'SALES REPORTING', N'sales', N'OrderStatusHistory', N'IX_OrderStatusHistory_SalesOrderID_StatusChangedDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_OrderStatusHistory_SalesOrderID_StatusChangedDate ON sales.OrderStatusHistory (SalesOrderID, StatusChangedDate) INCLUDE (FromOrderStatusID, ToOrderStatusID, ChangedByEmployeeID);'),
(46, 'SALES REPORTING', N'sales', N'Payment', N'IX_Payment_PaymentDate_PaymentStatusID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_Payment_PaymentDate_PaymentStatusID ON sales.Payment (PaymentDate, PaymentStatusID) INCLUDE (SalesOrderID, PaymentMethodID, Amount);'),
(47, 'SALES REPORTING', N'sales', N'ProductReturn', N'IX_ProductReturn_SalesOrderID_ReturnStatusID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_ProductReturn_SalesOrderID_ReturnStatusID ON sales.ProductReturn (SalesOrderID, ReturnStatusID) INCLUDE (RequestDate, ApprovedDate, ReceivedDate, ClosedDate);'),
(48, 'SALES REPORTING', N'sales', N'ProductReturn', N'IX_ProductReturn_RequestDate_ReturnStatusID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_ProductReturn_RequestDate_ReturnStatusID ON sales.ProductReturn (RequestDate, ReturnStatusID) INCLUDE (SalesOrderID, ClosedDate);'),
(49, 'SALES REPORTING', N'sales', N'ProductReturnItem', N'IX_ProductReturnItem_SalesOrderItemID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_ProductReturnItem_SalesOrderItemID ON sales.ProductReturnItem (SalesOrderItemID) INCLUDE (ProductReturnID, ReturnReasonID, QuantityRequested, QuantityAccepted, EligibleRefundAmount);'),
(50, 'SALES REPORTING', N'sales', N'Refund', N'IX_Refund_PaymentID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_Refund_PaymentID ON sales.Refund (PaymentID) INCLUDE (ProductReturnID, RefundDate, RefundAmount, RefundStatus);'),
(51, 'SALES REPORTING', N'sales', N'Refund', N'IX_Refund_ProductReturnID_RefundDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_Refund_ProductReturnID_RefundDate ON sales.Refund (ProductReturnID, RefundDate) INCLUDE (PaymentID, RefundAmount, RefundStatus);');

-- Inventory access paths. The existing UQ(ProductID, StoreID) already supports ProductID-leading balance lookups.
INSERT INTO #IndexBuild VALUES
(70, 'INVENTORY', N'inventory', N'InventoryBalance', N'IX_InventoryBalance_StoreID_ProductID', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_InventoryBalance_StoreID_ProductID ON inventory.InventoryBalance (StoreID, ProductID) INCLUDE (QuantityOnHand, QuantityReserved, LastMovementDate, LastRestockedDate);'),
(71, 'INVENTORY', N'inventory', N'InventoryMovement', N'IX_InventoryMovement_ProductID_StoreID_MovementDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_InventoryMovement_ProductID_StoreID_MovementDate ON inventory.InventoryMovement (ProductID, StoreID, MovementDate) INCLUDE (InventoryMovementTypeID, Quantity, QuantityDirection, ReferenceNumber);'),
(72, 'INVENTORY', N'inventory', N'InventoryMovement', N'IX_InventoryMovement_StoreID_MovementDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_InventoryMovement_StoreID_MovementDate ON inventory.InventoryMovement (StoreID, MovementDate) INCLUDE (ProductID, InventoryMovementTypeID, Quantity, QuantityDirection);'),
(73, 'INVENTORY', N'inventory', N'InventoryMovement', N'IX_InventoryMovement_InventoryMovementTypeID_MovementDate', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_InventoryMovement_InventoryMovementTypeID_MovementDate ON inventory.InventoryMovement (InventoryMovementTypeID, MovementDate) INCLUDE (ProductID, StoreID, Quantity, QuantityDirection);');

-- Audit drill-through for failed/warning validation results.
INSERT INTO #IndexBuild VALUES
(90, 'AUDIT', N'audit', N'ValidationResult', N'IX_ValidationResult_Status_Severity', 0, 0,
 N'CREATE NONCLUSTERED INDEX IX_ValidationResult_Status_Severity ON audit.ValidationResult (TestStatus, Severity) INCLUDE (ValidationRunID, TestCode, ExceptionCount, ExecutedDate);');

DECLARE
    @ObjectSchema SYSNAME,
    @ObjectName SYSNAME,
    @IndexName SYSNAME,
    @CreateStatement NVARCHAR(MAX);

DECLARE IndexCursor CURSOR LOCAL FAST_FORWARD FOR
SELECT ObjectSchema, ObjectName, IndexName, CreateStatement
FROM #IndexBuild
ORDER BY IndexSequence;

BEGIN TRY
    BEGIN TRANSACTION;

    OPEN IndexCursor;
    FETCH NEXT FROM IndexCursor
        INTO @ObjectSchema, @ObjectName, @IndexName, @CreateStatement;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM sys.indexes AS i
            WHERE i.object_id = OBJECT_ID(QUOTENAME(@ObjectSchema) + N'.' + QUOTENAME(@ObjectName), N'U')
              AND i.name = @IndexName
        )
        BEGIN
            EXEC sys.sp_executesql @CreateStatement;
        END;

        FETCH NEXT FROM IndexCursor
            INTO @ObjectSchema, @ObjectName, @IndexName, @CreateStatement;
    END;

    CLOSE IndexCursor;
    DEALLOCATE IndexCursor;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local', 'IndexCursor') >= 0
        CLOSE IndexCursor;

    IF CURSOR_STATUS('local', 'IndexCursor') >= -1
        DEALLOCATE IndexCursor;

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

IF EXISTS
(
    SELECT 1
    FROM #IndexBuild AS ib
    LEFT JOIN sys.indexes AS i
        ON i.object_id = OBJECT_ID(QUOTENAME(ib.ObjectSchema) + N'.' + QUOTENAME(ib.ObjectName), N'U')
       AND i.name = ib.IndexName
    WHERE i.index_id IS NULL
       OR i.is_disabled = 1
       OR i.is_hypothetical = 1
       OR i.is_unique <> ib.ExpectedUnique
       OR i.has_filter <> ib.ExpectedFiltered
)
BEGIN
    THROW 51043, 'Index validation failed: an index is missing, disabled or differs from its approved type.', 1;
END;

SELECT
    ib.IndexGroup,
    COUNT(*) AS ExpectedCount,
    COUNT(i.index_id) AS ExistingCount,
    CASE
        WHEN COUNT(*) = COUNT(i.index_id)
         AND SUM(CASE WHEN i.is_disabled = 0 AND i.is_hypothetical = 0
                           AND i.is_unique = ib.ExpectedUnique
                           AND i.has_filter = ib.ExpectedFiltered THEN 1 ELSE 0 END) = COUNT(*)
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM #IndexBuild AS ib
LEFT JOIN sys.indexes AS i
    ON i.object_id = OBJECT_ID(QUOTENAME(ib.ObjectSchema) + N'.' + QUOTENAME(ib.ObjectName), N'U')
   AND i.name = ib.IndexName
GROUP BY ib.IndexGroup
ORDER BY MIN(ib.IndexSequence);

SELECT
    COUNT(*) AS ApprovedIndexCount,
    SUM(CASE WHEN i.is_unique = 1 THEN 1 ELSE 0 END) AS FilteredUniqueIndexCount,
    SUM(CASE WHEN i.is_disabled = 1 THEN 1 ELSE 0 END) AS DisabledIndexCount,
    SUM(CASE WHEN i.is_hypothetical = 1 THEN 1 ELSE 0 END) AS HypotheticalIndexCount
FROM #IndexBuild AS ib
INNER JOIN sys.indexes AS i
    ON i.object_id = OBJECT_ID(QUOTENAME(ib.ObjectSchema) + N'.' + QUOTENAME(ib.ObjectName), N'U')
   AND i.name = ib.IndexName;

RAISERROR('05_Create_Indexes.sql completed successfully: 28 approved indexes validated.', 10, 1) WITH NOWAIT;
GO
