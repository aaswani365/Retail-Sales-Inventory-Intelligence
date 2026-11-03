/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      06_Create_Operational_Views.sql
Purpose:     Create reusable grain-safe operational and reconciliation views.
Author:      Akshay Aswani
Version:     2.0
Depends on:  03_Create_Tables.sql, 04_Create_Constraints.sql
Rerunnable:  Yes. CREATE OR ALTER preserves permissions and replaces definitions.

View boundary
-------------
- These views expose operational detail and reconciliation controls.
- Final Power BI dimensions, facts and semantic views are created in scripts 40-49.
- Separate pre-aggregations prevent multiplication of order, payment and refund values.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @ExpectedDatabaseName SYSNAME = N'$(DatabaseName)';

IF DB_NAME() <> @ExpectedDatabaseName
BEGIN
    THROW 51050, 'View creation stopped: unexpected database context.', 1;
END;

IF @ExpectedDatabaseName <> N'RetailIntelligenceDB'
BEGIN
    THROW 51051, 'View creation stopped: the approved database name is RetailIntelligenceDB.', 1;
END;

IF OBJECT_ID(N'sales.SalesOrder', N'U') IS NULL
   OR OBJECT_ID(N'sales.SalesOrderItem', N'U') IS NULL
   OR OBJECT_ID(N'sales.Payment', N'U') IS NULL
   OR OBJECT_ID(N'sales.ProductReturn', N'U') IS NULL
   OR OBJECT_ID(N'inventory.InventoryBalance', N'U') IS NULL
   OR OBJECT_ID(N'inventory.InventoryMovement', N'U') IS NULL
BEGIN
    THROW 51052, 'View creation stopped: one or more required operational tables are missing.', 1;
END;
GO

-- Grain: one row per sales order.
CREATE OR ALTER VIEW sales.vw_OrderSummary
AS
WITH ItemTotals AS
(
    SELECT
        soi.SalesOrderID,
        COUNT_BIG(*) AS LineCount,
        SUM(CONVERT(BIGINT, soi.Quantity)) AS UnitCount,
        SUM(soi.GrossAmount) AS ItemGrossAmount,
        SUM(soi.DiscountAmount) AS ItemDiscountAmount,
        SUM(soi.TaxAmount) AS ItemTaxAmount,
        SUM(soi.NetAmount) AS ItemNetAmount,
        SUM(CONVERT(DECIMAL(19,2), soi.Quantity) * soi.UnitCost) AS ItemCostAmount
    FROM sales.SalesOrderItem AS soi
    GROUP BY soi.SalesOrderID
),
PaymentTotals AS
(
    SELECT
        p.SalesOrderID,
        COUNT_BIG(*) AS PaymentAttemptCount,
        SUM(CASE WHEN ps.PaymentStatusCode = 'COMPLETED' THEN p.Amount ELSE CONVERT(DECIMAL(14,2), 0) END) AS CompletedPaymentAmount
    FROM sales.Payment AS p
    INNER JOIN ref.PaymentStatus AS ps
        ON ps.PaymentStatusID = p.PaymentStatusID
    GROUP BY p.SalesOrderID
),
ReturnTotals AS
(
    SELECT
        pr.SalesOrderID,
        COUNT_BIG(DISTINCT pr.ProductReturnID) AS ReturnRequestCount,
        SUM(CONVERT(BIGINT, pri.QuantityAccepted)) AS AcceptedReturnUnitCount,
        SUM(pri.EligibleRefundAmount) AS EligibleRefundAmount
    FROM sales.ProductReturn AS pr
    INNER JOIN sales.ProductReturnItem AS pri
        ON pri.ProductReturnID = pr.ProductReturnID
    GROUP BY pr.SalesOrderID
),
RefundTotals AS
(
    SELECT
        pr.SalesOrderID,
        SUM(CASE WHEN UPPER(r.RefundStatus) = 'COMPLETED' THEN r.RefundAmount ELSE CONVERT(DECIMAL(14,2), 0) END) AS CompletedRefundAmount
    FROM sales.Refund AS r
    INNER JOIN sales.ProductReturn AS pr
        ON pr.ProductReturnID = r.ProductReturnID
    GROUP BY pr.SalesOrderID
)
SELECT
    so.SalesOrderID,
    so.OrderNumber,
    so.OrderDate,
    CONVERT(DATE, so.OrderDate) AS OrderCalendarDate,
    so.ConfirmedDate,
    so.ShippedDate,
    so.DeliveredDate,
    so.CancelledDate,
    so.CustomerID,
    c.CustomerCode,
    CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
    COALESCE(c.City, 'Unknown') AS CustomerCity,
    COALESCE(c.State, 'Unknown') AS CustomerState,
    so.StoreID,
    s.StoreCode,
    s.StoreName,
    s.City AS StoreCity,
    s.State AS StoreState,
    so.EmployeeID,
    e.EmployeeCode,
    CONCAT(e.FirstName, ' ', e.LastName) AS EmployeeName,
    os.OrderStatusCode,
    os.OrderStatusName,
    COALESCE(it.LineCount, 0) AS LineCount,
    COALESCE(it.UnitCount, 0) AS UnitCount,
    so.SubtotalAmount,
    so.DiscountAmount,
    so.TaxAmount,
    so.NetAmount,
    COALESCE(it.ItemCostAmount, 0) AS ItemCostAmount,
    so.NetAmount - so.TaxAmount - COALESCE(it.ItemCostAmount, 0) AS GrossProfitBeforeRefund,
    COALESCE(pt.PaymentAttemptCount, 0) AS PaymentAttemptCount,
    COALESCE(pt.CompletedPaymentAmount, 0) AS CompletedPaymentAmount,
    COALESCE(rt.ReturnRequestCount, 0) AS ReturnRequestCount,
    COALESCE(rt.AcceptedReturnUnitCount, 0) AS AcceptedReturnUnitCount,
    COALESCE(rt.EligibleRefundAmount, 0) AS EligibleRefundAmount,
    COALESCE(rft.CompletedRefundAmount, 0) AS CompletedRefundAmount,
    COALESCE(pt.CompletedPaymentAmount, 0) - COALESCE(rft.CompletedRefundAmount, 0) AS NetCollectedAmount,
    so.NetAmount - COALESCE(it.ItemNetAmount, 0) AS HeaderItemNetVariance,
    so.CreatedDate,
    so.ModifiedDate
FROM sales.SalesOrder AS so
INNER JOIN core.Customer AS c
    ON c.CustomerID = so.CustomerID
INNER JOIN core.Store AS s
    ON s.StoreID = so.StoreID
INNER JOIN core.Employee AS e
    ON e.EmployeeID = so.EmployeeID
INNER JOIN ref.OrderStatus AS os
    ON os.OrderStatusID = so.OrderStatusID
LEFT JOIN ItemTotals AS it
    ON it.SalesOrderID = so.SalesOrderID
LEFT JOIN PaymentTotals AS pt
    ON pt.SalesOrderID = so.SalesOrderID
LEFT JOIN ReturnTotals AS rt
    ON rt.SalesOrderID = so.SalesOrderID
LEFT JOIN RefundTotals AS rft
    ON rft.SalesOrderID = so.SalesOrderID;
GO

-- Grain: one row per sales-order item.
CREATE OR ALTER VIEW sales.vw_OrderLineDetail
AS
SELECT
    soi.SalesOrderItemID,
    soi.SalesOrderID,
    so.OrderNumber,
    so.OrderDate,
    CONVERT(DATE, so.OrderDate) AS OrderCalendarDate,
    so.DeliveredDate,
    os.OrderStatusCode,
    os.OrderStatusName,
    so.CustomerID,
    so.StoreID,
    s.StoreCode,
    s.StoreName,
    so.EmployeeID,
    soi.ProductID,
    p.SKU,
    p.ProductName,
    sc.SubCategoryID,
    sc.SubCategoryCode,
    sc.SubCategoryName,
    c.CategoryID,
    c.CategoryCode,
    c.CategoryName,
    b.BrandID,
    b.BrandCode,
    b.BrandName,
    p.SupplierID,
    sup.SupplierCode,
    sup.SupplierName,
    soi.Quantity,
    soi.UnitCost,
    soi.UnitPrice,
    soi.GrossAmount,
    soi.DiscountAmount,
    soi.TaxRate,
    soi.TaxAmount,
    soi.NetAmount,
    CONVERT(DECIMAL(19,2), soi.Quantity) * soi.UnitCost AS CostAmount,
    soi.NetAmount - soi.TaxAmount - (CONVERT(DECIMAL(19,2), soi.Quantity) * soi.UnitCost) AS GrossProfitAmount,
    soi.CreatedDate,
    soi.ModifiedDate
FROM sales.SalesOrderItem AS soi
INNER JOIN sales.SalesOrder AS so
    ON so.SalesOrderID = soi.SalesOrderID
INNER JOIN ref.OrderStatus AS os
    ON os.OrderStatusID = so.OrderStatusID
INNER JOIN core.Store AS s
    ON s.StoreID = so.StoreID
INNER JOIN core.Product AS p
    ON p.ProductID = soi.ProductID
INNER JOIN ref.SubCategory AS sc
    ON sc.SubCategoryID = p.SubCategoryID
INNER JOIN ref.Category AS c
    ON c.CategoryID = sc.CategoryID
INNER JOIN ref.Brand AS b
    ON b.BrandID = p.BrandID
INNER JOIN core.Supplier AS sup
    ON sup.SupplierID = p.SupplierID;
GO

-- Grain: one row per payment attempt.
CREATE OR ALTER VIEW sales.vw_PaymentDetail
AS
SELECT
    p.PaymentID,
    p.SalesOrderID,
    so.OrderNumber,
    so.OrderDate,
    so.CustomerID,
    so.StoreID,
    p.AttemptNumber,
    p.PaymentDate,
    CONVERT(DATE, p.PaymentDate) AS PaymentCalendarDate,
    p.PaymentMethodID,
    pm.PaymentMethodCode,
    pm.PaymentMethodName,
    p.PaymentStatusID,
    ps.PaymentStatusCode,
    ps.PaymentStatusName,
    p.Amount,
    p.TransactionReference,
    p.FailureReason,
    p.Remarks,
    CASE WHEN ps.PaymentStatusCode = 'COMPLETED' THEN p.Amount ELSE CONVERT(DECIMAL(14,2), 0) END AS CompletedPaymentAmount,
    p.CreatedDate,
    p.ModifiedDate
FROM sales.Payment AS p
INNER JOIN sales.SalesOrder AS so
    ON so.SalesOrderID = p.SalesOrderID
INNER JOIN ref.PaymentMethod AS pm
    ON pm.PaymentMethodID = p.PaymentMethodID
INNER JOIN ref.PaymentStatus AS ps
    ON ps.PaymentStatusID = p.PaymentStatusID;
GO

-- Grain: one row per returned order item.
CREATE OR ALTER VIEW sales.vw_ReturnDetail
AS
WITH RefundByReturn AS
(
    SELECT
        r.ProductReturnID,
        SUM(CASE WHEN UPPER(r.RefundStatus) = 'COMPLETED' THEN r.RefundAmount ELSE CONVERT(DECIMAL(14,2), 0) END) AS CompletedRefundAmount
    FROM sales.Refund AS r
    GROUP BY r.ProductReturnID
)
SELECT
    pri.ProductReturnItemID,
    pr.ProductReturnID,
    pr.ReturnNumber,
    pr.SalesOrderID,
    so.OrderNumber,
    pr.ReturnStatusID,
    rs.ReturnStatusCode,
    rs.ReturnStatusName,
    pr.RequestDate,
    CONVERT(DATE, pr.RequestDate) AS RequestCalendarDate,
    pr.ApprovedDate,
    pr.ReceivedDate,
    pr.ClosedDate,
    pri.SalesOrderItemID,
    soi.ProductID,
    p.SKU,
    p.ProductName,
    rr.ReturnReasonID,
    rr.ReturnReasonCode,
    rr.ReturnReasonName,
    pri.QuantityRequested,
    pri.QuantityAccepted,
    pri.EligibleRefundAmount,
    pri.IsReusable,
    pri.InspectionNotes,
    COALESCE(rbr.CompletedRefundAmount, 0) AS ReturnLevelCompletedRefundAmount,
    pr.CreatedDate,
    pr.ModifiedDate
FROM sales.ProductReturnItem AS pri
INNER JOIN sales.ProductReturn AS pr
    ON pr.ProductReturnID = pri.ProductReturnID
INNER JOIN sales.SalesOrder AS so
    ON so.SalesOrderID = pr.SalesOrderID
INNER JOIN ref.ReturnStatus AS rs
    ON rs.ReturnStatusID = pr.ReturnStatusID
INNER JOIN sales.SalesOrderItem AS soi
    ON soi.SalesOrderItemID = pri.SalesOrderItemID
INNER JOIN core.Product AS p
    ON p.ProductID = soi.ProductID
INNER JOIN ref.ReturnReason AS rr
    ON rr.ReturnReasonID = pri.ReturnReasonID
LEFT JOIN RefundByReturn AS rbr
    ON rbr.ProductReturnID = pr.ProductReturnID;
GO

-- Grain: one row per product-store current inventory balance.
CREATE OR ALTER VIEW inventory.vw_CurrentInventory
AS
SELECT
    ib.InventoryBalanceID,
    ib.ProductID,
    p.SKU,
    p.ProductName,
    p.SubCategoryID,
    sc.SubCategoryName,
    sc.CategoryID,
    c.CategoryName,
    p.BrandID,
    b.BrandName,
    p.SupplierID,
    sup.SupplierName,
    ib.StoreID,
    s.StoreCode,
    s.StoreName,
    s.City AS StoreCity,
    s.State AS StoreState,
    ib.QuantityOnHand,
    ib.QuantityReserved,
    ib.QuantityOnHand - ib.QuantityReserved AS QuantityAvailable,
    p.ReorderLevel,
    p.ExcessStockLevel,
    CASE
        WHEN ib.QuantityOnHand - ib.QuantityReserved <= 0 THEN 'Out of Stock'
        WHEN ib.QuantityOnHand - ib.QuantityReserved <= p.ReorderLevel THEN 'Low Stock'
        WHEN p.ExcessStockLevel IS NOT NULL
         AND ib.QuantityOnHand - ib.QuantityReserved >= p.ExcessStockLevel THEN 'Excess Stock'
        ELSE 'Healthy'
    END AS StockStatus,
    CONVERT(DECIMAL(19,2), ib.QuantityOnHand) * p.CostPrice AS InventoryCostValue,
    CONVERT(DECIMAL(19,2), ib.QuantityOnHand) * p.SellingPrice AS InventoryRetailValue,
    ib.LastMovementDate,
    ib.LastRestockedDate,
    ib.CreatedDate,
    ib.ModifiedDate
FROM inventory.InventoryBalance AS ib
INNER JOIN core.Product AS p
    ON p.ProductID = ib.ProductID
INNER JOIN ref.SubCategory AS sc
    ON sc.SubCategoryID = p.SubCategoryID
INNER JOIN ref.Category AS c
    ON c.CategoryID = sc.CategoryID
INNER JOIN ref.Brand AS b
    ON b.BrandID = p.BrandID
INNER JOIN core.Supplier AS sup
    ON sup.SupplierID = p.SupplierID
INNER JOIN core.Store AS s
    ON s.StoreID = ib.StoreID;
GO

-- Grain: one row per immutable inventory movement.
CREATE OR ALTER VIEW inventory.vw_InventoryMovementDetail
AS
SELECT
    im.InventoryMovementID,
    im.MovementDate,
    CONVERT(DATE, im.MovementDate) AS MovementCalendarDate,
    im.ProductID,
    p.SKU,
    p.ProductName,
    im.StoreID,
    s.StoreCode,
    s.StoreName,
    im.InventoryMovementTypeID,
    imt.InventoryMovementTypeCode,
    imt.InventoryMovementTypeName,
    im.Quantity,
    im.QuantityDirection,
    CONVERT(BIGINT, im.Quantity) * im.QuantityDirection AS SignedQuantity,
    im.SalesOrderItemID,
    im.ProductReturnItemID,
    im.ReferenceNumber,
    im.Reason,
    im.CreatedByEmployeeID,
    CASE
        WHEN im.CreatedByEmployeeID IS NULL THEN NULL
        ELSE CONCAT(e.FirstName, ' ', e.LastName)
    END AS CreatedByEmployeeName,
    im.CreatedDate
FROM inventory.InventoryMovement AS im
INNER JOIN core.Product AS p
    ON p.ProductID = im.ProductID
INNER JOIN core.Store AS s
    ON s.StoreID = im.StoreID
INNER JOIN ref.InventoryMovementType AS imt
    ON imt.InventoryMovementTypeID = im.InventoryMovementTypeID
LEFT JOIN core.Employee AS e
    ON e.EmployeeID = im.CreatedByEmployeeID;
GO

-- Grain: one row per sales order; expected variances are within +/- 0.01.
CREATE OR ALTER VIEW audit.vw_OrderFinancialReconciliation
AS
WITH ItemTotals AS
(
    SELECT
        SalesOrderID,
        SUM(GrossAmount) AS ItemGrossAmount,
        SUM(DiscountAmount) AS ItemDiscountAmount,
        SUM(TaxAmount) AS ItemTaxAmount,
        SUM(NetAmount) AS ItemNetAmount
    FROM sales.SalesOrderItem
    GROUP BY SalesOrderID
)
SELECT
    so.SalesOrderID,
    so.OrderNumber,
    so.OrderDate,
    so.SubtotalAmount AS HeaderSubtotalAmount,
    COALESCE(it.ItemGrossAmount, 0) AS ItemGrossAmount,
    so.DiscountAmount AS HeaderDiscountAmount,
    COALESCE(it.ItemDiscountAmount, 0) AS ItemDiscountAmount,
    so.TaxAmount AS HeaderTaxAmount,
    COALESCE(it.ItemTaxAmount, 0) AS ItemTaxAmount,
    so.NetAmount AS HeaderNetAmount,
    COALESCE(it.ItemNetAmount, 0) AS ItemNetAmount,
    so.SubtotalAmount - COALESCE(it.ItemGrossAmount, 0) AS SubtotalVariance,
    so.DiscountAmount - COALESCE(it.ItemDiscountAmount, 0) AS DiscountVariance,
    so.TaxAmount - COALESCE(it.ItemTaxAmount, 0) AS TaxVariance,
    so.NetAmount - COALESCE(it.ItemNetAmount, 0) AS NetVariance,
    CASE
        WHEN ABS(so.SubtotalAmount - COALESCE(it.ItemGrossAmount, 0)) <= 0.01
         AND ABS(so.DiscountAmount - COALESCE(it.ItemDiscountAmount, 0)) <= 0.01
         AND ABS(so.TaxAmount - COALESCE(it.ItemTaxAmount, 0)) <= 0.01
         AND ABS(so.NetAmount - COALESCE(it.ItemNetAmount, 0)) <= 0.01
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ReconciliationStatus
FROM sales.SalesOrder AS so
LEFT JOIN ItemTotals AS it
    ON it.SalesOrderID = so.SalesOrderID;
GO

-- Grain: one row per product-store balance; signed movement total should equal on-hand quantity.
CREATE OR ALTER VIEW audit.vw_InventoryBalanceReconciliation
AS
WITH MovementTotals AS
(
    SELECT
        ProductID,
        StoreID,
        SUM(CONVERT(BIGINT, Quantity) * QuantityDirection) AS MovementQuantity
    FROM inventory.InventoryMovement
    GROUP BY ProductID, StoreID
)
SELECT
    ib.InventoryBalanceID,
    ib.ProductID,
    p.SKU,
    ib.StoreID,
    s.StoreCode,
    ib.QuantityOnHand,
    COALESCE(mt.MovementQuantity, 0) AS MovementQuantity,
    CONVERT(BIGINT, ib.QuantityOnHand) - COALESCE(mt.MovementQuantity, 0) AS QuantityVariance,
    CASE
        WHEN CONVERT(BIGINT, ib.QuantityOnHand) = COALESCE(mt.MovementQuantity, 0) THEN 'PASSED'
        ELSE 'FAILED'
    END AS ReconciliationStatus,
    ib.LastMovementDate
FROM inventory.InventoryBalance AS ib
INNER JOIN core.Product AS p
    ON p.ProductID = ib.ProductID
INNER JOIN core.Store AS s
    ON s.StoreID = ib.StoreID
LEFT JOIN MovementTotals AS mt
    ON mt.ProductID = ib.ProductID
   AND mt.StoreID = ib.StoreID;
GO

DECLARE @ExpectedViews TABLE
(
    ViewSequence TINYINT NOT NULL PRIMARY KEY,
    SchemaName SYSNAME NOT NULL,
    ViewName SYSNAME NOT NULL,
    ExpectedGrain VARCHAR(100) NOT NULL
);

INSERT INTO @ExpectedViews VALUES
(1, N'sales', N'vw_OrderSummary', 'One row per sales order'),
(2, N'sales', N'vw_OrderLineDetail', 'One row per sales-order item'),
(3, N'sales', N'vw_PaymentDetail', 'One row per payment attempt'),
(4, N'sales', N'vw_ReturnDetail', 'One row per returned order item'),
(5, N'inventory', N'vw_CurrentInventory', 'One row per product-store balance'),
(6, N'inventory', N'vw_InventoryMovementDetail', 'One row per inventory movement'),
(7, N'audit', N'vw_OrderFinancialReconciliation', 'One row per sales order'),
(8, N'audit', N'vw_InventoryBalanceReconciliation', 'One row per product-store balance');

IF EXISTS
(
    SELECT 1
    FROM @ExpectedViews AS ev
    WHERE OBJECT_ID(QUOTENAME(ev.SchemaName) + N'.' + QUOTENAME(ev.ViewName), N'V') IS NULL
)
BEGIN
    THROW 51053, 'View validation failed: one or more approved views are missing.', 1;
END;

SELECT
    ev.ViewSequence,
    ev.SchemaName,
    ev.ViewName,
    ev.ExpectedGrain,
    COUNT(c.column_id) AS ColumnCount,
    CASE
        WHEN OBJECT_ID(QUOTENAME(ev.SchemaName) + N'.' + QUOTENAME(ev.ViewName), N'V') IS NOT NULL
         AND COUNT(c.column_id) > 0
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM @ExpectedViews AS ev
LEFT JOIN sys.columns AS c
    ON c.object_id = OBJECT_ID(QUOTENAME(ev.SchemaName) + N'.' + QUOTENAME(ev.ViewName), N'V')
GROUP BY ev.ViewSequence, ev.SchemaName, ev.ViewName, ev.ExpectedGrain
ORDER BY ev.ViewSequence;

RAISERROR('06_Create_Operational_Views.sql completed successfully: 8 approved views validated.', 10, 1) WITH NOWAIT;
GO
