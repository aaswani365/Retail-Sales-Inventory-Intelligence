/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      16_Generate_Opening_Inventory.sql
Purpose:     Create realistic product-store assortments and opening inventory.
Author:      Akshay Aswani
Version:     2.0
Depends on:  15_Generate_Products.sql
Rerunnable:  Yes, until downstream non-opening inventory movements exist.

Store-tier assortment
---------------------
- Large:  6 stores x 437 active products = 2,622 balances (90.10% coverage)
- Medium: 8 stores x 349 active products = 2,792 balances (71.96% coverage)
- Small:  6 stores x 267 active products = 1,602 balances (55.05% coverage)
- Total:                                  7,016 balances

Every balance is supported by exactly one OPENING_STOCK ledger movement.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51260, 'Opening inventory generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'inventory.InventoryBalance', N'U') IS NULL
   OR OBJECT_ID(N'inventory.InventoryMovement', N'U') IS NULL
   OR OBJECT_ID(N'core.Product', N'U') IS NULL
   OR OBJECT_ID(N'core.Store', N'U') IS NULL
   OR OBJECT_ID(N'core.Employee', N'U') IS NULL
   OR OBJECT_ID(N'ref.InventoryMovementType', N'U') IS NULL
BEGIN
    THROW 51261, 'Opening inventory generation stopped: one or more required tables are missing.', 1;
END;

IF (SELECT COUNT(*) FROM core.Product) <> 500
   OR (SELECT COUNT(*) FROM core.Product WHERE IsActive = 1) <> 485
   OR (SELECT COUNT(*) FROM core.Store WHERE IsActive = 1) <> 20
BEGIN
    THROW 51262, 'Opening inventory generation stopped: expected 500 products, 485 active products, and 20 active stores.', 1;
END;

DECLARE @OpeningMovementTypeID SMALLINT;

SELECT @OpeningMovementTypeID = InventoryMovementTypeID
FROM ref.InventoryMovementType
WHERE InventoryMovementTypeCode = 'OPENING_STOCK'
  AND QuantityDirection = 1
  AND IsActive = 1;

IF @OpeningMovementTypeID IS NULL
BEGIN
    THROW 51263, 'Opening inventory generation stopped: active OPENING_STOCK movement type is missing or invalid.', 1;
END;

-- This master-data script must not rewrite balances after transactional movements exist.
IF EXISTS
(
    SELECT 1
    FROM inventory.InventoryMovement
    WHERE InventoryMovementTypeID <> @OpeningMovementTypeID
)
BEGIN
    THROW 51264, 'Opening inventory cannot be rerun after downstream inventory movements exist.', 1;
END;

DROP TABLE IF EXISTS #StoreTier;
DROP TABLE IF EXISTS #AssortmentSeed;

CREATE TABLE #StoreTier
(
    StoreCode VARCHAR(20) NOT NULL PRIMARY KEY,
    StoreTier VARCHAR(10) NOT NULL,
    TargetProductCount INT NOT NULL
);

INSERT INTO #StoreTier (StoreCode, StoreTier, TargetProductCount) VALUES
-- Large stores: 90.10% of 485 active products
('STR-BLR-01','Large',437),
('STR-DEL-01','Large',437),
('STR-GGN-01','Large',437),
('STR-HYD-01','Large',437),
('STR-MUM-01','Large',437),
('STR-PUN-01','Large',437),
-- Medium stores: 71.96% of 485 active products
('STR-AHM-01','Medium',349),
('STR-CHD-01','Medium',349),
('STR-CHE-01','Medium',349),
('STR-JAI-01','Medium',349),
('STR-KOL-01','Medium',349),
('STR-LKO-01','Medium',349),
('STR-NOI-01','Medium',349),
('STR-SUR-01','Medium',349),
-- Small stores: 55.05% of 485 active products
('STR-BBI-01','Small',267),
('STR-CBE-01','Small',267),
('STR-IND-01','Small',267),
('STR-KOC-01','Small',267),
('STR-RPR-01','Small',267),
('STR-VAD-01','Small',267);

IF EXISTS
(
    SELECT tier.StoreCode
    FROM #StoreTier AS tier
    LEFT JOIN core.Store AS store ON store.StoreCode = tier.StoreCode
    WHERE store.StoreID IS NULL OR store.IsActive <> 1
)
BEGIN
    THROW 51265, 'Opening inventory generation stopped: approved store-tier mapping is incomplete.', 1;
END;

CREATE TABLE #AssortmentSeed
(
    ProductID INT NOT NULL,
    StoreID INT NOT NULL,
    SKU VARCHAR(40) NOT NULL,
    StoreCode VARCHAR(20) NOT NULL,
    StoreTier VARCHAR(10) NOT NULL,
    OpeningQuantity INT NOT NULL,
    MovementDate DATETIME2(0) NOT NULL,
    ReferenceNumber VARCHAR(50) NOT NULL,
    CreatedByEmployeeID INT NOT NULL,
    PRIMARY KEY (ProductID, StoreID),
    UNIQUE (ReferenceNumber)
);

;WITH RankedProducts AS
(
    SELECT
        product.ProductID,
        product.SKU,
        product.ReorderLevel,
        ROW_NUMBER() OVER (ORDER BY product.SKU) AS ProductNumber
    FROM core.Product AS product
    WHERE product.IsActive = 1
),
RankedStores AS
(
    SELECT
        store.StoreID,
        store.StoreCode,
        store.ManagerEmployeeID,
        tier.StoreTier,
        tier.TargetProductCount,
        ROW_NUMBER() OVER (ORDER BY store.StoreCode) AS StoreNumber
    FROM core.Store AS store
    INNER JOIN #StoreTier AS tier ON tier.StoreCode = store.StoreCode
    WHERE store.IsActive = 1
),
Candidates AS
(
    SELECT
        product.ProductID,
        product.SKU,
        product.ReorderLevel,
        product.ProductNumber,
        store.StoreID,
        store.StoreCode,
        store.ManagerEmployeeID,
        store.StoreTier,
        store.StoreNumber,
        store.TargetProductCount,
        (((product.ProductNumber * 37) + (store.StoreNumber * 53) - 1) % 485) + 1 AS AssortmentRank
    FROM RankedProducts AS product
    CROSS JOIN RankedStores AS store
)
INSERT INTO #AssortmentSeed
(
    ProductID, StoreID, SKU, StoreCode, StoreTier,
    OpeningQuantity, MovementDate, ReferenceNumber, CreatedByEmployeeID
)
SELECT
    candidate.ProductID,
    candidate.StoreID,
    candidate.SKU,
    candidate.StoreCode,
    candidate.StoreTier,
    CASE
        WHEN candidate.ProductNumber <= 100
            THEN (candidate.ReorderLevel * 3) + (candidate.AssortmentRank % 15)
        WHEN candidate.ProductNumber <= 350
            THEN (candidate.ReorderLevel * 2) + (candidate.AssortmentRank % 12)
        ELSE candidate.ReorderLevel + 5 + (candidate.AssortmentRank % 8)
    END,
    DATEADD
    (
        MINUTE,
        ((candidate.ProductNumber * 7) + (candidate.StoreNumber * 11)) % 600,
        CONVERT(DATETIME2(0), '2023-06-30T06:00:00')
    ),
    CONCAT('OPEN-', candidate.StoreCode, '-', candidate.SKU),
    candidate.ManagerEmployeeID
FROM Candidates AS candidate
WHERE candidate.AssortmentRank <= candidate.TargetProductCount;

IF (SELECT COUNT(*) FROM #AssortmentSeed) <> 7016
   OR EXISTS (SELECT 1 FROM #AssortmentSeed WHERE OpeningQuantity <= 0)
   OR EXISTS (SELECT 1 FROM #AssortmentSeed WHERE CreatedByEmployeeID IS NULL)
BEGIN
    THROW 51266, 'Opening inventory seed validation failed before loading.', 1;
END;

IF EXISTS
(
    SELECT movement.ProductID, movement.StoreID
    FROM inventory.InventoryMovement AS movement
    WHERE movement.InventoryMovementTypeID = @OpeningMovementTypeID
    GROUP BY movement.ProductID, movement.StoreID
    HAVING COUNT(*) > 1
)
BEGIN
    THROW 51267, 'Opening inventory load stopped: duplicate opening movements already exist.', 1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE movement
    SET MovementDate = seed.MovementDate,
        Quantity = seed.OpeningQuantity,
        QuantityDirection = 1,
        SalesOrderItemID = NULL,
        ProductReturnItemID = NULL,
        ReferenceNumber = seed.ReferenceNumber,
        Reason = 'Deterministic opening inventory load',
        CreatedByEmployeeID = seed.CreatedByEmployeeID
    FROM inventory.InventoryMovement AS movement
    INNER JOIN #AssortmentSeed AS seed
        ON seed.ProductID = movement.ProductID
       AND seed.StoreID = movement.StoreID
    WHERE movement.InventoryMovementTypeID = @OpeningMovementTypeID;

    INSERT INTO inventory.InventoryMovement
    (
        ProductID, StoreID, InventoryMovementTypeID, MovementDate,
        Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
        ReferenceNumber, Reason, CreatedByEmployeeID
    )
    SELECT
        seed.ProductID, seed.StoreID, @OpeningMovementTypeID, seed.MovementDate,
        seed.OpeningQuantity, 1, NULL, NULL,
        seed.ReferenceNumber, 'Deterministic opening inventory load', seed.CreatedByEmployeeID
    FROM #AssortmentSeed AS seed
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM inventory.InventoryMovement AS movement
        WHERE movement.ProductID = seed.ProductID
          AND movement.StoreID = seed.StoreID
          AND movement.InventoryMovementTypeID = @OpeningMovementTypeID
    );

    UPDATE balance
    SET QuantityOnHand = seed.OpeningQuantity,
        QuantityReserved = 0,
        LastMovementDate = seed.MovementDate,
        LastRestockedDate = seed.MovementDate,
        ModifiedDate = SYSDATETIME()
    FROM inventory.InventoryBalance AS balance
    INNER JOIN #AssortmentSeed AS seed
        ON seed.ProductID = balance.ProductID
       AND seed.StoreID = balance.StoreID;

    INSERT INTO inventory.InventoryBalance
    (
        ProductID, StoreID, QuantityOnHand, QuantityReserved,
        LastMovementDate, LastRestockedDate
    )
    SELECT
        seed.ProductID, seed.StoreID, seed.OpeningQuantity, 0,
        seed.MovementDate, seed.MovementDate
    FROM #AssortmentSeed AS seed
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM inventory.InventoryBalance AS balance
        WHERE balance.ProductID = seed.ProductID
          AND balance.StoreID = seed.StoreID
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

DECLARE @BalanceCount BIGINT = (SELECT COUNT_BIG(*) FROM inventory.InventoryBalance);
DECLARE @OpeningMovementCount BIGINT =
(
    SELECT COUNT_BIG(*)
    FROM inventory.InventoryMovement
    WHERE InventoryMovementTypeID = @OpeningMovementTypeID
);

IF @BalanceCount <> 7016 OR @OpeningMovementCount <> 7016
BEGIN
    THROW 51268, 'Opening inventory validation failed: expected 7,016 balances and movements.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM inventory.InventoryBalance AS balance
    LEFT JOIN
    (
        SELECT
            movement.ProductID,
            movement.StoreID,
            SUM(CONVERT(BIGINT, movement.Quantity) * movement.QuantityDirection) AS CalculatedQuantity
        FROM inventory.InventoryMovement AS movement
        GROUP BY movement.ProductID, movement.StoreID
    ) AS ledger
        ON ledger.ProductID = balance.ProductID
       AND ledger.StoreID = balance.StoreID
    WHERE ledger.ProductID IS NULL
       OR ledger.CalculatedQuantity <> balance.QuantityOnHand
       OR balance.QuantityReserved <> 0
)
BEGIN
    THROW 51269, 'Opening inventory validation failed: balance-to-ledger reconciliation error.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM core.Product AS product
    LEFT JOIN inventory.InventoryBalance AS balance ON balance.ProductID = product.ProductID
    GROUP BY product.ProductID, product.IsActive
    HAVING (product.IsActive = 1 AND COUNT(balance.InventoryBalanceID) = 0)
        OR (product.IsActive = 0 AND COUNT(balance.InventoryBalanceID) > 0)
)
BEGIN
    THROW 51270, 'Opening inventory validation failed: active-product coverage or inactive-product exclusion error.', 1;
END;

SELECT
    seed.StoreTier,
    COUNT(DISTINCT seed.StoreID) AS StoreCount,
    COUNT_BIG(*) AS InventoryBalanceCount,
    MIN(store_count.ProductCount) AS MinimumProductsPerStore,
    MAX(store_count.ProductCount) AS MaximumProductsPerStore,
    SUM(CONVERT(BIGINT, seed.OpeningQuantity)) AS OpeningUnitCount,
    'PASSED' AS ValidationStatus
FROM #AssortmentSeed AS seed
INNER JOIN
(
    SELECT StoreID, COUNT(*) AS ProductCount
    FROM #AssortmentSeed
    GROUP BY StoreID
) AS store_count ON store_count.StoreID = seed.StoreID
GROUP BY seed.StoreTier
ORDER BY
    CASE seed.StoreTier WHEN 'Large' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;

SELECT
    @BalanceCount AS InventoryBalanceCount,
    @OpeningMovementCount AS OpeningMovementCount,
    COUNT(DISTINCT balance.StoreID) AS StoreCount,
    COUNT(DISTINCT balance.ProductID) AS StockedActiveProductCount,
    SUM(CONVERT(BIGINT, balance.QuantityOnHand)) AS OpeningUnitCount,
    SUM(CONVERT(BIGINT, balance.QuantityReserved)) AS ReservedUnitCount,
    CASE
        WHEN @BalanceCount = 7016
         AND @OpeningMovementCount = 7016
         AND COUNT(DISTINCT balance.StoreID) = 20
         AND COUNT(DISTINCT balance.ProductID) = 485
         AND SUM(CONVERT(BIGINT, balance.QuantityReserved)) = 0
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM inventory.InventoryBalance AS balance;

RAISERROR('16_Generate_Opening_Inventory.sql completed successfully: 7,016 balances reconciled to opening movements.', 10, 1) WITH NOWAIT;
GO
