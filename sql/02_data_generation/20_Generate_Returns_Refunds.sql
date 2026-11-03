/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      20_Generate_Returns_Refunds.sql
Purpose:     Generate controlled returns, return items, and connected refunds.
Author:      Akshay Aswani
Version:     2.0
Depends on:  19_Generate_Payments.sql
Rerunnable:  Yes, until downstream inventory movements exist.

Return-request design
---------------------
- 10,000 accepted requests support the existing order lifecycle:
  5,000 partially returned orders and 5,000 fully returned orders.
- 2,195 rejected requests are selected from otherwise delivered orders.
- 12,195 total requests produce approximately 72% fully accepted,
  10% partially accepted, and 18% rejected outcomes.
- Refund outcomes across accepted requests: 94% completed, 4% pending, 2% failed.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51340, 'Return generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'sales.ProductReturn', N'U') IS NULL
   OR OBJECT_ID(N'sales.ProductReturnItem', N'U') IS NULL
   OR OBJECT_ID(N'sales.Refund', N'U') IS NULL
   OR OBJECT_ID(N'sales.Payment', N'U') IS NULL
BEGIN
    THROW 51341, 'Return generation stopped: one or more required tables are missing.', 1;
END;

IF (SELECT COUNT_BIG(*) FROM sales.SalesOrder) <> 100000
   OR (SELECT COUNT_BIG(*) FROM sales.Payment) <> 108000
   OR (SELECT COUNT(*) FROM ref.ReturnReason WHERE IsActive = 1) <> 7
   OR (SELECT COUNT(*) FROM ref.ReturnStatus WHERE IsActive = 1) <> 6
BEGIN
    THROW 51342, 'Return generation stopped: approved upstream or reference counts are missing.', 1;
END;

DECLARE @OpeningMovementTypeID SMALLINT;
DECLARE @CompletedPaymentStatusID SMALLINT;
DECLARE @PartiallyRefundedPaymentStatusID SMALLINT;
DECLARE @RefundedPaymentStatusID SMALLINT;
DECLARE @PartiallyReturnedOrderStatusID SMALLINT;
DECLARE @ReturnedOrderStatusID SMALLINT;

SELECT @OpeningMovementTypeID = InventoryMovementTypeID
FROM ref.InventoryMovementType
WHERE InventoryMovementTypeCode = 'OPENING_STOCK' AND IsActive = 1;

SELECT @CompletedPaymentStatusID = PaymentStatusID
FROM ref.PaymentStatus WHERE PaymentStatusCode = 'COMPLETED';
SELECT @PartiallyRefundedPaymentStatusID = PaymentStatusID
FROM ref.PaymentStatus WHERE PaymentStatusCode = 'PARTIALLY_REFUNDED';
SELECT @RefundedPaymentStatusID = PaymentStatusID
FROM ref.PaymentStatus WHERE PaymentStatusCode = 'REFUNDED';
SELECT @PartiallyReturnedOrderStatusID = OrderStatusID
FROM ref.OrderStatus WHERE OrderStatusCode = 'PARTIALLY_RETURNED';
SELECT @ReturnedOrderStatusID = OrderStatusID
FROM ref.OrderStatus WHERE OrderStatusCode = 'RETURNED';

IF @OpeningMovementTypeID IS NULL
   OR @CompletedPaymentStatusID IS NULL
   OR @PartiallyRefundedPaymentStatusID IS NULL
   OR @RefundedPaymentStatusID IS NULL
   OR @PartiallyReturnedOrderStatusID IS NULL
   OR @ReturnedOrderStatusID IS NULL
BEGIN
    THROW 51343, 'Return generation stopped: a required status reference is missing.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM inventory.InventoryMovement
    WHERE InventoryMovementTypeID <> @OpeningMovementTypeID
)
BEGIN
    THROW 51344, 'Returns cannot be rebuilt after downstream inventory movements exist.', 1;
END;

DROP TABLE IF EXISTS #StatusSwap;
DROP TABLE IF EXISTS #EffectiveOrder;
DROP TABLE IF EXISTS #ReturnHeaderSeed;
DROP TABLE IF EXISTS #ReturnItemSeed;
DROP TABLE IF EXISTS #RefundSeed;

-- ============================================================================
-- 1. ELIGIBILITY REBALANCING FOR TRUE PARTIAL RETURNS
-- ============================================================================

CREATE TABLE #StatusSwap
(
    SalesOrderID BIGINT NOT NULL PRIMARY KEY,
    NewStatusCode VARCHAR(30) NOT NULL
);

;WITH OrderUnits AS
(
    SELECT item.SalesOrderID, SUM(item.Quantity) AS TotalUnits
    FROM sales.SalesOrderItem AS item
    GROUP BY item.SalesOrderID
),
InvalidPartial AS
(
    SELECT
        orders.SalesOrderID,
        ROW_NUMBER() OVER (ORDER BY orders.OrderNumber) AS SwapRank
    FROM sales.SalesOrder AS orders
    INNER JOIN ref.OrderStatus AS status ON status.OrderStatusID = orders.OrderStatusID
    INNER JOIN OrderUnits AS units ON units.SalesOrderID = orders.SalesOrderID
    WHERE status.OrderStatusCode = 'PARTIALLY_RETURNED'
      AND units.TotalUnits = 1
),
ReplacementReturned AS
(
    SELECT
        orders.SalesOrderID,
        ROW_NUMBER() OVER
        (
            ORDER BY ABS(CONVERT(BIGINT, CHECKSUM(orders.OrderNumber, 20401))), orders.OrderNumber
        ) AS SwapRank
    FROM sales.SalesOrder AS orders
    INNER JOIN ref.OrderStatus AS status ON status.OrderStatusID = orders.OrderStatusID
    INNER JOIN OrderUnits AS units ON units.SalesOrderID = orders.SalesOrderID
    WHERE status.OrderStatusCode = 'RETURNED'
      AND units.TotalUnits > 1
)
INSERT INTO #StatusSwap (SalesOrderID, NewStatusCode)
SELECT SalesOrderID, 'RETURNED' FROM InvalidPartial
UNION ALL
SELECT replacement.SalesOrderID, 'PARTIALLY_RETURNED'
FROM ReplacementReturned AS replacement
WHERE replacement.SwapRank <= (SELECT COUNT(*) FROM InvalidPartial);

IF
(
    SELECT COUNT(*) FROM #StatusSwap WHERE NewStatusCode = 'RETURNED'
) <>
(
    SELECT COUNT(*) FROM #StatusSwap WHERE NewStatusCode = 'PARTIALLY_RETURNED'
)
BEGIN
    THROW 51345, 'Return eligibility rebalance failed to preserve lifecycle status counts.', 1;
END;

CREATE TABLE #EffectiveOrder
(
    SalesOrderID BIGINT NOT NULL PRIMARY KEY,
    OrderSequence INT NOT NULL,
    OrderNumber VARCHAR(25) NOT NULL,
    EffectiveStatusCode VARCHAR(30) NOT NULL,
    DeliveredDate DATETIME2(0) NULL,
    NetAmount DECIMAL(14,2) NOT NULL,
    FinalLifecycleDate DATETIME2(0) NOT NULL
);

;WITH LatestHistory AS
(
    SELECT
        history.SalesOrderID,
        history.StatusChangedDate,
        ROW_NUMBER() OVER
        (
            PARTITION BY history.SalesOrderID
            ORDER BY history.StatusChangedDate DESC, history.OrderStatusHistoryID DESC
        ) AS LatestRank
    FROM sales.OrderStatusHistory AS history
)
INSERT INTO #EffectiveOrder
(
    SalesOrderID, OrderSequence, OrderNumber, EffectiveStatusCode,
    DeliveredDate, NetAmount, FinalLifecycleDate
)
SELECT
    orders.SalesOrderID,
    CONVERT(INT, RIGHT(orders.OrderNumber, 8)),
    orders.OrderNumber,
    COALESCE(swap.NewStatusCode, status.OrderStatusCode),
    orders.DeliveredDate,
    orders.NetAmount,
    latest.StatusChangedDate
FROM sales.SalesOrder AS orders
INNER JOIN ref.OrderStatus AS status ON status.OrderStatusID = orders.OrderStatusID
LEFT JOIN #StatusSwap AS swap ON swap.SalesOrderID = orders.SalesOrderID
INNER JOIN LatestHistory AS latest
    ON latest.SalesOrderID = orders.SalesOrderID
   AND latest.LatestRank = 1;

IF (SELECT COUNT(*) FROM #EffectiveOrder WHERE EffectiveStatusCode = 'PARTIALLY_RETURNED') <> 5000
   OR (SELECT COUNT(*) FROM #EffectiveOrder WHERE EffectiveStatusCode = 'RETURNED') <> 5000
BEGIN
    THROW 51346, 'Return eligibility rebalance changed approved lifecycle totals.', 1;
END;

-- ============================================================================
-- 2. RETURN HEADER SEED: ACCEPTED AND REJECTED REQUESTS
-- ============================================================================

CREATE TABLE #ReturnHeaderSeed
(
    ReturnSequence INT NOT NULL PRIMARY KEY,
    ReturnNumber VARCHAR(25) NOT NULL UNIQUE,
    SalesOrderID BIGINT NOT NULL UNIQUE,
    OrderSequence INT NOT NULL,
    OrderOutcome VARCHAR(30) NOT NULL,
    RequestOutcome VARCHAR(20) NOT NULL,
    RefundStatus VARCHAR(20) NULL,
    ReturnStatusCode VARCHAR(30) NOT NULL,
    RequestDate DATETIME2(0) NOT NULL,
    ApprovedDate DATETIME2(0) NULL,
    ReceivedDate DATETIME2(0) NULL,
    ClosedDate DATETIME2(0) NULL
);

;WITH AcceptedOrders AS
(
    SELECT
        effective.*,
        ROW_NUMBER() OVER
        (
            ORDER BY ABS(CONVERT(BIGINT, CHECKSUM(effective.OrderNumber, 20501))), effective.OrderNumber
        ) AS AcceptedRank,
        CASE WHEN effective.EffectiveStatusCode = 'PARTIALLY_RETURNED' THEN
            ROW_NUMBER() OVER
            (
                PARTITION BY effective.EffectiveStatusCode
                ORDER BY ABS(CONVERT(BIGINT, CHECKSUM(effective.OrderNumber, 20502))), effective.OrderNumber
            )
        END AS PartialOrderRank
    FROM #EffectiveOrder AS effective
    WHERE effective.EffectiveStatusCode IN ('PARTIALLY_RETURNED','RETURNED')
),
RejectedOrders AS
(
    SELECT TOP (2195)
        effective.*
    FROM #EffectiveOrder AS effective
    WHERE effective.EffectiveStatusCode = 'DELIVERED'
      AND effective.DeliveredDate <= '2026-06-20T23:59:59'
    ORDER BY ABS(CONVERT(BIGINT, CHECKSUM(effective.OrderNumber, 20503))), effective.OrderNumber
),
AllRequests AS
(
    SELECT
        accepted.SalesOrderID,
        accepted.OrderSequence,
        accepted.OrderNumber,
        accepted.EffectiveStatusCode AS OrderOutcome,
        CASE
            WHEN accepted.EffectiveStatusCode = 'PARTIALLY_RETURNED'
             AND accepted.PartialOrderRank <= 1220 THEN 'PARTIAL_ACCEPT'
            ELSE 'FULL_ACCEPT'
        END AS RequestOutcome,
        CASE
            WHEN accepted.AcceptedRank <= 9400 THEN 'Completed'
            WHEN accepted.AcceptedRank <= 9800 THEN 'Pending'
            ELSE 'Failed'
        END AS RefundStatus,
        CASE
            WHEN accepted.AcceptedRank <= 9400 THEN 'REFUNDED'
            WHEN accepted.AcceptedRank <= 9800 THEN 'RECEIVED'
            ELSE 'CLOSED'
        END AS ReturnStatusCode,
        DATEADD(DAY, 1, accepted.DeliveredDate) AS RequestDate,
        DATEADD(DAY, 2, accepted.DeliveredDate) AS ApprovedDate,
        accepted.FinalLifecycleDate AS ReceivedDate,
        CASE WHEN accepted.AcceptedRank <= 9400 OR accepted.AcceptedRank > 9800
             THEN accepted.FinalLifecycleDate ELSE NULL END AS ClosedDate
    FROM AcceptedOrders AS accepted

    UNION ALL

    SELECT
        rejected.SalesOrderID,
        rejected.OrderSequence,
        rejected.OrderNumber,
        rejected.EffectiveStatusCode,
        'REJECTED',
        NULL,
        'REJECTED',
        DATEADD(DAY, 3 + (rejected.OrderSequence % 5), rejected.DeliveredDate),
        NULL,
        NULL,
        DATEADD(DAY, 5 + (rejected.OrderSequence % 5), rejected.DeliveredDate)
    FROM RejectedOrders AS rejected
),
SequencedRequests AS
(
    SELECT
        request.*,
        ROW_NUMBER() OVER (ORDER BY request.OrderSequence) AS ReturnSequence
    FROM AllRequests AS request
)
INSERT INTO #ReturnHeaderSeed
(
    ReturnSequence, ReturnNumber, SalesOrderID, OrderSequence,
    OrderOutcome, RequestOutcome, RefundStatus, ReturnStatusCode,
    RequestDate, ApprovedDate, ReceivedDate, ClosedDate
)
SELECT
    CONVERT(INT, ReturnSequence),
    CONCAT('RET-', RIGHT(CONCAT('00000000', OrderSequence), 8)),
    SalesOrderID,
    OrderSequence,
    OrderOutcome,
    RequestOutcome,
    RefundStatus,
    ReturnStatusCode,
    RequestDate,
    ApprovedDate,
    ReceivedDate,
    ClosedDate
FROM SequencedRequests;

IF (SELECT COUNT(*) FROM #ReturnHeaderSeed) <> 12195
   OR (SELECT COUNT(*) FROM #ReturnHeaderSeed WHERE RequestOutcome = 'FULL_ACCEPT') <> 8780
   OR (SELECT COUNT(*) FROM #ReturnHeaderSeed WHERE RequestOutcome = 'PARTIAL_ACCEPT') <> 1220
   OR (SELECT COUNT(*) FROM #ReturnHeaderSeed WHERE RequestOutcome = 'REJECTED') <> 2195
BEGIN
    THROW 51347, 'Return-header seed failed to produce approved outcome counts.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM #ReturnHeaderSeed AS seed
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = seed.SalesOrderID
    WHERE seed.RequestDate < orders.DeliveredDate
       OR (seed.ApprovedDate IS NOT NULL AND seed.ApprovedDate < seed.RequestDate)
       OR (seed.ReceivedDate IS NOT NULL AND seed.ReceivedDate < seed.ApprovedDate)
       OR (seed.ClosedDate IS NOT NULL AND seed.ClosedDate < seed.RequestDate)
       OR seed.RequestDate > '2026-06-30T23:59:59'
       OR seed.ClosedDate > '2026-06-30T23:59:59'
)
BEGIN
    THROW 51348, 'Return-header seed contains an invalid lifecycle date.', 1;
END;

-- ============================================================================
-- 3. RETURN ITEM SEED
-- ============================================================================

CREATE TABLE #ReturnItemSeed
(
    ReturnNumber VARCHAR(25) NOT NULL,
    SalesOrderItemID BIGINT NOT NULL,
    ReturnReasonCode VARCHAR(30) NOT NULL,
    QuantityRequested INT NOT NULL,
    QuantityAccepted INT NOT NULL,
    EligibleRefundAmount DECIMAL(14,2) NOT NULL,
    IsReusable BIT NULL,
    InspectionNotes VARCHAR(500) NOT NULL,
    PRIMARY KEY (ReturnNumber, SalesOrderItemID)
);

;WITH OrderLines AS
(
    SELECT
        item.SalesOrderItemID,
        item.SalesOrderID,
        item.Quantity,
        item.NetAmount,
        category.CategoryCode,
        ROW_NUMBER() OVER
        (
            PARTITION BY item.SalesOrderID
            ORDER BY ABS(CONVERT(BIGINT, CHECKSUM(item.SalesOrderItemID, 20601))), item.SalesOrderItemID
        ) AS LineRank,
        COUNT(*) OVER (PARTITION BY item.SalesOrderID) AS LineCount,
        SUM(item.Quantity) OVER (PARTITION BY item.SalesOrderID) AS TotalOrderUnits
    FROM sales.SalesOrderItem AS item
    INNER JOIN core.Product AS product ON product.ProductID = item.ProductID
    INNER JOIN ref.SubCategory AS subcategory ON subcategory.SubCategoryID = product.SubCategoryID
    INNER JOIN ref.Category AS category ON category.CategoryID = subcategory.CategoryID
),
RequestedItems AS
(
    -- Fully returned orders: every delivered line and unit is accepted.
    SELECT
        header.ReturnNumber,
        line.SalesOrderItemID,
        line.CategoryCode,
        line.Quantity AS QuantityRequested,
        line.Quantity AS QuantityAccepted,
        line.NetAmount AS EligibleRefundAmount
    FROM #ReturnHeaderSeed AS header
    INNER JOIN OrderLines AS line ON line.SalesOrderID = header.SalesOrderID
    WHERE header.OrderOutcome = 'RETURNED'

    UNION ALL

    -- Partially returned orders: first selected line, never the entire order.
    SELECT
        header.ReturnNumber,
        line.SalesOrderItemID,
        line.CategoryCode,
        CASE
            WHEN header.RequestOutcome = 'PARTIAL_ACCEPT' THEN line.Quantity
            WHEN line.LineCount = 1 THEN 1
            ELSE line.Quantity
        END,
        CASE
            WHEN header.RequestOutcome = 'PARTIAL_ACCEPT' AND line.Quantity > 1
                THEN line.Quantity - 1
            WHEN header.RequestOutcome = 'PARTIAL_ACCEPT' THEN 1
            WHEN line.LineCount = 1 THEN 1
            ELSE line.Quantity
        END,
        CONVERT(DECIMAL(14,2),
            CASE
                WHEN header.RequestOutcome = 'PARTIAL_ACCEPT' AND line.Quantity > 1
                    THEN ROUND(line.NetAmount * (line.Quantity - 1) / line.Quantity, 2)
                WHEN header.RequestOutcome = 'PARTIAL_ACCEPT' THEN line.NetAmount
                WHEN line.LineCount = 1 THEN ROUND(line.NetAmount / line.Quantity, 2)
                ELSE line.NetAmount
            END
        )
    FROM #ReturnHeaderSeed AS header
    INNER JOIN OrderLines AS line
        ON line.SalesOrderID = header.SalesOrderID
       AND line.LineRank = 1
    WHERE header.OrderOutcome = 'PARTIALLY_RETURNED'

    UNION ALL

    -- If the first partial-acceptance line has one unit, reject a second line.
    SELECT
        header.ReturnNumber,
        line2.SalesOrderItemID,
        line2.CategoryCode,
        1,
        0,
        CONVERT(DECIMAL(14,2), 0)
    FROM #ReturnHeaderSeed AS header
    INNER JOIN OrderLines AS line1
        ON line1.SalesOrderID = header.SalesOrderID
       AND line1.LineRank = 1
    INNER JOIN OrderLines AS line2
        ON line2.SalesOrderID = header.SalesOrderID
       AND line2.LineRank = 2
    WHERE header.OrderOutcome = 'PARTIALLY_RETURNED'
      AND header.RequestOutcome = 'PARTIAL_ACCEPT'
      AND line1.Quantity = 1

    UNION ALL

    -- Rejected request: one requested unit, zero accepted units.
    SELECT
        header.ReturnNumber,
        line.SalesOrderItemID,
        line.CategoryCode,
        1,
        0,
        CONVERT(DECIMAL(14,2), 0)
    FROM #ReturnHeaderSeed AS header
    INNER JOIN OrderLines AS line
        ON line.SalesOrderID = header.SalesOrderID
       AND line.LineRank = 1
    WHERE header.RequestOutcome = 'REJECTED'
),
ReasonedItems AS
(
    SELECT
        requested.*,
        CASE
            WHEN requested.CategoryCode = 'FASHION'
             AND ((requested.SalesOrderItemID * 17) % 100) < 32 THEN 'SIZE_OR_FIT'
            WHEN ((requested.SalesOrderItemID * 17) % 100) < 20 THEN 'DAMAGED'
            WHEN ((requested.SalesOrderItemID * 17) % 100) < 40 THEN 'DEFECTIVE'
            WHEN ((requested.SalesOrderItemID * 17) % 100) < 52 THEN 'WRONG_ITEM'
            WHEN ((requested.SalesOrderItemID * 17) % 100) < 66 THEN 'NOT_AS_DESCRIBED'
            WHEN ((requested.SalesOrderItemID * 17) % 100) < 81 THEN 'SIZE_OR_FIT'
            WHEN ((requested.SalesOrderItemID * 17) % 100) < 97 THEN 'CUSTOMER_CHANGED_MIND'
            ELSE 'OTHER'
        END AS ReturnReasonCode
    FROM RequestedItems AS requested
)
INSERT INTO #ReturnItemSeed
(
    ReturnNumber, SalesOrderItemID, ReturnReasonCode,
    QuantityRequested, QuantityAccepted, EligibleRefundAmount,
    IsReusable, InspectionNotes
)
SELECT
    reasoned.ReturnNumber,
    reasoned.SalesOrderItemID,
    reasoned.ReturnReasonCode,
    reasoned.QuantityRequested,
    reasoned.QuantityAccepted,
    reasoned.EligibleRefundAmount,
    CASE
        WHEN reasoned.QuantityAccepted = 0 THEN NULL
        WHEN reasoned.ReturnReasonCode IN ('DAMAGED','DEFECTIVE')
            THEN CASE WHEN reasoned.SalesOrderItemID % 5 = 0 THEN 1 ELSE 0 END
        WHEN reasoned.ReturnReasonCode = 'CUSTOMER_CHANGED_MIND'
            THEN CASE WHEN reasoned.SalesOrderItemID % 20 < 17 THEN 1 ELSE 0 END
        ELSE CASE WHEN reasoned.SalesOrderItemID % 5 < 3 THEN 1 ELSE 0 END
    END,
    CASE
        WHEN reasoned.QuantityAccepted = 0 THEN 'Synthetic inspection: requested quantity rejected.'
        WHEN reasoned.ReturnReasonCode IN ('DAMAGED','DEFECTIVE')
            THEN 'Synthetic inspection: quality issue reviewed for reuse eligibility.'
        ELSE 'Synthetic inspection: accepted return assessed for resale.'
    END
FROM ReasonedItems AS reasoned;

DECLARE @ReturnItemCount BIGINT = (SELECT COUNT_BIG(*) FROM #ReturnItemSeed);

IF @ReturnItemCount NOT BETWEEN 8000 AND 25000
   OR EXISTS
   (
       SELECT 1 FROM #ReturnItemSeed
       WHERE QuantityRequested <= 0
          OR QuantityAccepted < 0
          OR QuantityAccepted > QuantityRequested
          OR EligibleRefundAmount < 0
   )
BEGIN
    THROW 51349, 'Return-item seed failed volume or quantity validation.', 1;
END;

-- ============================================================================
-- 4. REFUND SEED
-- ============================================================================

CREATE TABLE #RefundSeed
(
    ReturnNumber VARCHAR(25) NOT NULL PRIMARY KEY,
    PaymentID BIGINT NOT NULL,
    RefundDate DATETIME2(0) NOT NULL,
    RefundAmount DECIMAL(14,2) NOT NULL,
    RefundReference VARCHAR(100) NOT NULL UNIQUE,
    RefundStatus VARCHAR(20) NOT NULL
);

;WITH EligibleAmounts AS
(
    SELECT ReturnNumber, SUM(EligibleRefundAmount) AS RefundAmount
    FROM #ReturnItemSeed
    GROUP BY ReturnNumber
)
INSERT INTO #RefundSeed
(
    ReturnNumber, PaymentID, RefundDate,
    RefundAmount, RefundReference, RefundStatus
)
SELECT
    header.ReturnNumber,
    completed_payment.PaymentID,
    header.ReceivedDate,
    amount.RefundAmount,
    CONCAT('RFN-', header.ReturnNumber),
    header.RefundStatus
FROM #ReturnHeaderSeed AS header
INNER JOIN EligibleAmounts AS amount ON amount.ReturnNumber = header.ReturnNumber
CROSS APPLY
(
    SELECT TOP (1) payment.PaymentID
    FROM sales.Payment AS payment
    INNER JOIN ref.PaymentStatus AS status ON status.PaymentStatusID = payment.PaymentStatusID
    WHERE payment.SalesOrderID = header.SalesOrderID
      AND status.PaymentStatusCode IN ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
    ORDER BY payment.AttemptNumber DESC
) AS completed_payment
WHERE header.RequestOutcome IN ('FULL_ACCEPT','PARTIAL_ACCEPT');

IF (SELECT COUNT(*) FROM #RefundSeed) <> 10000
   OR (SELECT COUNT(*) FROM #RefundSeed WHERE RefundStatus = 'Completed') <> 9400
   OR (SELECT COUNT(*) FROM #RefundSeed WHERE RefundStatus = 'Pending') <> 400
   OR (SELECT COUNT(*) FROM #RefundSeed WHERE RefundStatus = 'Failed') <> 200
   OR EXISTS (SELECT 1 FROM #RefundSeed WHERE RefundAmount <= 0)
BEGIN
    THROW 51350, 'Refund seed failed to produce approved counts or positive amounts.', 1;
END;

-- ============================================================================
-- 5. LOAD RETURNS, ITEMS, REFUNDS, AND PAYMENT REFUND STATES
-- ============================================================================

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE FROM sales.Refund;
    DELETE FROM sales.ProductReturnItem;
    DELETE FROM sales.ProductReturn;

    -- Restore prior rerun payment states before applying the regenerated refunds.
    UPDATE sales.Payment
    SET PaymentStatusID = @CompletedPaymentStatusID,
        ModifiedDate = SYSDATETIME()
    WHERE PaymentStatusID IN (@PartiallyRefundedPaymentStatusID, @RefundedPaymentStatusID);

    -- Apply eligibility swaps to current status and the final lifecycle history row.
    UPDATE orders
    SET OrderStatusID = CASE swap.NewStatusCode
                            WHEN 'PARTIALLY_RETURNED' THEN @PartiallyReturnedOrderStatusID
                            ELSE @ReturnedOrderStatusID
                        END,
        Remarks = CONCAT('Synthetic lifecycle outcome: ', swap.NewStatusCode,
                         '; eligibility rebalanced for return integrity.'),
        ModifiedDate = SYSDATETIME()
    FROM sales.SalesOrder AS orders
    INNER JOIN #StatusSwap AS swap ON swap.SalesOrderID = orders.SalesOrderID;

    UPDATE history
    SET ToOrderStatusID = CASE swap.NewStatusCode
                              WHEN 'PARTIALLY_RETURNED' THEN @PartiallyReturnedOrderStatusID
                              ELSE @ReturnedOrderStatusID
                          END,
        ChangeReason = CASE swap.NewStatusCode
                           WHEN 'PARTIALLY_RETURNED' THEN 'Synthetic partial return accepted after eligibility rebalance'
                           ELSE 'Synthetic full return accepted after eligibility rebalance'
                       END
    FROM sales.OrderStatusHistory AS history
    INNER JOIN #StatusSwap AS swap ON swap.SalesOrderID = history.SalesOrderID
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM sales.OrderStatusHistory AS later
        WHERE later.SalesOrderID = history.SalesOrderID
          AND (later.StatusChangedDate > history.StatusChangedDate
               OR (later.StatusChangedDate = history.StatusChangedDate
                   AND later.OrderStatusHistoryID > history.OrderStatusHistoryID))
    );

    INSERT INTO sales.ProductReturn
    (
        ReturnNumber, SalesOrderID, ReturnStatusID,
        RequestDate, ApprovedDate, ReceivedDate, ClosedDate, Remarks
    )
    SELECT
        seed.ReturnNumber,
        seed.SalesOrderID,
        status.ReturnStatusID,
        seed.RequestDate,
        seed.ApprovedDate,
        seed.ReceivedDate,
        seed.ClosedDate,
        CONCAT('Synthetic return outcome: ', seed.RequestOutcome, '.')
    FROM #ReturnHeaderSeed AS seed
    INNER JOIN ref.ReturnStatus AS status
        ON status.ReturnStatusCode = seed.ReturnStatusCode;

    INSERT INTO sales.ProductReturnItem
    (
        ProductReturnID, SalesOrderItemID, ReturnReasonID,
        QuantityRequested, QuantityAccepted, EligibleRefundAmount,
        IsReusable, InspectionNotes
    )
    SELECT
        header.ProductReturnID,
        seed.SalesOrderItemID,
        reason.ReturnReasonID,
        seed.QuantityRequested,
        seed.QuantityAccepted,
        seed.EligibleRefundAmount,
        seed.IsReusable,
        seed.InspectionNotes
    FROM #ReturnItemSeed AS seed
    INNER JOIN sales.ProductReturn AS header ON header.ReturnNumber = seed.ReturnNumber
    INNER JOIN ref.ReturnReason AS reason ON reason.ReturnReasonCode = seed.ReturnReasonCode;

    INSERT INTO sales.Refund
    (
        PaymentID, ProductReturnID, RefundDate,
        RefundAmount, RefundReference, RefundStatus, Remarks
    )
    SELECT
        seed.PaymentID,
        header.ProductReturnID,
        seed.RefundDate,
        seed.RefundAmount,
        seed.RefundReference,
        seed.RefundStatus,
        'Synthetic refund generated from accepted return value'
    FROM #RefundSeed AS seed
    INNER JOIN sales.ProductReturn AS header ON header.ReturnNumber = seed.ReturnNumber;

    UPDATE payment
    SET PaymentStatusID = CASE
            WHEN header.OrderOutcome = 'RETURNED' THEN @RefundedPaymentStatusID
            ELSE @PartiallyRefundedPaymentStatusID
        END,
        ModifiedDate = SYSDATETIME()
    FROM sales.Payment AS payment
    INNER JOIN #RefundSeed AS refund_seed ON refund_seed.PaymentID = payment.PaymentID
    INNER JOIN #ReturnHeaderSeed AS header ON header.ReturnNumber = refund_seed.ReturnNumber
    WHERE refund_seed.RefundStatus = 'Completed';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ============================================================================
-- 6. ACCEPTANCE VALIDATION
-- ============================================================================

DECLARE @ReturnCount BIGINT = (SELECT COUNT_BIG(*) FROM sales.ProductReturn);
DECLARE @LoadedReturnItemCount BIGINT = (SELECT COUNT_BIG(*) FROM sales.ProductReturnItem);
DECLARE @RefundCount BIGINT = (SELECT COUNT_BIG(*) FROM sales.Refund);

IF @ReturnCount <> 12195
   OR @LoadedReturnItemCount <> @ReturnItemCount
   OR @RefundCount <> 10000
BEGIN
    THROW 51351, 'Return validation failed: header, item, or refund count differs from seed.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sales.ProductReturnItem AS return_item
    INNER JOIN sales.ProductReturn AS return_header
        ON return_header.ProductReturnID = return_item.ProductReturnID
    INNER JOIN sales.SalesOrderItem AS order_item
        ON order_item.SalesOrderItemID = return_item.SalesOrderItemID
    WHERE order_item.SalesOrderID <> return_header.SalesOrderID
       OR return_item.QuantityRequested > order_item.Quantity
       OR return_item.QuantityAccepted > return_item.QuantityRequested
)
BEGIN
    THROW 51352, 'Return validation failed: order ownership or quantity eligibility error.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM #ReturnHeaderSeed AS header
    INNER JOIN
    (
        SELECT
            return_header.ReturnNumber,
            SUM(return_item.QuantityAccepted) AS AcceptedUnits
        FROM sales.ProductReturn AS return_header
        INNER JOIN sales.ProductReturnItem AS return_item
            ON return_item.ProductReturnID = return_header.ProductReturnID
        GROUP BY return_header.ReturnNumber
    ) AS accepted ON accepted.ReturnNumber = header.ReturnNumber
    INNER JOIN
    (
        SELECT orders.SalesOrderID, SUM(item.Quantity) AS OrderedUnits
        FROM sales.SalesOrder AS orders
        INNER JOIN sales.SalesOrderItem AS item ON item.SalesOrderID = orders.SalesOrderID
        GROUP BY orders.SalesOrderID
    ) AS ordered ON ordered.SalesOrderID = header.SalesOrderID
    WHERE (header.OrderOutcome = 'RETURNED' AND accepted.AcceptedUnits <> ordered.OrderedUnits)
       OR (header.OrderOutcome = 'PARTIALLY_RETURNED'
           AND (accepted.AcceptedUnits <= 0 OR accepted.AcceptedUnits >= ordered.OrderedUnits))
       OR (header.RequestOutcome = 'REJECTED' AND accepted.AcceptedUnits <> 0)
)
BEGIN
    THROW 51353, 'Return validation failed: order-level partial/full/rejected outcome mismatch.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sales.Refund AS refund
    INNER JOIN sales.Payment AS payment ON payment.PaymentID = refund.PaymentID
    INNER JOIN sales.ProductReturn AS return_header
        ON return_header.ProductReturnID = refund.ProductReturnID
    WHERE payment.SalesOrderID <> return_header.SalesOrderID
       OR refund.RefundAmount > payment.Amount
       OR refund.RefundAmount >
          (
              SELECT SUM(item.EligibleRefundAmount)
              FROM sales.ProductReturnItem AS item
              WHERE item.ProductReturnID = return_header.ProductReturnID
          )
)
BEGIN
    THROW 51354, 'Refund validation failed: payment ownership or eligible amount error.', 1;
END;

SELECT
    seed.RequestOutcome,
    COUNT_BIG(*) AS ReturnRequestCount,
    CAST(100.0 * COUNT_BIG(*) / @ReturnCount AS DECIMAL(5,2)) AS RequestSharePercent,
    SUM(CASE WHEN seed.RefundStatus = 'Completed' THEN 1 ELSE 0 END) AS CompletedRefundCount,
    'PASSED' AS ValidationStatus
FROM #ReturnHeaderSeed AS seed
GROUP BY seed.RequestOutcome
ORDER BY
    CASE seed.RequestOutcome
        WHEN 'FULL_ACCEPT' THEN 1
        WHEN 'PARTIAL_ACCEPT' THEN 2
        ELSE 3
    END;

SELECT
    reason.ReturnReasonCode,
    reason.ReturnReasonName,
    COUNT_BIG(*) AS ReturnItemCount,
    SUM(return_item.QuantityRequested) AS RequestedUnitCount,
    SUM(return_item.QuantityAccepted) AS AcceptedUnitCount,
    SUM(return_item.EligibleRefundAmount) AS EligibleRefundValue,
    'PASSED' AS ValidationStatus
FROM sales.ProductReturnItem AS return_item
INNER JOIN ref.ReturnReason AS reason ON reason.ReturnReasonID = return_item.ReturnReasonID
GROUP BY reason.ReturnReasonCode, reason.ReturnReasonName, reason.SortOrder
ORDER BY reason.SortOrder;

SELECT
    RefundStatus,
    COUNT_BIG(*) AS RefundCount,
    SUM(RefundAmount) AS RefundValue,
    'PASSED' AS ValidationStatus
FROM sales.Refund
GROUP BY RefundStatus
ORDER BY CASE RefundStatus WHEN 'Completed' THEN 1 WHEN 'Pending' THEN 2 ELSE 3 END;

SELECT
    @ReturnCount AS ReturnRequestCount,
    @LoadedReturnItemCount AS ReturnItemCount,
    @RefundCount AS RefundCount,
    (SELECT SUM(refund.RefundAmount)
     FROM sales.Refund AS refund
     WHERE refund.RefundStatus = 'Completed') AS CompletedRefundValue,
    COUNT(DISTINCT CASE WHEN return_item.QuantityAccepted > 0
                         AND return_item.IsReusable = 1
                        THEN return_item.ProductReturnItemID END) AS ReusableAcceptedItemCount,
    CASE
        WHEN @ReturnCount = 12195
         AND @RefundCount = 10000
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM sales.ProductReturnItem AS return_item;

RAISERROR('20_Generate_Returns_Refunds.sql completed successfully: 12,195 returns and 10,000 refunds validated.', 10, 1) WITH NOWAIT;
GO
