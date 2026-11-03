/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      38_PowerBI_Reporting_Views.sql
Purpose:     Create a stable Power BI semantic reporting layer.
Author:      Akshay Aswani
Version:     2.1
Depends on:  37_Performance_Benchmarking.sql
Rerunnable:  Yes. Uses CREATE OR ALTER VIEW.

Power BI views and grains
-------------------------
- pbi_ExecutiveSummary:    one enterprise row
- pbi_SalesTrend:          one order month
- pbi_StorePerformance:    one selling store
- pbi_ProductPerformance:  one selling product
- pbi_CustomerPerformance: one purchasing customer
- pbi_InventoryPosition:   one product-store snapshot
- pbi_ReturnsPerformance:  one request month, return reason and category
- pbi_PaymentPerformance:  one payment month, payment method and payment status
Reporting attribution policy
----------------------------
- pbi_SalesTrend uses the existing vw_MonthlySalesControl sales-month grain.
  Its sales figures must be interpreted using that source view's date role.
- Payment metrics are attributed to payment month (PaymentDateKey).
- Return metrics are attributed to request month (RequestDateKey).
- Completed refunds are attributed to refund event month (RefundDateKey).
- Consequently monthly NetRevenue combines sales-month revenue and refund-month
  cash outflows; it is a calendar-activity measure, NOT a delivery-cohort net
  revenue measure. Compare to cohort-based measures only with aligned dates.
- These reporting views are not necessarily the Power BI model's fact tables;
  verify DAX measures and active relationships independently.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51580, 'Power BI reporting-view build stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.vw_ExecutiveKPIControl', N'V') IS NULL
   OR OBJECT_ID(N'analytics.vw_MonthlySalesControl', N'V') IS NULL
   OR OBJECT_ID(N'analytics.vw_StorePerformanceControl', N'V') IS NULL
   OR OBJECT_ID(N'analytics.vw_ProductPerformanceControl', N'V') IS NULL
   OR OBJECT_ID(N'analytics.vw_CurrentInventory', N'V') IS NULL
    THROW 51581, 'Power BI reporting-view build stopped: run script 24 successfully first.', 1;
GO

CREATE OR ALTER VIEW analytics.pbi_ExecutiveSummary
AS
SELECT
    control.TotalOrders,
    control.DeliveredOrders,
    control.CancelledOrders,
    control.DeliveredUnits,
    control.BookedOrderValue,
    control.RecognizedRevenue,
    control.CompletedRefundValue,
    control.NetRevenue,
    control.RecognizedCOGS,
    control.RecognizedGrossProfit,
    control.GrossMarginRate,
    control.PaymentAttempts,
    control.SuccessfulPaymentAttempts,
    control.CollectedValue,
    control.ReturnRequests,
    control.RequestedReturnUnits,
    control.AcceptedReturnUnits,
    control.ReusableReturnUnits,
    control.RefundEvents,
    control.PendingRefundValue,
    control.FailedRefundValue,
    control.QuantityOnHand,
    control.QuantityReserved,
    control.QuantityAvailable,
    control.StockCostValue,
    control.StockRetailValue,
    control.BelowReorderProductStoreCount,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), control.DeliveredOrders)
        / NULLIF(control.TotalOrders, 0)) AS DeliveryRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), control.CancelledOrders)
        / NULLIF(control.TotalOrders, 0)) AS CancellationRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), control.SuccessfulPaymentAttempts)
        / NULLIF(control.PaymentAttempts, 0)) AS PaymentSuccessRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), control.AcceptedReturnUnits)
        / NULLIF(control.DeliveredUnits, 0)) AS UnitReturnRate,
    CONVERT(DECIMAL(19,4), control.RecognizedGrossProfit
        / NULLIF(control.RecognizedRevenue, 0)) AS RecognizedGrossMarginRate,
    CONVERT(DECIMAL(19,4), control.NetRevenue
        / NULLIF(control.DeliveredOrders, 0)) AS AverageOrderValue,
	CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), control.QuantityAvailable)
		/ NULLIF(CONVERT(DECIMAL(38,6), control.QuantityOnHand), 0)) AS InventoryAvailabilityRate
FROM analytics.vw_ExecutiveKPIControl AS control;
GO

CREATE OR ALTER VIEW analytics.pbi_SalesTrend
AS
WITH PaymentMonth AS
(
    SELECT payment_date.YearMonthNumber,
           SUM(CONVERT(BIGINT, payment.AttemptCount)) AS PaymentAttempts,
           SUM(CONVERT(BIGINT, payment.IsSuccessful)) AS SuccessfulPaymentAttempts,
           SUM(payment.CollectedAmount) AS CollectedValue
    FROM analytics.FactPayments AS payment
    INNER JOIN analytics.DimDate AS payment_date
        ON payment_date.DateKey = payment.PaymentDateKey
    GROUP BY payment_date.YearMonthNumber
),
ReturnMonth AS
(
    SELECT request_date.YearMonthNumber,
           COUNT_BIG(DISTINCT fact_return.ProductReturnID) AS ReturnRequests,
           SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnUnits
    FROM analytics.FactReturns AS fact_return
    INNER JOIN analytics.DimDate AS request_date
        ON request_date.DateKey = fact_return.RequestDateKey
    GROUP BY request_date.YearMonthNumber
),
RefundMonth AS
(
    SELECT refund_date.YearMonthNumber,
           SUM(fact_refund.CompletedRefundAmount) AS CompletedRefundValue
    FROM analytics.FactRefunds AS fact_refund
    INNER JOIN analytics.DimDate AS refund_date
        ON refund_date.DateKey = fact_refund.RefundDateKey
    GROUP BY refund_date.YearMonthNumber
)
SELECT
    sales_month.YearMonthNumber,
    sales_month.MonthYearLabel,
    sales_month.CalendarYear,
    sales_month.CalendarQuarterLabel,
    sales_month.FinancialYearLabel,
    sales_month.FinancialQuarterLabel,
    sales_month.TotalOrders,
    sales_month.DeliveredOrders,
    sales_month.CancelledOrders,
    sales_month.OrderedUnits,
    sales_month.DeliveredUnits,
    sales_month.BookedOrderValue,
    sales_month.RecognizedRevenue,
    COALESCE(refund_month.CompletedRefundValue, 0) AS CompletedRefundValue,
    sales_month.RecognizedRevenue - COALESCE(refund_month.CompletedRefundValue, 0) AS NetRevenue,
    sales_month.RecognizedCOGS,
    sales_month.RecognizedGrossProfit,
    COALESCE(payment_month.PaymentAttempts, 0) AS PaymentAttempts,
    COALESCE(payment_month.SuccessfulPaymentAttempts, 0) AS SuccessfulPaymentAttempts,
    COALESCE(payment_month.CollectedValue, 0) AS CollectedValue,
    COALESCE(return_month.ReturnRequests, 0) AS ReturnRequests,
    COALESCE(return_month.AcceptedReturnUnits, 0) AS AcceptedReturnUnits,
    CONVERT(DECIMAL(19,4), sales_month.RecognizedGrossProfit
        / NULLIF(sales_month.RecognizedRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), sales_month.DeliveredOrders)
        / NULLIF(sales_month.TotalOrders, 0)) AS DeliveryRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), sales_month.CancelledOrders)
        / NULLIF(sales_month.TotalOrders, 0)) AS CancellationRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), COALESCE(return_month.AcceptedReturnUnits, 0))
        / NULLIF(sales_month.DeliveredUnits, 0)) AS UnitReturnRate
FROM analytics.vw_MonthlySalesControl AS sales_month
LEFT JOIN PaymentMonth AS payment_month
    ON payment_month.YearMonthNumber = sales_month.YearMonthNumber
LEFT JOIN ReturnMonth AS return_month
    ON return_month.YearMonthNumber = sales_month.YearMonthNumber
LEFT JOIN RefundMonth AS refund_month
    ON refund_month.YearMonthNumber = sales_month.YearMonthNumber;
GO

CREATE OR ALTER VIEW analytics.pbi_StorePerformance
AS
WITH PaymentStore AS
(
    SELECT StoreKey,
           SUM(CONVERT(BIGINT, AttemptCount)) AS PaymentAttempts,
           SUM(CONVERT(BIGINT, IsSuccessful)) AS SuccessfulPaymentAttempts,
           SUM(CollectedAmount) AS CollectedValue
    FROM analytics.FactPayments
    GROUP BY StoreKey
),
ReturnStore AS
(
    SELECT StoreKey,
           SUM(CONVERT(BIGINT, QuantityAccepted)) AS AcceptedReturnUnits
    FROM analytics.FactReturns
    GROUP BY StoreKey
),
InventoryStore AS
(
    SELECT StoreKey,
           SUM(CONVERT(BIGINT, QuantityOnHand)) AS QuantityOnHand,
           SUM(CONVERT(BIGINT, QuantityAvailable)) AS QuantityAvailable,
           SUM(StockCostValue) AS StockCostValue,
           SUM(CONVERT(BIGINT, IsOutOfStock)) AS StockoutProductCount,
           SUM(CONVERT(BIGINT, IsBelowReorderLevel)) AS BelowReorderProductCount,
           SUM(CONVERT(BIGINT, IsExcessStock)) AS ExcessStockProductCount
    FROM analytics.FactInventorySnapshot
    GROUP BY StoreKey
)
SELECT
    store_sales.StoreKey,
    store_sales.StoreCode,
    store_sales.StoreName,
    store_sales.StoreTier,
    store_sales.City,
    store_sales.StateName,
    store_sales.TotalOrders,
    store_sales.DeliveredOrders,
    store_sales.DeliveredUnits,
    store_sales.RecognizedRevenue,
    store_sales.RecognizedCOGS,
    store_sales.RecognizedGrossProfit,
    COALESCE(payment_store.PaymentAttempts, 0) AS PaymentAttempts,
    COALESCE(payment_store.SuccessfulPaymentAttempts, 0) AS SuccessfulPaymentAttempts,
    COALESCE(payment_store.CollectedValue, 0) AS CollectedValue,
    COALESCE(return_store.AcceptedReturnUnits, 0) AS AcceptedReturnUnits,
    COALESCE(inventory_store.QuantityOnHand, 0) AS QuantityOnHand,
    COALESCE(inventory_store.QuantityAvailable, 0) AS QuantityAvailable,
    COALESCE(inventory_store.StockCostValue, 0) AS StockCostValue,
    COALESCE(inventory_store.StockoutProductCount, 0) AS StockoutProductCount,
    COALESCE(inventory_store.BelowReorderProductCount, 0) AS BelowReorderProductCount,
    COALESCE(inventory_store.ExcessStockProductCount, 0) AS ExcessStockProductCount,
    CONVERT(DECIMAL(19,4), store_sales.RecognizedGrossProfit
        / NULLIF(store_sales.RecognizedRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(19,4), store_sales.RecognizedRevenue
        / NULLIF(store_sales.DeliveredOrders, 0)) AS AverageOrderValue,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), COALESCE(return_store.AcceptedReturnUnits, 0))
        / NULLIF(store_sales.DeliveredUnits, 0)) AS UnitReturnRate
FROM analytics.vw_StorePerformanceControl AS store_sales
LEFT JOIN PaymentStore AS payment_store ON payment_store.StoreKey = store_sales.StoreKey
LEFT JOIN ReturnStore AS return_store ON return_store.StoreKey = store_sales.StoreKey
LEFT JOIN InventoryStore AS inventory_store ON inventory_store.StoreKey = store_sales.StoreKey;
GO

CREATE OR ALTER VIEW analytics.pbi_ProductPerformance
AS
WITH ReturnProduct AS
(
    SELECT ProductKey,
           SUM(CONVERT(BIGINT, QuantityRequested)) AS RequestedReturnUnits,
           SUM(CONVERT(BIGINT, QuantityAccepted)) AS AcceptedReturnUnits,
           SUM(EligibleRefundAmount) AS EligibleRefundAmount
    FROM analytics.FactReturns
    GROUP BY ProductKey
),
InventoryProduct AS
(
    SELECT ProductKey,
           COUNT_BIG(*) AS StockedStoreCount,
           SUM(CONVERT(BIGINT, QuantityOnHand)) AS QuantityOnHand,
           SUM(CONVERT(BIGINT, QuantityAvailable)) AS QuantityAvailable,
           SUM(StockCostValue) AS StockCostValue,
           SUM(CONVERT(BIGINT, IsOutOfStock)) AS StockoutStoreCount,
           SUM(CONVERT(BIGINT, IsBelowReorderLevel)) AS BelowReorderStoreCount,
           SUM(CONVERT(BIGINT, IsExcessStock)) AS ExcessStockStoreCount
    FROM analytics.FactInventorySnapshot
    GROUP BY ProductKey
)
SELECT
    product_sales.ProductKey,
    product_sales.SKU,
    product_sales.ProductName,
    product_sales.BrandName,
    product_sales.SubCategoryName,
    product_sales.CategoryName,
    product_sales.SupplierName,
    product_sales.PriceBand,
    product_sales.DeliveredOrderCount,
    product_sales.DeliveredUnits,
    product_sales.RecognizedRevenue,
    product_sales.RecognizedCOGS,
    product_sales.RecognizedGrossProfit,
    COALESCE(return_product.RequestedReturnUnits, 0) AS RequestedReturnUnits,
    COALESCE(return_product.AcceptedReturnUnits, 0) AS AcceptedReturnUnits,
    COALESCE(return_product.EligibleRefundAmount, 0) AS EligibleRefundAmount,
    COALESCE(inventory_product.StockedStoreCount, 0) AS StockedStoreCount,
    COALESCE(inventory_product.QuantityOnHand, 0) AS QuantityOnHand,
    COALESCE(inventory_product.QuantityAvailable, 0) AS QuantityAvailable,
    COALESCE(inventory_product.StockCostValue, 0) AS StockCostValue,
    COALESCE(inventory_product.StockoutStoreCount, 0) AS StockoutStoreCount,
    COALESCE(inventory_product.BelowReorderStoreCount, 0) AS BelowReorderStoreCount,
    COALESCE(inventory_product.ExcessStockStoreCount, 0) AS ExcessStockStoreCount,
    CONVERT(DECIMAL(19,4), product_sales.RecognizedGrossProfit
        / NULLIF(product_sales.RecognizedRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), COALESCE(return_product.AcceptedReturnUnits, 0))
        / NULLIF(product_sales.DeliveredUnits, 0)) AS UnitReturnRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), product_sales.DeliveredUnits)
        / NULLIF(COALESCE(inventory_product.QuantityOnHand, 0) + product_sales.DeliveredUnits, 0)) AS SellThroughRate
FROM analytics.vw_ProductPerformanceControl AS product_sales
LEFT JOIN ReturnProduct AS return_product ON return_product.ProductKey = product_sales.ProductKey
LEFT JOIN InventoryProduct AS inventory_product ON inventory_product.ProductKey = product_sales.ProductKey;
GO

CREATE OR ALTER VIEW analytics.pbi_CustomerPerformance
AS
WITH CustomerSales AS
(
    SELECT fact_sales.CustomerKey,
           SUM(CONVERT(BIGINT, fact_sales.OrderCount)) AS TotalOrders,
           SUM(CASE WHEN fact_sales.IsDelivered = 1 THEN CONVERT(BIGINT, fact_sales.OrderCount) ELSE 0 END) AS DeliveredOrders,
           SUM(CASE WHEN fact_sales.IsCancelled = 1 THEN CONVERT(BIGINT, fact_sales.OrderCount) ELSE 0 END) AS CancelledOrders,
           SUM(CONVERT(BIGINT, fact_sales.Quantity) * fact_sales.IsDelivered) AS DeliveredUnits,
           SUM(fact_sales.RecognizedRevenueAmount) AS RecognizedRevenue,
           SUM(fact_sales.RecognizedGrossProfitAmount) AS RecognizedGrossProfit,
           MIN(order_date.[Date]) AS FirstOrderDate,
           MAX(order_date.[Date]) AS LastOrderDate
    FROM analytics.FactSales AS fact_sales
    INNER JOIN analytics.DimDate AS order_date ON order_date.DateKey = fact_sales.OrderDateKey
    GROUP BY fact_sales.CustomerKey
),
CustomerPayment AS
(
    SELECT CustomerKey,
           SUM(CONVERT(BIGINT, AttemptCount)) AS PaymentAttempts,
           SUM(CONVERT(BIGINT, IsSuccessful)) AS SuccessfulPaymentAttempts,
           SUM(CollectedAmount) AS CollectedValue
    FROM analytics.FactPayments GROUP BY CustomerKey
),
CustomerReturn AS
(
    SELECT CustomerKey,
           COUNT_BIG(DISTINCT ProductReturnID) AS ReturnRequests,
           SUM(CONVERT(BIGINT, QuantityAccepted)) AS AcceptedReturnUnits
    FROM analytics.FactReturns GROUP BY CustomerKey
)
SELECT
    customer.CustomerKey,
    customer.CustomerCode,
    customer.CustomerName,
    customer.CustomerSegment,
    customer.City,
    customer.StateName,
    customer.RegistrationDate,
    customer.LoyaltyPoints,
    customer_sales.FirstOrderDate,
    customer_sales.LastOrderDate,
    customer_sales.TotalOrders,
    customer_sales.DeliveredOrders,
    customer_sales.CancelledOrders,
    customer_sales.DeliveredUnits,
    customer_sales.RecognizedRevenue,
    customer_sales.RecognizedGrossProfit,
    COALESCE(customer_payment.PaymentAttempts, 0) AS PaymentAttempts,
    COALESCE(customer_payment.SuccessfulPaymentAttempts, 0) AS SuccessfulPaymentAttempts,
    COALESCE(customer_payment.CollectedValue, 0) AS CollectedValue,
    COALESCE(customer_return.ReturnRequests, 0) AS ReturnRequests,
    COALESCE(customer_return.AcceptedReturnUnits, 0) AS AcceptedReturnUnits,
    CONVERT(DECIMAL(19,4), customer_sales.RecognizedRevenue
        / NULLIF(customer_sales.DeliveredOrders, 0)) AS AverageOrderValue,
    CONVERT(DECIMAL(19,4), customer_sales.RecognizedGrossProfit
        / NULLIF(customer_sales.RecognizedRevenue, 0)) AS GrossMarginRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), COALESCE(customer_return.AcceptedReturnUnits, 0))
        / NULLIF(customer_sales.DeliveredUnits, 0)) AS UnitReturnRate
FROM CustomerSales AS customer_sales
INNER JOIN analytics.DimCustomer AS customer ON customer.CustomerKey = customer_sales.CustomerKey
LEFT JOIN CustomerPayment AS customer_payment ON customer_payment.CustomerKey = customer_sales.CustomerKey
LEFT JOIN CustomerReturn AS customer_return ON customer_return.CustomerKey = customer_sales.CustomerKey;
GO

CREATE OR ALTER VIEW analytics.pbi_InventoryPosition
AS
SELECT
    current_inventory.SnapshotDate,
    current_inventory.SKU,
    current_inventory.ProductName,
    current_inventory.BrandName,
    current_inventory.SubCategoryName,
    current_inventory.CategoryName,
    current_inventory.SupplierName,
    current_inventory.PriceBand,
    current_inventory.StoreCode,
    current_inventory.StoreName,
    current_inventory.StoreTier,
    current_inventory.StoreCity,
    current_inventory.StoreState,
    current_inventory.InventoryBalanceID,
    current_inventory.QuantityOnHand,
    current_inventory.QuantityReserved,
    current_inventory.QuantityAvailable,
    current_inventory.UnitCost,
    current_inventory.UnitRetailPrice,
    current_inventory.StockCostValue,
    current_inventory.StockRetailValue,
    current_inventory.ReorderLevel,
    current_inventory.ExcessStockLevel,
    current_inventory.IsOutOfStock,
    current_inventory.IsBelowReorderLevel,
    current_inventory.IsExcessStock,
    current_inventory.SnapshotRowCount,
    current_inventory.StockRetailValue - current_inventory.StockCostValue AS PotentialGrossProfitValue,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), current_inventory.QuantityAvailable)
        / NULLIF(current_inventory.QuantityOnHand, 0)) AS AvailabilityRate,
    CASE
        WHEN current_inventory.IsOutOfStock = 1 THEN 'OUT OF STOCK'
        WHEN current_inventory.IsBelowReorderLevel = 1 THEN 'LOW STOCK'
        WHEN current_inventory.IsExcessStock = 1 THEN 'EXCESS STOCK'
        ELSE 'HEALTHY'
    END AS InventoryStatus
FROM analytics.vw_CurrentInventory AS current_inventory;
GO

CREATE OR ALTER VIEW analytics.pbi_ReturnsPerformance
AS
SELECT
    request_date.YearMonthNumber,
    request_date.MonthYearLabel,
    request_date.FinancialYearLabel,
    return_reason.ReturnReasonCode,
    return_reason.ReturnReasonName,
    product.CategoryName,
    COUNT_BIG(DISTINCT fact_return.ProductReturnID) AS ReturnRequests,
    SUM(CONVERT(BIGINT, fact_return.QuantityRequested)) AS RequestedReturnUnits,
    SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnUnits,
    SUM(CONVERT(BIGINT, fact_return.QuantityRejected)) AS RejectedReturnUnits,
    SUM(CASE WHEN fact_return.IsReusable = 1 THEN CONVERT(BIGINT, fact_return.QuantityAccepted) ELSE 0 END) AS ReusableReturnUnits,
    SUM(fact_return.EligibleRefundAmount) AS EligibleRefundAmount,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)))
        / NULLIF(SUM(CONVERT(BIGINT, fact_return.QuantityRequested)), 0)) AS AcceptanceRate,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6),
        SUM(CASE WHEN fact_return.IsReusable = 1 THEN CONVERT(BIGINT, fact_return.QuantityAccepted) ELSE 0 END))
        / NULLIF(SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)), 0)) AS ReusabilityRate
FROM analytics.FactReturns AS fact_return
INNER JOIN analytics.DimDate AS request_date ON request_date.DateKey = fact_return.RequestDateKey
INNER JOIN analytics.DimReturnReason AS return_reason ON return_reason.ReturnReasonKey = fact_return.ReturnReasonKey
INNER JOIN analytics.DimProduct AS product ON product.ProductKey = fact_return.ProductKey
GROUP BY request_date.YearMonthNumber, request_date.MonthYearLabel,
         request_date.FinancialYearLabel, return_reason.ReturnReasonCode,
         return_reason.ReturnReasonName, product.CategoryName;
GO

CREATE OR ALTER VIEW analytics.pbi_PaymentPerformance
AS
SELECT
    payment_date.YearMonthNumber,
    payment_date.MonthYearLabel,
    payment_date.FinancialYearLabel,
    payment_method.PaymentMethodCode,
    payment_method.PaymentMethodName,
    payment_status.PaymentStatusCode,
    payment_status.PaymentStatusName,
    SUM(CONVERT(BIGINT, fact_payment.AttemptCount)) AS PaymentAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsSuccessful)) AS SuccessfulPaymentAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsFailed)) AS FailedPaymentAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsPending)) AS PendingPaymentAttempts,
    SUM(fact_payment.Amount) AS AttemptedValue,
    SUM(fact_payment.CollectedAmount) AS CollectedValue,
    CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(38,6), SUM(CONVERT(BIGINT, fact_payment.IsSuccessful)))
        / NULLIF(SUM(CONVERT(BIGINT, fact_payment.AttemptCount)), 0)) AS PaymentSuccessRate,
    CONVERT(DECIMAL(19,4), SUM(fact_payment.CollectedAmount)
        / NULLIF(SUM(fact_payment.Amount), 0)) AS CollectionRate
FROM analytics.FactPayments AS fact_payment
INNER JOIN analytics.DimDate AS payment_date ON payment_date.DateKey = fact_payment.PaymentDateKey
INNER JOIN analytics.DimPaymentMethod AS payment_method ON payment_method.PaymentMethodKey = fact_payment.PaymentMethodKey
INNER JOIN analytics.DimPaymentStatus AS payment_status ON payment_status.PaymentStatusKey = fact_payment.PaymentStatusKey
GROUP BY payment_date.YearMonthNumber, payment_date.MonthYearLabel,
         payment_date.FinancialYearLabel, payment_method.PaymentMethodCode,
         payment_method.PaymentMethodName, payment_status.PaymentStatusCode,
         payment_status.PaymentStatusName;
GO

DECLARE @ViewValidation TABLE
(
    ViewSequence TINYINT NOT NULL PRIMARY KEY,
    ViewName SYSNAME NOT NULL,
    ExpectedGrain VARCHAR(100) NOT NULL,
    ExpectedRowCount BIGINT NOT NULL,
    ExistingRowCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NULL
);

INSERT INTO @ViewValidation
(ViewSequence, ViewName, ExpectedGrain, ExpectedRowCount, ExistingRowCount)
VALUES
(1, 'pbi_ExecutiveSummary', 'One enterprise row', 1,
 (SELECT COUNT_BIG(*) FROM analytics.pbi_ExecutiveSummary)),
(2, 'pbi_SalesTrend', 'One row per selling order month',
 (SELECT COUNT_BIG(*) FROM analytics.vw_MonthlySalesControl),
 (SELECT COUNT_BIG(*) FROM analytics.pbi_SalesTrend)),
(3, 'pbi_StorePerformance', 'One row per selling store',
 (SELECT COUNT_BIG(*) FROM analytics.vw_StorePerformanceControl),
 (SELECT COUNT_BIG(*) FROM analytics.pbi_StorePerformance)),
(4, 'pbi_ProductPerformance', 'One row per selling product',
 (SELECT COUNT_BIG(*) FROM analytics.vw_ProductPerformanceControl),
 (SELECT COUNT_BIG(*) FROM analytics.pbi_ProductPerformance)),
(5, 'pbi_CustomerPerformance', 'One row per purchasing customer',
 (SELECT COUNT_BIG(DISTINCT CustomerKey) FROM analytics.FactSales),
 (SELECT COUNT_BIG(*) FROM analytics.pbi_CustomerPerformance)),
(6, 'pbi_InventoryPosition', 'One row per product-store snapshot',
 (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot),
 (SELECT COUNT_BIG(*) FROM analytics.pbi_InventoryPosition)),
(7, 'pbi_ReturnsPerformance', 'One row per month-reason-category',
 (SELECT COUNT_BIG(*) FROM
   (SELECT request_date.YearMonthNumber, fact_return.ReturnReasonKey, product.CategoryName
    FROM analytics.FactReturns AS fact_return
    INNER JOIN analytics.DimDate AS request_date ON request_date.DateKey = fact_return.RequestDateKey
    INNER JOIN analytics.DimProduct AS product ON product.ProductKey = fact_return.ProductKey
    GROUP BY request_date.YearMonthNumber, fact_return.ReturnReasonKey, product.CategoryName) AS return_grain),
 (SELECT COUNT_BIG(*) FROM analytics.pbi_ReturnsPerformance)),
(8, 'pbi_PaymentPerformance', 'One row per month-method-status',
 (SELECT COUNT_BIG(*) FROM
   (SELECT payment_date.YearMonthNumber, fact_payment.PaymentMethodKey, fact_payment.PaymentStatusKey
    FROM analytics.FactPayments AS fact_payment
    INNER JOIN analytics.DimDate AS payment_date ON payment_date.DateKey = fact_payment.PaymentDateKey
    GROUP BY payment_date.YearMonthNumber, fact_payment.PaymentMethodKey, fact_payment.PaymentStatusKey) AS payment_grain),
 (SELECT COUNT_BIG(*) FROM analytics.pbi_PaymentPerformance));

UPDATE @ViewValidation
SET ValidationStatus = CASE WHEN ExpectedRowCount = ExistingRowCount THEN 'PASSED' ELSE 'FAILED' END;

SELECT ViewSequence, ViewName, ExpectedGrain, ExpectedRowCount, ExistingRowCount, ValidationStatus
FROM @ViewValidation
ORDER BY ViewSequence;

IF EXISTS (SELECT 1 FROM @ViewValidation WHERE ValidationStatus = 'FAILED')
    THROW 51582, 'Power BI reporting-view validation failed. Review the final validation result set.', 1;

RAISERROR('38_PowerBI_Reporting_Views.sql completed successfully: eight Power BI views validated.', 10, 1) WITH NOWAIT;
GO
