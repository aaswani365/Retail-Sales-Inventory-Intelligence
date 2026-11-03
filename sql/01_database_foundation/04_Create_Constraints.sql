/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      04_Create_Constraints.sql
Purpose:     Create and validate primary, alternate, foreign, default and check constraints.
Author:      Akshay Aswani
Version:     2.0
Depends on:  03_Create_Tables.sql
Rerunnable:  Yes. Named constraints are created only when missing.

Boundary
--------
- Filtered unique indexes for nullable email/barcode/reference fields belong to 05_Create_Indexes.sql.
- Cross-table cumulative and lifecycle rules that cannot be expressed as row-level
  constraints are enforced by procedures and validation scripts.
- Existing constraints are preserved; definition drift is detected by 21_Validate_Constraints.sql.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)'
    THROW 51030, 'Constraint creation stopped: unexpected database context.', 1;

IF N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51031, 'Constraint creation stopped: unexpected database name.', 1;

IF (SELECT COUNT(*) FROM sys.tables WHERE schema_id IN
    (SCHEMA_ID(N'ref'), SCHEMA_ID(N'core'), SCHEMA_ID(N'sales'), SCHEMA_ID(N'inventory'), SCHEMA_ID(N'audit'))) < 25
BEGIN
    THROW 51032, 'Constraint creation stopped: all 25 operational/audit tables must exist first.', 1;
END;
GO

CREATE TABLE #ConstraintBuild
(
    ConstraintSequence SMALLINT NOT NULL PRIMARY KEY,
    ConstraintSchema SYSNAME NOT NULL,
    ConstraintName SYSNAME NOT NULL,
    ConstraintType CHAR(2) NOT NULL,
    ConstraintGroup VARCHAR(20) NOT NULL,
    CreateStatement NVARCHAR(MAX) NOT NULL,
    UNIQUE (ConstraintSchema, ConstraintName)
);

-- ============================================================================
-- PRIMARY KEYS (25)
-- ============================================================================

INSERT INTO #ConstraintBuild VALUES
(1,  N'ref',       N'PK_Category',              'PK', 'PRIMARY KEY', N'ALTER TABLE ref.Category ADD CONSTRAINT PK_Category PRIMARY KEY CLUSTERED (CategoryID);'),
(2,  N'ref',       N'PK_SubCategory',           'PK', 'PRIMARY KEY', N'ALTER TABLE ref.SubCategory ADD CONSTRAINT PK_SubCategory PRIMARY KEY CLUSTERED (SubCategoryID);'),
(3,  N'ref',       N'PK_Brand',                 'PK', 'PRIMARY KEY', N'ALTER TABLE ref.Brand ADD CONSTRAINT PK_Brand PRIMARY KEY CLUSTERED (BrandID);'),
(4,  N'ref',       N'PK_OrderStatus',           'PK', 'PRIMARY KEY', N'ALTER TABLE ref.OrderStatus ADD CONSTRAINT PK_OrderStatus PRIMARY KEY CLUSTERED (OrderStatusID);'),
(5,  N'ref',       N'PK_PaymentMethod',         'PK', 'PRIMARY KEY', N'ALTER TABLE ref.PaymentMethod ADD CONSTRAINT PK_PaymentMethod PRIMARY KEY CLUSTERED (PaymentMethodID);'),
(6,  N'ref',       N'PK_PaymentStatus',         'PK', 'PRIMARY KEY', N'ALTER TABLE ref.PaymentStatus ADD CONSTRAINT PK_PaymentStatus PRIMARY KEY CLUSTERED (PaymentStatusID);'),
(7,  N'ref',       N'PK_ReturnReason',          'PK', 'PRIMARY KEY', N'ALTER TABLE ref.ReturnReason ADD CONSTRAINT PK_ReturnReason PRIMARY KEY CLUSTERED (ReturnReasonID);'),
(8,  N'ref',       N'PK_ReturnStatus',          'PK', 'PRIMARY KEY', N'ALTER TABLE ref.ReturnStatus ADD CONSTRAINT PK_ReturnStatus PRIMARY KEY CLUSTERED (ReturnStatusID);'),
(9,  N'ref',       N'PK_InventoryMovementType', 'PK', 'PRIMARY KEY', N'ALTER TABLE ref.InventoryMovementType ADD CONSTRAINT PK_InventoryMovementType PRIMARY KEY CLUSTERED (InventoryMovementTypeID);'),
(10, N'core',      N'PK_Store',                 'PK', 'PRIMARY KEY', N'ALTER TABLE core.Store ADD CONSTRAINT PK_Store PRIMARY KEY CLUSTERED (StoreID);'),
(11, N'core',      N'PK_Employee',              'PK', 'PRIMARY KEY', N'ALTER TABLE core.Employee ADD CONSTRAINT PK_Employee PRIMARY KEY CLUSTERED (EmployeeID);'),
(12, N'core',      N'PK_Customer',              'PK', 'PRIMARY KEY', N'ALTER TABLE core.Customer ADD CONSTRAINT PK_Customer PRIMARY KEY CLUSTERED (CustomerID);'),
(13, N'core',      N'PK_Supplier',              'PK', 'PRIMARY KEY', N'ALTER TABLE core.Supplier ADD CONSTRAINT PK_Supplier PRIMARY KEY CLUSTERED (SupplierID);'),
(14, N'core',      N'PK_Product',               'PK', 'PRIMARY KEY', N'ALTER TABLE core.Product ADD CONSTRAINT PK_Product PRIMARY KEY CLUSTERED (ProductID);'),
(15, N'sales',     N'PK_SalesOrder',            'PK', 'PRIMARY KEY', N'ALTER TABLE sales.SalesOrder ADD CONSTRAINT PK_SalesOrder PRIMARY KEY CLUSTERED (SalesOrderID);'),
(16, N'sales',     N'PK_SalesOrderItem',        'PK', 'PRIMARY KEY', N'ALTER TABLE sales.SalesOrderItem ADD CONSTRAINT PK_SalesOrderItem PRIMARY KEY CLUSTERED (SalesOrderItemID);'),
(17, N'sales',     N'PK_OrderStatusHistory',    'PK', 'PRIMARY KEY', N'ALTER TABLE sales.OrderStatusHistory ADD CONSTRAINT PK_OrderStatusHistory PRIMARY KEY CLUSTERED (OrderStatusHistoryID);'),
(18, N'sales',     N'PK_Payment',               'PK', 'PRIMARY KEY', N'ALTER TABLE sales.Payment ADD CONSTRAINT PK_Payment PRIMARY KEY CLUSTERED (PaymentID);'),
(19, N'sales',     N'PK_ProductReturn',         'PK', 'PRIMARY KEY', N'ALTER TABLE sales.ProductReturn ADD CONSTRAINT PK_ProductReturn PRIMARY KEY CLUSTERED (ProductReturnID);'),
(20, N'sales',     N'PK_ProductReturnItem',     'PK', 'PRIMARY KEY', N'ALTER TABLE sales.ProductReturnItem ADD CONSTRAINT PK_ProductReturnItem PRIMARY KEY CLUSTERED (ProductReturnItemID);'),
(21, N'sales',     N'PK_Refund',                'PK', 'PRIMARY KEY', N'ALTER TABLE sales.Refund ADD CONSTRAINT PK_Refund PRIMARY KEY CLUSTERED (RefundID);'),
(22, N'inventory', N'PK_InventoryBalance',      'PK', 'PRIMARY KEY', N'ALTER TABLE inventory.InventoryBalance ADD CONSTRAINT PK_InventoryBalance PRIMARY KEY CLUSTERED (InventoryBalanceID);'),
(23, N'inventory', N'PK_InventoryMovement',     'PK', 'PRIMARY KEY', N'ALTER TABLE inventory.InventoryMovement ADD CONSTRAINT PK_InventoryMovement PRIMARY KEY CLUSTERED (InventoryMovementID);'),
(24, N'audit',     N'PK_ValidationRun',         'PK', 'PRIMARY KEY', N'ALTER TABLE audit.ValidationRun ADD CONSTRAINT PK_ValidationRun PRIMARY KEY CLUSTERED (ValidationRunID);'),
(25, N'audit',     N'PK_ValidationResult',      'PK', 'PRIMARY KEY', N'ALTER TABLE audit.ValidationResult ADD CONSTRAINT PK_ValidationResult PRIMARY KEY CLUSTERED (ValidationResultID);');

-- ============================================================================
-- BUSINESS ALTERNATE KEYS / UNIQUE CONSTRAINTS (33)
-- Nullable-field uniqueness is implemented as filtered indexes in script 05.
-- ============================================================================

INSERT INTO #ConstraintBuild VALUES
(30, N'ref', N'UQ_Category_CategoryCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.Category ADD CONSTRAINT UQ_Category_CategoryCode UNIQUE (CategoryCode);'),
(31, N'ref', N'UQ_Category_CategoryName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.Category ADD CONSTRAINT UQ_Category_CategoryName UNIQUE (CategoryName);'),
(32, N'ref', N'UQ_SubCategory_SubCategoryCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.SubCategory ADD CONSTRAINT UQ_SubCategory_SubCategoryCode UNIQUE (SubCategoryCode);'),
(33, N'ref', N'UQ_SubCategory_CategoryID_SubCategoryName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.SubCategory ADD CONSTRAINT UQ_SubCategory_CategoryID_SubCategoryName UNIQUE (CategoryID, SubCategoryName);'),
(34, N'ref', N'UQ_Brand_BrandCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.Brand ADD CONSTRAINT UQ_Brand_BrandCode UNIQUE (BrandCode);'),
(35, N'ref', N'UQ_Brand_BrandName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.Brand ADD CONSTRAINT UQ_Brand_BrandName UNIQUE (BrandName);'),
(36, N'ref', N'UQ_OrderStatus_OrderStatusCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.OrderStatus ADD CONSTRAINT UQ_OrderStatus_OrderStatusCode UNIQUE (OrderStatusCode);'),
(37, N'ref', N'UQ_OrderStatus_OrderStatusName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.OrderStatus ADD CONSTRAINT UQ_OrderStatus_OrderStatusName UNIQUE (OrderStatusName);'),
(38, N'ref', N'UQ_OrderStatus_SortOrder', 'UQ', 'UNIQUE', N'ALTER TABLE ref.OrderStatus ADD CONSTRAINT UQ_OrderStatus_SortOrder UNIQUE (SortOrder);'),
(39, N'ref', N'UQ_PaymentMethod_PaymentMethodCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.PaymentMethod ADD CONSTRAINT UQ_PaymentMethod_PaymentMethodCode UNIQUE (PaymentMethodCode);'),
(40, N'ref', N'UQ_PaymentMethod_PaymentMethodName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.PaymentMethod ADD CONSTRAINT UQ_PaymentMethod_PaymentMethodName UNIQUE (PaymentMethodName);'),
(41, N'ref', N'UQ_PaymentStatus_PaymentStatusCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.PaymentStatus ADD CONSTRAINT UQ_PaymentStatus_PaymentStatusCode UNIQUE (PaymentStatusCode);'),
(42, N'ref', N'UQ_PaymentStatus_PaymentStatusName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.PaymentStatus ADD CONSTRAINT UQ_PaymentStatus_PaymentStatusName UNIQUE (PaymentStatusName);'),
(43, N'ref', N'UQ_ReturnReason_ReturnReasonCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.ReturnReason ADD CONSTRAINT UQ_ReturnReason_ReturnReasonCode UNIQUE (ReturnReasonCode);'),
(44, N'ref', N'UQ_ReturnReason_ReturnReasonName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.ReturnReason ADD CONSTRAINT UQ_ReturnReason_ReturnReasonName UNIQUE (ReturnReasonName);'),
(45, N'ref', N'UQ_ReturnStatus_ReturnStatusCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.ReturnStatus ADD CONSTRAINT UQ_ReturnStatus_ReturnStatusCode UNIQUE (ReturnStatusCode);'),
(46, N'ref', N'UQ_ReturnStatus_ReturnStatusName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.ReturnStatus ADD CONSTRAINT UQ_ReturnStatus_ReturnStatusName UNIQUE (ReturnStatusName);'),
(47, N'ref', N'UQ_InventoryMovementType_InventoryMovementTypeCode', 'UQ', 'UNIQUE', N'ALTER TABLE ref.InventoryMovementType ADD CONSTRAINT UQ_InventoryMovementType_InventoryMovementTypeCode UNIQUE (InventoryMovementTypeCode);'),
(48, N'ref', N'UQ_InventoryMovementType_InventoryMovementTypeName', 'UQ', 'UNIQUE', N'ALTER TABLE ref.InventoryMovementType ADD CONSTRAINT UQ_InventoryMovementType_InventoryMovementTypeName UNIQUE (InventoryMovementTypeName);'),
(49, N'core', N'UQ_Store_StoreCode', 'UQ', 'UNIQUE', N'ALTER TABLE core.Store ADD CONSTRAINT UQ_Store_StoreCode UNIQUE (StoreCode);'),
(50, N'core', N'UQ_Store_StoreName', 'UQ', 'UNIQUE', N'ALTER TABLE core.Store ADD CONSTRAINT UQ_Store_StoreName UNIQUE (StoreName);'),
(51, N'core', N'UQ_Employee_EmployeeCode', 'UQ', 'UNIQUE', N'ALTER TABLE core.Employee ADD CONSTRAINT UQ_Employee_EmployeeCode UNIQUE (EmployeeCode);'),
(52, N'core', N'UQ_Customer_CustomerCode', 'UQ', 'UNIQUE', N'ALTER TABLE core.Customer ADD CONSTRAINT UQ_Customer_CustomerCode UNIQUE (CustomerCode);'),
(53, N'core', N'UQ_Supplier_SupplierCode', 'UQ', 'UNIQUE', N'ALTER TABLE core.Supplier ADD CONSTRAINT UQ_Supplier_SupplierCode UNIQUE (SupplierCode);'),
(54, N'core', N'UQ_Supplier_SupplierName', 'UQ', 'UNIQUE', N'ALTER TABLE core.Supplier ADD CONSTRAINT UQ_Supplier_SupplierName UNIQUE (SupplierName);'),
(55, N'core', N'UQ_Product_SKU', 'UQ', 'UNIQUE', N'ALTER TABLE core.Product ADD CONSTRAINT UQ_Product_SKU UNIQUE (SKU);'),
(56, N'sales', N'UQ_SalesOrder_OrderNumber', 'UQ', 'UNIQUE', N'ALTER TABLE sales.SalesOrder ADD CONSTRAINT UQ_SalesOrder_OrderNumber UNIQUE (OrderNumber);'),
(57, N'sales', N'UQ_SalesOrderItem_SalesOrderID_ProductID', 'UQ', 'UNIQUE', N'ALTER TABLE sales.SalesOrderItem ADD CONSTRAINT UQ_SalesOrderItem_SalesOrderID_ProductID UNIQUE (SalesOrderID, ProductID);'),
(58, N'sales', N'UQ_Payment_SalesOrderID_AttemptNumber', 'UQ', 'UNIQUE', N'ALTER TABLE sales.Payment ADD CONSTRAINT UQ_Payment_SalesOrderID_AttemptNumber UNIQUE (SalesOrderID, AttemptNumber);'),
(59, N'sales', N'UQ_ProductReturn_ReturnNumber', 'UQ', 'UNIQUE', N'ALTER TABLE sales.ProductReturn ADD CONSTRAINT UQ_ProductReturn_ReturnNumber UNIQUE (ReturnNumber);'),
(60, N'sales', N'UQ_ProductReturnItem_ProductReturnID_SalesOrderItemID', 'UQ', 'UNIQUE', N'ALTER TABLE sales.ProductReturnItem ADD CONSTRAINT UQ_ProductReturnItem_ProductReturnID_SalesOrderItemID UNIQUE (ProductReturnID, SalesOrderItemID);'),
(61, N'inventory', N'UQ_InventoryBalance_ProductID_StoreID', 'UQ', 'UNIQUE', N'ALTER TABLE inventory.InventoryBalance ADD CONSTRAINT UQ_InventoryBalance_ProductID_StoreID UNIQUE (ProductID, StoreID);'),
(62, N'audit', N'UQ_ValidationResult_ValidationRunID_TestCode', 'UQ', 'UNIQUE', N'ALTER TABLE audit.ValidationResult ADD CONSTRAINT UQ_ValidationResult_ValidationRunID_TestCode UNIQUE (ValidationRunID, TestCode);');

-- ============================================================================
-- DEFAULT CONSTRAINTS (59)
-- ============================================================================

INSERT INTO #ConstraintBuild VALUES
(100, N'ref', N'DF_Category_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.Category ADD CONSTRAINT DF_Category_IsActive DEFAULT (1) FOR IsActive;'),
(101, N'ref', N'DF_Category_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.Category ADD CONSTRAINT DF_Category_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(102, N'ref', N'DF_SubCategory_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.SubCategory ADD CONSTRAINT DF_SubCategory_IsActive DEFAULT (1) FOR IsActive;'),
(103, N'ref', N'DF_SubCategory_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.SubCategory ADD CONSTRAINT DF_SubCategory_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(104, N'ref', N'DF_Brand_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.Brand ADD CONSTRAINT DF_Brand_IsActive DEFAULT (1) FOR IsActive;'),
(105, N'ref', N'DF_Brand_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.Brand ADD CONSTRAINT DF_Brand_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(106, N'ref', N'DF_OrderStatus_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.OrderStatus ADD CONSTRAINT DF_OrderStatus_IsActive DEFAULT (1) FOR IsActive;'),
(107, N'ref', N'DF_OrderStatus_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.OrderStatus ADD CONSTRAINT DF_OrderStatus_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(108, N'ref', N'DF_PaymentMethod_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.PaymentMethod ADD CONSTRAINT DF_PaymentMethod_IsActive DEFAULT (1) FOR IsActive;'),
(109, N'ref', N'DF_PaymentMethod_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.PaymentMethod ADD CONSTRAINT DF_PaymentMethod_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(110, N'ref', N'DF_PaymentStatus_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.PaymentStatus ADD CONSTRAINT DF_PaymentStatus_IsActive DEFAULT (1) FOR IsActive;'),
(111, N'ref', N'DF_PaymentStatus_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.PaymentStatus ADD CONSTRAINT DF_PaymentStatus_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(112, N'ref', N'DF_ReturnReason_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.ReturnReason ADD CONSTRAINT DF_ReturnReason_IsActive DEFAULT (1) FOR IsActive;'),
(113, N'ref', N'DF_ReturnReason_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.ReturnReason ADD CONSTRAINT DF_ReturnReason_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(114, N'ref', N'DF_ReturnStatus_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.ReturnStatus ADD CONSTRAINT DF_ReturnStatus_IsActive DEFAULT (1) FOR IsActive;'),
(115, N'ref', N'DF_ReturnStatus_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.ReturnStatus ADD CONSTRAINT DF_ReturnStatus_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(116, N'ref', N'DF_InventoryMovementType_RequiresReference', 'D ', 'DEFAULT', N'ALTER TABLE ref.InventoryMovementType ADD CONSTRAINT DF_InventoryMovementType_RequiresReference DEFAULT (0) FOR RequiresReference;'),
(117, N'ref', N'DF_InventoryMovementType_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE ref.InventoryMovementType ADD CONSTRAINT DF_InventoryMovementType_IsActive DEFAULT (1) FOR IsActive;'),
(118, N'ref', N'DF_InventoryMovementType_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE ref.InventoryMovementType ADD CONSTRAINT DF_InventoryMovementType_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(119, N'core', N'DF_Store_Country', 'D ', 'DEFAULT', N'ALTER TABLE core.Store ADD CONSTRAINT DF_Store_Country DEFAULT (''India'') FOR Country;'),
(120, N'core', N'DF_Store_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE core.Store ADD CONSTRAINT DF_Store_IsActive DEFAULT (1) FOR IsActive;'),
(121, N'core', N'DF_Store_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE core.Store ADD CONSTRAINT DF_Store_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(122, N'core', N'DF_Employee_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE core.Employee ADD CONSTRAINT DF_Employee_IsActive DEFAULT (1) FOR IsActive;'),
(123, N'core', N'DF_Employee_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE core.Employee ADD CONSTRAINT DF_Employee_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(124, N'core', N'DF_Customer_LoyaltyPoints', 'D ', 'DEFAULT', N'ALTER TABLE core.Customer ADD CONSTRAINT DF_Customer_LoyaltyPoints DEFAULT (0) FOR LoyaltyPoints;'),
(125, N'core', N'DF_Customer_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE core.Customer ADD CONSTRAINT DF_Customer_IsActive DEFAULT (1) FOR IsActive;'),
(126, N'core', N'DF_Customer_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE core.Customer ADD CONSTRAINT DF_Customer_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(127, N'core', N'DF_Supplier_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE core.Supplier ADD CONSTRAINT DF_Supplier_IsActive DEFAULT (1) FOR IsActive;'),
(128, N'core', N'DF_Supplier_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE core.Supplier ADD CONSTRAINT DF_Supplier_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(129, N'core', N'DF_Product_ReorderLevel', 'D ', 'DEFAULT', N'ALTER TABLE core.Product ADD CONSTRAINT DF_Product_ReorderLevel DEFAULT (10) FOR ReorderLevel;'),
(130, N'core', N'DF_Product_IsActive', 'D ', 'DEFAULT', N'ALTER TABLE core.Product ADD CONSTRAINT DF_Product_IsActive DEFAULT (1) FOR IsActive;'),
(131, N'core', N'DF_Product_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE core.Product ADD CONSTRAINT DF_Product_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(132, N'sales', N'DF_SalesOrder_SubtotalAmount', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrder ADD CONSTRAINT DF_SalesOrder_SubtotalAmount DEFAULT (0) FOR SubtotalAmount;'),
(133, N'sales', N'DF_SalesOrder_DiscountAmount', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrder ADD CONSTRAINT DF_SalesOrder_DiscountAmount DEFAULT (0) FOR DiscountAmount;'),
(134, N'sales', N'DF_SalesOrder_TaxAmount', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrder ADD CONSTRAINT DF_SalesOrder_TaxAmount DEFAULT (0) FOR TaxAmount;'),
(135, N'sales', N'DF_SalesOrder_NetAmount', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrder ADD CONSTRAINT DF_SalesOrder_NetAmount DEFAULT (0) FOR NetAmount;'),
(136, N'sales', N'DF_SalesOrder_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrder ADD CONSTRAINT DF_SalesOrder_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(137, N'sales', N'DF_SalesOrderItem_DiscountAmount', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrderItem ADD CONSTRAINT DF_SalesOrderItem_DiscountAmount DEFAULT (0) FOR DiscountAmount;'),
(138, N'sales', N'DF_SalesOrderItem_TaxRate', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrderItem ADD CONSTRAINT DF_SalesOrderItem_TaxRate DEFAULT (0) FOR TaxRate;'),
(139, N'sales', N'DF_SalesOrderItem_TaxAmount', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrderItem ADD CONSTRAINT DF_SalesOrderItem_TaxAmount DEFAULT (0) FOR TaxAmount;'),
(140, N'sales', N'DF_SalesOrderItem_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE sales.SalesOrderItem ADD CONSTRAINT DF_SalesOrderItem_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(141, N'sales', N'DF_OrderStatusHistory_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE sales.OrderStatusHistory ADD CONSTRAINT DF_OrderStatusHistory_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(142, N'sales', N'DF_Payment_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE sales.Payment ADD CONSTRAINT DF_Payment_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(143, N'sales', N'DF_ProductReturn_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE sales.ProductReturn ADD CONSTRAINT DF_ProductReturn_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(144, N'sales', N'DF_ProductReturnItem_QuantityAccepted', 'D ', 'DEFAULT', N'ALTER TABLE sales.ProductReturnItem ADD CONSTRAINT DF_ProductReturnItem_QuantityAccepted DEFAULT (0) FOR QuantityAccepted;'),
(145, N'sales', N'DF_ProductReturnItem_EligibleRefundAmount', 'D ', 'DEFAULT', N'ALTER TABLE sales.ProductReturnItem ADD CONSTRAINT DF_ProductReturnItem_EligibleRefundAmount DEFAULT (0) FOR EligibleRefundAmount;'),
(146, N'sales', N'DF_ProductReturnItem_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE sales.ProductReturnItem ADD CONSTRAINT DF_ProductReturnItem_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(147, N'sales', N'DF_Refund_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE sales.Refund ADD CONSTRAINT DF_Refund_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(148, N'inventory', N'DF_InventoryBalance_QuantityOnHand', 'D ', 'DEFAULT', N'ALTER TABLE inventory.InventoryBalance ADD CONSTRAINT DF_InventoryBalance_QuantityOnHand DEFAULT (0) FOR QuantityOnHand;'),
(149, N'inventory', N'DF_InventoryBalance_QuantityReserved', 'D ', 'DEFAULT', N'ALTER TABLE inventory.InventoryBalance ADD CONSTRAINT DF_InventoryBalance_QuantityReserved DEFAULT (0) FOR QuantityReserved;'),
(150, N'inventory', N'DF_InventoryBalance_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE inventory.InventoryBalance ADD CONSTRAINT DF_InventoryBalance_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(151, N'inventory', N'DF_InventoryMovement_CreatedDate', 'D ', 'DEFAULT', N'ALTER TABLE inventory.InventoryMovement ADD CONSTRAINT DF_InventoryMovement_CreatedDate DEFAULT (SYSDATETIME()) FOR CreatedDate;'),
(152, N'audit', N'DF_ValidationRun_EnvironmentName', 'D ', 'DEFAULT', N'ALTER TABLE audit.ValidationRun ADD CONSTRAINT DF_ValidationRun_EnvironmentName DEFAULT (''Local'') FOR EnvironmentName;'),
(153, N'audit', N'DF_ValidationRun_OverallStatus', 'D ', 'DEFAULT', N'ALTER TABLE audit.ValidationRun ADD CONSTRAINT DF_ValidationRun_OverallStatus DEFAULT (''Running'') FOR OverallStatus;'),
(154, N'audit', N'DF_ValidationRun_TotalTests', 'D ', 'DEFAULT', N'ALTER TABLE audit.ValidationRun ADD CONSTRAINT DF_ValidationRun_TotalTests DEFAULT (0) FOR TotalTests;'),
(155, N'audit', N'DF_ValidationRun_PassedTests', 'D ', 'DEFAULT', N'ALTER TABLE audit.ValidationRun ADD CONSTRAINT DF_ValidationRun_PassedTests DEFAULT (0) FOR PassedTests;'),
(156, N'audit', N'DF_ValidationRun_FailedTests', 'D ', 'DEFAULT', N'ALTER TABLE audit.ValidationRun ADD CONSTRAINT DF_ValidationRun_FailedTests DEFAULT (0) FOR FailedTests;'),
(157, N'audit', N'DF_ValidationResult_ExceptionCount', 'D ', 'DEFAULT', N'ALTER TABLE audit.ValidationResult ADD CONSTRAINT DF_ValidationResult_ExceptionCount DEFAULT (0) FOR ExceptionCount;'),
(158, N'audit', N'DF_ValidationResult_ExecutedDate', 'D ', 'DEFAULT', N'ALTER TABLE audit.ValidationResult ADD CONSTRAINT DF_ValidationResult_ExecutedDate DEFAULT (SYSDATETIME()) FOR ExecutedDate;');

-- ============================================================================
-- CHECK CONSTRAINTS (43)
-- ============================================================================

INSERT INTO #ConstraintBuild VALUES
(200, N'ref', N'CK_InventoryMovementType_QuantityDirection', 'C ', 'CHECK', N'ALTER TABLE ref.InventoryMovementType WITH CHECK ADD CONSTRAINT CK_InventoryMovementType_QuantityDirection CHECK (QuantityDirection IN (-1, 1)); ALTER TABLE ref.InventoryMovementType CHECK CONSTRAINT CK_InventoryMovementType_QuantityDirection;'),
(201, N'core', N'CK_Store_OperatingDates', 'C ', 'CHECK', N'ALTER TABLE core.Store WITH CHECK ADD CONSTRAINT CK_Store_OperatingDates CHECK (ClosingDate IS NULL OR ClosingDate >= OpeningDate); ALTER TABLE core.Store CHECK CONSTRAINT CK_Store_OperatingDates;'),
(202, N'core', N'CK_Employee_SalaryPositive', 'C ', 'CHECK', N'ALTER TABLE core.Employee WITH CHECK ADD CONSTRAINT CK_Employee_SalaryPositive CHECK (Salary > 0); ALTER TABLE core.Employee CHECK CONSTRAINT CK_Employee_SalaryPositive;'),
(203, N'core', N'CK_Employee_EmploymentDates', 'C ', 'CHECK', N'ALTER TABLE core.Employee WITH CHECK ADD CONSTRAINT CK_Employee_EmploymentDates CHECK (TerminationDate IS NULL OR TerminationDate >= HireDate); ALTER TABLE core.Employee CHECK CONSTRAINT CK_Employee_EmploymentDates;'),
(204, N'core', N'CK_Employee_NotOwnManager', 'C ', 'CHECK', N'ALTER TABLE core.Employee WITH CHECK ADD CONSTRAINT CK_Employee_NotOwnManager CHECK (ManagerEmployeeID IS NULL OR ManagerEmployeeID <> EmployeeID); ALTER TABLE core.Employee CHECK CONSTRAINT CK_Employee_NotOwnManager;'),
(205, N'core', N'CK_Customer_LoyaltyPointsNonNegative', 'C ', 'CHECK', N'ALTER TABLE core.Customer WITH CHECK ADD CONSTRAINT CK_Customer_LoyaltyPointsNonNegative CHECK (LoyaltyPoints >= 0); ALTER TABLE core.Customer CHECK CONSTRAINT CK_Customer_LoyaltyPointsNonNegative;'),
(206, N'core', N'CK_Product_CostPricePositive', 'C ', 'CHECK', N'ALTER TABLE core.Product WITH CHECK ADD CONSTRAINT CK_Product_CostPricePositive CHECK (CostPrice > 0); ALTER TABLE core.Product CHECK CONSTRAINT CK_Product_CostPricePositive;'),
(207, N'core', N'CK_Product_SellingPricePositive', 'C ', 'CHECK', N'ALTER TABLE core.Product WITH CHECK ADD CONSTRAINT CK_Product_SellingPricePositive CHECK (SellingPrice > 0); ALTER TABLE core.Product CHECK CONSTRAINT CK_Product_SellingPricePositive;'),
(208, N'core', N'CK_Product_ReorderLevelNonNegative', 'C ', 'CHECK', N'ALTER TABLE core.Product WITH CHECK ADD CONSTRAINT CK_Product_ReorderLevelNonNegative CHECK (ReorderLevel >= 0); ALTER TABLE core.Product CHECK CONSTRAINT CK_Product_ReorderLevelNonNegative;'),
(209, N'core', N'CK_Product_ExcessStockLevel', 'C ', 'CHECK', N'ALTER TABLE core.Product WITH CHECK ADD CONSTRAINT CK_Product_ExcessStockLevel CHECK (ExcessStockLevel IS NULL OR ExcessStockLevel >= ReorderLevel); ALTER TABLE core.Product CHECK CONSTRAINT CK_Product_ExcessStockLevel;'),
(210, N'sales', N'CK_SalesOrder_LifecycleDates', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_LifecycleDates CHECK ((ConfirmedDate IS NULL OR ConfirmedDate >= OrderDate) AND (ShippedDate IS NULL OR (ConfirmedDate IS NOT NULL AND ShippedDate >= ConfirmedDate)) AND (DeliveredDate IS NULL OR (ShippedDate IS NOT NULL AND DeliveredDate >= ShippedDate)) AND (CancelledDate IS NULL OR CancelledDate >= OrderDate)); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT CK_SalesOrder_LifecycleDates;'),
(211, N'sales', N'CK_SalesOrder_TerminalDates', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_TerminalDates CHECK (DeliveredDate IS NULL OR CancelledDate IS NULL); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT CK_SalesOrder_TerminalDates;'),
(212, N'sales', N'CK_SalesOrder_AmountsNonNegative', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_AmountsNonNegative CHECK (SubtotalAmount >= 0 AND DiscountAmount >= 0 AND TaxAmount >= 0 AND NetAmount >= 0); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT CK_SalesOrder_AmountsNonNegative;'),
(213, N'sales', N'CK_SalesOrder_DiscountWithinSubtotal', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_DiscountWithinSubtotal CHECK (DiscountAmount <= SubtotalAmount); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT CK_SalesOrder_DiscountWithinSubtotal;'),
(214, N'sales', N'CK_SalesOrder_NetAmountFormula', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT CK_SalesOrder_NetAmountFormula CHECK (NetAmount = SubtotalAmount - DiscountAmount + TaxAmount); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT CK_SalesOrder_NetAmountFormula;'),
(215, N'sales', N'CK_SalesOrderItem_QuantityPositive', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT CK_SalesOrderItem_QuantityPositive CHECK (Quantity > 0); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT CK_SalesOrderItem_QuantityPositive;'),
(216, N'sales', N'CK_SalesOrderItem_PricesPositive', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT CK_SalesOrderItem_PricesPositive CHECK (UnitCost > 0 AND UnitPrice > 0); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT CK_SalesOrderItem_PricesPositive;'),
(217, N'sales', N'CK_SalesOrderItem_GrossAmountFormula', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT CK_SalesOrderItem_GrossAmountFormula CHECK (GrossAmount = Quantity * UnitPrice); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT CK_SalesOrderItem_GrossAmountFormula;'),
(218, N'sales', N'CK_SalesOrderItem_DiscountAmount', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT CK_SalesOrderItem_DiscountAmount CHECK (DiscountAmount >= 0 AND DiscountAmount <= GrossAmount); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT CK_SalesOrderItem_DiscountAmount;'),
(219, N'sales', N'CK_SalesOrderItem_TaxRate', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT CK_SalesOrderItem_TaxRate CHECK (TaxRate >= 0 AND TaxRate <= 100); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT CK_SalesOrderItem_TaxRate;'),
(220, N'sales', N'CK_SalesOrderItem_TaxAmountFormula', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT CK_SalesOrderItem_TaxAmountFormula CHECK (TaxAmount = ROUND((GrossAmount - DiscountAmount) * TaxRate / 100.0, 2)); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT CK_SalesOrderItem_TaxAmountFormula;'),
(221, N'sales', N'CK_SalesOrderItem_NetAmountFormula', 'C ', 'CHECK', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT CK_SalesOrderItem_NetAmountFormula CHECK (NetAmount = GrossAmount - DiscountAmount + TaxAmount); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT CK_SalesOrderItem_NetAmountFormula;'),
(222, N'sales', N'CK_OrderStatusHistory_StatusChange', 'C ', 'CHECK', N'ALTER TABLE sales.OrderStatusHistory WITH CHECK ADD CONSTRAINT CK_OrderStatusHistory_StatusChange CHECK (FromOrderStatusID IS NULL OR FromOrderStatusID <> ToOrderStatusID); ALTER TABLE sales.OrderStatusHistory CHECK CONSTRAINT CK_OrderStatusHistory_StatusChange;'),
(223, N'sales', N'CK_Payment_AttemptNumberPositive', 'C ', 'CHECK', N'ALTER TABLE sales.Payment WITH CHECK ADD CONSTRAINT CK_Payment_AttemptNumberPositive CHECK (AttemptNumber > 0); ALTER TABLE sales.Payment CHECK CONSTRAINT CK_Payment_AttemptNumberPositive;'),
(224, N'sales', N'CK_Payment_AmountPositive', 'C ', 'CHECK', N'ALTER TABLE sales.Payment WITH CHECK ADD CONSTRAINT CK_Payment_AmountPositive CHECK (Amount > 0); ALTER TABLE sales.Payment CHECK CONSTRAINT CK_Payment_AmountPositive;'),
(225, N'sales', N'CK_ProductReturn_LifecycleDates', 'C ', 'CHECK', N'ALTER TABLE sales.ProductReturn WITH CHECK ADD CONSTRAINT CK_ProductReturn_LifecycleDates CHECK ((ApprovedDate IS NULL OR ApprovedDate >= RequestDate) AND (ReceivedDate IS NULL OR (ApprovedDate IS NOT NULL AND ReceivedDate >= ApprovedDate)) AND (ClosedDate IS NULL OR ClosedDate >= RequestDate)); ALTER TABLE sales.ProductReturn CHECK CONSTRAINT CK_ProductReturn_LifecycleDates;'),
(226, N'sales', N'CK_ProductReturnItem_QuantityRequestedPositive', 'C ', 'CHECK', N'ALTER TABLE sales.ProductReturnItem WITH CHECK ADD CONSTRAINT CK_ProductReturnItem_QuantityRequestedPositive CHECK (QuantityRequested > 0); ALTER TABLE sales.ProductReturnItem CHECK CONSTRAINT CK_ProductReturnItem_QuantityRequestedPositive;'),
(227, N'sales', N'CK_ProductReturnItem_QuantityAccepted', 'C ', 'CHECK', N'ALTER TABLE sales.ProductReturnItem WITH CHECK ADD CONSTRAINT CK_ProductReturnItem_QuantityAccepted CHECK (QuantityAccepted >= 0 AND QuantityAccepted <= QuantityRequested); ALTER TABLE sales.ProductReturnItem CHECK CONSTRAINT CK_ProductReturnItem_QuantityAccepted;'),
(228, N'sales', N'CK_ProductReturnItem_EligibleRefundAmount', 'C ', 'CHECK', N'ALTER TABLE sales.ProductReturnItem WITH CHECK ADD CONSTRAINT CK_ProductReturnItem_EligibleRefundAmount CHECK (EligibleRefundAmount >= 0); ALTER TABLE sales.ProductReturnItem CHECK CONSTRAINT CK_ProductReturnItem_EligibleRefundAmount;'),
(229, N'sales', N'CK_Refund_AmountPositive', 'C ', 'CHECK', N'ALTER TABLE sales.Refund WITH CHECK ADD CONSTRAINT CK_Refund_AmountPositive CHECK (RefundAmount > 0); ALTER TABLE sales.Refund CHECK CONSTRAINT CK_Refund_AmountPositive;'),
(230, N'sales', N'CK_Refund_Status', 'C ', 'CHECK', N'ALTER TABLE sales.Refund WITH CHECK ADD CONSTRAINT CK_Refund_Status CHECK (RefundStatus IN (''Pending'', ''Completed'', ''Failed'')); ALTER TABLE sales.Refund CHECK CONSTRAINT CK_Refund_Status;'),
(231, N'inventory', N'CK_InventoryBalance_Quantities', 'C ', 'CHECK', N'ALTER TABLE inventory.InventoryBalance WITH CHECK ADD CONSTRAINT CK_InventoryBalance_Quantities CHECK (QuantityOnHand >= 0 AND QuantityReserved >= 0 AND QuantityReserved <= QuantityOnHand); ALTER TABLE inventory.InventoryBalance CHECK CONSTRAINT CK_InventoryBalance_Quantities;'),
(232, N'inventory', N'CK_InventoryBalance_MovementDates', 'C ', 'CHECK', N'ALTER TABLE inventory.InventoryBalance WITH CHECK ADD CONSTRAINT CK_InventoryBalance_MovementDates CHECK (LastRestockedDate IS NULL OR LastMovementDate IS NULL OR LastRestockedDate <= LastMovementDate); ALTER TABLE inventory.InventoryBalance CHECK CONSTRAINT CK_InventoryBalance_MovementDates;'),
(233, N'inventory', N'CK_InventoryMovement_QuantityPositive', 'C ', 'CHECK', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT CK_InventoryMovement_QuantityPositive CHECK (Quantity > 0); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT CK_InventoryMovement_QuantityPositive;'),
(234, N'inventory', N'CK_InventoryMovement_QuantityDirection', 'C ', 'CHECK', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT CK_InventoryMovement_QuantityDirection CHECK (QuantityDirection IN (-1, 1)); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT CK_InventoryMovement_QuantityDirection;'),
(235, N'inventory', N'CK_InventoryMovement_SourceReference', 'C ', 'CHECK', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT CK_InventoryMovement_SourceReference CHECK (SalesOrderItemID IS NULL OR ProductReturnItemID IS NULL); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT CK_InventoryMovement_SourceReference;'),
(236, N'audit', N'CK_ValidationRun_RunDates', 'C ', 'CHECK', N'ALTER TABLE audit.ValidationRun WITH CHECK ADD CONSTRAINT CK_ValidationRun_RunDates CHECK (RunEndDate IS NULL OR RunEndDate >= RunStartDate); ALTER TABLE audit.ValidationRun CHECK CONSTRAINT CK_ValidationRun_RunDates;'),
(237, N'audit', N'CK_ValidationRun_OverallStatus', 'C ', 'CHECK', N'ALTER TABLE audit.ValidationRun WITH CHECK ADD CONSTRAINT CK_ValidationRun_OverallStatus CHECK (OverallStatus IN (''Running'', ''Passed'', ''Failed'')); ALTER TABLE audit.ValidationRun CHECK CONSTRAINT CK_ValidationRun_OverallStatus;'),
(238, N'audit', N'CK_ValidationRun_TestCounts', 'C ', 'CHECK', N'ALTER TABLE audit.ValidationRun WITH CHECK ADD CONSTRAINT CK_ValidationRun_TestCounts CHECK (TotalTests >= 0 AND PassedTests >= 0 AND FailedTests >= 0 AND PassedTests + FailedTests <= TotalTests); ALTER TABLE audit.ValidationRun CHECK CONSTRAINT CK_ValidationRun_TestCounts;'),
(239, N'audit', N'CK_ValidationRun_CompletedCounts', 'C ', 'CHECK', N'ALTER TABLE audit.ValidationRun WITH CHECK ADD CONSTRAINT CK_ValidationRun_CompletedCounts CHECK (OverallStatus = ''Running'' OR (RunEndDate IS NOT NULL AND PassedTests + FailedTests = TotalTests)); ALTER TABLE audit.ValidationRun CHECK CONSTRAINT CK_ValidationRun_CompletedCounts;'),
(240, N'audit', N'CK_ValidationResult_Severity', 'C ', 'CHECK', N'ALTER TABLE audit.ValidationResult WITH CHECK ADD CONSTRAINT CK_ValidationResult_Severity CHECK (Severity IN (''Critical'', ''High'', ''Medium'', ''Warning'', ''Info'')); ALTER TABLE audit.ValidationResult CHECK CONSTRAINT CK_ValidationResult_Severity;'),
(241, N'audit', N'CK_ValidationResult_ExceptionCount', 'C ', 'CHECK', N'ALTER TABLE audit.ValidationResult WITH CHECK ADD CONSTRAINT CK_ValidationResult_ExceptionCount CHECK (ExceptionCount >= 0); ALTER TABLE audit.ValidationResult CHECK CONSTRAINT CK_ValidationResult_ExceptionCount;'),
(242, N'audit', N'CK_ValidationResult_TestStatus', 'C ', 'CHECK', N'ALTER TABLE audit.ValidationResult WITH CHECK ADD CONSTRAINT CK_ValidationResult_TestStatus CHECK (TestStatus IN (''Passed'', ''Failed'')); ALTER TABLE audit.ValidationResult CHECK CONSTRAINT CK_ValidationResult_TestStatus;');

-- ============================================================================
-- FOREIGN KEYS (36) — all use NO ACTION for delete/update.
-- ============================================================================

INSERT INTO #ConstraintBuild VALUES
(300, N'ref', N'FK_SubCategory_Category', 'F ', 'FOREIGN KEY', N'ALTER TABLE ref.SubCategory WITH CHECK ADD CONSTRAINT FK_SubCategory_Category FOREIGN KEY (CategoryID) REFERENCES ref.Category (CategoryID); ALTER TABLE ref.SubCategory CHECK CONSTRAINT FK_SubCategory_Category;'),
(301, N'core', N'FK_Product_SubCategory', 'F ', 'FOREIGN KEY', N'ALTER TABLE core.Product WITH CHECK ADD CONSTRAINT FK_Product_SubCategory FOREIGN KEY (SubCategoryID) REFERENCES ref.SubCategory (SubCategoryID); ALTER TABLE core.Product CHECK CONSTRAINT FK_Product_SubCategory;'),
(302, N'core', N'FK_Product_Brand', 'F ', 'FOREIGN KEY', N'ALTER TABLE core.Product WITH CHECK ADD CONSTRAINT FK_Product_Brand FOREIGN KEY (BrandID) REFERENCES ref.Brand (BrandID); ALTER TABLE core.Product CHECK CONSTRAINT FK_Product_Brand;'),
(303, N'core', N'FK_Product_Supplier', 'F ', 'FOREIGN KEY', N'ALTER TABLE core.Product WITH CHECK ADD CONSTRAINT FK_Product_Supplier FOREIGN KEY (SupplierID) REFERENCES core.Supplier (SupplierID); ALTER TABLE core.Product CHECK CONSTRAINT FK_Product_Supplier;'),
(304, N'core', N'FK_Employee_Store', 'F ', 'FOREIGN KEY', N'ALTER TABLE core.Employee WITH CHECK ADD CONSTRAINT FK_Employee_Store FOREIGN KEY (StoreID) REFERENCES core.Store (StoreID); ALTER TABLE core.Employee CHECK CONSTRAINT FK_Employee_Store;'),
(305, N'core', N'FK_Employee_Manager', 'F ', 'FOREIGN KEY', N'ALTER TABLE core.Employee WITH CHECK ADD CONSTRAINT FK_Employee_Manager FOREIGN KEY (ManagerEmployeeID) REFERENCES core.Employee (EmployeeID); ALTER TABLE core.Employee CHECK CONSTRAINT FK_Employee_Manager;'),
(306, N'core', N'FK_Store_ManagerEmployee', 'F ', 'FOREIGN KEY', N'ALTER TABLE core.Store WITH CHECK ADD CONSTRAINT FK_Store_ManagerEmployee FOREIGN KEY (ManagerEmployeeID) REFERENCES core.Employee (EmployeeID); ALTER TABLE core.Store CHECK CONSTRAINT FK_Store_ManagerEmployee;'),
(307, N'sales', N'FK_SalesOrder_Customer', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT FK_SalesOrder_Customer FOREIGN KEY (CustomerID) REFERENCES core.Customer (CustomerID); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT FK_SalesOrder_Customer;'),
(308, N'sales', N'FK_SalesOrder_Store', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT FK_SalesOrder_Store FOREIGN KEY (StoreID) REFERENCES core.Store (StoreID); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT FK_SalesOrder_Store;'),
(309, N'sales', N'FK_SalesOrder_Employee', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT FK_SalesOrder_Employee FOREIGN KEY (EmployeeID) REFERENCES core.Employee (EmployeeID); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT FK_SalesOrder_Employee;'),
(310, N'sales', N'FK_SalesOrder_OrderStatus', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.SalesOrder WITH CHECK ADD CONSTRAINT FK_SalesOrder_OrderStatus FOREIGN KEY (OrderStatusID) REFERENCES ref.OrderStatus (OrderStatusID); ALTER TABLE sales.SalesOrder CHECK CONSTRAINT FK_SalesOrder_OrderStatus;'),
(311, N'sales', N'FK_SalesOrderItem_SalesOrder', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT FK_SalesOrderItem_SalesOrder FOREIGN KEY (SalesOrderID) REFERENCES sales.SalesOrder (SalesOrderID); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT FK_SalesOrderItem_SalesOrder;'),
(312, N'sales', N'FK_SalesOrderItem_Product', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.SalesOrderItem WITH CHECK ADD CONSTRAINT FK_SalesOrderItem_Product FOREIGN KEY (ProductID) REFERENCES core.Product (ProductID); ALTER TABLE sales.SalesOrderItem CHECK CONSTRAINT FK_SalesOrderItem_Product;'),
(313, N'sales', N'FK_OrderStatusHistory_SalesOrder', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.OrderStatusHistory WITH CHECK ADD CONSTRAINT FK_OrderStatusHistory_SalesOrder FOREIGN KEY (SalesOrderID) REFERENCES sales.SalesOrder (SalesOrderID); ALTER TABLE sales.OrderStatusHistory CHECK CONSTRAINT FK_OrderStatusHistory_SalesOrder;'),
(314, N'sales', N'FK_OrderStatusHistory_FromOrderStatus', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.OrderStatusHistory WITH CHECK ADD CONSTRAINT FK_OrderStatusHistory_FromOrderStatus FOREIGN KEY (FromOrderStatusID) REFERENCES ref.OrderStatus (OrderStatusID); ALTER TABLE sales.OrderStatusHistory CHECK CONSTRAINT FK_OrderStatusHistory_FromOrderStatus;'),
(315, N'sales', N'FK_OrderStatusHistory_ToOrderStatus', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.OrderStatusHistory WITH CHECK ADD CONSTRAINT FK_OrderStatusHistory_ToOrderStatus FOREIGN KEY (ToOrderStatusID) REFERENCES ref.OrderStatus (OrderStatusID); ALTER TABLE sales.OrderStatusHistory CHECK CONSTRAINT FK_OrderStatusHistory_ToOrderStatus;'),
(316, N'sales', N'FK_OrderStatusHistory_ChangedByEmployee', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.OrderStatusHistory WITH CHECK ADD CONSTRAINT FK_OrderStatusHistory_ChangedByEmployee FOREIGN KEY (ChangedByEmployeeID) REFERENCES core.Employee (EmployeeID); ALTER TABLE sales.OrderStatusHistory CHECK CONSTRAINT FK_OrderStatusHistory_ChangedByEmployee;'),
(317, N'sales', N'FK_Payment_SalesOrder', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.Payment WITH CHECK ADD CONSTRAINT FK_Payment_SalesOrder FOREIGN KEY (SalesOrderID) REFERENCES sales.SalesOrder (SalesOrderID); ALTER TABLE sales.Payment CHECK CONSTRAINT FK_Payment_SalesOrder;'),
(318, N'sales', N'FK_Payment_PaymentMethod', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.Payment WITH CHECK ADD CONSTRAINT FK_Payment_PaymentMethod FOREIGN KEY (PaymentMethodID) REFERENCES ref.PaymentMethod (PaymentMethodID); ALTER TABLE sales.Payment CHECK CONSTRAINT FK_Payment_PaymentMethod;'),
(319, N'sales', N'FK_Payment_PaymentStatus', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.Payment WITH CHECK ADD CONSTRAINT FK_Payment_PaymentStatus FOREIGN KEY (PaymentStatusID) REFERENCES ref.PaymentStatus (PaymentStatusID); ALTER TABLE sales.Payment CHECK CONSTRAINT FK_Payment_PaymentStatus;'),
(320, N'sales', N'FK_ProductReturn_SalesOrder', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.ProductReturn WITH CHECK ADD CONSTRAINT FK_ProductReturn_SalesOrder FOREIGN KEY (SalesOrderID) REFERENCES sales.SalesOrder (SalesOrderID); ALTER TABLE sales.ProductReturn CHECK CONSTRAINT FK_ProductReturn_SalesOrder;'),
(321, N'sales', N'FK_ProductReturn_ReturnStatus', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.ProductReturn WITH CHECK ADD CONSTRAINT FK_ProductReturn_ReturnStatus FOREIGN KEY (ReturnStatusID) REFERENCES ref.ReturnStatus (ReturnStatusID); ALTER TABLE sales.ProductReturn CHECK CONSTRAINT FK_ProductReturn_ReturnStatus;'),
(322, N'sales', N'FK_ProductReturnItem_ProductReturn', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.ProductReturnItem WITH CHECK ADD CONSTRAINT FK_ProductReturnItem_ProductReturn FOREIGN KEY (ProductReturnID) REFERENCES sales.ProductReturn (ProductReturnID); ALTER TABLE sales.ProductReturnItem CHECK CONSTRAINT FK_ProductReturnItem_ProductReturn;'),
(323, N'sales', N'FK_ProductReturnItem_SalesOrderItem', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.ProductReturnItem WITH CHECK ADD CONSTRAINT FK_ProductReturnItem_SalesOrderItem FOREIGN KEY (SalesOrderItemID) REFERENCES sales.SalesOrderItem (SalesOrderItemID); ALTER TABLE sales.ProductReturnItem CHECK CONSTRAINT FK_ProductReturnItem_SalesOrderItem;'),
(324, N'sales', N'FK_ProductReturnItem_ReturnReason', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.ProductReturnItem WITH CHECK ADD CONSTRAINT FK_ProductReturnItem_ReturnReason FOREIGN KEY (ReturnReasonID) REFERENCES ref.ReturnReason (ReturnReasonID); ALTER TABLE sales.ProductReturnItem CHECK CONSTRAINT FK_ProductReturnItem_ReturnReason;'),
(325, N'sales', N'FK_Refund_Payment', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.Refund WITH CHECK ADD CONSTRAINT FK_Refund_Payment FOREIGN KEY (PaymentID) REFERENCES sales.Payment (PaymentID); ALTER TABLE sales.Refund CHECK CONSTRAINT FK_Refund_Payment;'),
(326, N'sales', N'FK_Refund_ProductReturn', 'F ', 'FOREIGN KEY', N'ALTER TABLE sales.Refund WITH CHECK ADD CONSTRAINT FK_Refund_ProductReturn FOREIGN KEY (ProductReturnID) REFERENCES sales.ProductReturn (ProductReturnID); ALTER TABLE sales.Refund CHECK CONSTRAINT FK_Refund_ProductReturn;'),
(327, N'inventory', N'FK_InventoryBalance_Product', 'F ', 'FOREIGN KEY', N'ALTER TABLE inventory.InventoryBalance WITH CHECK ADD CONSTRAINT FK_InventoryBalance_Product FOREIGN KEY (ProductID) REFERENCES core.Product (ProductID); ALTER TABLE inventory.InventoryBalance CHECK CONSTRAINT FK_InventoryBalance_Product;'),
(328, N'inventory', N'FK_InventoryBalance_Store', 'F ', 'FOREIGN KEY', N'ALTER TABLE inventory.InventoryBalance WITH CHECK ADD CONSTRAINT FK_InventoryBalance_Store FOREIGN KEY (StoreID) REFERENCES core.Store (StoreID); ALTER TABLE inventory.InventoryBalance CHECK CONSTRAINT FK_InventoryBalance_Store;'),
(329, N'inventory', N'FK_InventoryMovement_Product', 'F ', 'FOREIGN KEY', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT FK_InventoryMovement_Product FOREIGN KEY (ProductID) REFERENCES core.Product (ProductID); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT FK_InventoryMovement_Product;'),
(330, N'inventory', N'FK_InventoryMovement_Store', 'F ', 'FOREIGN KEY', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT FK_InventoryMovement_Store FOREIGN KEY (StoreID) REFERENCES core.Store (StoreID); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT FK_InventoryMovement_Store;'),
(331, N'inventory', N'FK_InventoryMovement_InventoryMovementType', 'F ', 'FOREIGN KEY', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT FK_InventoryMovement_InventoryMovementType FOREIGN KEY (InventoryMovementTypeID) REFERENCES ref.InventoryMovementType (InventoryMovementTypeID); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT FK_InventoryMovement_InventoryMovementType;'),
(332, N'inventory', N'FK_InventoryMovement_SalesOrderItem', 'F ', 'FOREIGN KEY', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT FK_InventoryMovement_SalesOrderItem FOREIGN KEY (SalesOrderItemID) REFERENCES sales.SalesOrderItem (SalesOrderItemID); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT FK_InventoryMovement_SalesOrderItem;'),
(333, N'inventory', N'FK_InventoryMovement_ProductReturnItem', 'F ', 'FOREIGN KEY', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT FK_InventoryMovement_ProductReturnItem FOREIGN KEY (ProductReturnItemID) REFERENCES sales.ProductReturnItem (ProductReturnItemID); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT FK_InventoryMovement_ProductReturnItem;'),
(334, N'inventory', N'FK_InventoryMovement_CreatedByEmployee', 'F ', 'FOREIGN KEY', N'ALTER TABLE inventory.InventoryMovement WITH CHECK ADD CONSTRAINT FK_InventoryMovement_CreatedByEmployee FOREIGN KEY (CreatedByEmployeeID) REFERENCES core.Employee (EmployeeID); ALTER TABLE inventory.InventoryMovement CHECK CONSTRAINT FK_InventoryMovement_CreatedByEmployee;'),
(335, N'audit', N'FK_ValidationResult_ValidationRun', 'F ', 'FOREIGN KEY', N'ALTER TABLE audit.ValidationResult WITH CHECK ADD CONSTRAINT FK_ValidationResult_ValidationRun FOREIGN KEY (ValidationRunID) REFERENCES audit.ValidationRun (ValidationRunID); ALTER TABLE audit.ValidationResult CHECK CONSTRAINT FK_ValidationResult_ValidationRun;');

-- ============================================================================
-- APPLY ALL MISSING CONSTRAINTS IN DEPENDENCY ORDER
-- A local cursor is appropriate here because it executes a small deterministic
-- DDL manifest; business-data processing remains set-based.
-- ============================================================================

DECLARE
    @ConstraintSequence SMALLINT,
    @ConstraintSchema SYSNAME,
    @ConstraintName SYSNAME,
    @ConstraintType CHAR(2),
    @CreateStatement NVARCHAR(MAX),
    @QualifiedConstraintName NVARCHAR(517);

DECLARE ConstraintCursor CURSOR LOCAL FAST_FORWARD FOR
SELECT
    cb.ConstraintSequence,
    cb.ConstraintSchema,
    cb.ConstraintName,
    cb.ConstraintType,
    cb.CreateStatement
FROM #ConstraintBuild AS cb
ORDER BY
    cb.ConstraintSequence;

BEGIN TRY
    BEGIN TRANSACTION;

    OPEN ConstraintCursor;

    FETCH NEXT FROM ConstraintCursor
    INTO
        @ConstraintSequence,
        @ConstraintSchema,
        @ConstraintName,
        @ConstraintType,
        @CreateStatement;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @QualifiedConstraintName = QUOTENAME(@ConstraintSchema) + N'.' + QUOTENAME(@ConstraintName);

        IF OBJECT_ID(@QualifiedConstraintName, RTRIM(@ConstraintType)) IS NULL
        BEGIN
            EXEC sys.sp_executesql @CreateStatement;
        END;

        FETCH NEXT FROM ConstraintCursor
        INTO
            @ConstraintSequence,
            @ConstraintSchema,
            @ConstraintName,
            @ConstraintType,
            @CreateStatement;
    END;

    CLOSE ConstraintCursor;
    DEALLOCATE ConstraintCursor;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local', 'ConstraintCursor') >= 0
        CLOSE ConstraintCursor;

    IF CURSOR_STATUS('local', 'ConstraintCursor') >= -1
        DEALLOCATE ConstraintCursor;

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

-- ============================================================================
-- MANIFEST VALIDATION
-- ============================================================================

DECLARE @MissingConstraintCount INT;

SELECT
    @MissingConstraintCount = COUNT(*)
FROM #ConstraintBuild AS cb
WHERE OBJECT_ID
(
    QUOTENAME(cb.ConstraintSchema) + N'.' + QUOTENAME(cb.ConstraintName),
    RTRIM(cb.ConstraintType)
) IS NULL;

IF @MissingConstraintCount > 0
BEGIN
    SELECT
        cb.ConstraintSequence,
        cb.ConstraintSchema,
        cb.ConstraintName,
        cb.ConstraintGroup
    FROM #ConstraintBuild AS cb
    WHERE OBJECT_ID
    (
        QUOTENAME(cb.ConstraintSchema) + N'.' + QUOTENAME(cb.ConstraintName),
        RTRIM(cb.ConstraintType)
    ) IS NULL
    ORDER BY
        cb.ConstraintSequence;

    THROW 51033, 'Constraint creation validation failed: one or more constraints are missing.', 1;
END;

SELECT
    cb.ConstraintGroup,
    COUNT(*) AS ExpectedCount,
    SUM
    (
        CASE
            WHEN OBJECT_ID
                 (
                     QUOTENAME(cb.ConstraintSchema) + N'.' + QUOTENAME(cb.ConstraintName),
                     RTRIM(cb.ConstraintType)
                 ) IS NOT NULL
            THEN 1
            ELSE 0
        END
    ) AS ExistingCount,
    CASE
        WHEN COUNT(*) = SUM
        (
            CASE
                WHEN OBJECT_ID
                     (
                         QUOTENAME(cb.ConstraintSchema) + N'.' + QUOTENAME(cb.ConstraintName),
                         RTRIM(cb.ConstraintType)
                     ) IS NOT NULL
                THEN 1
                ELSE 0
            END
        )
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM #ConstraintBuild AS cb
GROUP BY
    cb.ConstraintGroup
ORDER BY
    MIN(cb.ConstraintSequence);

SELECT
    COUNT(*) AS ForeignKeyCount,
    SUM(CASE WHEN fk.is_disabled = 1 THEN 1 ELSE 0 END) AS DisabledForeignKeyCount,
    SUM(CASE WHEN fk.is_not_trusted = 1 THEN 1 ELSE 0 END) AS UntrustedForeignKeyCount,
    SUM(CASE WHEN fk.delete_referential_action <> 0 THEN 1 ELSE 0 END) AS CascadingDeleteCount,
    SUM(CASE WHEN fk.update_referential_action <> 0 THEN 1 ELSE 0 END) AS CascadingUpdateCount
FROM sys.foreign_keys AS fk
INNER JOIN sys.tables AS t
    ON t.object_id = fk.parent_object_id
WHERE t.schema_id IN
(
    SCHEMA_ID(N'ref'),
    SCHEMA_ID(N'core'),
    SCHEMA_ID(N'sales'),
    SCHEMA_ID(N'inventory'),
    SCHEMA_ID(N'audit')
);

RAISERROR('04_Create_Constraints.sql completed successfully: constraint manifest validated.', 10, 1) WITH NOWAIT;
GO
