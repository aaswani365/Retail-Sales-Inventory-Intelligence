/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      33_Returns_Payments_Analysis.sql
Purpose:     Analyze payment performance, returns, refunds and recovery outcomes.
Author:      Akshay Aswani
Version:     2.0
Depends on:  32_Store_Employee_Analysis.sql
Rerunnable:  Yes. Read-only analysis using session-scoped temporary tables.

Grain policy
------------
- Payment analysis: one row per payment attempt, aggregated to order when needed.
- Return analysis: one row per returned order item.
- Refund analysis: one row per refund event.
- Facts are aggregated independently before cross-domain KPI calculations.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51530, 'Returns and payments analysis stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactPayments', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimPaymentMethod', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimReturnReason', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
    THROW 51531, 'Returns and payments analysis stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51532, 'Returns and payments analysis stopped: run script 26 successfully first.', 1;

DROP TABLE IF EXISTS #PaymentOrderOutcome;
DROP TABLE IF EXISTS #MonthlyPayment;
DROP TABLE IF EXISTS #ReturnOrderOutcome;
DROP TABLE IF EXISTS #MonthlyReturn;

/* ============================================================================
   1. PAYMENT OUTCOME AT ORDER GRAIN
   ============================================================================ */

SELECT
    fact_payment.SalesOrderID,
    MIN(fact_payment.PaymentDateKey) AS FirstPaymentDateKey,
    MAX(fact_payment.PaymentDateKey) AS LastPaymentDateKey,
    COUNT_BIG(*) AS PaymentAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsSuccessful)) AS SuccessfulAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsFailed)) AS FailedAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsPending)) AS PendingAttempts,
    SUM(fact_payment.Amount) AS AttemptedValue,
    SUM(fact_payment.CollectedAmount) AS CompletedPaymentValue,
    MAX(CASE WHEN fact_payment.AttemptNumber = 1 AND fact_payment.IsFailed = 1
             THEN 1 ELSE 0 END) AS InitialAttemptFailed,
    MAX(CASE WHEN fact_payment.AttemptNumber > 1 AND fact_payment.IsSuccessful = 1
             THEN 1 ELSE 0 END) AS LaterAttemptSucceeded,
    MAX(fact_payment.AttemptNumber) AS MaximumAttemptNumber
INTO #PaymentOrderOutcome
FROM analytics.FactPayments AS fact_payment
GROUP BY fact_payment.SalesOrderID;

CREATE UNIQUE CLUSTERED INDEX CIX_PaymentOrderOutcome33
    ON #PaymentOrderOutcome (SalesOrderID);

DECLARE @PaymentAttempts BIGINT =
    (SELECT COALESCE(SUM(PaymentAttempts), 0) FROM #PaymentOrderOutcome);
DECLARE @SuccessfulAttempts BIGINT =
    (SELECT COALESCE(SUM(SuccessfulAttempts), 0) FROM #PaymentOrderOutcome);
DECLARE @FailedAttempts BIGINT =
    (SELECT COALESCE(SUM(FailedAttempts), 0) FROM #PaymentOrderOutcome);
DECLARE @PendingAttempts BIGINT =
    (SELECT COALESCE(SUM(PendingAttempts), 0) FROM #PaymentOrderOutcome);
DECLARE @CompletedPaymentValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(CompletedPaymentValue), 0) FROM #PaymentOrderOutcome);
DECLARE @InitialFailureOrders BIGINT =
    (SELECT COUNT_BIG(*) FROM #PaymentOrderOutcome WHERE InitialAttemptFailed = 1);
DECLARE @RecoveredRetryOrders BIGINT =
    (SELECT COUNT_BIG(*) FROM #PaymentOrderOutcome
     WHERE InitialAttemptFailed = 1 AND LaterAttemptSucceeded = 1);

/* ============================================================================
   2. RETURN OUTCOME AT RETURN-HEADER / ORDER GRAIN
   ============================================================================ */

SELECT
    fact_return.ProductReturnID,
    MAX(fact_return.SalesOrderID) AS SalesOrderID,
    MIN(fact_return.RequestDateKey) AS RequestDateKey,
    MAX(fact_return.ReceivedDateKey) AS ReceivedDateKey,
    MAX(fact_return.ClosedDateKey) AS ClosedDateKey,
    MAX(fact_return.CustomerKey) AS CustomerKey,
    MAX(fact_return.StoreKey) AS StoreKey,
    COUNT_BIG(*) AS ReturnedLineCount,
    SUM(CONVERT(BIGINT, fact_return.QuantityRequested)) AS RequestedReturnUnits,
    SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnedUnits,
    SUM(CONVERT(BIGINT, fact_return.QuantityRejected)) AS RejectedReturnUnits,
    SUM(CASE WHEN fact_return.IsReusable = 1
             THEN CONVERT(BIGINT, fact_return.QuantityAccepted) ELSE 0 END) AS ReusableReturnedUnits,
    SUM(fact_return.EligibleRefundAmount) AS EligibleRefundValue
INTO #ReturnOrderOutcome
FROM analytics.FactReturns AS fact_return
GROUP BY fact_return.ProductReturnID;

CREATE UNIQUE CLUSTERED INDEX CIX_ReturnOrderOutcome33
    ON #ReturnOrderOutcome (ProductReturnID);
CREATE INDEX IX_ReturnOrderOutcome_Order33
    ON #ReturnOrderOutcome (SalesOrderID);

DECLARE @DeliveredOrders BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, OrderCount)), 0)
     FROM analytics.FactSales WHERE IsDelivered = 1);
DECLARE @DeliveredUnits BIGINT =
    (SELECT COALESCE(SUM(CONVERT(BIGINT, Quantity)), 0)
     FROM analytics.FactSales WHERE IsDelivered = 1);
DECLARE @OrdersWithAcceptedReturns BIGINT =
    (SELECT COUNT_BIG(DISTINCT SalesOrderID)
     FROM #ReturnOrderOutcome WHERE AcceptedReturnedUnits > 0);
DECLARE @RequestedReturnUnits BIGINT =
    (SELECT COALESCE(SUM(RequestedReturnUnits), 0) FROM #ReturnOrderOutcome);
DECLARE @AcceptedReturnedUnits BIGINT =
    (SELECT COALESCE(SUM(AcceptedReturnedUnits), 0) FROM #ReturnOrderOutcome);
DECLARE @ReusableReturnedUnits BIGINT =
    (SELECT COALESCE(SUM(ReusableReturnedUnits), 0) FROM #ReturnOrderOutcome);
DECLARE @CompletedRefundValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(CompletedRefundAmount), 0) FROM analytics.FactRefunds);
DECLARE @PendingRefundValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(PendingRefundAmount), 0) FROM analytics.FactRefunds);
DECLARE @FailedRefundValue DECIMAL(38,2) =
    (SELECT COALESCE(SUM(FailedRefundAmount), 0) FROM analytics.FactRefunds);

/* ============================================================================
   3. RETURNS AND PAYMENTS EXECUTIVE SCORECARD
   ============================================================================ */

SELECT
    @PaymentAttempts AS PaymentAttempts,
    @SuccessfulAttempts AS SuccessfulPaymentAttempts,
    @FailedAttempts AS FailedPaymentAttempts,
    @PendingAttempts AS PendingPaymentAttempts,
    @CompletedPaymentValue AS CompletedPaymentValue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @SuccessfulAttempts)
        / NULLIF(@PaymentAttempts, 0)) AS PaymentSuccessRate,
    @InitialFailureOrders AS OrdersWithInitialPaymentFailure,
    @RecoveredRetryOrders AS RetryRecoveredOrders,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @RecoveredRetryOrders)
        / NULLIF(@InitialFailureOrders, 0)) AS PaymentRetrySuccessRate,
    (SELECT COUNT_BIG(*) FROM #ReturnOrderOutcome) AS ReturnRequests,
    @RequestedReturnUnits AS RequestedReturnUnits,
    @AcceptedReturnedUnits AS AcceptedReturnedUnits,
    @OrdersWithAcceptedReturns AS OrdersWithAcceptedReturns,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @AcceptedReturnedUnits)
        / NULLIF(@DeliveredUnits, 0)) AS ReturnRateByQuantity,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @OrdersWithAcceptedReturns)
        / NULLIF(@DeliveredOrders, 0)) AS ReturnRateByOrders,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), @ReusableReturnedUnits)
        / NULLIF(@AcceptedReturnedUnits, 0)) AS ReusableReturnRate,
    @CompletedRefundValue AS GrossRefundValue,
    @PendingRefundValue AS PendingRefundValue,
    @FailedRefundValue AS FailedRefundValue,
    @CompletedPaymentValue - @CompletedRefundValue AS NetCashCollection,
    CONVERT(DECIMAL(9,4), @CompletedRefundValue
        / NULLIF(@CompletedPaymentValue, 0)) AS RefundRate;

/* ============================================================================
   4. PAYMENT METHOD PERFORMANCE
   ============================================================================ */

SELECT
    payment_method.PaymentMethodCode,
    payment_method.PaymentMethodName,
    COUNT_BIG(*) AS PaymentAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsSuccessful)) AS SuccessfulAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsFailed)) AS FailedAttempts,
    SUM(fact_payment.Amount) AS AttemptedValue,
    SUM(fact_payment.CollectedAmount) AS CompletedPaymentValue,
    CONVERT(DECIMAL(9,4), SUM(CONVERT(DECIMAL(38,6), fact_payment.IsSuccessful))
        / NULLIF(COUNT_BIG(*), 0)) AS PaymentSuccessRate,
    CONVERT(DECIMAL(19,2), SUM(fact_payment.CollectedAmount)
        / NULLIF(SUM(CONVERT(BIGINT, fact_payment.IsSuccessful)), 0)) AS AverageSuccessfulPaymentValue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), COUNT_BIG(*))
        / NULLIF(@PaymentAttempts, 0)) AS AttemptShareRate
FROM analytics.FactPayments AS fact_payment
INNER JOIN analytics.DimPaymentMethod AS payment_method
    ON payment_method.PaymentMethodKey = fact_payment.PaymentMethodKey
GROUP BY
    payment_method.PaymentMethodCode,
    payment_method.PaymentMethodName,
    payment_method.SortOrder
ORDER BY payment_method.SortOrder;

/* ============================================================================
   5. PAYMENT STATUS AND FAILURE REASON
   ============================================================================ */

SELECT
    payment_status.PaymentStatusCode,
    payment_status.PaymentStatusName,
    COUNT_BIG(*) AS PaymentAttempts,
    SUM(fact_payment.Amount) AS AttemptedValue,
    SUM(fact_payment.CollectedAmount) AS CollectedValue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), COUNT_BIG(*))
        / NULLIF(@PaymentAttempts, 0)) AS AttemptShareRate
FROM analytics.FactPayments AS fact_payment
INNER JOIN analytics.DimPaymentStatus AS payment_status
    ON payment_status.PaymentStatusKey = fact_payment.PaymentStatusKey
GROUP BY
    payment_status.PaymentStatusCode,
    payment_status.PaymentStatusName,
    payment_status.SortOrder
ORDER BY payment_status.SortOrder;

SELECT TOP (20)
    fact_payment.FailureReason,
    COUNT_BIG(*) AS FailedAttempts,
    SUM(fact_payment.Amount) AS FailedAttemptValue,
    COUNT_BIG(DISTINCT fact_payment.SalesOrderID) AS AffectedOrders,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), COUNT_BIG(*))
        / NULLIF(@FailedAttempts, 0)) AS FailureContributionRate
FROM analytics.FactPayments AS fact_payment
WHERE fact_payment.IsFailed = 1
GROUP BY fact_payment.FailureReason
ORDER BY FailedAttempts DESC, fact_payment.FailureReason;

/* ============================================================================
   6. MONTHLY PAYMENT AND COLLECTION TREND
   ============================================================================ */

SELECT
    payment_date.YearMonthNumber,
    payment_date.MonthYearLabel,
    payment_date.FinancialYearLabel,
    COUNT_BIG(*) AS PaymentAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsSuccessful)) AS SuccessfulAttempts,
    SUM(CONVERT(BIGINT, fact_payment.IsFailed)) AS FailedAttempts,
    SUM(fact_payment.Amount) AS AttemptedValue,
    SUM(fact_payment.CollectedAmount) AS CompletedPaymentValue,
    CONVERT(DECIMAL(9,4), SUM(CONVERT(DECIMAL(38,6), fact_payment.IsSuccessful))
        / NULLIF(COUNT_BIG(*), 0)) AS PaymentSuccessRate
INTO #MonthlyPayment
FROM analytics.FactPayments AS fact_payment
INNER JOIN analytics.DimDate AS payment_date
    ON payment_date.DateKey = fact_payment.PaymentDateKey
GROUP BY
    payment_date.YearMonthNumber,
    payment_date.MonthYearLabel,
    payment_date.FinancialYearLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_MonthlyPayment33
    ON #MonthlyPayment (YearMonthNumber);

SELECT
    monthly_payment.*,
    SUM(monthly_payment.CompletedPaymentValue) OVER
        (ORDER BY monthly_payment.YearMonthNumber ROWS UNBOUNDED PRECEDING) AS RunningCompletedPaymentValue,
    CONVERT
    (
        DECIMAL(9,4),
        (monthly_payment.CompletedPaymentValue
         - LAG(monthly_payment.CompletedPaymentValue) OVER (ORDER BY monthly_payment.YearMonthNumber))
        / NULLIF(LAG(monthly_payment.CompletedPaymentValue)
                 OVER (ORDER BY monthly_payment.YearMonthNumber), 0)
    ) AS CollectionMoMRate
FROM #MonthlyPayment AS monthly_payment
ORDER BY monthly_payment.YearMonthNumber;

/* ============================================================================
   7. PAYMENT RETRY FUNNEL BY INITIAL FAILURE MONTH
   ============================================================================ */

SELECT
    first_payment_date.YearMonthNumber,
    first_payment_date.MonthYearLabel,
    COUNT_BIG(*) AS OrdersWithInitialFailure,
    SUM(CASE WHEN payment_outcome.LaterAttemptSucceeded = 1
             THEN CONVERT(BIGINT, 1) ELSE 0 END) AS RetryRecoveredOrders,
    SUM(CASE WHEN payment_outcome.LaterAttemptSucceeded = 0
             THEN CONVERT(BIGINT, 1) ELSE 0 END) AS UnrecoveredOrders,
    CONVERT(DECIMAL(9,4),
        SUM(CASE WHEN payment_outcome.LaterAttemptSucceeded = 1
                 THEN CONVERT(DECIMAL(38,6), 1) ELSE 0 END)
        / NULLIF(COUNT_BIG(*), 0)) AS PaymentRetrySuccessRate,
    AVG(CONVERT(DECIMAL(19,2), payment_outcome.MaximumAttemptNumber)) AS AverageMaximumAttemptNumber
FROM #PaymentOrderOutcome AS payment_outcome
INNER JOIN analytics.DimDate AS first_payment_date
    ON first_payment_date.DateKey = payment_outcome.FirstPaymentDateKey
WHERE payment_outcome.InitialAttemptFailed = 1
GROUP BY first_payment_date.YearMonthNumber, first_payment_date.MonthYearLabel
ORDER BY first_payment_date.YearMonthNumber;

/* ============================================================================
   8. RETURN REASON AND PRODUCT RISK
   ============================================================================ */

SELECT
    return_reason.ReturnReasonCode,
    return_reason.ReturnReasonName,
    COUNT_BIG(*) AS ReturnedLineCount,
    COUNT_BIG(DISTINCT fact_return.ProductReturnID) AS ReturnRequests,
    COUNT_BIG(DISTINCT fact_return.SalesOrderID) AS AffectedOrders,
    SUM(CONVERT(BIGINT, fact_return.QuantityRequested)) AS RequestedReturnUnits,
    SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnedUnits,
    SUM(fact_return.EligibleRefundAmount) AS EligibleRefundValue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), SUM(fact_return.QuantityAccepted))
        / NULLIF(SUM(fact_return.QuantityRequested), 0)) AS AcceptanceRate,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6),
        SUM(CASE WHEN fact_return.IsReusable = 1 THEN fact_return.QuantityAccepted ELSE 0 END))
        / NULLIF(SUM(fact_return.QuantityAccepted), 0)) AS ReusableReturnRate
FROM analytics.FactReturns AS fact_return
INNER JOIN analytics.DimReturnReason AS return_reason
    ON return_reason.ReturnReasonKey = fact_return.ReturnReasonKey
GROUP BY
    return_reason.ReturnReasonCode,
    return_reason.ReturnReasonName,
    return_reason.SortOrder
ORDER BY AcceptedReturnedUnits DESC, return_reason.SortOrder;

SELECT TOP (20)
    product_dimension.SKU,
    product_dimension.ProductName,
    product_dimension.BrandName,
    product_dimension.CategoryName,
    SUM(CONVERT(BIGINT, fact_return.QuantityRequested)) AS RequestedReturnUnits,
    SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnedUnits,
    SUM(fact_return.EligibleRefundAmount) AS EligibleRefundValue,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), SUM(fact_return.QuantityAccepted))
        / NULLIF
          (
              (SELECT SUM(CONVERT(BIGINT, fact_sales.Quantity))
               FROM analytics.FactSales AS fact_sales
               WHERE fact_sales.ProductKey = fact_return.ProductKey
                 AND fact_sales.IsDelivered = 1),
              0
          )) AS ProductReturnRate
FROM analytics.FactReturns AS fact_return
INNER JOIN analytics.DimProduct AS product_dimension
    ON product_dimension.ProductKey = fact_return.ProductKey
GROUP BY
    fact_return.ProductKey,
    product_dimension.SKU,
    product_dimension.ProductName,
    product_dimension.BrandName,
    product_dimension.CategoryName
ORDER BY ProductReturnRate DESC, AcceptedReturnedUnits DESC;

/* ============================================================================
   9. MONTHLY RETURN AND REFUND TREND
   Request volume uses request date. Refund cash uses refund date separately.
   ============================================================================ */

SELECT
    request_date.YearMonthNumber,
    request_date.MonthYearLabel,
    COUNT_BIG(DISTINCT fact_return.ProductReturnID) AS ReturnRequests,
    COUNT_BIG(DISTINCT fact_return.SalesOrderID) AS OrdersWithReturnRequests,
    SUM(CONVERT(BIGINT, fact_return.QuantityRequested)) AS RequestedReturnUnits,
    SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS AcceptedReturnedUnits,
    SUM(fact_return.EligibleRefundAmount) AS EligibleRefundValue
INTO #MonthlyReturn
FROM analytics.FactReturns AS fact_return
INNER JOIN analytics.DimDate AS request_date
    ON request_date.DateKey = fact_return.RequestDateKey
GROUP BY request_date.YearMonthNumber, request_date.MonthYearLabel;

CREATE UNIQUE CLUSTERED INDEX CIX_MonthlyReturn33
    ON #MonthlyReturn (YearMonthNumber);

SELECT * FROM #MonthlyReturn ORDER BY YearMonthNumber;

SELECT
    refund_date.YearMonthNumber,
    refund_date.MonthYearLabel,
    COUNT_BIG(*) AS RefundEvents,
    SUM(fact_refund.CompletedRefundAmount) AS CompletedRefundValue,
    SUM(fact_refund.PendingRefundAmount) AS PendingRefundValue,
    SUM(fact_refund.FailedRefundAmount) AS FailedRefundValue
FROM analytics.FactRefunds AS fact_refund
INNER JOIN analytics.DimDate AS refund_date
    ON refund_date.DateKey = fact_refund.RefundDateKey
GROUP BY refund_date.YearMonthNumber, refund_date.MonthYearLabel
ORDER BY refund_date.YearMonthNumber;

/* ============================================================================
   10. RETURN PROCESSING TIME AND STORE PERFORMANCE
   ============================================================================ */

SELECT
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier,
    COUNT_BIG(DISTINCT source_return.ProductReturnID) AS ReturnRequests,
    SUM(CONVERT(BIGINT, source_return_item.QuantityRequested)) AS RequestedReturnUnits,
    SUM(CONVERT(BIGINT, source_return_item.QuantityAccepted)) AS AcceptedReturnedUnits,
    CONVERT(DECIMAL(19,2), AVG(CONVERT(DECIMAL(19,2),
        DATEDIFF(MINUTE, source_return.RequestDate, source_return.ReceivedDate))) / 1440.0) AS AverageReceiptDays,
    CONVERT(DECIMAL(19,2), AVG(CONVERT(DECIMAL(19,2),
        DATEDIFF(MINUTE, source_return.RequestDate, source_return.ClosedDate))) / 1440.0) AS AverageClosureDays,
    CONVERT(DECIMAL(9,4), CONVERT(DECIMAL(38,6), SUM(source_return_item.QuantityAccepted))
        / NULLIF(SUM(source_return_item.QuantityRequested), 0)) AS AcceptanceRate
FROM sales.ProductReturn AS source_return
INNER JOIN sales.ProductReturnItem AS source_return_item
    ON source_return_item.ProductReturnID = source_return.ProductReturnID
INNER JOIN sales.SalesOrder AS source_order
    ON source_order.SalesOrderID = source_return.SalesOrderID
INNER JOIN analytics.DimStore AS store_dimension
    ON store_dimension.StoreID = source_order.StoreID
GROUP BY
    store_dimension.StoreCode,
    store_dimension.StoreName,
    store_dimension.StoreTier
ORDER BY ReturnRequests DESC, store_dimension.StoreCode;

/* ============================================================================
   11. RETURNS AND PAYMENTS VALIDATION
   ============================================================================ */

DECLARE @ReturnsPaymentsValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(110) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

INSERT INTO @ReturnsPaymentsValidation VALUES
(1, 'Payment attempts reconcile to payment fact',
 ABS(@PaymentAttempts - (SELECT COUNT_BIG(*) FROM analytics.FactPayments)),
 CASE WHEN @PaymentAttempts = (SELECT COUNT_BIG(*) FROM analytics.FactPayments)
      THEN 'PASSED' ELSE 'FAILED' END),
(2, 'Payment outcome flags do not overlap',
 (SELECT COUNT_BIG(*) FROM analytics.FactPayments
  WHERE CONVERT(INT, IsSuccessful) + CONVERT(INT, IsFailed) + CONVERT(INT, IsPending) > 1),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM analytics.FactPayments
       WHERE CONVERT(INT, IsSuccessful) + CONVERT(INT, IsFailed) + CONVERT(INT, IsPending) > 1)
      THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Successful, failed and pending attempts fit total attempts',
 CASE WHEN @SuccessfulAttempts + @FailedAttempts + @PendingAttempts <= @PaymentAttempts
      THEN 0 ELSE 1 END,
 CASE WHEN @SuccessfulAttempts + @FailedAttempts + @PendingAttempts <= @PaymentAttempts
      THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Accepted return units do not exceed requested units',
 CASE WHEN @AcceptedReturnedUnits <= @RequestedReturnUnits THEN 0 ELSE 1 END,
 CASE WHEN @AcceptedReturnedUnits <= @RequestedReturnUnits THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Accepted return units do not exceed delivered units',
 CASE WHEN @AcceptedReturnedUnits <= @DeliveredUnits THEN 0 ELSE 1 END,
 CASE WHEN @AcceptedReturnedUnits <= @DeliveredUnits THEN 'PASSED' ELSE 'FAILED' END),
(6, 'Reusable return units do not exceed accepted units',
 CASE WHEN @ReusableReturnedUnits <= @AcceptedReturnedUnits THEN 0 ELSE 1 END,
 CASE WHEN @ReusableReturnedUnits <= @AcceptedReturnedUnits THEN 'PASSED' ELSE 'FAILED' END),
(7, 'Refund status value components reconcile',
 (SELECT COUNT_BIG(*) FROM analytics.FactRefunds
  WHERE RefundAmount <> CompletedRefundAmount + PendingRefundAmount + FailedRefundAmount),
 CASE WHEN NOT EXISTS
      (SELECT 1 FROM analytics.FactRefunds
       WHERE RefundAmount <> CompletedRefundAmount + PendingRefundAmount + FailedRefundAmount)
      THEN 'PASSED' ELSE 'FAILED' END),
(8, 'Monthly payment attempts reconcile',
 ABS(@PaymentAttempts - (SELECT COALESCE(SUM(PaymentAttempts), 0) FROM #MonthlyPayment)),
 CASE WHEN @PaymentAttempts = (SELECT COALESCE(SUM(PaymentAttempts), 0) FROM #MonthlyPayment)
      THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @ReturnsPaymentsValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @ReturnsPaymentsValidation WHERE ValidationStatus = 'FAILED')
    THROW 51533, 'Returns and payments analysis validation failed. Review the final validation result set.', 1;

RAISERROR('33_Returns_Payments_Analysis.sql completed successfully: payment, return and refund analyses validated.', 10, 1) WITH NOWAIT;
GO
