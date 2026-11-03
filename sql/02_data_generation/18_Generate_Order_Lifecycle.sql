/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      18_Generate_Order_Lifecycle.sql
Purpose:     Assign valid order outcomes, lifecycle dates, and status history.
Author:      Akshay Aswani
Version:     2.0
Depends on:  17_Generate_Sales_Orders.sql
Rerunnable:  Yes, until payment, return, or downstream inventory facts exist.

Final-status targets
--------------------
- Delivered:          78,000 (78.0%)
- Cancelled:          10,000 (10.0%)
- Partially Returned:  5,000 ( 5.0%)
- Returned:            5,000 ( 5.0%)
- Shipped:             1,000 ( 1.0%)
- Processing:            600 ( 0.6%)
- Confirmed:             300 ( 0.3%)
- Pending:               100 ( 0.1%)

The final 2,000 orders contain all open statuses so snapshot behavior is realistic.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51300, 'Order-lifecycle generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'sales.SalesOrder', N'U') IS NULL
   OR OBJECT_ID(N'sales.OrderStatusHistory', N'U') IS NULL
   OR OBJECT_ID(N'ref.OrderStatus', N'U') IS NULL
BEGIN
    THROW 51301, 'Order-lifecycle generation stopped: one or more required tables are missing.', 1;
END;

IF (SELECT COUNT_BIG(*) FROM sales.SalesOrder) <> 100000
   OR (SELECT COUNT(*) FROM ref.OrderStatus WHERE IsActive = 1) <> 8
BEGIN
    THROW 51302, 'Order-lifecycle generation stopped: expected orders or statuses are missing.', 1;
END;

DECLARE @OpeningMovementTypeID SMALLINT;

SELECT @OpeningMovementTypeID = InventoryMovementTypeID
FROM ref.InventoryMovementType
WHERE InventoryMovementTypeCode = 'OPENING_STOCK' AND IsActive = 1;

IF @OpeningMovementTypeID IS NULL
BEGIN
    THROW 51303, 'Order-lifecycle generation stopped: Opening Stock reference is missing.', 1;
END;

IF EXISTS (SELECT 1 FROM sales.Payment)
   OR EXISTS (SELECT 1 FROM sales.ProductReturn)
   OR EXISTS
      (
          SELECT 1
          FROM inventory.InventoryMovement
          WHERE InventoryMovementTypeID <> @OpeningMovementTypeID
      )
BEGIN
    THROW 51304, 'Order lifecycle cannot be rebuilt after downstream transactional facts exist.', 1;
END;

DROP TABLE IF EXISTS #StatusMap;
DROP TABLE IF EXISTS #LifecycleSeed;
DROP TABLE IF EXISTS #HistorySeed;

CREATE TABLE #StatusMap
(
    StatusCode VARCHAR(30) NOT NULL PRIMARY KEY,
    OrderStatusID SMALLINT NOT NULL UNIQUE
);

INSERT INTO #StatusMap (StatusCode, OrderStatusID)
SELECT OrderStatusCode, OrderStatusID
FROM ref.OrderStatus
WHERE IsActive = 1;

IF EXISTS
(
    SELECT required.StatusCode
    FROM (VALUES
        ('PENDING'),('CONFIRMED'),('PROCESSING'),('SHIPPED'),
        ('DELIVERED'),('CANCELLED'),('PARTIALLY_RETURNED'),('RETURNED')
    ) AS required (StatusCode)
    LEFT JOIN #StatusMap AS existing ON existing.StatusCode = required.StatusCode
    WHERE existing.OrderStatusID IS NULL
)
BEGIN
    THROW 51305, 'Order-lifecycle generation stopped: approved status map is incomplete.', 1;
END;

CREATE TABLE #LifecycleSeed
(
    SalesOrderID BIGINT NOT NULL PRIMARY KEY,
    OrderSequence INT NOT NULL UNIQUE,
    EmployeeID INT NOT NULL,
    OrderDate DATETIME2(0) NOT NULL,
    FinalStatusCode VARCHAR(30) NOT NULL,
    CancellationStage TINYINT NULL,
    ConfirmedDate DATETIME2(0) NULL,
    ProcessingDate DATETIME2(0) NULL,
    ShippedDate DATETIME2(0) NULL,
    DeliveredDate DATETIME2(0) NULL,
    CancelledDate DATETIME2(0) NULL,
    ReturnStatusDate DATETIME2(0) NULL
);

;WITH NumberedOrders AS
(
    SELECT
        orders.SalesOrderID,
        CONVERT(INT, RIGHT(orders.OrderNumber, 8)) AS OrderSequence,
        orders.EmployeeID,
        orders.OrderDate
    FROM sales.SalesOrder AS orders
),
OutcomeAssignments AS
(
    SELECT
        numbered.*,
        CASE
            WHEN numbered.OrderSequence > 99900 THEN 'PENDING'
            WHEN numbered.OrderSequence > 99600 THEN 'CONFIRMED'
            WHEN numbered.OrderSequence > 99000 THEN 'PROCESSING'
            WHEN numbered.OrderSequence > 98000 THEN 'SHIPPED'
            WHEN (((CONVERT(BIGINT, numbered.OrderSequence) * 37) - 1) % 98000) + 1 <= 78000
                THEN 'DELIVERED'
            WHEN (((CONVERT(BIGINT, numbered.OrderSequence) * 37) - 1) % 98000) + 1 <= 88000
                THEN 'CANCELLED'
            WHEN (((CONVERT(BIGINT, numbered.OrderSequence) * 37) - 1) % 98000) + 1 <= 93000
                THEN 'PARTIALLY_RETURNED'
            ELSE 'RETURNED'
        END AS FinalStatusCode,
        CASE
            WHEN numbered.OrderSequence <= 98000
             AND (((CONVERT(BIGINT, numbered.OrderSequence) * 37) - 1) % 98000) + 1
                 BETWEEN 78001 AND 88000
            THEN CONVERT(TINYINT, 1 + (numbered.OrderSequence % 3))
            ELSE NULL
        END AS CancellationStage
    FROM NumberedOrders AS numbered
),
ConfirmedEvents AS
(
    SELECT
        assignment.*,
        CASE
            WHEN assignment.FinalStatusCode = 'PENDING' THEN NULL
            WHEN assignment.FinalStatusCode = 'CANCELLED'
             AND assignment.CancellationStage = 1 THEN NULL
            ELSE DATEADD(MINUTE, 15 + (assignment.OrderSequence % 106), assignment.OrderDate)
        END AS ConfirmedDate
    FROM OutcomeAssignments AS assignment
),
ProcessingEvents AS
(
    SELECT
        event.*,
        CASE
            WHEN event.FinalStatusCode IN
                 ('PROCESSING','SHIPPED','DELIVERED','PARTIALLY_RETURNED','RETURNED')
              OR (event.FinalStatusCode = 'CANCELLED' AND event.CancellationStage = 3)
            THEN DATEADD(MINUTE, 60 + (event.OrderSequence % 181), event.ConfirmedDate)
            ELSE NULL
        END AS ProcessingDate
    FROM ConfirmedEvents AS event
),
ShippedEvents AS
(
    SELECT
        event.*,
        CASE
            WHEN event.FinalStatusCode IN
                 ('SHIPPED','DELIVERED','PARTIALLY_RETURNED','RETURNED')
            THEN DATEADD(DAY, 1, event.ProcessingDate)
            ELSE NULL
        END AS ShippedDate
    FROM ProcessingEvents AS event
),
DeliveredEvents AS
(
    SELECT
        event.*,
        CASE
            WHEN event.FinalStatusCode IN
                 ('DELIVERED','PARTIALLY_RETURNED','RETURNED')
            THEN DATEADD(DAY, 1 + (event.OrderSequence % 2), event.ShippedDate)
            ELSE NULL
        END AS DeliveredDate
    FROM ShippedEvents AS event
),
TerminalEvents AS
(
    SELECT
        event.*,
        CASE
            WHEN event.FinalStatusCode <> 'CANCELLED' THEN NULL
            WHEN event.CancellationStage = 1
                THEN DATEADD(MINUTE, 30 + (event.OrderSequence % 180), event.OrderDate)
            WHEN event.CancellationStage = 2
                THEN DATEADD(MINUTE, 30 + (event.OrderSequence % 180), event.ConfirmedDate)
            ELSE DATEADD(MINUTE, 30 + (event.OrderSequence % 180), event.ProcessingDate)
        END AS CancelledDate,
        CASE
            WHEN event.FinalStatusCode IN ('PARTIALLY_RETURNED','RETURNED')
            THEN DATEADD(DAY, 3 + (event.OrderSequence % 10), event.DeliveredDate)
            ELSE NULL
        END AS ReturnStatusDate
    FROM DeliveredEvents AS event
)
INSERT INTO #LifecycleSeed
(
    SalesOrderID, OrderSequence, EmployeeID, OrderDate,
    FinalStatusCode, CancellationStage,
    ConfirmedDate, ProcessingDate, ShippedDate,
    DeliveredDate, CancelledDate, ReturnStatusDate
)
SELECT
    SalesOrderID, OrderSequence, EmployeeID, OrderDate,
    FinalStatusCode, CancellationStage,
    ConfirmedDate, ProcessingDate, ShippedDate,
    DeliveredDate, CancelledDate, ReturnStatusDate
FROM TerminalEvents;

IF (SELECT COUNT(*) FROM #LifecycleSeed) <> 100000
   OR EXISTS
   (
       SELECT FinalStatusCode
       FROM #LifecycleSeed
       GROUP BY FinalStatusCode
       HAVING COUNT(*) <>
           CASE FinalStatusCode
               WHEN 'DELIVERED' THEN 78000
               WHEN 'CANCELLED' THEN 10000
               WHEN 'PARTIALLY_RETURNED' THEN 5000
               WHEN 'RETURNED' THEN 5000
               WHEN 'SHIPPED' THEN 1000
               WHEN 'PROCESSING' THEN 600
               WHEN 'CONFIRMED' THEN 300
               WHEN 'PENDING' THEN 100
           END
   )
BEGIN
    THROW 51306, 'Order-lifecycle seed failed to produce the approved status distribution.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM #LifecycleSeed
    WHERE (ConfirmedDate IS NOT NULL AND ConfirmedDate < OrderDate)
       OR (ProcessingDate IS NOT NULL AND ProcessingDate < ConfirmedDate)
       OR (ShippedDate IS NOT NULL AND ShippedDate < ProcessingDate)
       OR (DeliveredDate IS NOT NULL AND DeliveredDate < ShippedDate)
       OR (CancelledDate IS NOT NULL AND CancelledDate < OrderDate)
       OR (ReturnStatusDate IS NOT NULL AND ReturnStatusDate < DeliveredDate)
       OR ReturnStatusDate > '2026-06-30T23:59:59'
)
BEGIN
    THROW 51307, 'Order-lifecycle seed contains an invalid or out-of-period event timestamp.', 1;
END;

CREATE TABLE #HistorySeed
(
    SalesOrderID BIGINT NOT NULL,
    HistorySequence TINYINT NOT NULL,
    FromStatusCode VARCHAR(30) NULL,
    ToStatusCode VARCHAR(30) NOT NULL,
    StatusChangedDate DATETIME2(0) NOT NULL,
    ChangedByEmployeeID INT NOT NULL,
    ChangeReason VARCHAR(255) NOT NULL,
    PRIMARY KEY (SalesOrderID, HistorySequence)
);

-- Every order begins in Pending.
INSERT INTO #HistorySeed
SELECT
    SalesOrderID, 1, NULL, 'PENDING', OrderDate, EmployeeID,
    'Synthetic order created'
FROM #LifecycleSeed;

-- Confirmation where the lifecycle reaches Confirmed.
INSERT INTO #HistorySeed
SELECT
    SalesOrderID, 2, 'PENDING', 'CONFIRMED', ConfirmedDate, EmployeeID,
    'Synthetic order confirmed'
FROM #LifecycleSeed
WHERE ConfirmedDate IS NOT NULL;

-- Processing where the lifecycle reaches Processing.
INSERT INTO #HistorySeed
SELECT
    SalesOrderID, 3, 'CONFIRMED', 'PROCESSING', ProcessingDate, EmployeeID,
    'Synthetic fulfilment processing started'
FROM #LifecycleSeed
WHERE ProcessingDate IS NOT NULL;

-- Shipment where the lifecycle reaches Shipped.
INSERT INTO #HistorySeed
SELECT
    SalesOrderID, 4, 'PROCESSING', 'SHIPPED', ShippedDate, EmployeeID,
    'Synthetic order dispatched'
FROM #LifecycleSeed
WHERE ShippedDate IS NOT NULL;

-- Delivery for completed and later-returned orders.
INSERT INTO #HistorySeed
SELECT
    SalesOrderID, 5, 'SHIPPED', 'DELIVERED', DeliveredDate, EmployeeID,
    'Synthetic order delivered'
FROM #LifecycleSeed
WHERE DeliveredDate IS NOT NULL;

-- Accepted return outcome; detailed return facts are generated in script 20.
INSERT INTO #HistorySeed
SELECT
    SalesOrderID, 6, 'DELIVERED', FinalStatusCode, ReturnStatusDate, EmployeeID,
    CASE FinalStatusCode
        WHEN 'PARTIALLY_RETURNED' THEN 'Synthetic partial return accepted'
        ELSE 'Synthetic full return accepted'
    END
FROM #LifecycleSeed
WHERE FinalStatusCode IN ('PARTIALLY_RETURNED','RETURNED');

-- Cancellation occurs from the applicable pre-shipment stage.
INSERT INTO #HistorySeed
SELECT
    SalesOrderID,
    CONVERT(TINYINT, CancellationStage + 1),
    CASE CancellationStage
        WHEN 1 THEN 'PENDING'
        WHEN 2 THEN 'CONFIRMED'
        ELSE 'PROCESSING'
    END,
    'CANCELLED',
    CancelledDate,
    EmployeeID,
    CASE CancellationStage
        WHEN 1 THEN 'Synthetic customer cancellation before confirmation'
        WHEN 2 THEN 'Synthetic cancellation after confirmation'
        ELSE 'Synthetic fulfilment cancellation before shipment'
    END
FROM #LifecycleSeed
WHERE FinalStatusCode = 'CANCELLED';

BEGIN TRY
    BEGIN TRANSACTION;

    -- Safe because downstream facts are blocked above; this enables deterministic reruns.
    DELETE FROM sales.OrderStatusHistory;

    UPDATE orders
    SET OrderStatusID = final_status.OrderStatusID,
        ConfirmedDate = seed.ConfirmedDate,
        ShippedDate = seed.ShippedDate,
        DeliveredDate = seed.DeliveredDate,
        CancelledDate = seed.CancelledDate,
        Remarks = CONCAT('Synthetic lifecycle outcome: ', seed.FinalStatusCode, '.'),
        ModifiedDate = SYSDATETIME()
    FROM sales.SalesOrder AS orders
    INNER JOIN #LifecycleSeed AS seed ON seed.SalesOrderID = orders.SalesOrderID
    INNER JOIN #StatusMap AS final_status ON final_status.StatusCode = seed.FinalStatusCode;

    INSERT INTO sales.OrderStatusHistory
    (
        SalesOrderID, FromOrderStatusID, ToOrderStatusID,
        StatusChangedDate, ChangedByEmployeeID, ChangeReason
    )
    SELECT
        history.SalesOrderID,
        from_status.OrderStatusID,
        to_status.OrderStatusID,
        history.StatusChangedDate,
        history.ChangedByEmployeeID,
        history.ChangeReason
    FROM #HistorySeed AS history
    LEFT JOIN #StatusMap AS from_status ON from_status.StatusCode = history.FromStatusCode
    INNER JOIN #StatusMap AS to_status ON to_status.StatusCode = history.ToStatusCode;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @ExpectedHistoryCount BIGINT = (SELECT COUNT_BIG(*) FROM #HistorySeed);
DECLARE @ActualHistoryCount BIGINT = (SELECT COUNT_BIG(*) FROM sales.OrderStatusHistory);

IF @ActualHistoryCount <> @ExpectedHistoryCount
BEGIN
    THROW 51308, 'Order-lifecycle validation failed: status-history row count differs from seed.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM
    (
        SELECT
            history.SalesOrderID,
            history.FromOrderStatusID,
            history.ToOrderStatusID,
            history.StatusChangedDate,
            LAG(history.ToOrderStatusID) OVER
            (
                PARTITION BY history.SalesOrderID
                ORDER BY history.StatusChangedDate, history.OrderStatusHistoryID
            ) AS PreviousToStatusID,
            ROW_NUMBER() OVER
            (
                PARTITION BY history.SalesOrderID
                ORDER BY history.StatusChangedDate, history.OrderStatusHistoryID
            ) AS HistorySequence
        FROM sales.OrderStatusHistory AS history
    ) AS sequenced
    WHERE (sequenced.HistorySequence = 1 AND sequenced.FromOrderStatusID IS NOT NULL)
       OR (sequenced.HistorySequence > 1
           AND sequenced.FromOrderStatusID <> sequenced.PreviousToStatusID)
)
BEGIN
    THROW 51309, 'Order-lifecycle validation failed: broken status-history transition chain.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sales.SalesOrder AS orders
    INNER JOIN
    (
        SELECT SalesOrderID, ToOrderStatusID
        FROM
        (
            SELECT
                history.SalesOrderID,
                history.ToOrderStatusID,
                ROW_NUMBER() OVER
                (
                    PARTITION BY history.SalesOrderID
                    ORDER BY history.StatusChangedDate DESC,
                             history.OrderStatusHistoryID DESC
                ) AS LatestRank
            FROM sales.OrderStatusHistory AS history
        ) AS ranked
        WHERE LatestRank = 1
    ) AS latest ON latest.SalesOrderID = orders.SalesOrderID
    WHERE latest.ToOrderStatusID <> orders.OrderStatusID
)
BEGIN
    THROW 51310, 'Order-lifecycle validation failed: current status differs from latest history.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sales.SalesOrder AS orders
    INNER JOIN ref.OrderStatus AS status ON status.OrderStatusID = orders.OrderStatusID
    WHERE (status.OrderStatusCode IN ('DELIVERED','PARTIALLY_RETURNED','RETURNED')
           AND orders.DeliveredDate IS NULL)
       OR (status.OrderStatusCode = 'CANCELLED' AND orders.CancelledDate IS NULL)
       OR (orders.DeliveredDate IS NOT NULL AND orders.CancelledDate IS NOT NULL)
       OR (status.OrderStatusCode IN ('PENDING','CONFIRMED','PROCESSING','SHIPPED')
           AND orders.OrderDate < '2026-06-01')
)
BEGIN
    THROW 51311, 'Order-lifecycle validation failed: terminal dates or open-order timing are invalid.', 1;
END;

SELECT
    status.OrderStatusCode,
    status.OrderStatusName,
    COUNT_BIG(*) AS OrderCount,
    CAST(100.0 * COUNT_BIG(*) / 100000.0 AS DECIMAL(5,2)) AS OrderSharePercent,
    MIN(orders.OrderDate) AS EarliestOrderDate,
    MAX(orders.OrderDate) AS LatestOrderDate,
    'PASSED' AS ValidationStatus
FROM sales.SalesOrder AS orders
INNER JOIN ref.OrderStatus AS status ON status.OrderStatusID = orders.OrderStatusID
GROUP BY status.OrderStatusCode, status.OrderStatusName, status.SortOrder
ORDER BY status.SortOrder;

SELECT
    COUNT_BIG(*) AS StatusHistoryCount,
    COUNT(DISTINCT SalesOrderID) AS OrdersWithHistory,
    MIN(StatusChangedDate) AS EarliestStatusChange,
    MAX(StatusChangedDate) AS LatestStatusChange,
    CASE
        WHEN COUNT_BIG(*) = @ExpectedHistoryCount
         AND COUNT(DISTINCT SalesOrderID) = 100000
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM sales.OrderStatusHistory;

RAISERROR('18_Generate_Order_Lifecycle.sql completed successfully: 100,000 lifecycle outcomes and complete status history validated.', 10, 1) WITH NOWAIT;
GO
