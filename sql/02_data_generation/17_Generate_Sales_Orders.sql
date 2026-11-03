/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      17_Generate_Sales_Orders.sql
Purpose:     Generate 100,000 order headers and 300,000 connected order items.
Author:      Akshay Aswani
Version:     2.0
Depends on:  16_Generate_Opening_Inventory.sql
Rerunnable:  Yes, until downstream lifecycle, payment, return, or sale-movement data exists.

Core design
-----------
- Reporting period: 2023-07-01 through 2026-06-30.
- Annual order mix: 28,000 / 33,000 / 39,000.
- Weighted dates model weekday, weekend, seasonal, and growth effects.
- Customer order contribution: 33% high value, 37% regular,
  25% occasional, and 5% one-time/dormant.
- Item-count distribution produces exactly 300,000 unique order lines.
- Product demand mix targets 60% high, 34% medium, and 6% low demand.
- All amounts are calculated at line level and reconciled to the header.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51270, 'Sales-order generation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'sales.SalesOrder', N'U') IS NULL
   OR OBJECT_ID(N'sales.SalesOrderItem', N'U') IS NULL
   OR OBJECT_ID(N'core.Customer', N'U') IS NULL
   OR OBJECT_ID(N'core.Employee', N'U') IS NULL
   OR OBJECT_ID(N'core.Product', N'U') IS NULL
   OR OBJECT_ID(N'inventory.InventoryBalance', N'U') IS NULL
BEGIN
    THROW 51271, 'Sales-order generation stopped: one or more required tables are missing.', 1;
END;

IF (SELECT COUNT(*) FROM core.Customer) <> 10000
   OR (SELECT COUNT(*) FROM core.Store WHERE IsActive = 1) <> 20
   OR (SELECT COUNT(*) FROM core.Product WHERE IsActive = 1) <> 485
   OR (SELECT COUNT_BIG(*) FROM inventory.InventoryBalance) <> 7016
BEGIN
    THROW 51272, 'Sales-order generation stopped: approved master-data counts are missing.', 1;
END;

DECLARE @PendingStatusID SMALLINT;
DECLARE @OpeningMovementTypeID SMALLINT;
DECLARE @ControlledOneTimeCustomerID INT;

SELECT @PendingStatusID = OrderStatusID
FROM ref.OrderStatus
WHERE OrderStatusCode = 'PENDING' AND IsActive = 1;

SELECT @OpeningMovementTypeID = InventoryMovementTypeID
FROM ref.InventoryMovementType
WHERE InventoryMovementTypeCode = 'OPENING_STOCK' AND IsActive = 1;

SELECT TOP (1) @ControlledOneTimeCustomerID = CustomerID
FROM core.Customer
WHERE IsActive = 1
  AND CONVERT(INT, RIGHT(CustomerCode, 5)) BETWEEN 8501 AND 9500
ORDER BY RegistrationDate, CustomerCode;

IF @PendingStatusID IS NULL
   OR @OpeningMovementTypeID IS NULL
   OR @ControlledOneTimeCustomerID IS NULL
BEGIN
    THROW 51273, 'Sales-order generation stopped: required Pending or Opening Stock reference is missing.', 1;
END;

-- Prevent this stage from rewriting order foundations after downstream facts exist.
IF EXISTS (SELECT 1 FROM sales.OrderStatusHistory)
   OR EXISTS (SELECT 1 FROM sales.Payment)
   OR EXISTS (SELECT 1 FROM sales.ProductReturn)
   OR EXISTS
      (
          SELECT 1
          FROM inventory.InventoryMovement
          WHERE InventoryMovementTypeID <> @OpeningMovementTypeID
      )
BEGIN
    THROW 51274, 'Sales-order generation cannot be rerun after downstream transactional data exists.', 1;
END;

DROP TABLE IF EXISTS #CalendarWeight;
DROP TABLE IF EXISTS #DateQuota;
DROP TABLE IF EXISTS #CustomerPool;
DROP TABLE IF EXISTS #EligibleCustomerCount;
DROP TABLE IF EXISTS #StorePool;
DROP TABLE IF EXISTS #OrderSeed;
DROP TABLE IF EXISTS #StoreProductPool;
DROP TABLE IF EXISTS #LineSlot;
DROP TABLE IF EXISTS #ItemSeed;

-- ============================================================================
-- 1. CALENDAR WEIGHTS AND EXACT DAILY QUOTAS
-- ============================================================================

CREATE TABLE #CalendarWeight
(
    BusinessDate DATE NOT NULL PRIMARY KEY,
    PeriodNumber TINYINT NOT NULL,
    PeriodTarget INT NOT NULL,
    CombinedWeight DECIMAL(12,6) NOT NULL
);

;WITH Digits AS
(
    SELECT Digit
    FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS value_list (Digit)
),
DayNumbers AS
(
    SELECT TOP (1096)
        ROW_NUMBER() OVER (ORDER BY d4.Digit, d3.Digit, d2.Digit, d1.Digit) - 1 AS DayNumber
    FROM Digits AS d1
    CROSS JOIN Digits AS d2
    CROSS JOIN Digits AS d3
    CROSS JOIN Digits AS d4
),
Calendar AS
(
    SELECT DATEADD(DAY, DayNumber, CONVERT(DATE, '2023-07-01')) AS BusinessDate
    FROM DayNumbers
),
WeightedCalendar AS
(
    SELECT
        BusinessDate,
        CASE
            WHEN BusinessDate < '2024-07-01' THEN 1
            WHEN BusinessDate < '2025-07-01' THEN 2
            ELSE 3
        END AS PeriodNumber,
        CASE
            WHEN BusinessDate < '2024-07-01' THEN 28000
            WHEN BusinessDate < '2025-07-01' THEN 33000
            ELSE 39000
        END AS PeriodTarget,
        CONVERT(DECIMAL(12,6),
            CASE ((DATEDIFF(DAY, '2023-07-03', BusinessDate) % 7 + 7) % 7) + 1
                WHEN 5 THEN 1.05
                WHEN 6 THEN 1.25
                WHEN 7 THEN 1.20
                ELSE 0.95
            END
            *
            CASE MONTH(BusinessDate)
                WHEN 1 THEN 0.95
                WHEN 2 THEN 0.92
                WHEN 3 THEN 0.92
                WHEN 4 THEN 0.98
                WHEN 5 THEN 1.00
                WHEN 6 THEN 1.05
                WHEN 7 THEN 1.03
                WHEN 8 THEN 1.05
                WHEN 9 THEN 1.10
                WHEN 10 THEN 1.35
                WHEN 11 THEN 1.30
                ELSE 1.15
            END
        ) AS CombinedWeight
    FROM Calendar
)
INSERT INTO #CalendarWeight (BusinessDate, PeriodNumber, PeriodTarget, CombinedWeight)
SELECT BusinessDate, PeriodNumber, PeriodTarget, CombinedWeight
FROM WeightedCalendar;

CREATE TABLE #DateQuota
(
    BusinessDate DATE NOT NULL PRIMARY KEY,
    PeriodNumber TINYINT NOT NULL,
    OrderCount INT NOT NULL
);

;WITH ExactAllocations AS
(
    SELECT
        calendar.BusinessDate,
        calendar.PeriodNumber,
        calendar.PeriodTarget,
        CONVERT(INT, FLOOR(
            calendar.PeriodTarget * calendar.CombinedWeight
            / SUM(calendar.CombinedWeight) OVER (PARTITION BY calendar.PeriodNumber)
        )) AS BaseCount,
        (calendar.PeriodTarget * calendar.CombinedWeight
            / SUM(calendar.CombinedWeight) OVER (PARTITION BY calendar.PeriodNumber))
        - FLOOR(calendar.PeriodTarget * calendar.CombinedWeight
            / SUM(calendar.CombinedWeight) OVER (PARTITION BY calendar.PeriodNumber)) AS FractionalRemainder
    FROM #CalendarWeight AS calendar
),
RankedRemainders AS
(
    SELECT
        allocation.*,
        allocation.PeriodTarget
          - SUM(allocation.BaseCount) OVER (PARTITION BY allocation.PeriodNumber) AS RemainingOrders,
        ROW_NUMBER() OVER
        (
            PARTITION BY allocation.PeriodNumber
            ORDER BY allocation.FractionalRemainder DESC, allocation.BusinessDate
        ) AS RemainderRank
    FROM ExactAllocations AS allocation
)
INSERT INTO #DateQuota (BusinessDate, PeriodNumber, OrderCount)
SELECT
    BusinessDate,
    PeriodNumber,
    BaseCount + CASE WHEN RemainderRank <= RemainingOrders THEN 1 ELSE 0 END
FROM RankedRemainders;

IF (SELECT SUM(OrderCount) FROM #DateQuota) <> 100000
   OR EXISTS
   (
       SELECT 1
       FROM #DateQuota
       GROUP BY PeriodNumber
       HAVING SUM(OrderCount) <>
           CASE PeriodNumber WHEN 1 THEN 28000 WHEN 2 THEN 33000 ELSE 39000 END
   )
BEGIN
    THROW 51275, 'Sales-order date allocation failed to produce exact period totals.', 1;
END;

-- ============================================================================
-- 2. CUSTOMER, STORE, AND EMPLOYEE POOLS
-- ============================================================================

CREATE TABLE #CustomerPool
(
    CustomerID INT NOT NULL PRIMARY KEY,
    CustomerCode VARCHAR(20) NOT NULL,
    CustomerSegment VARCHAR(30) NOT NULL,
    RegistrationDate DATE NOT NULL,
    City VARCHAR(100) NULL,
    SegmentSequence INT NOT NULL,
    UNIQUE (CustomerSegment, SegmentSequence)
);

;WITH ClassifiedCustomers AS
(
    SELECT
        customer.CustomerID,
        customer.CustomerCode,
        customer.RegistrationDate,
        customer.City,
        CASE
            WHEN CONVERT(INT, RIGHT(customer.CustomerCode, 5)) <= 1000 THEN 'High Value / Loyal'
            WHEN CONVERT(INT, RIGHT(customer.CustomerCode, 5)) <= 4000 THEN 'Regular'
            WHEN CONVERT(INT, RIGHT(customer.CustomerCode, 5)) <= 8500 THEN 'Occasional'
            ELSE 'One-Time / Dormant'
        END AS CustomerSegment
    FROM core.Customer AS customer
    WHERE customer.IsActive = 1
      AND customer.CustomerID <> @ControlledOneTimeCustomerID
),
SequencedCustomers AS
(
    SELECT
        classified.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY classified.CustomerSegment
            ORDER BY classified.RegistrationDate, classified.CustomerCode
        ) AS SegmentSequence
    FROM ClassifiedCustomers AS classified
)
INSERT INTO #CustomerPool
(
    CustomerID, CustomerCode, CustomerSegment,
    RegistrationDate, City, SegmentSequence
)
SELECT
    CustomerID, CustomerCode, CustomerSegment,
    RegistrationDate, City, SegmentSequence
FROM SequencedCustomers;

CREATE TABLE #EligibleCustomerCount
(
    BusinessDate DATE NOT NULL,
    CustomerSegment VARCHAR(30) NOT NULL,
    EligibleCount INT NOT NULL,
    PRIMARY KEY (BusinessDate, CustomerSegment)
);

;WITH Segments AS
(
    SELECT CustomerSegment
    FROM (VALUES
        ('High Value / Loyal'),
        ('Regular'),
        ('Occasional'),
        ('One-Time / Dormant')
    ) AS value_list (CustomerSegment)
)
INSERT INTO #EligibleCustomerCount (BusinessDate, CustomerSegment, EligibleCount)
SELECT
    quota.BusinessDate,
    segment.CustomerSegment,
    COUNT(customer.CustomerID)
FROM #DateQuota AS quota
CROSS JOIN Segments AS segment
LEFT JOIN #CustomerPool AS customer
    ON customer.CustomerSegment = segment.CustomerSegment
   AND customer.RegistrationDate <= quota.BusinessDate
GROUP BY quota.BusinessDate, segment.CustomerSegment;

IF EXISTS (SELECT 1 FROM #EligibleCustomerCount WHERE EligibleCount = 0)
BEGIN
    THROW 51276, 'Sales-order generation failed: a date has no eligible customer in a required segment.', 1;
END;

CREATE TABLE #StorePool
(
    StoreID INT NOT NULL PRIMARY KEY,
    StoreCode VARCHAR(20) NOT NULL,
    City VARCHAR(100) NOT NULL,
    StoreTier VARCHAR(10) NOT NULL,
    TierSequence INT NOT NULL,
    TierStoreCount INT NOT NULL,
    UNIQUE (StoreTier, TierSequence)
);

;WITH StoreInventory AS
(
    SELECT
        store.StoreID,
        store.StoreCode,
        store.City,
        COUNT(balance.InventoryBalanceID) AS ProductCount
    FROM core.Store AS store
    INNER JOIN inventory.InventoryBalance AS balance ON balance.StoreID = store.StoreID
    WHERE store.IsActive = 1
    GROUP BY store.StoreID, store.StoreCode, store.City
),
ClassifiedStores AS
(
    SELECT
        inventory.*,
        CASE inventory.ProductCount
            WHEN 437 THEN 'Large'
            WHEN 349 THEN 'Medium'
            WHEN 267 THEN 'Small'
        END AS StoreTier
    FROM StoreInventory AS inventory
),
SequencedStores AS
(
    SELECT
        classified.*,
        ROW_NUMBER() OVER (PARTITION BY classified.StoreTier ORDER BY classified.StoreCode) AS TierSequence,
        COUNT(*) OVER (PARTITION BY classified.StoreTier) AS TierStoreCount
    FROM ClassifiedStores AS classified
)
INSERT INTO #StorePool
(
    StoreID, StoreCode, City, StoreTier, TierSequence, TierStoreCount
)
SELECT StoreID, StoreCode, City, StoreTier, TierSequence, TierStoreCount
FROM SequencedStores;

IF (SELECT COUNT(*) FROM #StorePool) <> 20
   OR EXISTS (SELECT 1 FROM #StorePool WHERE StoreTier IS NULL)
BEGIN
    THROW 51277, 'Sales-order generation failed: store-tier pool is invalid.', 1;
END;

-- ============================================================================
-- 3. EXACT ORDER SEED
-- ============================================================================

CREATE TABLE #OrderSeed
(
    OrderSequence INT NOT NULL PRIMARY KEY,
    OrderNumber VARCHAR(25) NOT NULL UNIQUE,
    CustomerID INT NOT NULL,
    CustomerSegment VARCHAR(30) NOT NULL,
    StoreID INT NOT NULL,
    EmployeeID INT NOT NULL,
    OrderDate DATETIME2(0) NOT NULL,
    ItemCount TINYINT NOT NULL
);

;WITH Digits AS
(
    SELECT Digit
    FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS value_list (Digit)
),
OrderNumbers AS
(
    SELECT TOP (100000)
        CONVERT(INT, ROW_NUMBER() OVER
        (
            ORDER BY d5.Digit, d4.Digit, d3.Digit, d2.Digit, d1.Digit
        )) AS OrderSequence
    FROM Digits AS d1
    CROSS JOIN Digits AS d2
    CROSS JOIN Digits AS d3
    CROSS JOIN Digits AS d4
    CROSS JOIN Digits AS d5
),
CumulativeDates AS
(
    SELECT
        quota.BusinessDate,
        quota.OrderCount,
        SUM(quota.OrderCount) OVER
        (
            ORDER BY quota.BusinessDate
            ROWS UNBOUNDED PRECEDING
        ) AS CumulativeEnd
    FROM #DateQuota AS quota
),
DatedOrders AS
(
    SELECT
        numbers.OrderSequence,
        dates.BusinessDate,
        CASE
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 33 THEN 'High Value / Loyal'
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 70 THEN 'Regular'
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 95 THEN 'Occasional'
            ELSE 'One-Time / Dormant'
        END AS CustomerSegment,
        CASE
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 20 THEN 1
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 45 THEN 2
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 67 THEN 3
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 82 THEN 4
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 91 THEN 5
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 96 THEN 6
            WHEN ((numbers.OrderSequence - 1) % 100) + 1 <= 99 THEN 7
            ELSE 8
        END AS ItemCount
    FROM OrderNumbers AS numbers
    INNER JOIN CumulativeDates AS dates
        ON numbers.OrderSequence > dates.CumulativeEnd - dates.OrderCount
       AND numbers.OrderSequence <= dates.CumulativeEnd
),
TimedOrders AS
(
    SELECT
        dated.*,
        DATEADD
        (
            MINUTE,
            CASE
                WHEN dated.OrderSequence % 10 BETWEEN 0 AND 3
                    THEN (18 * 60) + ((dated.OrderSequence * 17) % 240)
                ELSE (10 * 60) + ((dated.OrderSequence * 29) % 480)
            END,
            CONVERT(DATETIME2(0), dated.BusinessDate)
        ) AS OrderDate
    FROM DatedOrders AS dated
),
CustomerAssignments AS
(
    SELECT
        timed.*,
        customer.CustomerID,
        customer.City AS CustomerCity
    FROM TimedOrders AS timed
    INNER JOIN #EligibleCustomerCount AS eligible
        ON eligible.BusinessDate = timed.BusinessDate
       AND eligible.CustomerSegment = timed.CustomerSegment
    INNER JOIN #CustomerPool AS customer
        ON customer.CustomerSegment = timed.CustomerSegment
       AND customer.SegmentSequence =
           ((CONVERT(BIGINT, timed.OrderSequence) * 97 - 1) % eligible.EligibleCount) + 1
),
StorePreferences AS
(
    SELECT
        assignment.*,
        CASE
            WHEN ((assignment.OrderSequence - 1) % 20) + 1 <= 9 THEN 'Large'
            WHEN ((assignment.OrderSequence - 1) % 20) + 1 <= 17 THEN 'Medium'
            ELSE 'Small'
        END AS PreferredTier
    FROM CustomerAssignments AS assignment
),
StoreAssignments AS
(
    SELECT
        preference.*,
        COALESCE
        (
            CASE WHEN preference.OrderSequence % 10 < 6 THEN home_store.StoreID END,
            tier_store.StoreID
        ) AS StoreID
    FROM StorePreferences AS preference
    LEFT JOIN #StorePool AS home_store
        ON home_store.City = preference.CustomerCity
    INNER JOIN #StorePool AS tier_store
        ON tier_store.StoreTier = preference.PreferredTier
       AND tier_store.TierSequence =
           ((CONVERT(BIGINT, preference.OrderSequence) * 31 - 1) % tier_store.TierStoreCount) + 1
)
INSERT INTO #OrderSeed
(
    OrderSequence, OrderNumber, CustomerID, CustomerSegment,
    StoreID, EmployeeID, OrderDate, ItemCount
)
SELECT
    assignment.OrderSequence,
    CONCAT('ORD-', RIGHT(CONCAT('00000000', assignment.OrderSequence), 8)),
    assignment.CustomerID,
    assignment.CustomerSegment,
    assignment.StoreID,
    employee.EmployeeID,
    assignment.OrderDate,
    assignment.ItemCount
FROM StoreAssignments AS assignment
CROSS APPLY
(
    SELECT TOP (1) candidate.EmployeeID
    FROM core.Employee AS candidate
    WHERE candidate.StoreID = assignment.StoreID
      AND candidate.JobTitle <> 'Inventory Coordinator'
      AND candidate.HireDate <= CONVERT(DATE, assignment.OrderDate)
      AND (candidate.TerminationDate IS NULL
           OR candidate.TerminationDate >= CONVERT(DATE, assignment.OrderDate))
    ORDER BY
        ABS(CONVERT(BIGINT, CHECKSUM(assignment.OrderSequence, candidate.EmployeeCode))),
        candidate.EmployeeCode
) AS employee;

-- Reserve one late-period order for a guaranteed one-time customer edge case.
UPDATE #OrderSeed
SET CustomerID = @ControlledOneTimeCustomerID
WHERE OrderSequence = 100000;

IF (SELECT COUNT(*) FROM #OrderSeed) <> 100000
BEGIN
    THROW 51278, 'Sales-order seed failed: expected exactly 100,000 eligible orders.', 1;
END;

-- ============================================================================
-- 4. STORE-ASSORTMENT PRODUCT POOL AND EXACT ITEM SEED
-- ============================================================================

CREATE TABLE #StoreProductPool
(
    StoreID INT NOT NULL,
    ProductID INT NOT NULL,
    ProductNumber INT NOT NULL,
    DemandBand VARCHAR(20) NOT NULL,
    BandSequence INT NOT NULL,
    BandProductCount INT NOT NULL,
    UnitCost DECIMAL(12,2) NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    CategoryCode VARCHAR(20) NOT NULL,
    PRIMARY KEY (StoreID, DemandBand, BandSequence),
    UNIQUE (StoreID, ProductID)
);

;WITH AssortmentProducts AS
(
    SELECT
        balance.StoreID,
        product.ProductID,
        CONVERT(INT, RIGHT(product.SKU, 5)) AS ProductNumber,
        CASE
            WHEN CONVERT(INT, RIGHT(product.SKU, 5)) <= 100 THEN 'High Demand'
            WHEN CONVERT(INT, RIGHT(product.SKU, 5)) <= 350 THEN 'Medium Demand'
            ELSE 'Low Demand'
        END AS DemandBand,
        product.CostPrice,
        product.SellingPrice,
        category.CategoryCode
    FROM inventory.InventoryBalance AS balance
    INNER JOIN core.Product AS product ON product.ProductID = balance.ProductID
    INNER JOIN ref.SubCategory AS subcategory ON subcategory.SubCategoryID = product.SubCategoryID
    INNER JOIN ref.Category AS category ON category.CategoryID = subcategory.CategoryID
    WHERE product.IsActive = 1
),
SequencedProducts AS
(
    SELECT
        assortment.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY assortment.StoreID, assortment.DemandBand
            ORDER BY assortment.ProductID
        ) AS BandSequence,
        COUNT(*) OVER
        (
            PARTITION BY assortment.StoreID, assortment.DemandBand
        ) AS BandProductCount
    FROM AssortmentProducts AS assortment
)
INSERT INTO #StoreProductPool
(
    StoreID, ProductID, ProductNumber, DemandBand,
    BandSequence, BandProductCount, UnitCost, UnitPrice, CategoryCode
)
SELECT
    StoreID, ProductID, ProductNumber, DemandBand,
    BandSequence, BandProductCount, CostPrice, SellingPrice, CategoryCode
FROM SequencedProducts;

IF EXISTS
(
    SELECT StoreID
    FROM #StoreProductPool
    GROUP BY StoreID
    HAVING COUNT(DISTINCT DemandBand) <> 3
)
BEGIN
    THROW 51279, 'Sales-order item generation failed: a store lacks a required demand band.', 1;
END;

CREATE TABLE #LineSlot (LineNumber TINYINT NOT NULL PRIMARY KEY);
INSERT INTO #LineSlot VALUES (1),(2),(3),(4),(5),(6),(7),(8);

CREATE TABLE #ItemSeed
(
    OrderNumber VARCHAR(25) NOT NULL,
    LineNumber TINYINT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitCost DECIMAL(12,2) NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    GrossAmount DECIMAL(14,2) NOT NULL,
    DiscountAmount DECIMAL(14,2) NOT NULL,
    TaxRate DECIMAL(5,2) NOT NULL,
    TaxAmount DECIMAL(14,2) NOT NULL,
    NetAmount DECIMAL(14,2) NOT NULL,
    DemandBand VARCHAR(20) NOT NULL,
    PRIMARY KEY (OrderNumber, ProductID),
    UNIQUE (OrderNumber, LineNumber)
);

;WITH RequestedLines AS
(
    SELECT
        orders.OrderSequence,
        orders.OrderNumber,
        orders.StoreID,
        slot.LineNumber,
        CASE
            WHEN ((orders.OrderSequence * 13 + slot.LineNumber * 17) % 100) < 60
                THEN 'High Demand'
            WHEN ((orders.OrderSequence * 13 + slot.LineNumber * 17) % 100) < 94
                THEN 'Medium Demand'
            ELSE 'Low Demand'
        END AS DemandBand
    FROM #OrderSeed AS orders
    INNER JOIN #LineSlot AS slot ON slot.LineNumber <= orders.ItemCount
),
AssignedProducts AS
(
    SELECT
        line.OrderSequence,
        line.OrderNumber,
        line.LineNumber,
        line.DemandBand,
        product.ProductID,
        product.ProductNumber,
        product.UnitCost,
        product.UnitPrice,
        product.CategoryCode,
        CASE
            WHEN product.UnitPrice >= 30000 THEN 1
            WHEN ((line.OrderSequence * 19 + line.LineNumber * 23) % 100) < 72 THEN 1
            WHEN ((line.OrderSequence * 19 + line.LineNumber * 23) % 100) < 91 THEN 2
            WHEN ((line.OrderSequence * 19 + line.LineNumber * 23) % 100) < 97 THEN 3
            WHEN ((line.OrderSequence * 19 + line.LineNumber * 23) % 100) < 99 THEN 4
            ELSE 5
        END AS Quantity,
        CASE
            WHEN ((line.OrderSequence * 29 + line.LineNumber * 31) % 100) < 35 THEN 0.00
            WHEN ((line.OrderSequence * 29 + line.LineNumber * 31) % 100) < 60 THEN 0.03
            WHEN ((line.OrderSequence * 29 + line.LineNumber * 31) % 100) < 85 THEN 0.08
            WHEN ((line.OrderSequence * 29 + line.LineNumber * 31) % 100) < 98 THEN 0.15
            ELSE 0.25
        END AS DiscountRate,
        CONVERT(DECIMAL(5,2),
            CASE product.CategoryCode
                WHEN 'BOOKS_STAT' THEN CASE WHEN product.ProductNumber % 4 = 0 THEN 0 ELSE 5 END
                WHEN 'FASHION' THEN CASE WHEN product.ProductNumber % 3 = 0 THEN 12 ELSE 5 END
                WHEN 'SPORTS' THEN 12
                WHEN 'ELECTRONICS' THEN CASE WHEN product.ProductNumber % 5 = 0 THEN 28 ELSE 18 END
                WHEN 'MOBILE' THEN CASE WHEN product.ProductNumber % 7 = 0 THEN 28 ELSE 18 END
                ELSE 18
            END
        ) AS TaxRate
    FROM RequestedLines AS line
    INNER JOIN #StoreProductPool AS product
        ON product.StoreID = line.StoreID
       AND product.DemandBand = line.DemandBand
       AND product.BandSequence =
           ((CONVERT(BIGINT, line.OrderSequence) * 17 + line.LineNumber - 2)
              % product.BandProductCount) + 1
),
GrossAndDiscount AS
(
    SELECT
        product.*,
        CONVERT(DECIMAL(14,2), product.Quantity * product.UnitPrice) AS GrossAmount,
        CONVERT(DECIMAL(14,2), ROUND(
            product.Quantity * product.UnitPrice * product.DiscountRate, 2
        )) AS DiscountAmount
    FROM AssignedProducts AS product
),
TaxedLines AS
(
    SELECT
        amount.*,
        CONVERT(DECIMAL(14,2), ROUND(
            (amount.GrossAmount - amount.DiscountAmount) * amount.TaxRate / 100.0, 2
        )) AS TaxAmount
    FROM GrossAndDiscount AS amount
)
INSERT INTO #ItemSeed
(
    OrderNumber, LineNumber, ProductID, Quantity,
    UnitCost, UnitPrice, GrossAmount, DiscountAmount,
    TaxRate, TaxAmount, NetAmount, DemandBand
)
SELECT
    line.OrderNumber,
    line.LineNumber,
    line.ProductID,
    line.Quantity,
    line.UnitCost,
    line.UnitPrice,
    line.GrossAmount,
    line.DiscountAmount,
    line.TaxRate,
    line.TaxAmount,
    CONVERT(DECIMAL(14,2), line.GrossAmount - line.DiscountAmount + line.TaxAmount),
    line.DemandBand
FROM TaxedLines AS line;

IF (SELECT COUNT(*) FROM #ItemSeed) <> 300000
BEGIN
    THROW 51280, 'Sales-order item seed failed: expected exactly 300,000 unique lines.', 1;
END;

-- ============================================================================
-- 5. LOAD ORDERS AND ITEMS, THEN DERIVE HEADER TOTALS
-- ============================================================================

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE target
    SET CustomerID = seed.CustomerID,
        StoreID = seed.StoreID,
        EmployeeID = seed.EmployeeID,
        OrderStatusID = @PendingStatusID,
        OrderDate = seed.OrderDate,
        ConfirmedDate = NULL,
        ShippedDate = NULL,
        DeliveredDate = NULL,
        CancelledDate = NULL,
        Remarks = 'Synthetic baseline order; lifecycle assigned in script 18.',
        ModifiedDate = SYSDATETIME()
    FROM sales.SalesOrder AS target
    INNER JOIN #OrderSeed AS seed ON seed.OrderNumber = target.OrderNumber;

    INSERT INTO sales.SalesOrder
    (
        OrderNumber, CustomerID, StoreID, EmployeeID, OrderStatusID,
        OrderDate, ConfirmedDate, ShippedDate, DeliveredDate, CancelledDate,
        SubtotalAmount, DiscountAmount, TaxAmount, NetAmount, Remarks
    )
    SELECT
        seed.OrderNumber, seed.CustomerID, seed.StoreID, seed.EmployeeID, @PendingStatusID,
        seed.OrderDate, NULL, NULL, NULL, NULL,
        0, 0, 0, 0,
        'Synthetic baseline order; lifecycle assigned in script 18.'
    FROM #OrderSeed AS seed
    WHERE NOT EXISTS
    (
        SELECT 1 FROM sales.SalesOrder AS target WHERE target.OrderNumber = seed.OrderNumber
    );

    UPDATE target
    SET Quantity = seed.Quantity,
        UnitCost = seed.UnitCost,
        UnitPrice = seed.UnitPrice,
        GrossAmount = seed.GrossAmount,
        DiscountAmount = seed.DiscountAmount,
        TaxRate = seed.TaxRate,
        TaxAmount = seed.TaxAmount,
        NetAmount = seed.NetAmount,
        ModifiedDate = SYSDATETIME()
    FROM sales.SalesOrderItem AS target
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = target.SalesOrderID
    INNER JOIN #ItemSeed AS seed
        ON seed.OrderNumber = orders.OrderNumber
       AND seed.ProductID = target.ProductID;

    INSERT INTO sales.SalesOrderItem
    (
        SalesOrderID, ProductID, Quantity, UnitCost, UnitPrice,
        GrossAmount, DiscountAmount, TaxRate, TaxAmount, NetAmount
    )
    SELECT
        orders.SalesOrderID, seed.ProductID, seed.Quantity, seed.UnitCost, seed.UnitPrice,
        seed.GrossAmount, seed.DiscountAmount, seed.TaxRate, seed.TaxAmount, seed.NetAmount
    FROM #ItemSeed AS seed
    INNER JOIN sales.SalesOrder AS orders ON orders.OrderNumber = seed.OrderNumber
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM sales.SalesOrderItem AS target
        WHERE target.SalesOrderID = orders.SalesOrderID
          AND target.ProductID = seed.ProductID
    );

    ;WITH HeaderTotals AS
    (
        SELECT
            item.SalesOrderID,
            SUM(item.GrossAmount) AS SubtotalAmount,
            SUM(item.DiscountAmount) AS DiscountAmount,
            SUM(item.TaxAmount) AS TaxAmount,
            SUM(item.NetAmount) AS NetAmount
        FROM sales.SalesOrderItem AS item
        GROUP BY item.SalesOrderID
    )
    UPDATE orders
    SET SubtotalAmount = totals.SubtotalAmount,
        DiscountAmount = totals.DiscountAmount,
        TaxAmount = totals.TaxAmount,
        NetAmount = totals.NetAmount,
        ModifiedDate = SYSDATETIME()
    FROM sales.SalesOrder AS orders
    INNER JOIN HeaderTotals AS totals ON totals.SalesOrderID = orders.SalesOrderID;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ============================================================================
-- 6. ACCEPTANCE VALIDATION
-- ============================================================================

DECLARE @OrderCount BIGINT = (SELECT COUNT_BIG(*) FROM sales.SalesOrder);
DECLARE @OrderItemCount BIGINT = (SELECT COUNT_BIG(*) FROM sales.SalesOrderItem);

IF @OrderCount <> 100000 OR @OrderItemCount <> 300000
    THROW 51281, 'Sales-order validation failed: unexpected header or item count.', 1;

IF EXISTS
(
    SELECT 1
    FROM sales.SalesOrder AS orders
    INNER JOIN core.Customer AS customer ON customer.CustomerID = orders.CustomerID
    INNER JOIN core.Employee AS employee ON employee.EmployeeID = orders.EmployeeID
    INNER JOIN core.Store AS store ON store.StoreID = orders.StoreID
    WHERE orders.OrderDate < customer.RegistrationDate
       OR customer.IsActive <> 1
       OR employee.StoreID <> orders.StoreID
       OR employee.HireDate > CONVERT(DATE, orders.OrderDate)
       OR (employee.TerminationDate IS NOT NULL
           AND employee.TerminationDate < CONVERT(DATE, orders.OrderDate))
       OR store.OpeningDate > CONVERT(DATE, orders.OrderDate)
)
    THROW 51282, 'Sales-order validation failed: customer, employee, or store date eligibility error.', 1;

IF EXISTS
(
    SELECT 1
    FROM sales.SalesOrderItem AS item
    INNER JOIN sales.SalesOrder AS orders ON orders.SalesOrderID = item.SalesOrderID
    LEFT JOIN inventory.InventoryBalance AS balance
        ON balance.ProductID = item.ProductID
       AND balance.StoreID = orders.StoreID
    WHERE balance.InventoryBalanceID IS NULL
)
    THROW 51283, 'Sales-order validation failed: an item is outside the store assortment.', 1;

IF EXISTS
(
    SELECT 1
    FROM sales.SalesOrder AS orders
    INNER JOIN
    (
        SELECT
            SalesOrderID,
            SUM(GrossAmount) AS SubtotalAmount,
            SUM(DiscountAmount) AS DiscountAmount,
            SUM(TaxAmount) AS TaxAmount,
            SUM(NetAmount) AS NetAmount
        FROM sales.SalesOrderItem
        GROUP BY SalesOrderID
    ) AS totals ON totals.SalesOrderID = orders.SalesOrderID
    WHERE ABS(orders.SubtotalAmount - totals.SubtotalAmount) > 0.01
       OR ABS(orders.DiscountAmount - totals.DiscountAmount) > 0.01
       OR ABS(orders.TaxAmount - totals.TaxAmount) > 0.01
       OR ABS(orders.NetAmount - totals.NetAmount) > 0.01
)
    THROW 51284, 'Sales-order validation failed: header-to-line financial reconciliation error.', 1;

IF EXISTS
(
    SELECT SalesOrderID
    FROM sales.SalesOrderItem
    GROUP BY SalesOrderID, ProductID
    HAVING COUNT(*) > 1
)
    THROW 51285, 'Sales-order validation failed: duplicate product within an order.', 1;

IF EXISTS
(
    SELECT 1
    FROM sales.SalesOrderItem
    WHERE TaxRate NOT IN (0, 5, 12, 18, 28)
       OR Quantity NOT BETWEEN 1 AND 5
)
    THROW 51286, 'Sales-order validation failed: unapproved tax rate or quantity.', 1;

IF
(
    SELECT COUNT_BIG(*)
    FROM sales.SalesOrder
    WHERE CustomerID = @ControlledOneTimeCustomerID
) <> 1
BEGIN
    THROW 51287, 'Sales-order validation failed: controlled one-time customer edge case is missing.', 1;
END;

SELECT
    CASE
        WHEN OrderDate < '2024-07-01' THEN 'FY2023-24'
        WHEN OrderDate < '2025-07-01' THEN 'FY2024-25'
        ELSE 'FY2025-26'
    END AS ReportingYear,
    COUNT_BIG(*) AS OrderCount,
    SUM(NetAmount) AS NetOrderValue,
    'PASSED' AS ValidationStatus
FROM sales.SalesOrder
GROUP BY
    CASE
        WHEN OrderDate < '2024-07-01' THEN 'FY2023-24'
        WHEN OrderDate < '2025-07-01' THEN 'FY2024-25'
        ELSE 'FY2025-26'
    END
ORDER BY ReportingYear;

SELECT
    seed.CustomerSegment,
    COUNT_BIG(*) AS OrderCount,
    CAST(100.0 * COUNT_BIG(*) / @OrderCount AS DECIMAL(5,2)) AS OrderSharePercent,
    COUNT(DISTINCT seed.CustomerID) AS CustomerCount,
    'PASSED' AS ValidationStatus
FROM #OrderSeed AS seed
GROUP BY seed.CustomerSegment
ORDER BY MIN(seed.OrderSequence);

SELECT
    seed.DemandBand,
    COUNT_BIG(*) AS OrderItemCount,
    CAST(100.0 * COUNT_BIG(*) / @OrderItemCount AS DECIMAL(5,2)) AS ItemSharePercent,
    SUM(CONVERT(BIGINT, seed.Quantity)) AS UnitCount,
    'PASSED' AS ValidationStatus
FROM #ItemSeed AS seed
GROUP BY seed.DemandBand
ORDER BY MIN(seed.LineNumber);

SELECT
    @OrderCount AS OrderCount,
    @OrderItemCount AS OrderItemCount,
    CAST(1.0 * @OrderItemCount / @OrderCount AS DECIMAL(5,2)) AS AverageLinesPerOrder,
    COUNT(DISTINCT orders.CustomerID) AS PurchasingCustomerCount,
    COUNT(DISTINCT orders.StoreID) AS StoreCount,
    (SELECT COUNT(DISTINCT ProductID) FROM sales.SalesOrderItem) AS SoldProductCount,
    MIN(orders.OrderDate) AS EarliestOrderDate,
    MAX(orders.OrderDate) AS LatestOrderDate,
    SUM(orders.SubtotalAmount) AS GrossOrderValue,
    SUM(orders.DiscountAmount) AS DiscountValue,
    SUM(orders.TaxAmount) AS TaxValue,
    SUM(orders.NetAmount) AS NetOrderValue,
    CASE
        WHEN @OrderCount = 100000
         AND @OrderItemCount = 300000
         AND COUNT(DISTINCT orders.StoreID) = 20
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM sales.SalesOrder AS orders;

RAISERROR('17_Generate_Sales_Orders.sql completed successfully: 100,000 orders and 300,000 items validated.', 10, 1) WITH NOWAIT;
GO
