/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      19_Generate_Payments.sql
Purpose:     Generate 108,000 deterministic payment attempts and retry journeys.
Author:      Akshay Aswani
Version:     2.0
Depends on:  18_Generate_Order_Lifecycle.sql
Rerunnable:  Yes, until returns, refunds, or downstream inventory facts exist.

Payment design
--------------
- 80,000 completed orders succeed on the first attempt.
- 8,000 completed orders have two failed attempts followed by success.
- 2,000 open orders retain an initiated or pending attempt at snapshot.
- 2,000 cancelled orders retain a cancelled attempt.
- 8,000 orders were cancelled before a payment attempt was created.
- Total payment attempts: 108,000.

Payment-method mix across attempts
----------------------------------
- UPI 35%, Credit Card 20%, Debit Card 16%, Cash 15%,
  Net Banking 8%, Digital Wallet 6%.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51320, 'Payment generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'sales.Payment', N'U') IS NULL
   OR OBJECT_ID(N'sales.SalesOrder', N'U') IS NULL
   OR OBJECT_ID(N'ref.PaymentMethod', N'U') IS NULL
   OR OBJECT_ID(N'ref.PaymentStatus', N'U') IS NULL
BEGIN
    THROW 51321, 'Payment generation stopped: one or more required tables are missing.', 1;
END;

IF (SELECT COUNT_BIG(*) FROM sales.SalesOrder) <> 100000
   OR (SELECT COUNT(*) FROM ref.PaymentMethod WHERE IsActive = 1) <> 6
   OR (SELECT COUNT(*) FROM ref.PaymentStatus WHERE IsActive = 1) <> 7
BEGIN
    THROW 51322, 'Payment generation stopped: approved order or payment-reference counts are missing.', 1;
END;

DECLARE @OpeningMovementTypeID SMALLINT;

SELECT @OpeningMovementTypeID = InventoryMovementTypeID
FROM ref.InventoryMovementType
WHERE InventoryMovementTypeCode = 'OPENING_STOCK' AND IsActive = 1;

IF @OpeningMovementTypeID IS NULL
BEGIN
    THROW 51323, 'Payment generation stopped: Opening Stock reference is missing.', 1;
END;

IF EXISTS (SELECT 1 FROM sales.ProductReturn)
   OR EXISTS (SELECT 1 FROM sales.Refund)
   OR EXISTS
      (
          SELECT 1
          FROM inventory.InventoryMovement
          WHERE InventoryMovementTypeID <> @OpeningMovementTypeID
      )
BEGIN
    THROW 51324, 'Payments cannot be rebuilt after return, refund, or downstream inventory facts exist.', 1;
END;

DROP TABLE IF EXISTS #PaymentMethodMap;
DROP TABLE IF EXISTS #PaymentStatusMap;
DROP TABLE IF EXISTS #OrderPaymentSchedule;
DROP TABLE IF EXISTS #AttemptSlot;
DROP TABLE IF EXISTS #PaymentSeed;

CREATE TABLE #PaymentMethodMap
(
    PaymentMethodCode VARCHAR(30) NOT NULL PRIMARY KEY,
    PaymentMethodID SMALLINT NOT NULL UNIQUE
);

INSERT INTO #PaymentMethodMap (PaymentMethodCode, PaymentMethodID)
SELECT PaymentMethodCode, PaymentMethodID
FROM ref.PaymentMethod
WHERE IsActive = 1;

CREATE TABLE #PaymentStatusMap
(
    PaymentStatusCode VARCHAR(30) NOT NULL PRIMARY KEY,
    PaymentStatusID SMALLINT NOT NULL UNIQUE
);

INSERT INTO #PaymentStatusMap (PaymentStatusCode, PaymentStatusID)
SELECT PaymentStatusCode, PaymentStatusID
FROM ref.PaymentStatus
WHERE IsActive = 1;

CREATE TABLE #OrderPaymentSchedule
(
    SalesOrderID BIGINT NOT NULL PRIMARY KEY,
    OrderSequence INT NOT NULL UNIQUE,
    OrderNumber VARCHAR(25) NOT NULL,
    OrderStatusCode VARCHAR(30) NOT NULL,
    OrderDate DATETIME2(0) NOT NULL,
    ConfirmedDate DATETIME2(0) NULL,
    CancelledDate DATETIME2(0) NULL,
    NetAmount DECIMAL(14,2) NOT NULL,
    PaymentJourney VARCHAR(20) NOT NULL,
    AttemptCount TINYINT NOT NULL
);

;WITH ClassifiedOrders AS
(
    SELECT
        orders.SalesOrderID,
        CONVERT(INT, RIGHT(orders.OrderNumber, 8)) AS OrderSequence,
        orders.OrderNumber,
        status.OrderStatusCode,
        orders.OrderDate,
        orders.ConfirmedDate,
        orders.CancelledDate,
        orders.NetAmount,
        CASE WHEN status.OrderStatusCode IN
            ('DELIVERED','PARTIALLY_RETURNED','RETURNED') THEN 1 ELSE 0 END AS IsPayable,
        CASE WHEN status.OrderStatusCode = 'CANCELLED' THEN 1 ELSE 0 END AS IsCancelled,
        CASE WHEN status.OrderStatusCode IN
            ('PENDING','CONFIRMED','PROCESSING','SHIPPED') THEN 1 ELSE 0 END AS IsOpen
    FROM sales.SalesOrder AS orders
    INNER JOIN ref.OrderStatus AS status ON status.OrderStatusID = orders.OrderStatusID
),
RankedOrders AS
(
    SELECT
        classified.*,
        CASE WHEN classified.IsPayable = 1 THEN
            ROW_NUMBER() OVER
            (
                PARTITION BY classified.IsPayable
                ORDER BY
                    ABS(CONVERT(BIGINT, CHECKSUM(classified.OrderNumber, 20260921))),
                    classified.OrderNumber
            )
        END AS PayableRank,
        CASE WHEN classified.IsCancelled = 1 THEN
            ROW_NUMBER() OVER
            (
                PARTITION BY classified.IsCancelled
                ORDER BY
                    ABS(CONVERT(BIGINT, CHECKSUM(classified.OrderNumber, 19001))),
                    classified.OrderNumber
            )
        END AS CancelledRank
    FROM ClassifiedOrders AS classified
)
INSERT INTO #OrderPaymentSchedule
(
    SalesOrderID, OrderSequence, OrderNumber, OrderStatusCode,
    OrderDate, ConfirmedDate, CancelledDate, NetAmount,
    PaymentJourney, AttemptCount
)
SELECT
    ranked.SalesOrderID,
    ranked.OrderSequence,
    ranked.OrderNumber,
    ranked.OrderStatusCode,
    ranked.OrderDate,
    ranked.ConfirmedDate,
    ranked.CancelledDate,
    ranked.NetAmount,
    CASE
        WHEN ranked.IsPayable = 1 AND ranked.PayableRank <= 8000 THEN 'RETRY_SUCCESS'
        WHEN ranked.IsPayable = 1 THEN 'FIRST_SUCCESS'
        WHEN ranked.IsOpen = 1 THEN 'OPEN_ATTEMPT'
        ELSE 'CANCELLED_ATTEMPT'
    END,
    CASE
        WHEN ranked.IsPayable = 1 AND ranked.PayableRank <= 8000 THEN 3
        ELSE 1
    END
FROM RankedOrders AS ranked
WHERE ranked.IsPayable = 1
   OR ranked.IsOpen = 1
   OR (ranked.IsCancelled = 1 AND ranked.CancelledRank <= 2000);

IF (SELECT COUNT(*) FROM #OrderPaymentSchedule) <> 92000
   OR (SELECT SUM(CONVERT(INT, AttemptCount)) FROM #OrderPaymentSchedule) <> 108000
   OR (SELECT COUNT(*) FROM #OrderPaymentSchedule WHERE PaymentJourney = 'RETRY_SUCCESS') <> 8000
BEGIN
    THROW 51325, 'Payment-schedule generation failed to produce approved order and attempt counts.', 1;
END;

CREATE TABLE #AttemptSlot (AttemptNumber TINYINT NOT NULL PRIMARY KEY);
INSERT INTO #AttemptSlot VALUES (1),(2),(3);

CREATE TABLE #PaymentSeed
(
    PaymentSequence INT NOT NULL PRIMARY KEY,
    SalesOrderID BIGINT NOT NULL,
    OrderNumber VARCHAR(25) NOT NULL,
    AttemptNumber SMALLINT NOT NULL,
    PaymentMethodCode VARCHAR(30) NOT NULL,
    PaymentStatusCode VARCHAR(30) NOT NULL,
    PaymentDate DATETIME2(0) NOT NULL,
    Amount DECIMAL(14,2) NOT NULL,
    TransactionReference VARCHAR(100) NULL,
    FailureReason VARCHAR(255) NULL,
    Remarks VARCHAR(255) NOT NULL,
    UNIQUE (SalesOrderID, AttemptNumber)
);

;WITH AttemptRows AS
(
    SELECT
        pmt.*,
        slot.AttemptNumber,
        ROW_NUMBER() OVER
        (
            ORDER BY pmt.OrderSequence, slot.AttemptNumber
        ) AS PaymentSequence
    FROM #OrderPaymentSchedule AS pmt
    INNER JOIN #AttemptSlot AS slot
        ON slot.AttemptNumber <= pmt.AttemptCount
),
AttemptMethods AS
(
    SELECT
        attempt.*,
        CASE
            WHEN ((attempt.PaymentSequence - 1) % 100) + 1 <= 35 THEN 'UPI'
            WHEN ((attempt.PaymentSequence - 1) % 100) + 1 <= 55 THEN 'CREDIT_CARD'
            WHEN ((attempt.PaymentSequence - 1) % 100) + 1 <= 71 THEN 'DEBIT_CARD'
            WHEN ((attempt.PaymentSequence - 1) % 100) + 1 <= 86 THEN 'CASH'
            WHEN ((attempt.PaymentSequence - 1) % 100) + 1 <= 94 THEN 'NET_BANKING'
            ELSE 'WALLET'
        END AS PaymentMethodCode,
        CASE
            WHEN attempt.PaymentJourney = 'RETRY_SUCCESS'
             AND attempt.AttemptNumber IN (1, 2) THEN 'FAILED'
            WHEN attempt.PaymentJourney IN ('RETRY_SUCCESS','FIRST_SUCCESS') THEN 'COMPLETED'
            WHEN attempt.PaymentJourney = 'CANCELLED_ATTEMPT' THEN 'CANCELLED'
            WHEN attempt.OrderStatusCode IN ('PENDING','CONFIRMED') THEN 'INITIATED'
            ELSE 'PENDING'
        END AS PaymentStatusCode
    FROM AttemptRows AS attempt
)
INSERT INTO #PaymentSeed
(
    PaymentSequence, SalesOrderID, OrderNumber, AttemptNumber,
    PaymentMethodCode, PaymentStatusCode, PaymentDate, Amount,
    TransactionReference, FailureReason, Remarks
)
SELECT
    CONVERT(INT, attempt.PaymentSequence),
    attempt.SalesOrderID,
    attempt.OrderNumber,
    attempt.AttemptNumber,
    attempt.PaymentMethodCode,
    attempt.PaymentStatusCode,
    DATEADD
    (
        MINUTE,
        CASE attempt.AttemptNumber WHEN 1 THEN 5 WHEN 2 THEN 35 ELSE 75 END,
        attempt.OrderDate
    ),
    attempt.NetAmount,
    CASE
        WHEN attempt.PaymentMethodCode = 'CASH' THEN NULL
        ELSE CONCAT(
            'TXN-', attempt.OrderNumber, '-A',
            CONVERT(VARCHAR(2), attempt.AttemptNumber)
        )
    END,
    CASE
        WHEN attempt.PaymentStatusCode = 'FAILED' THEN
            CASE attempt.OrderSequence % 4
                WHEN 0 THEN 'Issuer declined the synthetic transaction'
                WHEN 1 THEN 'Synthetic network timeout'
                WHEN 2 THEN 'Synthetic authentication failure'
                ELSE 'Synthetic insufficient-funds response'
            END
        ELSE NULL
    END,
    CASE attempt.PaymentJourney
        WHEN 'RETRY_SUCCESS' THEN 'Synthetic retry-payment journey'
        WHEN 'FIRST_SUCCESS' THEN 'Synthetic first-attempt payment success'
        WHEN 'OPEN_ATTEMPT' THEN 'Synthetic payment open at reporting snapshot'
        ELSE 'Synthetic payment cancelled with order'
    END
FROM AttemptMethods AS attempt;

IF (SELECT COUNT(*) FROM #PaymentSeed) <> 108000
   OR EXISTS (SELECT 1 FROM #PaymentSeed WHERE Amount <= 0)
BEGIN
    THROW 51326, 'Payment seed validation failed before loading.', 1;
END;

IF EXISTS
(
    SELECT TransactionReference
    FROM #PaymentSeed
    WHERE TransactionReference IS NOT NULL
    GROUP BY TransactionReference
    HAVING COUNT(*) > 1
)
BEGIN
    THROW 51333, 'Payment seed validation failed: duplicate transaction reference detected.', 1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Safe deterministic rebuild because all downstream facts were blocked above.
    DELETE FROM sales.Payment;

    INSERT INTO sales.Payment
    (
        SalesOrderID, PaymentMethodID, PaymentStatusID, AttemptNumber,
        PaymentDate, Amount, TransactionReference,
        FailureReason, Remarks
    )
    SELECT
        seed.SalesOrderID,
        method.PaymentMethodID,
        status.PaymentStatusID,
        seed.AttemptNumber,
        seed.PaymentDate,
        seed.Amount,
        seed.TransactionReference,
        seed.FailureReason,
        seed.Remarks
    FROM #PaymentSeed AS seed
    INNER JOIN #PaymentMethodMap AS method
        ON method.PaymentMethodCode = seed.PaymentMethodCode
    INNER JOIN #PaymentStatusMap AS status
        ON status.PaymentStatusCode = seed.PaymentStatusCode;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @PaymentCount BIGINT = (SELECT COUNT_BIG(*) FROM sales.Payment);

IF @PaymentCount <> 108000
BEGIN
    THROW 51327, 'Payment validation failed: expected exactly 108,000 attempts.', 1;
END;

IF EXISTS
(
    SELECT method.PaymentMethodCode
    FROM sales.Payment AS payment
    INNER JOIN ref.PaymentMethod AS method ON method.PaymentMethodID = payment.PaymentMethodID
    GROUP BY method.PaymentMethodCode
    HAVING COUNT(*) <>
        CASE method.PaymentMethodCode
            WHEN 'UPI' THEN 37800
            WHEN 'CREDIT_CARD' THEN 21600
            WHEN 'DEBIT_CARD' THEN 17280
            WHEN 'CASH' THEN 16200
            WHEN 'NET_BANKING' THEN 8640
            WHEN 'WALLET' THEN 6480
        END
)
BEGIN
    THROW 51334, 'Payment validation failed: payment-method distribution differs from design.', 1;
END;

IF EXISTS
(
    SELECT status.PaymentStatusCode
    FROM sales.Payment AS payment
    INNER JOIN ref.PaymentStatus AS status ON status.PaymentStatusID = payment.PaymentStatusID
    GROUP BY status.PaymentStatusCode
    HAVING COUNT(*) <>
        CASE status.PaymentStatusCode
            WHEN 'COMPLETED' THEN 88000
            WHEN 'FAILED' THEN 16000
            WHEN 'PENDING' THEN 1600
            WHEN 'INITIATED' THEN 400
            WHEN 'CANCELLED' THEN 2000
            ELSE 0
        END
)
BEGIN
    THROW 51335, 'Payment validation failed: payment-status distribution differs from design.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sales.Payment AS payment
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = payment.SalesOrderID
    WHERE payment.PaymentDate < orders.OrderDate
       OR payment.Amount <> orders.NetAmount
)
BEGIN
    THROW 51328, 'Payment validation failed: invalid date or attempted amount.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sales.Payment AS payment
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = payment.SalesOrderID
    INNER JOIN ref.OrderStatus AS order_status ON order_status.OrderStatusID = orders.OrderStatusID
    INNER JOIN ref.PaymentStatus AS payment_status ON payment_status.PaymentStatusID = payment.PaymentStatusID
    WHERE order_status.OrderStatusCode = 'CANCELLED'
      AND payment_status.PaymentStatusCode IN ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
)
BEGIN
    THROW 51329, 'Payment validation failed: cancelled order retains a collected payment.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sales.SalesOrder AS orders
    LEFT JOIN
    (
        SELECT
            payment.SalesOrderID,
            SUM(CASE WHEN status.PaymentStatusCode IN
                ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
                THEN payment.Amount ELSE 0 END) AS CollectedAmount
        FROM sales.Payment AS payment
        INNER JOIN ref.PaymentStatus AS status
            ON status.PaymentStatusID = payment.PaymentStatusID
        GROUP BY payment.SalesOrderID
    ) AS collection ON collection.SalesOrderID = orders.SalesOrderID
    WHERE COALESCE(collection.CollectedAmount, 0) > orders.NetAmount
)
BEGIN
    THROW 51330, 'Payment validation failed: collected amount exceeds order net amount.', 1;
END;

IF
(
    SELECT COUNT(*)
    FROM
    (
        SELECT
            payment.SalesOrderID,
            COUNT(*) AS AttemptCount,
            SUM(CASE WHEN status.PaymentStatusCode = 'FAILED' THEN 1 ELSE 0 END) AS FailedCount,
            SUM(CASE WHEN status.PaymentStatusCode = 'COMPLETED' THEN 1 ELSE 0 END) AS CompletedCount,
            MIN(payment.AttemptNumber) AS MinimumAttempt,
            MAX(payment.AttemptNumber) AS MaximumAttempt
        FROM sales.Payment AS payment
        INNER JOIN ref.PaymentStatus AS status
            ON status.PaymentStatusID = payment.PaymentStatusID
        GROUP BY payment.SalesOrderID
        HAVING COUNT(*) = 3
           AND SUM(CASE WHEN status.PaymentStatusCode = 'FAILED' THEN 1 ELSE 0 END) = 2
           AND SUM(CASE WHEN status.PaymentStatusCode = 'COMPLETED' THEN 1 ELSE 0 END) = 1
           AND MIN(payment.AttemptNumber) = 1
           AND MAX(payment.AttemptNumber) = 3
    ) AS retry
) <> 8000
BEGIN
    THROW 51331, 'Payment validation failed: expected 8,000 failed-first retry journeys.', 1;
END;

IF NOT EXISTS
(
    SELECT payment.SalesOrderID
    FROM sales.Payment AS payment
    INNER JOIN ref.PaymentMethod AS method ON method.PaymentMethodID = payment.PaymentMethodID
    GROUP BY payment.SalesOrderID
    HAVING COUNT(*) > 1 AND COUNT(DISTINCT method.PaymentMethodCode) > 1
)
BEGIN
    THROW 51332, 'Payment validation failed: method-change retry edge case is missing.', 1;
END;

SELECT
    method.PaymentMethodCode,
    method.PaymentMethodName,
    COUNT_BIG(*) AS PaymentAttemptCount,
    CAST(100.0 * COUNT_BIG(*) / @PaymentCount AS DECIMAL(5,2)) AS AttemptSharePercent,
    SUM(payment.Amount) AS AttemptedValue,
    'PASSED' AS ValidationStatus
FROM sales.Payment AS payment
INNER JOIN ref.PaymentMethod AS method ON method.PaymentMethodID = payment.PaymentMethodID
GROUP BY method.PaymentMethodCode, method.PaymentMethodName, method.SortOrder
ORDER BY method.SortOrder;

SELECT
    status.PaymentStatusCode,
    status.PaymentStatusName,
    COUNT_BIG(*) AS PaymentAttemptCount,
    SUM(payment.Amount) AS AttemptedValue,
    CASE WHEN status.PaymentStatusCode IN ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
         THEN SUM(payment.Amount) ELSE 0 END AS CollectedValue,
    'PASSED' AS ValidationStatus
FROM sales.Payment AS payment
INNER JOIN ref.PaymentStatus AS status ON status.PaymentStatusID = payment.PaymentStatusID
GROUP BY status.PaymentStatusCode, status.PaymentStatusName, status.SortOrder
ORDER BY status.SortOrder;

SELECT
    @PaymentCount AS PaymentAttemptCount,
    COUNT(DISTINCT payment.SalesOrderID) AS OrdersWithPaymentAttempts,
    COUNT(DISTINCT CASE WHEN status.PaymentStatusCode = 'COMPLETED'
                        THEN payment.SalesOrderID END) AS SuccessfullyPaidOrders,
    SUM(CASE WHEN status.PaymentStatusCode = 'COMPLETED'
             THEN payment.Amount ELSE 0 END) AS CollectedValue,
    SUM(CASE WHEN status.PaymentStatusCode = 'FAILED' THEN 1 ELSE 0 END) AS FailedAttemptCount,
    COUNT(DISTINCT CASE WHEN payment.AttemptNumber = 3
                        AND status.PaymentStatusCode = 'COMPLETED'
                        THEN payment.SalesOrderID END) AS RetrySuccessOrderCount,
    CASE
        WHEN @PaymentCount = 108000
         AND COUNT(DISTINCT payment.SalesOrderID) = 92000
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM sales.Payment AS payment
INNER JOIN ref.PaymentStatus AS status ON status.PaymentStatusID = payment.PaymentStatusID;

RAISERROR('19_Generate_Payments.sql completed successfully: 108,000 payment attempts and 8,000 retry journeys validated.', 10, 1) WITH NOWAIT;
GO
