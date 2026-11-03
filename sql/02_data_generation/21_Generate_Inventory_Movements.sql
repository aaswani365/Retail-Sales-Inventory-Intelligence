/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      21_Generate_Inventory_Movements.sql
Purpose:     Build the inventory ledger from sales, returns, replenishment,
             transfers, write-offs, and controlled adjustments.
Author:      Akshay Aswani
Version:     2.0
Depends on:  20_Generate_Returns_Refunds.sql
Rerunnable:  Yes. All non-opening movements are deterministically rebuilt.

Inventory policy
----------------
- Stock is issued only once an order reaches Shipped or a later fulfilled state.
- Accepted returns first enter inventory; non-reusable units are then written off.
- Confirmed and Processing orders remain reserved rather than issued.
- Every transfer has equal Transfer Out and Transfer In quantities.
- Purchase receipts provide sufficient stock to avoid negative running balances.
- InventoryBalance is derived from the immutable movement ledger.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51360, 'Inventory generation stopped: unexpected database context.', 1;

IF OBJECT_ID(N'inventory.InventoryMovement', N'U') IS NULL
   OR OBJECT_ID(N'inventory.InventoryBalance', N'U') IS NULL
   OR OBJECT_ID(N'sales.SalesOrderItem', N'U') IS NULL
   OR OBJECT_ID(N'sales.ProductReturnItem', N'U') IS NULL
    THROW 51361, 'Inventory generation stopped: one or more required tables are missing.', 1;

IF (SELECT COUNT_BIG(*) FROM sales.SalesOrder) <> 100000
   OR (SELECT COUNT_BIG(*) FROM sales.SalesOrderItem) <> 300000
   OR (SELECT COUNT_BIG(*) FROM sales.ProductReturn) <> 12195
   OR (SELECT COUNT_BIG(*) FROM sales.Refund) <> 10000
   OR (SELECT COUNT_BIG(*) FROM inventory.InventoryBalance) <> 7016
    THROW 51362, 'Inventory generation stopped: approved upstream counts are missing.', 1;

DROP TABLE IF EXISTS #MovementTypeMap;
DROP TABLE IF EXISTS #OpeningBalance;
DROP TABLE IF EXISTS #ReservedSeed;
DROP TABLE IF EXISTS #MovementSeed;
DROP TABLE IF EXISTS #TransferSeed;

CREATE TABLE #MovementTypeMap
(
    InventoryMovementTypeCode VARCHAR(30) NOT NULL PRIMARY KEY,
    InventoryMovementTypeID SMALLINT NOT NULL UNIQUE,
    QuantityDirection SMALLINT NOT NULL
);

INSERT INTO #MovementTypeMap
SELECT InventoryMovementTypeCode, InventoryMovementTypeID, QuantityDirection
FROM ref.InventoryMovementType
WHERE IsActive = 1;

IF (SELECT COUNT(*) FROM #MovementTypeMap) <> 10
   OR EXISTS
      (
          SELECT required.Code
          FROM (VALUES
              ('OPENING_STOCK'),('PURCHASE_RECEIPT'),('SALE'),
              ('CUSTOMER_RETURN'),('DAMAGE_WRITEOFF'),
              ('ADJUSTMENT_IN'),('ADJUSTMENT_OUT'),
              ('TRANSFER_IN'),('TRANSFER_OUT')
          ) AS required (Code)
          WHERE NOT EXISTS
          (
              SELECT 1 FROM #MovementTypeMap AS movement_type
              WHERE movement_type.InventoryMovementTypeCode = required.Code
          )
      )
    THROW 51363, 'Inventory generation stopped: movement-type reference data is incomplete.', 1;

DECLARE @OpeningMovementTypeID SMALLINT =
(
    SELECT InventoryMovementTypeID FROM #MovementTypeMap
    WHERE InventoryMovementTypeCode = 'OPENING_STOCK'
);

CREATE TABLE #OpeningBalance
(
    ProductID INT NOT NULL,
    StoreID INT NOT NULL,
    OpeningQuantity INT NOT NULL,
    OpeningMovementDate DATETIME2(0) NOT NULL,
    PRIMARY KEY (ProductID, StoreID)
);

INSERT INTO #OpeningBalance
SELECT
    movement.ProductID,
    movement.StoreID,
    CONVERT(INT, SUM(CONVERT(BIGINT, movement.Quantity) * movement.QuantityDirection)),
    MAX(movement.MovementDate)
FROM inventory.InventoryMovement AS movement
WHERE movement.InventoryMovementTypeID = @OpeningMovementTypeID
GROUP BY movement.ProductID, movement.StoreID;

IF (SELECT COUNT(*) FROM #OpeningBalance) <> 7016
   OR EXISTS (SELECT 1 FROM #OpeningBalance WHERE OpeningQuantity <= 0)
    THROW 51364, 'Opening inventory ledger is incomplete or invalid.', 1;

CREATE TABLE #ReservedSeed
(
    ProductID INT NOT NULL,
    StoreID INT NOT NULL,
    ReservedQuantity INT NOT NULL,
    PRIMARY KEY (ProductID, StoreID)
);

INSERT INTO #ReservedSeed
SELECT item.ProductID, orders.StoreID, SUM(item.Quantity)
FROM sales.SalesOrder AS orders
INNER JOIN sales.SalesOrderItem AS item ON item.SalesOrderID = orders.SalesOrderID
INNER JOIN ref.OrderStatus AS status ON status.OrderStatusID = orders.OrderStatusID
WHERE status.OrderStatusCode IN ('CONFIRMED','PROCESSING')
GROUP BY item.ProductID, orders.StoreID;

CREATE TABLE #MovementSeed
(
    MovementSeedID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ProductID INT NOT NULL,
    StoreID INT NOT NULL,
    InventoryMovementTypeCode VARCHAR(30) NOT NULL,
    MovementDate DATETIME2(0) NOT NULL,
    Quantity INT NOT NULL,
    QuantityDirection SMALLINT NOT NULL,
    SalesOrderItemID BIGINT NULL,
    ProductReturnItemID BIGINT NULL,
    ReferenceNumber VARCHAR(50) NOT NULL,
    Reason VARCHAR(255) NOT NULL,
    CreatedByEmployeeID INT NOT NULL
);

-- Fulfilled orders issue stock at shipment.
INSERT INTO #MovementSeed
(
    ProductID, StoreID, InventoryMovementTypeCode, MovementDate,
    Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
    ReferenceNumber, Reason, CreatedByEmployeeID
)
SELECT
    item.ProductID,
    orders.StoreID,
    'SALE',
    orders.ShippedDate,
    item.Quantity,
    -1,
    item.SalesOrderItemID,
    NULL,
    CONCAT('SALE-', orders.OrderNumber, '-', item.SalesOrderItemID),
    'Inventory issued when the synthetic order was shipped',
    orders.EmployeeID
FROM sales.SalesOrder AS orders
INNER JOIN sales.SalesOrderItem AS item ON item.SalesOrderID = orders.SalesOrderID
INNER JOIN ref.OrderStatus AS status ON status.OrderStatusID = orders.OrderStatusID
WHERE status.OrderStatusCode IN ('SHIPPED','DELIVERED','PARTIALLY_RETURNED','RETURNED');

DECLARE @ExpectedSaleMovementCount BIGINT = @@ROWCOUNT;

-- All accepted units enter inspection inventory.
INSERT INTO #MovementSeed
(
    ProductID, StoreID, InventoryMovementTypeCode, MovementDate,
    Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
    ReferenceNumber, Reason, CreatedByEmployeeID
)
SELECT
    order_item.ProductID,
    orders.StoreID,
    'CUSTOMER_RETURN',
    return_header.ReceivedDate,
    return_item.QuantityAccepted,
    1,
    NULL,
    return_item.ProductReturnItemID,
    CONCAT('RETURN-', return_header.ReturnNumber, '-', return_item.ProductReturnItemID),
    'Accepted customer return received for inspection',
    orders.EmployeeID
FROM sales.ProductReturnItem AS return_item
INNER JOIN sales.ProductReturn AS return_header
    ON return_header.ProductReturnID = return_item.ProductReturnID
INNER JOIN sales.SalesOrderItem AS order_item
    ON order_item.SalesOrderItemID = return_item.SalesOrderItemID
INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = return_header.SalesOrderID
WHERE return_item.QuantityAccepted > 0;

DECLARE @ExpectedReturnMovementCount BIGINT = @@ROWCOUNT;

-- Non-reusable accepted units are removed after inspection.
INSERT INTO #MovementSeed
(
    ProductID, StoreID, InventoryMovementTypeCode, MovementDate,
    Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
    ReferenceNumber, Reason, CreatedByEmployeeID
)
SELECT
    order_item.ProductID,
    orders.StoreID,
    'DAMAGE_WRITEOFF',
    DATEADD(MINUTE, 5, return_header.ReceivedDate),
    return_item.QuantityAccepted,
    -1,
    NULL,
    return_item.ProductReturnItemID,
    CONCAT('WRITEOFF-', return_header.ReturnNumber, '-', return_item.ProductReturnItemID),
    'Accepted return classified as non-reusable after inspection',
    orders.EmployeeID
FROM sales.ProductReturnItem AS return_item
INNER JOIN sales.ProductReturn AS return_header
    ON return_header.ProductReturnID = return_item.ProductReturnID
INNER JOIN sales.SalesOrderItem AS order_item
    ON order_item.SalesOrderItemID = return_item.SalesOrderItemID
INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = return_header.SalesOrderID
WHERE return_item.QuantityAccepted > 0
  AND return_item.IsReusable = 0;

-- A small controlled cycle-count sample creates realistic positive/negative adjustments.
;WITH RankedBalances AS
(
    SELECT
        opening.ProductID,
        opening.StoreID,
        store.ManagerEmployeeID,
        ROW_NUMBER() OVER (ORDER BY store.StoreCode, product.SKU) AS AdjustmentSequence
    FROM #OpeningBalance AS opening
    INNER JOIN core.Store AS store ON store.StoreID = opening.StoreID
    INNER JOIN core.Product AS product ON product.ProductID = opening.ProductID
)
INSERT INTO #MovementSeed
(
    ProductID, StoreID, InventoryMovementTypeCode, MovementDate,
    Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
    ReferenceNumber, Reason, CreatedByEmployeeID
)
SELECT TOP (500)
    ranked.ProductID,
    ranked.StoreID,
    CASE WHEN ranked.AdjustmentSequence % 2 = 0 THEN 'ADJUSTMENT_IN' ELSE 'ADJUSTMENT_OUT' END,
    DATEADD(MINUTE, ranked.AdjustmentSequence % 720, CONVERT(DATETIME2(0), '2026-06-28T06:00:00')),
    1 + (ranked.AdjustmentSequence % 2),
    CASE WHEN ranked.AdjustmentSequence % 2 = 0 THEN 1 ELSE -1 END,
    NULL,
    NULL,
    CONCAT('ADJ-', RIGHT(CONCAT('000000', ranked.AdjustmentSequence), 6)),
    'Synthetic approved cycle-count adjustment',
    ranked.ManagerEmployeeID
FROM RankedBalances AS ranked
ORDER BY ranked.AdjustmentSequence;

CREATE TABLE #TransferSeed
(
    TransferSequence INT NOT NULL PRIMARY KEY,
    ProductID INT NOT NULL,
    SourceStoreID INT NOT NULL,
    DestinationStoreID INT NOT NULL,
    Quantity INT NOT NULL,
    MovementDate DATETIME2(0) NOT NULL,
    ReferenceNumber VARCHAR(50) NOT NULL UNIQUE,
    SourceEmployeeID INT NOT NULL,
    DestinationEmployeeID INT NOT NULL
);

;WITH TransferCandidates AS
(
    SELECT TOP (500)
        source.ProductID,
        source.StoreID AS SourceStoreID,
        destination.StoreID AS DestinationStoreID,
        source_store.ManagerEmployeeID AS SourceEmployeeID,
        destination_store.ManagerEmployeeID AS DestinationEmployeeID,
        ROW_NUMBER() OVER
        (
            ORDER BY source.ProductID, source.StoreID, destination.StoreID
        ) AS TransferSequence
    FROM #OpeningBalance AS source
    INNER JOIN #OpeningBalance AS destination
        ON destination.ProductID = source.ProductID
       AND destination.StoreID > source.StoreID
    INNER JOIN core.Store AS source_store ON source_store.StoreID = source.StoreID
    INNER JOIN core.Store AS destination_store ON destination_store.StoreID = destination.StoreID
    ORDER BY source.ProductID, source.StoreID, destination.StoreID
)
INSERT INTO #TransferSeed
SELECT
    CONVERT(INT, TransferSequence),
    ProductID,
    SourceStoreID,
    DestinationStoreID,
    1 + (TransferSequence % 3),
    DATEADD(MINUTE, TransferSequence, CONVERT(DATETIME2(0), '2026-06-29T06:00:00')),
    CONCAT('TRF-', RIGHT(CONCAT('000000', TransferSequence), 6)),
    SourceEmployeeID,
    DestinationEmployeeID
FROM TransferCandidates;

IF (SELECT COUNT(*) FROM #TransferSeed) <> 500
    THROW 51365, 'Inventory transfer seed failed to produce 500 transfer events.', 1;

INSERT INTO #MovementSeed
(
    ProductID, StoreID, InventoryMovementTypeCode, MovementDate,
    Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
    ReferenceNumber, Reason, CreatedByEmployeeID
)
SELECT ProductID, SourceStoreID, 'TRANSFER_OUT', MovementDate,
       Quantity, -1, NULL, NULL, ReferenceNumber,
       'Synthetic inter-store transfer dispatched', SourceEmployeeID
FROM #TransferSeed
UNION ALL
SELECT ProductID, DestinationStoreID, 'TRANSFER_IN', DATEADD(MINUTE, 30, MovementDate),
       Quantity, 1, NULL, NULL, ReferenceNumber,
       'Synthetic inter-store transfer received', DestinationEmployeeID
FROM #TransferSeed;

-- Replenishment is calculated from all projected outgoing movements. Positive
-- future movements are deliberately ignored, guaranteeing non-negative stock
-- throughout the complete chronology rather than only at the final snapshot.
;WITH OutgoingDemand AS
(
    SELECT ProductID, StoreID, SUM(Quantity) AS OutgoingQuantity
    FROM #MovementSeed
    WHERE QuantityDirection = -1
    GROUP BY ProductID, StoreID
),
ReceiptRequirement AS
(
    SELECT
        opening.ProductID,
        opening.StoreID,
        store.ManagerEmployeeID,
        CASE
            WHEN COALESCE(outgoing.OutgoingQuantity, 0)
               + COALESCE(reserved.ReservedQuantity, 0)
               + product.ReorderLevel > opening.OpeningQuantity
            THEN COALESCE(outgoing.OutgoingQuantity, 0)
               + COALESCE(reserved.ReservedQuantity, 0)
               + product.ReorderLevel - opening.OpeningQuantity
            ELSE 0
        END AS ReceiptQuantity
    FROM #OpeningBalance AS opening
    INNER JOIN core.Product AS product ON product.ProductID = opening.ProductID
    INNER JOIN core.Store AS store ON store.StoreID = opening.StoreID
    LEFT JOIN OutgoingDemand AS outgoing
        ON outgoing.ProductID = opening.ProductID AND outgoing.StoreID = opening.StoreID
    LEFT JOIN #ReservedSeed AS reserved
        ON reserved.ProductID = opening.ProductID AND reserved.StoreID = opening.StoreID
)
INSERT INTO #MovementSeed
(
    ProductID, StoreID, InventoryMovementTypeCode, MovementDate,
    Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
    ReferenceNumber, Reason, CreatedByEmployeeID
)
SELECT
    requirement.ProductID,
    requirement.StoreID,
    'PURCHASE_RECEIPT',
    CONVERT(DATETIME2(0), '2023-06-30T23:00:00'),
    requirement.ReceiptQuantity,
    1,
    NULL,
    NULL,
    CONCAT('PO-INITIAL-', requirement.StoreID, '-', requirement.ProductID),
    'Synthetic demand-covering supplier receipt',
    requirement.ManagerEmployeeID
FROM ReceiptRequirement AS requirement
WHERE requirement.ReceiptQuantity > 0;

IF EXISTS
(
    SELECT 1 FROM #MovementSeed AS seed
    LEFT JOIN #MovementTypeMap AS movement_type
        ON movement_type.InventoryMovementTypeCode = seed.InventoryMovementTypeCode
    WHERE seed.Quantity <= 0
       OR seed.CreatedByEmployeeID IS NULL
       OR movement_type.InventoryMovementTypeID IS NULL
       OR movement_type.QuantityDirection <> seed.QuantityDirection
       OR (seed.SalesOrderItemID IS NOT NULL AND seed.ProductReturnItemID IS NOT NULL)
)
    THROW 51366, 'Inventory movement seed failed structural validation.', 1;

IF @ExpectedSaleMovementCount = 0 OR @ExpectedReturnMovementCount = 0
    THROW 51367, 'Inventory movement seed is missing sale or accepted-return activity.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE FROM inventory.InventoryMovement
    WHERE InventoryMovementTypeID <> @OpeningMovementTypeID;

    INSERT INTO inventory.InventoryMovement
    (
        ProductID, StoreID, InventoryMovementTypeID, MovementDate,
        Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
        ReferenceNumber, Reason, CreatedByEmployeeID
    )
    SELECT
        seed.ProductID,
        seed.StoreID,
        movement_type.InventoryMovementTypeID,
        seed.MovementDate,
        seed.Quantity,
        seed.QuantityDirection,
        seed.SalesOrderItemID,
        seed.ProductReturnItemID,
        seed.ReferenceNumber,
        seed.Reason,
        seed.CreatedByEmployeeID
    FROM #MovementSeed AS seed
    INNER JOIN #MovementTypeMap AS movement_type
        ON movement_type.InventoryMovementTypeCode = seed.InventoryMovementTypeCode;

    ;WITH LedgerBalance AS
    (
        SELECT
            movement.ProductID,
            movement.StoreID,
            SUM(CONVERT(BIGINT, movement.Quantity) * movement.QuantityDirection) AS QuantityOnHand,
            MAX(movement.MovementDate) AS LastMovementDate,
            MAX(CASE WHEN movement.QuantityDirection = 1
                     THEN movement.MovementDate
                     ELSE CONVERT(DATETIME2(0), '1900-01-01') END) AS LastRestockedDate
        FROM inventory.InventoryMovement AS movement
        GROUP BY movement.ProductID, movement.StoreID
    )
    UPDATE balance
    SET QuantityOnHand = CONVERT(INT, ledger.QuantityOnHand),
        QuantityReserved = COALESCE(reserved.ReservedQuantity, 0),
        LastMovementDate = ledger.LastMovementDate,
        LastRestockedDate = ledger.LastRestockedDate,
        ModifiedDate = SYSDATETIME()
    FROM inventory.InventoryBalance AS balance
    INNER JOIN LedgerBalance AS ledger
        ON ledger.ProductID = balance.ProductID AND ledger.StoreID = balance.StoreID
    LEFT JOIN #ReservedSeed AS reserved
        ON reserved.ProductID = balance.ProductID AND reserved.StoreID = balance.StoreID;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ============================================================================
-- ACCEPTANCE VALIDATION
-- ============================================================================

IF EXISTS
(
    SELECT 1
    FROM inventory.InventoryBalance AS balance
    LEFT JOIN
    (
        SELECT ProductID, StoreID,
               SUM(CONVERT(BIGINT, Quantity) * QuantityDirection) AS LedgerQuantity
        FROM inventory.InventoryMovement
        GROUP BY ProductID, StoreID
    ) AS ledger
        ON ledger.ProductID = balance.ProductID AND ledger.StoreID = balance.StoreID
    WHERE ledger.ProductID IS NULL
       OR ledger.LedgerQuantity <> balance.QuantityOnHand
       OR balance.QuantityOnHand < 0
       OR balance.QuantityReserved < 0
       OR balance.QuantityReserved > balance.QuantityOnHand
)
    THROW 51368, 'Inventory validation failed: balance-to-ledger reconciliation error.', 1;

IF EXISTS
(
    SELECT movement.ReferenceNumber
    FROM inventory.InventoryMovement AS movement
    INNER JOIN #MovementTypeMap AS movement_type
        ON movement_type.InventoryMovementTypeID = movement.InventoryMovementTypeID
    WHERE movement_type.InventoryMovementTypeCode IN ('TRANSFER_IN','TRANSFER_OUT')
    GROUP BY movement.ReferenceNumber
    HAVING SUM(movement.Quantity * movement.QuantityDirection) <> 0
       OR COUNT(*) <> 2
)
    THROW 51369, 'Inventory validation failed: an inter-store transfer is unbalanced.', 1;

IF EXISTS
(
    SELECT 1
    FROM
    (
        SELECT
            movement.ProductID,
            movement.StoreID,
            movement.MovementDate,
            movement.InventoryMovementID,
            SUM(CONVERT(BIGINT, movement.Quantity) * movement.QuantityDirection) OVER
            (
                PARTITION BY movement.ProductID, movement.StoreID
                ORDER BY movement.MovementDate, movement.InventoryMovementID
                ROWS UNBOUNDED PRECEDING
            ) AS RunningQuantity
        FROM inventory.InventoryMovement AS movement
    ) AS running_ledger
    WHERE running_ledger.RunningQuantity < 0
)
    THROW 51370, 'Inventory validation failed: chronological ledger produced negative stock.', 1;

IF (SELECT COUNT(*) FROM inventory.InventoryMovement AS movement
    INNER JOIN #MovementTypeMap AS movement_type
        ON movement_type.InventoryMovementTypeID = movement.InventoryMovementTypeID
    WHERE movement_type.InventoryMovementTypeCode = 'SALE') <> @ExpectedSaleMovementCount
   OR (SELECT COUNT(*) FROM inventory.InventoryMovement AS movement
       INNER JOIN #MovementTypeMap AS movement_type
        ON movement_type.InventoryMovementTypeID = movement.InventoryMovementTypeID
       WHERE movement_type.InventoryMovementTypeCode = 'CUSTOMER_RETURN') <> @ExpectedReturnMovementCount
    THROW 51371, 'Inventory validation failed: sale or return movement count mismatch.', 1;

SELECT
    movement_type.InventoryMovementTypeCode,
    movement_type.InventoryMovementTypeName,
    COUNT_BIG(*) AS MovementCount,
    SUM(CONVERT(BIGINT, movement.Quantity)) AS UnitCount,
    SUM(CONVERT(BIGINT, movement.Quantity) * movement.QuantityDirection) AS NetUnitImpact,
    'PASSED' AS ValidationStatus
FROM inventory.InventoryMovement AS movement
INNER JOIN ref.InventoryMovementType AS movement_type
    ON movement_type.InventoryMovementTypeID = movement.InventoryMovementTypeID
GROUP BY movement_type.InventoryMovementTypeCode,
         movement_type.InventoryMovementTypeName,
         movement_type.SortOrder
ORDER BY movement_type.SortOrder;

SELECT
    COUNT_BIG(*) AS InventoryBalanceCount,
    COUNT(DISTINCT StoreID) AS StoreCount,
    COUNT(DISTINCT ProductID) AS StockedProductCount,
    SUM(CONVERT(BIGINT, QuantityOnHand)) AS QuantityOnHand,
    SUM(CONVERT(BIGINT, QuantityReserved)) AS QuantityReserved,
    SUM(CONVERT(BIGINT, QuantityOnHand - QuantityReserved)) AS QuantityAvailable,
    MIN(QuantityOnHand) AS MinimumBalance,
    MAX(QuantityOnHand) AS MaximumBalance,
    'PASSED' AS ValidationStatus
FROM inventory.InventoryBalance;

SELECT
    @ExpectedSaleMovementCount AS SaleMovementCount,
    @ExpectedReturnMovementCount AS CustomerReturnMovementCount,
    (SELECT COUNT(*) FROM #TransferSeed) AS TransferEventCount,
    (SELECT COUNT_BIG(*) FROM inventory.InventoryMovement) AS TotalMovementCount,
    'PASSED' AS ValidationStatus;

RAISERROR('21_Generate_Inventory_Movements.sql completed successfully: inventory ledger and balances reconciled.', 10, 1) WITH NOWAIT;
GO
