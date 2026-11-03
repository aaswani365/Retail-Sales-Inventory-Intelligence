/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      23_Create_Analytics_Facts.sql
Purpose:     Create and load Power BI-ready analytical fact tables.
Author:      Akshay Aswani
Version:     2.0
Depends on:  22_Create_Analytics_Dimensions.sql
Rerunnable:  Yes. Facts are rebuilt from validated operational sources.

Approved grains
---------------
- FactSales: one row per sales-order item.
- FactPayments: one row per payment attempt.
- FactReturns: one row per returned order item.
- FactRefunds: one row per refund event.
- FactInventoryMovement: one row per inventory movement.
- FactInventorySnapshot: one row per product-store snapshot date.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51400, 'Fact build stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimCustomer', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimProduct', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimStore', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimEmployee', N'U') IS NULL
    THROW 51401, 'Fact build stopped: required analytical dimensions are missing.', 1;

IF (SELECT COUNT(*) FROM analytics.DimDate) <> 1462
   OR (SELECT COUNT(*) FROM analytics.DimCustomer) <> 10001
   OR (SELECT COUNT(*) FROM analytics.DimProduct) <> 501
   OR (SELECT COUNT(*) FROM analytics.DimStore) <> 21
    THROW 51402, 'Fact build stopped: analytical dimensions have not passed approved counts.', 1;

-- ============================================================================
-- 1. CREATE FACT TABLES
-- ============================================================================

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
CREATE TABLE analytics.FactSales
(
    SalesFactKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactSales PRIMARY KEY,
    SalesOrderItemID BIGINT NOT NULL CONSTRAINT UQ_FactSales_SalesOrderItemID UNIQUE,
    SalesOrderID BIGINT NOT NULL,
    OrderNumber VARCHAR(25) NOT NULL,
    OrderDateKey INT NOT NULL CONSTRAINT FK_FactSales_OrderDate REFERENCES analytics.DimDate(DateKey),
    ConfirmedDateKey INT NOT NULL CONSTRAINT FK_FactSales_ConfirmedDate REFERENCES analytics.DimDate(DateKey),
    ShippedDateKey INT NOT NULL CONSTRAINT FK_FactSales_ShippedDate REFERENCES analytics.DimDate(DateKey),
    DeliveredDateKey INT NOT NULL CONSTRAINT FK_FactSales_DeliveredDate REFERENCES analytics.DimDate(DateKey),
    CustomerKey INT NOT NULL CONSTRAINT FK_FactSales_Customer REFERENCES analytics.DimCustomer(CustomerKey),
    ProductKey INT NOT NULL CONSTRAINT FK_FactSales_Product REFERENCES analytics.DimProduct(ProductKey),
    StoreKey INT NOT NULL CONSTRAINT FK_FactSales_Store REFERENCES analytics.DimStore(StoreKey),
    EmployeeKey INT NOT NULL CONSTRAINT FK_FactSales_Employee REFERENCES analytics.DimEmployee(EmployeeKey),
    OrderStatusKey SMALLINT NOT NULL CONSTRAINT FK_FactSales_OrderStatus REFERENCES analytics.DimOrderStatus(OrderStatusKey),
    Quantity INT NOT NULL,
    UnitCost DECIMAL(12,2) NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    GrossAmount DECIMAL(14,2) NOT NULL,
    DiscountAmount DECIMAL(14,2) NOT NULL,
    TaxAmount DECIMAL(14,2) NOT NULL,
    NetAmount DECIMAL(14,2) NOT NULL,
    CostAmount DECIMAL(14,2) NOT NULL,
    GrossProfitAmount DECIMAL(14,2) NOT NULL,
    RecognizedRevenueAmount DECIMAL(14,2) NOT NULL,
    RecognizedCostAmount DECIMAL(14,2) NOT NULL,
    RecognizedGrossProfitAmount DECIMAL(14,2) NOT NULL,
    IsDelivered BIT NOT NULL,
    IsCancelled BIT NOT NULL,
    IsReturned BIT NOT NULL,
    OrderCount TINYINT NOT NULL,
    LineCount TINYINT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_FactSales_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.FactPayments', N'U') IS NULL
CREATE TABLE analytics.FactPayments
(
    PaymentFactKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactPayments PRIMARY KEY,
    PaymentID BIGINT NOT NULL CONSTRAINT UQ_FactPayments_PaymentID UNIQUE,
    SalesOrderID BIGINT NOT NULL,
    OrderNumber VARCHAR(25) NOT NULL,
    PaymentDateKey INT NOT NULL CONSTRAINT FK_FactPayments_Date REFERENCES analytics.DimDate(DateKey),
    CustomerKey INT NOT NULL CONSTRAINT FK_FactPayments_Customer REFERENCES analytics.DimCustomer(CustomerKey),
    StoreKey INT NOT NULL CONSTRAINT FK_FactPayments_Store REFERENCES analytics.DimStore(StoreKey),
    PaymentMethodKey SMALLINT NOT NULL CONSTRAINT FK_FactPayments_Method REFERENCES analytics.DimPaymentMethod(PaymentMethodKey),
    PaymentStatusKey SMALLINT NOT NULL CONSTRAINT FK_FactPayments_Status REFERENCES analytics.DimPaymentStatus(PaymentStatusKey),
    OrderStatusKey SMALLINT NOT NULL CONSTRAINT FK_FactPayments_OrderStatus REFERENCES analytics.DimOrderStatus(OrderStatusKey),
    AttemptNumber SMALLINT NOT NULL,
    Amount DECIMAL(14,2) NOT NULL,
    CollectedAmount DECIMAL(14,2) NOT NULL,
    IsSuccessful BIT NOT NULL,
    IsFailed BIT NOT NULL,
    IsPending BIT NOT NULL,
    AttemptCount TINYINT NOT NULL,
    TransactionReference VARCHAR(100) NOT NULL,
    FailureReason VARCHAR(255) NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_FactPayments_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
CREATE TABLE analytics.FactReturns
(
    ReturnFactKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactReturns PRIMARY KEY,
    ProductReturnItemID BIGINT NOT NULL CONSTRAINT UQ_FactReturns_ProductReturnItemID UNIQUE,
    ProductReturnID BIGINT NOT NULL,
    SalesOrderItemID BIGINT NOT NULL,
    SalesOrderID BIGINT NOT NULL,
    ReturnNumber VARCHAR(25) NOT NULL,
    OrderNumber VARCHAR(25) NOT NULL,
    RequestDateKey INT NOT NULL CONSTRAINT FK_FactReturns_RequestDate REFERENCES analytics.DimDate(DateKey),
    ApprovedDateKey INT NOT NULL CONSTRAINT FK_FactReturns_ApprovedDate REFERENCES analytics.DimDate(DateKey),
    ReceivedDateKey INT NOT NULL CONSTRAINT FK_FactReturns_ReceivedDate REFERENCES analytics.DimDate(DateKey),
    ClosedDateKey INT NOT NULL CONSTRAINT FK_FactReturns_ClosedDate REFERENCES analytics.DimDate(DateKey),
    CustomerKey INT NOT NULL CONSTRAINT FK_FactReturns_Customer REFERENCES analytics.DimCustomer(CustomerKey),
    ProductKey INT NOT NULL CONSTRAINT FK_FactReturns_Product REFERENCES analytics.DimProduct(ProductKey),
    StoreKey INT NOT NULL CONSTRAINT FK_FactReturns_Store REFERENCES analytics.DimStore(StoreKey),
    EmployeeKey INT NOT NULL CONSTRAINT FK_FactReturns_Employee REFERENCES analytics.DimEmployee(EmployeeKey),
    ReturnReasonKey SMALLINT NOT NULL CONSTRAINT FK_FactReturns_Reason REFERENCES analytics.DimReturnReason(ReturnReasonKey),
    ReturnStatusKey SMALLINT NOT NULL CONSTRAINT FK_FactReturns_Status REFERENCES analytics.DimReturnStatus(ReturnStatusKey),
    OrderStatusKey SMALLINT NOT NULL CONSTRAINT FK_FactReturns_OrderStatus REFERENCES analytics.DimOrderStatus(OrderStatusKey),
    QuantityRequested INT NOT NULL,
    QuantityAccepted INT NOT NULL,
    QuantityRejected INT NOT NULL,
    EligibleRefundAmount DECIMAL(14,2) NOT NULL,
    IsReusable BIT NOT NULL,
    IsAccepted BIT NOT NULL,
    ReturnLineCount TINYINT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_FactReturns_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
CREATE TABLE analytics.FactRefunds
(
    RefundFactKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactRefunds PRIMARY KEY,
    RefundID BIGINT NOT NULL CONSTRAINT UQ_FactRefunds_RefundID UNIQUE,
    ProductReturnID BIGINT NOT NULL,
    PaymentID BIGINT NOT NULL,
    SalesOrderID BIGINT NOT NULL,
    ReturnNumber VARCHAR(25) NOT NULL,
    OrderNumber VARCHAR(25) NOT NULL,
    RefundDateKey INT NOT NULL CONSTRAINT FK_FactRefunds_Date REFERENCES analytics.DimDate(DateKey),
    CustomerKey INT NOT NULL CONSTRAINT FK_FactRefunds_Customer REFERENCES analytics.DimCustomer(CustomerKey),
    StoreKey INT NOT NULL CONSTRAINT FK_FactRefunds_Store REFERENCES analytics.DimStore(StoreKey),
    PaymentMethodKey SMALLINT NOT NULL CONSTRAINT FK_FactRefunds_Method REFERENCES analytics.DimPaymentMethod(PaymentMethodKey),
    PaymentStatusKey SMALLINT NOT NULL CONSTRAINT FK_FactRefunds_PaymentStatus REFERENCES analytics.DimPaymentStatus(PaymentStatusKey),
    OrderStatusKey SMALLINT NOT NULL CONSTRAINT FK_FactRefunds_OrderStatus REFERENCES analytics.DimOrderStatus(OrderStatusKey),
    RefundAmount DECIMAL(14,2) NOT NULL,
    CompletedRefundAmount DECIMAL(14,2) NOT NULL,
    PendingRefundAmount DECIMAL(14,2) NOT NULL,
    FailedRefundAmount DECIMAL(14,2) NOT NULL,
    RefundStatus VARCHAR(20) NOT NULL,
    RefundCount TINYINT NOT NULL,
    RefundReference VARCHAR(100) NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_FactRefunds_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.FactInventoryMovement', N'U') IS NULL
CREATE TABLE analytics.FactInventoryMovement
(
    InventoryMovementFactKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactInventoryMovement PRIMARY KEY,
    InventoryMovementID BIGINT NOT NULL CONSTRAINT UQ_FactInventoryMovement_ID UNIQUE,
    MovementDateKey INT NOT NULL CONSTRAINT FK_FactInventoryMovement_Date REFERENCES analytics.DimDate(DateKey),
    ProductKey INT NOT NULL CONSTRAINT FK_FactInventoryMovement_Product REFERENCES analytics.DimProduct(ProductKey),
    StoreKey INT NOT NULL CONSTRAINT FK_FactInventoryMovement_Store REFERENCES analytics.DimStore(StoreKey),
    EmployeeKey INT NOT NULL CONSTRAINT FK_FactInventoryMovement_Employee REFERENCES analytics.DimEmployee(EmployeeKey),
    InventoryMovementTypeKey SMALLINT NOT NULL CONSTRAINT FK_FactInventoryMovement_Type REFERENCES analytics.DimInventoryMovementType(InventoryMovementTypeKey),
    SalesOrderItemID BIGINT NULL,
    ProductReturnItemID BIGINT NULL,
    ReferenceNumber VARCHAR(50) NOT NULL,
    Quantity INT NOT NULL,
    QuantityDirection SMALLINT NOT NULL,
    SignedQuantity INT NOT NULL,
    InflowQuantity INT NOT NULL,
    OutflowQuantity INT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_FactInventoryMovement_LoadDate DEFAULT (SYSDATETIME())
);

IF OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
CREATE TABLE analytics.FactInventorySnapshot
(
    InventorySnapshotFactKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactInventorySnapshot PRIMARY KEY,
    SnapshotDateKey INT NOT NULL CONSTRAINT FK_FactInventorySnapshot_Date REFERENCES analytics.DimDate(DateKey),
    ProductKey INT NOT NULL CONSTRAINT FK_FactInventorySnapshot_Product REFERENCES analytics.DimProduct(ProductKey),
    StoreKey INT NOT NULL CONSTRAINT FK_FactInventorySnapshot_Store REFERENCES analytics.DimStore(StoreKey),
    InventoryBalanceID BIGINT NOT NULL,
    QuantityOnHand INT NOT NULL,
    QuantityReserved INT NOT NULL,
    QuantityAvailable INT NOT NULL,
    UnitCost DECIMAL(12,2) NOT NULL,
    UnitRetailPrice DECIMAL(12,2) NOT NULL,
    StockCostValue DECIMAL(16,2) NOT NULL,
    StockRetailValue DECIMAL(16,2) NOT NULL,
    ReorderLevel INT NOT NULL,
    ExcessStockLevel INT NOT NULL,
    IsOutOfStock BIT NOT NULL,
    IsBelowReorderLevel BIT NOT NULL,
    IsExcessStock BIT NOT NULL,
    SnapshotRowCount TINYINT NOT NULL,
    LoadDate DATETIME2(0) NOT NULL CONSTRAINT DF_FactInventorySnapshot_LoadDate DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_FactInventorySnapshot_Grain UNIQUE (SnapshotDateKey, ProductKey, StoreKey)
);

-- ============================================================================
-- 2. REBUILD ALL FACT TABLES
-- ============================================================================

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE FROM analytics.FactInventorySnapshot;
    DELETE FROM analytics.FactInventoryMovement;
    DELETE FROM analytics.FactRefunds;
    DELETE FROM analytics.FactReturns;
    DELETE FROM analytics.FactPayments;
    DELETE FROM analytics.FactSales;

    DBCC CHECKIDENT ('analytics.FactSales', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.FactPayments', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.FactReturns', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.FactRefunds', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.FactInventoryMovement', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('analytics.FactInventorySnapshot', RESEED, 0) WITH NO_INFOMSGS;

    INSERT INTO analytics.FactSales
    (
        SalesOrderItemID, SalesOrderID, OrderNumber,
        OrderDateKey, ConfirmedDateKey, ShippedDateKey, DeliveredDateKey,
        CustomerKey, ProductKey, StoreKey, EmployeeKey, OrderStatusKey,
        Quantity, UnitCost, UnitPrice, GrossAmount, DiscountAmount, TaxAmount,
        NetAmount, CostAmount, GrossProfitAmount, RecognizedRevenueAmount,
        RecognizedCostAmount, RecognizedGrossProfitAmount,
        IsDelivered, IsCancelled, IsReturned, OrderCount, LineCount
    )
    SELECT
        item.SalesOrderItemID, orders.SalesOrderID, orders.OrderNumber,
        CONVERT(INT, CONVERT(CHAR(8), orders.OrderDate, 112)),
        COALESCE(CONVERT(INT, CONVERT(CHAR(8), orders.ConfirmedDate, 112)), 0),
        COALESCE(CONVERT(INT, CONVERT(CHAR(8), orders.ShippedDate, 112)), 0),
        COALESCE(CONVERT(INT, CONVERT(CHAR(8), orders.DeliveredDate, 112)), 0),
        customer.CustomerKey, product.ProductKey, store.StoreKey,
        employee.EmployeeKey, order_status.OrderStatusKey,
        item.Quantity, item.UnitCost, item.UnitPrice, item.GrossAmount,
        item.DiscountAmount, item.TaxAmount, item.NetAmount,
        CONVERT(DECIMAL(14,2), item.Quantity * item.UnitCost),
        CONVERT(DECIMAL(14,2), item.NetAmount - (item.Quantity * item.UnitCost)),
        CASE WHEN source_status.OrderStatusCode IN ('DELIVERED','PARTIALLY_RETURNED','RETURNED')
             THEN item.NetAmount ELSE 0 END,
        CASE WHEN source_status.OrderStatusCode IN ('DELIVERED','PARTIALLY_RETURNED','RETURNED')
             THEN CONVERT(DECIMAL(14,2), item.Quantity * item.UnitCost) ELSE 0 END,
        CASE WHEN source_status.OrderStatusCode IN ('DELIVERED','PARTIALLY_RETURNED','RETURNED')
             THEN CONVERT(DECIMAL(14,2), item.NetAmount - (item.Quantity * item.UnitCost)) ELSE 0 END,
        CASE WHEN source_status.OrderStatusCode IN ('DELIVERED','PARTIALLY_RETURNED','RETURNED') THEN 1 ELSE 0 END,
        CASE WHEN source_status.OrderStatusCode = 'CANCELLED' THEN 1 ELSE 0 END,
        CASE WHEN source_status.OrderStatusCode IN ('PARTIALLY_RETURNED','RETURNED') THEN 1 ELSE 0 END,
        CASE WHEN ROW_NUMBER() OVER (PARTITION BY orders.SalesOrderID ORDER BY item.SalesOrderItemID) = 1 THEN 1 ELSE 0 END,
        1
    FROM sales.SalesOrderItem AS item
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = item.SalesOrderID
    INNER JOIN ref.OrderStatus AS source_status ON source_status.OrderStatusID = orders.OrderStatusID
    INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerID = orders.CustomerID
    INNER JOIN analytics.DimProduct AS product ON product.ProductID = item.ProductID
    INNER JOIN analytics.DimStore AS store ON store.StoreID = orders.StoreID
    INNER JOIN analytics.DimEmployee AS employee ON employee.EmployeeID = orders.EmployeeID
    INNER JOIN analytics.DimOrderStatus AS order_status ON order_status.OrderStatusID = orders.OrderStatusID;

    INSERT INTO analytics.FactPayments
    (
        PaymentID, SalesOrderID, OrderNumber, PaymentDateKey, CustomerKey,
        StoreKey, PaymentMethodKey, PaymentStatusKey, OrderStatusKey,
        AttemptNumber, Amount, CollectedAmount, IsSuccessful, IsFailed,
        IsPending, AttemptCount, TransactionReference, FailureReason
    )
    SELECT
        payment.PaymentID, orders.SalesOrderID, orders.OrderNumber,
        CONVERT(INT, CONVERT(CHAR(8), payment.PaymentDate, 112)),
        customer.CustomerKey, store.StoreKey, method.PaymentMethodKey,
        payment_status.PaymentStatusKey, order_status.OrderStatusKey,
        payment.AttemptNumber, payment.Amount,
        CASE WHEN source_payment_status.PaymentStatusCode IN ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
             THEN payment.Amount ELSE 0 END,
        CASE WHEN source_payment_status.PaymentStatusCode IN ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED') THEN 1 ELSE 0 END,
        CASE WHEN source_payment_status.PaymentStatusCode = 'FAILED' THEN 1 ELSE 0 END,
        CASE WHEN source_payment_status.PaymentStatusCode IN ('INITIATED','PENDING') THEN 1 ELSE 0 END,
        1, COALESCE(payment.TransactionReference, 'Not Applicable'),
        COALESCE(payment.FailureReason, 'Not Applicable')
    FROM sales.Payment AS payment
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = payment.SalesOrderID
    INNER JOIN ref.PaymentStatus AS source_payment_status ON source_payment_status.PaymentStatusID = payment.PaymentStatusID
    INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerID = orders.CustomerID
    INNER JOIN analytics.DimStore AS store ON store.StoreID = orders.StoreID
    INNER JOIN analytics.DimPaymentMethod AS method ON method.PaymentMethodID = payment.PaymentMethodID
    INNER JOIN analytics.DimPaymentStatus AS payment_status ON payment_status.PaymentStatusID = payment.PaymentStatusID
    INNER JOIN analytics.DimOrderStatus AS order_status ON order_status.OrderStatusID = orders.OrderStatusID;

    INSERT INTO analytics.FactReturns
    (
        ProductReturnItemID, ProductReturnID, SalesOrderItemID, SalesOrderID,
        ReturnNumber, OrderNumber, RequestDateKey, ApprovedDateKey,
        ReceivedDateKey, ClosedDateKey, CustomerKey, ProductKey, StoreKey,
        EmployeeKey, ReturnReasonKey, ReturnStatusKey, OrderStatusKey,
        QuantityRequested, QuantityAccepted, QuantityRejected,
        EligibleRefundAmount, IsReusable, IsAccepted, ReturnLineCount
    )
    SELECT
        return_item.ProductReturnItemID, return_header.ProductReturnID,
        order_item.SalesOrderItemID, orders.SalesOrderID,
        return_header.ReturnNumber, orders.OrderNumber,
        CONVERT(INT, CONVERT(CHAR(8), return_header.RequestDate, 112)),
        COALESCE(CONVERT(INT, CONVERT(CHAR(8), return_header.ApprovedDate, 112)), 0),
        COALESCE(CONVERT(INT, CONVERT(CHAR(8), return_header.ReceivedDate, 112)), 0),
        COALESCE(CONVERT(INT, CONVERT(CHAR(8), return_header.ClosedDate, 112)), 0),
        customer.CustomerKey, product.ProductKey, store.StoreKey,
        employee.EmployeeKey, reason.ReturnReasonKey, return_status.ReturnStatusKey,
        order_status.OrderStatusKey, return_item.QuantityRequested,
        return_item.QuantityAccepted,
        return_item.QuantityRequested - return_item.QuantityAccepted,
        return_item.EligibleRefundAmount, COALESCE(return_item.IsReusable, 0),
        CASE WHEN return_item.QuantityAccepted > 0 THEN 1 ELSE 0 END, 1
    FROM sales.ProductReturnItem AS return_item
    INNER JOIN sales.ProductReturn AS return_header ON return_header.ProductReturnID = return_item.ProductReturnID
    INNER JOIN sales.SalesOrderItem AS order_item ON order_item.SalesOrderItemID = return_item.SalesOrderItemID
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = return_header.SalesOrderID
    INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerID = orders.CustomerID
    INNER JOIN analytics.DimProduct AS product ON product.ProductID = order_item.ProductID
    INNER JOIN analytics.DimStore AS store ON store.StoreID = orders.StoreID
    INNER JOIN analytics.DimEmployee AS employee ON employee.EmployeeID = orders.EmployeeID
    INNER JOIN analytics.DimReturnReason AS reason ON reason.ReturnReasonID = return_item.ReturnReasonID
    INNER JOIN analytics.DimReturnStatus AS return_status ON return_status.ReturnStatusID = return_header.ReturnStatusID
    INNER JOIN analytics.DimOrderStatus AS order_status ON order_status.OrderStatusID = orders.OrderStatusID;

    INSERT INTO analytics.FactRefunds
    (
        RefundID, ProductReturnID, PaymentID, SalesOrderID, ReturnNumber,
        OrderNumber, RefundDateKey, CustomerKey, StoreKey, PaymentMethodKey,
        PaymentStatusKey, OrderStatusKey, RefundAmount, CompletedRefundAmount,
        PendingRefundAmount, FailedRefundAmount, RefundStatus, RefundCount,
        RefundReference
    )
    SELECT
        refund.RefundID, return_header.ProductReturnID, payment.PaymentID,
        orders.SalesOrderID, return_header.ReturnNumber, orders.OrderNumber,
        CONVERT(INT, CONVERT(CHAR(8), refund.RefundDate, 112)),
        customer.CustomerKey, store.StoreKey, method.PaymentMethodKey,
        payment_status.PaymentStatusKey, order_status.OrderStatusKey,
        refund.RefundAmount,
        CASE WHEN refund.RefundStatus = 'Completed' THEN refund.RefundAmount ELSE 0 END,
        CASE WHEN refund.RefundStatus = 'Pending' THEN refund.RefundAmount ELSE 0 END,
        CASE WHEN refund.RefundStatus = 'Failed' THEN refund.RefundAmount ELSE 0 END,
        refund.RefundStatus, 1, COALESCE(refund.RefundReference, 'Unknown')
    FROM sales.Refund AS refund
    INNER JOIN sales.ProductReturn AS return_header ON return_header.ProductReturnID = refund.ProductReturnID
    INNER JOIN sales.Payment AS payment ON payment.PaymentID = refund.PaymentID
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = return_header.SalesOrderID
    INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerID = orders.CustomerID
    INNER JOIN analytics.DimStore AS store ON store.StoreID = orders.StoreID
    INNER JOIN analytics.DimPaymentMethod AS method ON method.PaymentMethodID = payment.PaymentMethodID
    INNER JOIN analytics.DimPaymentStatus AS payment_status ON payment_status.PaymentStatusID = payment.PaymentStatusID
    INNER JOIN analytics.DimOrderStatus AS order_status ON order_status.OrderStatusID = orders.OrderStatusID;

    INSERT INTO analytics.FactInventoryMovement
    (
        InventoryMovementID, MovementDateKey, ProductKey, StoreKey, EmployeeKey,
        InventoryMovementTypeKey, SalesOrderItemID, ProductReturnItemID,
        ReferenceNumber, Quantity, QuantityDirection, SignedQuantity,
        InflowQuantity, OutflowQuantity
    )
    SELECT
        movement.InventoryMovementID,
        CONVERT(INT, CONVERT(CHAR(8), movement.MovementDate, 112)),
        product.ProductKey, store.StoreKey, COALESCE(employee.EmployeeKey, 0),
        movement_type.InventoryMovementTypeKey, movement.SalesOrderItemID,
        movement.ProductReturnItemID, COALESCE(movement.ReferenceNumber, 'Unknown'),
        movement.Quantity, movement.QuantityDirection,
        movement.Quantity * movement.QuantityDirection,
        CASE WHEN movement.QuantityDirection = 1 THEN movement.Quantity ELSE 0 END,
        CASE WHEN movement.QuantityDirection = -1 THEN movement.Quantity ELSE 0 END
    FROM inventory.InventoryMovement AS movement
    INNER JOIN analytics.DimProduct AS product ON product.ProductID = movement.ProductID
    INNER JOIN analytics.DimStore AS store ON store.StoreID = movement.StoreID
    LEFT JOIN analytics.DimEmployee AS employee ON employee.EmployeeID = movement.CreatedByEmployeeID
    INNER JOIN analytics.DimInventoryMovementType AS movement_type
        ON movement_type.InventoryMovementTypeID = movement.InventoryMovementTypeID;

    INSERT INTO analytics.FactInventorySnapshot
    (
        SnapshotDateKey, ProductKey, StoreKey, InventoryBalanceID,
        QuantityOnHand, QuantityReserved, QuantityAvailable,
        UnitCost, UnitRetailPrice, StockCostValue, StockRetailValue,
        ReorderLevel, ExcessStockLevel, IsOutOfStock,
        IsBelowReorderLevel, IsExcessStock, SnapshotRowCount
    )
    SELECT
        20260630, product.ProductKey, store.StoreKey, balance.InventoryBalanceID,
        balance.QuantityOnHand, balance.QuantityReserved,
        balance.QuantityOnHand - balance.QuantityReserved,
        source_product.CostPrice, source_product.SellingPrice,
        CONVERT(DECIMAL(16,2), balance.QuantityOnHand * source_product.CostPrice),
        CONVERT(DECIMAL(16,2), balance.QuantityOnHand * source_product.SellingPrice),
        source_product.ReorderLevel, COALESCE(source_product.ExcessStockLevel, 0),
        CASE WHEN balance.QuantityOnHand = 0 THEN 1 ELSE 0 END,
        CASE WHEN balance.QuantityOnHand <= source_product.ReorderLevel THEN 1 ELSE 0 END,
        CASE WHEN source_product.ExcessStockLevel IS NOT NULL
                  AND balance.QuantityOnHand >= source_product.ExcessStockLevel THEN 1 ELSE 0 END,
        1
    FROM inventory.InventoryBalance AS balance
    INNER JOIN core.Product AS source_product ON source_product.ProductID = balance.ProductID
    INNER JOIN analytics.DimProduct AS product ON product.ProductID = balance.ProductID
    INNER JOIN analytics.DimStore AS store ON store.StoreID = balance.StoreID;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ============================================================================
-- 3. GRAIN, KEY-COVERAGE, AND FINANCIAL RECONCILIATION
-- ============================================================================

IF (SELECT COUNT_BIG(*) FROM analytics.FactSales) <> (SELECT COUNT_BIG(*) FROM sales.SalesOrderItem)
   OR (SELECT COUNT_BIG(*) FROM analytics.FactPayments) <> (SELECT COUNT_BIG(*) FROM sales.Payment)
   OR (SELECT COUNT_BIG(*) FROM analytics.FactReturns) <> (SELECT COUNT_BIG(*) FROM sales.ProductReturnItem)
   OR (SELECT COUNT_BIG(*) FROM analytics.FactRefunds) <> (SELECT COUNT_BIG(*) FROM sales.Refund)
   OR (SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement) <> (SELECT COUNT_BIG(*) FROM inventory.InventoryMovement)
   OR (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot) <> (SELECT COUNT_BIG(*) FROM inventory.InventoryBalance)
    THROW 51403, 'Fact validation failed: source-to-fact row-count mismatch.', 1;

IF EXISTS
(
    SELECT 1 FROM analytics.FactSales
    WHERE CustomerKey = 0 OR ProductKey = 0 OR StoreKey = 0
       OR EmployeeKey = 0 OR OrderStatusKey = 0 OR OrderDateKey = 0
)
OR EXISTS
(
    SELECT 1 FROM analytics.FactPayments
    WHERE CustomerKey = 0 OR StoreKey = 0 OR PaymentMethodKey = 0
       OR PaymentStatusKey = 0 OR OrderStatusKey = 0 OR PaymentDateKey = 0
)
OR EXISTS
(
    SELECT 1 FROM analytics.FactInventoryMovement
    WHERE ProductKey = 0 OR StoreKey = 0 OR InventoryMovementTypeKey = 0
       OR MovementDateKey = 0
)
    THROW 51404, 'Fact validation failed: an unresolved required dimension key exists.', 1;

DECLARE @SourceSalesValue DECIMAL(38,2) = (SELECT SUM(NetAmount) FROM sales.SalesOrderItem);
DECLARE @FactSalesValue DECIMAL(38,2) = (SELECT SUM(NetAmount) FROM analytics.FactSales);
DECLARE @SourcePaymentValue DECIMAL(38,2) = (SELECT SUM(Amount) FROM sales.Payment);
DECLARE @FactPaymentValue DECIMAL(38,2) = (SELECT SUM(Amount) FROM analytics.FactPayments);
DECLARE @SourceRefundValue DECIMAL(38,2) = (SELECT SUM(RefundAmount) FROM sales.Refund);
DECLARE @FactRefundValue DECIMAL(38,2) = (SELECT SUM(RefundAmount) FROM analytics.FactRefunds);
DECLARE @SourceSignedUnits BIGINT =
(
    SELECT SUM(CONVERT(BIGINT, Quantity) * QuantityDirection)
    FROM inventory.InventoryMovement
);
DECLARE @FactSignedUnits BIGINT = (SELECT SUM(CONVERT(BIGINT, SignedQuantity)) FROM analytics.FactInventoryMovement);

IF @SourceSalesValue <> @FactSalesValue
   OR @SourcePaymentValue <> @FactPaymentValue
   OR @SourceRefundValue <> @FactRefundValue
   OR @SourceSignedUnits <> @FactSignedUnits
    THROW 51405, 'Fact validation failed: financial or inventory reconciliation mismatch.', 1;

DECLARE @FactValidation TABLE
(
    FactName SYSNAME NOT NULL,
    DeclaredGrain VARCHAR(100) NOT NULL,
    SourceRowCount BIGINT NOT NULL,
    FactRowCount BIGINT NOT NULL
);

INSERT INTO @FactValidation VALUES
('FactSales', 'One row per sales-order item',
 (SELECT COUNT_BIG(*) FROM sales.SalesOrderItem), (SELECT COUNT_BIG(*) FROM analytics.FactSales)),
('FactPayments', 'One row per payment attempt',
 (SELECT COUNT_BIG(*) FROM sales.Payment), (SELECT COUNT_BIG(*) FROM analytics.FactPayments)),
('FactReturns', 'One row per returned order item',
 (SELECT COUNT_BIG(*) FROM sales.ProductReturnItem), (SELECT COUNT_BIG(*) FROM analytics.FactReturns)),
('FactRefunds', 'One row per refund event',
 (SELECT COUNT_BIG(*) FROM sales.Refund), (SELECT COUNT_BIG(*) FROM analytics.FactRefunds)),
('FactInventoryMovement', 'One row per inventory movement',
 (SELECT COUNT_BIG(*) FROM inventory.InventoryMovement), (SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement)),
('FactInventorySnapshot', 'One row per date-product-store snapshot',
 (SELECT COUNT_BIG(*) FROM inventory.InventoryBalance), (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot));

SELECT FactName, DeclaredGrain, SourceRowCount, FactRowCount,
       CASE WHEN SourceRowCount = FactRowCount THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM @FactValidation
ORDER BY CASE FactName WHEN 'FactSales' THEN 1 WHEN 'FactPayments' THEN 2
         WHEN 'FactReturns' THEN 3 WHEN 'FactRefunds' THEN 4
         WHEN 'FactInventoryMovement' THEN 5 ELSE 6 END;

SELECT
    @SourceSalesValue AS SourceSalesValue,
    @FactSalesValue AS FactSalesValue,
    @SourcePaymentValue AS SourcePaymentValue,
    @FactPaymentValue AS FactPaymentValue,
    @SourceRefundValue AS SourceRefundValue,
    @FactRefundValue AS FactRefundValue,
    @SourceSignedUnits AS SourceSignedInventoryUnits,
    @FactSignedUnits AS FactSignedInventoryUnits,
    'PASSED' AS ValidationStatus;

RAISERROR('23_Create_Analytics_Facts.sql completed successfully: six fact tables loaded and reconciled.', 10, 1) WITH NOWAIT;
GO
