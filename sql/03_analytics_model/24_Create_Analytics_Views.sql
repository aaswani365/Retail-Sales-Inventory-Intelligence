/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      24_Create_Analytics_Views.sql
Purpose:     Publish governed analytical detail and SQL control-total views.
Author:      Akshay Aswani
Version:     2.0
Depends on:  23_Create_Analytics_Facts.sql
Rerunnable:  Yes, through CREATE OR ALTER VIEW.

Power BI guidance
-----------------
- Import dimension and fact tables for the primary semantic model.
- Use these views for SQL exploration, drill-through extracts and reconciliation.
- Do not relate flattened detail views back to their underlying facts.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51420, 'Analytics-view build stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactPayments', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventoryMovement', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
    THROW 51421, 'Analytics-view build stopped: one or more fact tables are missing.', 1;
GO

CREATE OR ALTER VIEW analytics.vw_SalesDetail
AS
SELECT
    sales.SalesFactKey,
    sales.SalesOrderItemID,
    sales.SalesOrderID,
    sales.OrderNumber,
    order_date.[Date] AS OrderDate,
    order_date.DayName AS OrderDayName,
    order_date.MonthYearLabel,
    order_date.YearMonthNumber,
    order_date.CalendarQuarterLabel,
    order_date.CalendarYear,
    order_date.FinancialQuarterLabel,
    order_date.FinancialYearLabel,
    delivered_date.[Date] AS DeliveredDate,
    customer.CustomerCode,
    customer.CustomerName,
    customer.CustomerSegment,
    customer.City AS CustomerCity,
    customer.StateName AS CustomerState,
    product.SKU,
    product.ProductName,
    product.BrandName,
    product.SubCategoryName,
    product.CategoryName,
    product.SupplierName,
    product.PriceBand,
    store.StoreCode,
    store.StoreName,
    store.StoreTier,
    store.City AS StoreCity,
    store.StateName AS StoreState,
    employee.EmployeeCode,
    employee.EmployeeName,
    employee.JobTitle,
    order_status.OrderStatusCode,
    order_status.OrderStatusName,
    sales.Quantity,
    sales.UnitCost,
    sales.UnitPrice,
    sales.GrossAmount,
    sales.DiscountAmount,
    sales.TaxAmount,
    sales.NetAmount,
    sales.CostAmount,
    sales.GrossProfitAmount,
    sales.RecognizedRevenueAmount,
    sales.RecognizedCostAmount,
    sales.RecognizedGrossProfitAmount,
    sales.IsDelivered,
    sales.IsCancelled,
    sales.IsReturned,
    sales.OrderCount,
    sales.LineCount
FROM analytics.FactSales AS sales
INNER JOIN analytics.DimDate AS order_date ON order_date.DateKey = sales.OrderDateKey
INNER JOIN analytics.DimDate AS delivered_date ON delivered_date.DateKey = sales.DeliveredDateKey
INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerKey = sales.CustomerKey
INNER JOIN analytics.DimProduct AS product ON product.ProductKey = sales.ProductKey
INNER JOIN analytics.DimStore AS store ON store.StoreKey = sales.StoreKey
INNER JOIN analytics.DimEmployee AS employee ON employee.EmployeeKey = sales.EmployeeKey
INNER JOIN analytics.DimOrderStatus AS order_status ON order_status.OrderStatusKey = sales.OrderStatusKey;
GO

CREATE OR ALTER VIEW analytics.vw_PaymentDetail
AS
SELECT
    payment.PaymentFactKey,
    payment.PaymentID,
    payment.SalesOrderID,
    payment.OrderNumber,
    payment_date.[Date] AS PaymentDate,
    payment_date.MonthYearLabel,
    payment_date.YearMonthNumber,
    payment_date.FinancialQuarterLabel,
    payment_date.FinancialYearLabel,
    customer.CustomerCode,
    customer.CustomerName,
    customer.CustomerSegment,
    store.StoreCode,
    store.StoreName,
    store.StoreTier,
    store.City AS StoreCity,
    method.PaymentMethodCode,
    method.PaymentMethodName,
    payment_status.PaymentStatusCode,
    payment_status.PaymentStatusName,
    order_status.OrderStatusCode,
    payment.AttemptNumber,
    payment.Amount,
    payment.CollectedAmount,
    payment.IsSuccessful,
    payment.IsFailed,
    payment.IsPending,
    payment.AttemptCount,
    payment.TransactionReference,
    payment.FailureReason
FROM analytics.FactPayments AS payment
INNER JOIN analytics.DimDate AS payment_date ON payment_date.DateKey = payment.PaymentDateKey
INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerKey = payment.CustomerKey
INNER JOIN analytics.DimStore AS store ON store.StoreKey = payment.StoreKey
INNER JOIN analytics.DimPaymentMethod AS method ON method.PaymentMethodKey = payment.PaymentMethodKey
INNER JOIN analytics.DimPaymentStatus AS payment_status ON payment_status.PaymentStatusKey = payment.PaymentStatusKey
INNER JOIN analytics.DimOrderStatus AS order_status ON order_status.OrderStatusKey = payment.OrderStatusKey;
GO

CREATE OR ALTER VIEW analytics.vw_ReturnDetail
AS
SELECT
    returns.ReturnFactKey,
    returns.ProductReturnItemID,
    returns.ProductReturnID,
    returns.SalesOrderItemID,
    returns.SalesOrderID,
    returns.ReturnNumber,
    returns.OrderNumber,
    request_date.[Date] AS RequestDate,
    request_date.MonthYearLabel,
    request_date.YearMonthNumber,
    request_date.FinancialYearLabel,
    approved_date.[Date] AS ApprovedDate,
    received_date.[Date] AS ReceivedDate,
    closed_date.[Date] AS ClosedDate,
    customer.CustomerCode,
    customer.CustomerName,
    customer.CustomerSegment,
    product.SKU,
    product.ProductName,
    product.BrandName,
    product.SubCategoryName,
    product.CategoryName,
    store.StoreCode,
    store.StoreName,
    store.StoreTier,
    employee.EmployeeCode,
    employee.EmployeeName,
    reason.ReturnReasonCode,
    reason.ReturnReasonName,
    return_status.ReturnStatusCode,
    return_status.ReturnStatusName,
    order_status.OrderStatusCode,
    returns.QuantityRequested,
    returns.QuantityAccepted,
    returns.QuantityRejected,
    returns.EligibleRefundAmount,
    returns.IsReusable,
    returns.IsAccepted,
    returns.ReturnLineCount
FROM analytics.FactReturns AS returns
INNER JOIN analytics.DimDate AS request_date ON request_date.DateKey = returns.RequestDateKey
INNER JOIN analytics.DimDate AS approved_date ON approved_date.DateKey = returns.ApprovedDateKey
INNER JOIN analytics.DimDate AS received_date ON received_date.DateKey = returns.ReceivedDateKey
INNER JOIN analytics.DimDate AS closed_date ON closed_date.DateKey = returns.ClosedDateKey
INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerKey = returns.CustomerKey
INNER JOIN analytics.DimProduct AS product ON product.ProductKey = returns.ProductKey
INNER JOIN analytics.DimStore AS store ON store.StoreKey = returns.StoreKey
INNER JOIN analytics.DimEmployee AS employee ON employee.EmployeeKey = returns.EmployeeKey
INNER JOIN analytics.DimReturnReason AS reason ON reason.ReturnReasonKey = returns.ReturnReasonKey
INNER JOIN analytics.DimReturnStatus AS return_status ON return_status.ReturnStatusKey = returns.ReturnStatusKey
INNER JOIN analytics.DimOrderStatus AS order_status ON order_status.OrderStatusKey = returns.OrderStatusKey;
GO

CREATE OR ALTER VIEW analytics.vw_RefundDetail
AS
SELECT
    refund.RefundFactKey,
    refund.RefundID,
    refund.ProductReturnID,
    refund.PaymentID,
    refund.SalesOrderID,
    refund.ReturnNumber,
    refund.OrderNumber,
    refund_date.[Date] AS RefundDate,
    refund_date.MonthYearLabel,
    refund_date.YearMonthNumber,
    refund_date.FinancialYearLabel,
    customer.CustomerCode,
    customer.CustomerName,
    customer.CustomerSegment,
    store.StoreCode,
    store.StoreName,
    store.StoreTier,
    method.PaymentMethodCode,
    method.PaymentMethodName,
    payment_status.PaymentStatusCode,
    order_status.OrderStatusCode,
    refund.RefundAmount,
    refund.CompletedRefundAmount,
    refund.PendingRefundAmount,
    refund.FailedRefundAmount,
    refund.RefundStatus,
    refund.RefundCount,
    refund.RefundReference
FROM analytics.FactRefunds AS refund
INNER JOIN analytics.DimDate AS refund_date ON refund_date.DateKey = refund.RefundDateKey
INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerKey = refund.CustomerKey
INNER JOIN analytics.DimStore AS store ON store.StoreKey = refund.StoreKey
INNER JOIN analytics.DimPaymentMethod AS method ON method.PaymentMethodKey = refund.PaymentMethodKey
INNER JOIN analytics.DimPaymentStatus AS payment_status ON payment_status.PaymentStatusKey = refund.PaymentStatusKey
INNER JOIN analytics.DimOrderStatus AS order_status ON order_status.OrderStatusKey = refund.OrderStatusKey;
GO

CREATE OR ALTER VIEW analytics.vw_InventoryMovementDetail
AS
SELECT
    movement.InventoryMovementFactKey,
    movement.InventoryMovementID,
    movement_date.[Date] AS MovementDate,
    movement_date.MonthYearLabel,
    movement_date.YearMonthNumber,
    movement_date.FinancialQuarterLabel,
    movement_date.FinancialYearLabel,
    product.SKU,
    product.ProductName,
    product.BrandName,
    product.SubCategoryName,
    product.CategoryName,
    product.SupplierName,
    store.StoreCode,
    store.StoreName,
    store.StoreTier,
    store.City AS StoreCity,
    employee.EmployeeCode,
    employee.EmployeeName,
    movement_type.InventoryMovementTypeCode,
    movement_type.InventoryMovementTypeName,
    movement.SalesOrderItemID,
    movement.ProductReturnItemID,
    movement.ReferenceNumber,
    movement.Quantity,
    movement.QuantityDirection,
    movement.SignedQuantity,
    movement.InflowQuantity,
    movement.OutflowQuantity
FROM analytics.FactInventoryMovement AS movement
INNER JOIN analytics.DimDate AS movement_date ON movement_date.DateKey = movement.MovementDateKey
INNER JOIN analytics.DimProduct AS product ON product.ProductKey = movement.ProductKey
INNER JOIN analytics.DimStore AS store ON store.StoreKey = movement.StoreKey
INNER JOIN analytics.DimEmployee AS employee ON employee.EmployeeKey = movement.EmployeeKey
INNER JOIN analytics.DimInventoryMovementType AS movement_type
    ON movement_type.InventoryMovementTypeKey = movement.InventoryMovementTypeKey;
GO

CREATE OR ALTER VIEW analytics.vw_CurrentInventory
AS
SELECT
    snapshot.InventorySnapshotFactKey,
    snapshot_date.[Date] AS SnapshotDate,
    product.SKU,
    product.ProductName,
    product.BrandName,
    product.SubCategoryName,
    product.CategoryName,
    product.SupplierName,
    product.PriceBand,
    store.StoreCode,
    store.StoreName,
    store.StoreTier,
    store.City AS StoreCity,
    store.StateName AS StoreState,
    snapshot.InventoryBalanceID,
    snapshot.QuantityOnHand,
    snapshot.QuantityReserved,
    snapshot.QuantityAvailable,
    snapshot.UnitCost,
    snapshot.UnitRetailPrice,
    snapshot.StockCostValue,
    snapshot.StockRetailValue,
    snapshot.ReorderLevel,
    snapshot.ExcessStockLevel,
    snapshot.IsOutOfStock,
    snapshot.IsBelowReorderLevel,
    snapshot.IsExcessStock,
    snapshot.SnapshotRowCount
FROM analytics.FactInventorySnapshot AS snapshot
INNER JOIN analytics.DimDate AS snapshot_date ON snapshot_date.DateKey = snapshot.SnapshotDateKey
INNER JOIN analytics.DimProduct AS product ON product.ProductKey = snapshot.ProductKey
INNER JOIN analytics.DimStore AS store ON store.StoreKey = snapshot.StoreKey;
GO

CREATE OR ALTER VIEW analytics.vw_ExecutiveKPIControl
AS
WITH SalesControl AS
(
    SELECT
        SUM(CONVERT(BIGINT, OrderCount)) AS TotalOrders,
        SUM(CASE WHEN IsDelivered = 1 THEN CONVERT(BIGINT, OrderCount) ELSE 0 END) AS DeliveredOrders,
        SUM(CASE WHEN IsCancelled = 1 THEN CONVERT(BIGINT, OrderCount) ELSE 0 END) AS CancelledOrders,
        SUM(CONVERT(BIGINT, Quantity) * IsDelivered) AS DeliveredUnits,
        SUM(NetAmount) AS BookedOrderValue,
        SUM(RecognizedRevenueAmount) AS RecognizedRevenue,
        SUM(RecognizedCostAmount) AS RecognizedCOGS,
        SUM(RecognizedGrossProfitAmount) AS RecognizedGrossProfit
    FROM analytics.FactSales
),
PaymentControl AS
(
    SELECT
        SUM(CONVERT(BIGINT, AttemptCount)) AS PaymentAttempts,
        SUM(CONVERT(BIGINT, IsSuccessful)) AS SuccessfulPaymentAttempts,
        SUM(CollectedAmount) AS CollectedValue
    FROM analytics.FactPayments
),
ReturnControl AS
(
    SELECT
        COUNT(DISTINCT ProductReturnID) AS ReturnRequests,
        SUM(CONVERT(BIGINT, QuantityRequested)) AS RequestedReturnUnits,
        SUM(CONVERT(BIGINT, QuantityAccepted)) AS AcceptedReturnUnits,
        SUM(CASE WHEN IsReusable = 1 THEN CONVERT(BIGINT, QuantityAccepted) ELSE 0 END) AS ReusableReturnUnits
    FROM analytics.FactReturns
),
RefundControl AS
(
    SELECT
        SUM(CONVERT(BIGINT, RefundCount)) AS RefundEvents,
        SUM(CompletedRefundAmount) AS CompletedRefundValue,
        SUM(PendingRefundAmount) AS PendingRefundValue,
        SUM(FailedRefundAmount) AS FailedRefundValue
    FROM analytics.FactRefunds
),
InventoryControl AS
(
    SELECT
        SUM(CONVERT(BIGINT, QuantityOnHand)) AS QuantityOnHand,
        SUM(CONVERT(BIGINT, QuantityReserved)) AS QuantityReserved,
        SUM(CONVERT(BIGINT, QuantityAvailable)) AS QuantityAvailable,
        SUM(StockCostValue) AS StockCostValue,
        SUM(StockRetailValue) AS StockRetailValue,
        SUM(CONVERT(BIGINT, IsBelowReorderLevel)) AS BelowReorderProductStoreCount
    FROM analytics.FactInventorySnapshot
)
SELECT
    sales.TotalOrders,
    sales.DeliveredOrders,
    sales.CancelledOrders,
    sales.DeliveredUnits,
    sales.BookedOrderValue,
    sales.RecognizedRevenue,
    refund.CompletedRefundValue,
    sales.RecognizedRevenue - refund.CompletedRefundValue AS NetRevenue,
    sales.RecognizedCOGS,
    sales.RecognizedGrossProfit,
    CASE WHEN sales.RecognizedRevenue = 0 THEN 0
         ELSE sales.RecognizedGrossProfit / sales.RecognizedRevenue END AS GrossMarginRate,
    payment.PaymentAttempts,
    payment.SuccessfulPaymentAttempts,
    payment.CollectedValue,
    returns.ReturnRequests,
    returns.RequestedReturnUnits,
    returns.AcceptedReturnUnits,
    returns.ReusableReturnUnits,
    refund.RefundEvents,
    refund.PendingRefundValue,
    refund.FailedRefundValue,
    inventory.QuantityOnHand,
    inventory.QuantityReserved,
    inventory.QuantityAvailable,
    inventory.StockCostValue,
    inventory.StockRetailValue,
    inventory.BelowReorderProductStoreCount
FROM SalesControl AS sales
CROSS JOIN PaymentControl AS payment
CROSS JOIN ReturnControl AS returns
CROSS JOIN RefundControl AS refund
CROSS JOIN InventoryControl AS inventory;
GO

CREATE OR ALTER VIEW analytics.vw_MonthlySalesControl
AS
SELECT
    order_date.YearMonthNumber,
    order_date.MonthYearLabel,
    order_date.CalendarYear,
    order_date.CalendarQuarterLabel,
    order_date.FinancialYearLabel,
    order_date.FinancialQuarterLabel,
    SUM(CONVERT(BIGINT, sales.OrderCount)) AS TotalOrders,
    SUM(CASE WHEN sales.IsDelivered = 1 THEN CONVERT(BIGINT, sales.OrderCount) ELSE 0 END) AS DeliveredOrders,
    SUM(CASE WHEN sales.IsCancelled = 1 THEN CONVERT(BIGINT, sales.OrderCount) ELSE 0 END) AS CancelledOrders,
    SUM(CONVERT(BIGINT, sales.Quantity)) AS OrderedUnits,
    SUM(CASE WHEN sales.IsDelivered = 1 THEN CONVERT(BIGINT, sales.Quantity) ELSE 0 END) AS DeliveredUnits,
    SUM(sales.NetAmount) AS BookedOrderValue,
    SUM(sales.RecognizedRevenueAmount) AS RecognizedRevenue,
    SUM(sales.RecognizedCostAmount) AS RecognizedCOGS,
    SUM(sales.RecognizedGrossProfitAmount) AS RecognizedGrossProfit
FROM analytics.FactSales AS sales
INNER JOIN analytics.DimDate AS order_date ON order_date.DateKey = sales.OrderDateKey
GROUP BY order_date.YearMonthNumber, order_date.MonthYearLabel,
         order_date.CalendarYear, order_date.CalendarQuarterLabel,
         order_date.FinancialYearLabel, order_date.FinancialQuarterLabel;
GO

CREATE OR ALTER VIEW analytics.vw_StorePerformanceControl
AS
SELECT
    store.StoreKey,
    store.StoreCode,
    store.StoreName,
    store.StoreTier,
    store.City,
    store.StateName,
    SUM(CONVERT(BIGINT, sales.OrderCount)) AS TotalOrders,
    SUM(CASE WHEN sales.IsDelivered = 1 THEN CONVERT(BIGINT, sales.OrderCount) ELSE 0 END) AS DeliveredOrders,
    SUM(CONVERT(BIGINT, sales.Quantity) * sales.IsDelivered) AS DeliveredUnits,
    SUM(sales.RecognizedRevenueAmount) AS RecognizedRevenue,
    SUM(sales.RecognizedCostAmount) AS RecognizedCOGS,
    SUM(sales.RecognizedGrossProfitAmount) AS RecognizedGrossProfit
FROM analytics.FactSales AS sales
INNER JOIN analytics.DimStore AS store ON store.StoreKey = sales.StoreKey
GROUP BY store.StoreKey, store.StoreCode, store.StoreName,
         store.StoreTier, store.City, store.StateName;
GO

CREATE OR ALTER VIEW analytics.vw_ProductPerformanceControl
AS
SELECT
    product.ProductKey,
    product.SKU,
    product.ProductName,
    product.BrandName,
    product.SubCategoryName,
    product.CategoryName,
    product.SupplierName,
    product.PriceBand,
    SUM(CASE WHEN sales.IsDelivered = 1 THEN CONVERT(BIGINT, sales.Quantity) ELSE 0 END) AS DeliveredUnits,
    SUM(sales.RecognizedRevenueAmount) AS RecognizedRevenue,
    SUM(sales.RecognizedCostAmount) AS RecognizedCOGS,
    SUM(sales.RecognizedGrossProfitAmount) AS RecognizedGrossProfit,
    COUNT(DISTINCT CASE WHEN sales.IsDelivered = 1 THEN sales.SalesOrderID END) AS DeliveredOrderCount
FROM analytics.FactSales AS sales
INNER JOIN analytics.DimProduct AS product ON product.ProductKey = sales.ProductKey
GROUP BY product.ProductKey, product.SKU, product.ProductName,
         product.BrandName, product.SubCategoryName, product.CategoryName,
         product.SupplierName, product.PriceBand;
GO

-- ============================================================================
-- VIEW ACCEPTANCE VALIDATION
-- ============================================================================

DECLARE @ViewValidation TABLE
(
    ViewSequence TINYINT NOT NULL,
    ViewName SYSNAME NOT NULL,
    ExpectedGrain VARCHAR(100) NOT NULL,
    ExpectedRowCount BIGINT NOT NULL,
    ExistingRowCount BIGINT NOT NULL
);

INSERT INTO @ViewValidation VALUES
(1, 'vw_SalesDetail', 'One row per sales-order item',
 (SELECT COUNT_BIG(*) FROM analytics.FactSales), (SELECT COUNT_BIG(*) FROM analytics.vw_SalesDetail)),
(2, 'vw_PaymentDetail', 'One row per payment attempt',
 (SELECT COUNT_BIG(*) FROM analytics.FactPayments), (SELECT COUNT_BIG(*) FROM analytics.vw_PaymentDetail)),
(3, 'vw_ReturnDetail', 'One row per returned order item',
 (SELECT COUNT_BIG(*) FROM analytics.FactReturns), (SELECT COUNT_BIG(*) FROM analytics.vw_ReturnDetail)),
(4, 'vw_RefundDetail', 'One row per refund event',
 (SELECT COUNT_BIG(*) FROM analytics.FactRefunds), (SELECT COUNT_BIG(*) FROM analytics.vw_RefundDetail)),
(5, 'vw_InventoryMovementDetail', 'One row per inventory movement',
 (SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement), (SELECT COUNT_BIG(*) FROM analytics.vw_InventoryMovementDetail)),
(6, 'vw_CurrentInventory', 'One row per current product-store snapshot',
 (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot), (SELECT COUNT_BIG(*) FROM analytics.vw_CurrentInventory)),
(7, 'vw_ExecutiveKPIControl', 'One enterprise control row', 1,
 (SELECT COUNT_BIG(*) FROM analytics.vw_ExecutiveKPIControl)),
(8, 'vw_MonthlySalesControl', 'One row per order month',
 (SELECT COUNT(DISTINCT YearMonthNumber) FROM analytics.DimDate AS date_dimension
  WHERE EXISTS (SELECT 1 FROM analytics.FactSales AS sales WHERE sales.OrderDateKey = date_dimension.DateKey)),
 (SELECT COUNT_BIG(*) FROM analytics.vw_MonthlySalesControl)),
(9, 'vw_StorePerformanceControl', 'One row per selling store',
 (SELECT COUNT(DISTINCT StoreKey) FROM analytics.FactSales),
 (SELECT COUNT_BIG(*) FROM analytics.vw_StorePerformanceControl)),
(10, 'vw_ProductPerformanceControl', 'One row per sold product',
 (SELECT COUNT(DISTINCT ProductKey) FROM analytics.FactSales),
 (SELECT COUNT_BIG(*) FROM analytics.vw_ProductPerformanceControl));

IF EXISTS
(
    SELECT 1 FROM @ViewValidation
    WHERE ExpectedRowCount <> ExistingRowCount
)
    THROW 51422, 'Analytics-view validation failed: a view changed its declared grain.', 1;

SELECT
    ViewSequence,
    ViewName,
    ExpectedGrain,
    ExpectedRowCount,
    ExistingRowCount,
    CASE WHEN ExpectedRowCount = ExistingRowCount THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM @ViewValidation
ORDER BY ViewSequence;

SELECT * FROM analytics.vw_ExecutiveKPIControl;

RAISERROR('24_Create_Analytics_Views.sql completed successfully: 10 analytical views validated.', 10, 1) WITH NOWAIT;
GO
