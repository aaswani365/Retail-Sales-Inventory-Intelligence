/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      37_Performance_Benchmarking.sql
Purpose:     Benchmark representative Power BI workloads and document database readiness.
Author:      Akshay Aswani
Version:     2.1
Depends on:  36_Data_Quality_Framework.sql
Rerunnable:  Yes. Read-only benchmark; session-scoped temporary tables only.

Benchmark design
----------------
- Five representative analytical workloads
- Three executions per workload to expose first-run versus warm-cache behavior
- Row-count and checksum indicators for repeated-result consistency (not proof of equality)
- Median, minimum and maximum elapsed-time reporting
- Table and index storage inventory
- Optional index-usage report when VIEW SERVER STATE is available

Elapsed time is observational, not a hard pass/fail threshold. Hardware, cache,
concurrency and SQL Server edition all affect duration.
CHECKSUM_AGG/BINARY_CHECKSUM may collide and cannot establish exact result equality.
Monthly sales revenue/profit is attributed to the delivery month (delivered lines only).
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51570, 'Performance benchmark stopped: unexpected database context.', 1;

IF OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactPayments', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimDate', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimProduct', N'U') IS NULL
   OR OBJECT_ID(N'analytics.DimStore', N'U') IS NULL
    THROW 51571, 'Performance benchmark stopped: required analytics objects are missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Data-quality framework passed:%'
)
    THROW 51572, 'Performance benchmark stopped: run script 36 successfully first.', 1;

DROP TABLE IF EXISTS #BenchmarkDefinition;
DROP TABLE IF EXISTS #BenchmarkResult;

CREATE TABLE #BenchmarkDefinition
(
    BenchmarkID TINYINT NOT NULL PRIMARY KEY,
    BenchmarkName VARCHAR(100) NOT NULL,
    BusinessPurpose VARCHAR(250) NOT NULL,
    QueryText NVARCHAR(MAX) NOT NULL
);

CREATE TABLE #BenchmarkResult
(
    BenchmarkID TINYINT NOT NULL,
    IterationNumber TINYINT NOT NULL,
    StartedAt DATETIME2(7) NOT NULL,
    CompletedAt DATETIME2(7) NOT NULL,
    ElapsedMilliseconds BIGINT NOT NULL,
    OutputRowCount BIGINT NOT NULL,
    ResultChecksum INT NULL,
    PRIMARY KEY (BenchmarkID, IterationNumber)
);

/* Every query returns only control values to the harness. */
INSERT INTO #BenchmarkDefinition
(
    BenchmarkID, BenchmarkName, BusinessPurpose, QueryText
)
VALUES
(1, 'Executive KPI aggregation',
 'Portfolio-level revenue, profit, orders, customers and units for the executive page.',
 N';WITH KPI AS
   (
       SELECT
           SUM(fact_sales.RecognizedRevenueAmount) AS Revenue,
           SUM(fact_sales.RecognizedGrossProfitAmount) AS GrossProfit,
           SUM(CONVERT(BIGINT, fact_sales.OrderCount)) AS Orders,
           COUNT_BIG(DISTINCT fact_sales.CustomerKey) AS Customers,
           SUM(CONVERT(BIGINT, fact_sales.Quantity)) AS Units
       FROM analytics.FactSales AS fact_sales
   )
   SELECT @OutputRowCount = COUNT_BIG(*),
          @OutputChecksum = CHECKSUM_AGG(BINARY_CHECKSUM(Revenue, GrossProfit, Orders, Customers, Units))
   FROM KPI;'),
(2, 'Monthly sales trend',
 'Delivered-line revenue and gross-profit by delivery month; distinct delivered orders.',
 N';WITH MonthlySales AS
   (
       SELECT date_dimension.YearMonthNumber,
              SUM(fact_sales.RecognizedRevenueAmount) AS Revenue,
              SUM(fact_sales.RecognizedGrossProfitAmount) AS GrossProfit,
              COUNT_BIG(DISTINCT fact_sales.SalesOrderID) AS Orders,
              SUM(CONVERT(BIGINT, fact_sales.Quantity)) AS Units
       FROM analytics.FactSales AS fact_sales
       INNER JOIN analytics.DimDate AS date_dimension
           ON date_dimension.DateKey = fact_sales.DeliveredDateKey
       WHERE fact_sales.IsDelivered = 1
       GROUP BY date_dimension.YearMonthNumber
   )
   SELECT @OutputRowCount = COUNT_BIG(*),
          @OutputChecksum = CHECKSUM_AGG(BINARY_CHECKSUM(YearMonthNumber, Revenue, GrossProfit, Orders, Units))
   FROM MonthlySales;'),
(3, 'Store performance matrix',
 'Store comparison by tier, revenue, margin, orders and customer reach.',
 N';WITH StorePerformance AS
   (
       SELECT store_dimension.StoreKey,
              store_dimension.StoreTier,
              SUM(fact_sales.RecognizedRevenueAmount) AS Revenue,
              SUM(fact_sales.RecognizedGrossProfitAmount) AS GrossProfit,
              SUM(CONVERT(BIGINT, fact_sales.OrderCount)) AS Orders,
              COUNT_BIG(DISTINCT fact_sales.CustomerKey) AS Customers
       FROM analytics.FactSales AS fact_sales
       INNER JOIN analytics.DimStore AS store_dimension
           ON store_dimension.StoreKey = fact_sales.StoreKey
       GROUP BY store_dimension.StoreKey, store_dimension.StoreTier
   )
   SELECT @OutputRowCount = COUNT_BIG(*),
          @OutputChecksum = CHECKSUM_AGG(BINARY_CHECKSUM(StoreKey, StoreTier, Revenue, GrossProfit, Orders, Customers))
   FROM StorePerformance;'),
(4, 'Product category performance',
 'Category and subcategory revenue, profitability, units and return exposure.',
 N';WITH SalesByProduct AS
   (
       SELECT fact_sales.ProductKey,
              SUM(fact_sales.RecognizedRevenueAmount) AS Revenue,
              SUM(fact_sales.RecognizedGrossProfitAmount) AS GrossProfit,
              SUM(CONVERT(BIGINT, fact_sales.Quantity)) AS Units
       FROM analytics.FactSales AS fact_sales
       GROUP BY fact_sales.ProductKey
   ),
   ReturnsByProduct AS
   (
       SELECT fact_return.ProductKey,
              SUM(CONVERT(BIGINT, fact_return.QuantityAccepted)) AS ReturnedUnits
       FROM analytics.FactReturns AS fact_return
       GROUP BY fact_return.ProductKey
   ),
   ProductCategory AS
   (
       SELECT product_dimension.CategoryName,
              product_dimension.SubCategoryName,
              SUM(COALESCE(product_sales.Revenue, 0)) AS Revenue,
              SUM(COALESCE(product_sales.GrossProfit, 0)) AS GrossProfit,
              SUM(COALESCE(product_sales.Units, 0)) AS Units,
              SUM(COALESCE(product_return.ReturnedUnits, 0)) AS ReturnedUnits
       FROM analytics.DimProduct AS product_dimension
       LEFT JOIN SalesByProduct AS product_sales
           ON product_sales.ProductKey = product_dimension.ProductKey
       LEFT JOIN ReturnsByProduct AS product_return
           ON product_return.ProductKey = product_dimension.ProductKey
       WHERE product_dimension.IsUnknown = 0
       GROUP BY product_dimension.CategoryName, product_dimension.SubCategoryName
   )
   SELECT @OutputRowCount = COUNT_BIG(*),
          @OutputChecksum = CHECKSUM_AGG(BINARY_CHECKSUM(CategoryName, SubCategoryName, Revenue, GrossProfit, Units, ReturnedUnits))
   FROM ProductCategory;'),
(5, 'Current inventory exposure',
 'Store-product inventory position, stock flags and working-capital exposure.',
 N';WITH InventoryExposure AS
   (
       SELECT fact_inventory.StoreKey,
              fact_inventory.ProductKey,
              SUM(CONVERT(BIGINT, fact_inventory.QuantityOnHand)) AS QuantityOnHand,
              SUM(CONVERT(BIGINT, fact_inventory.QuantityAvailable)) AS QuantityAvailable,
              SUM(fact_inventory.StockCostValue) AS StockCostValue,
              MAX(CONVERT(TINYINT, fact_inventory.IsOutOfStock)) AS IsOutOfStock,
              MAX(CONVERT(TINYINT, fact_inventory.IsBelowReorderLevel)) AS IsBelowReorderLevel,
              MAX(CONVERT(TINYINT, fact_inventory.IsExcessStock)) AS IsExcessStock
       FROM analytics.FactInventorySnapshot AS fact_inventory
       GROUP BY fact_inventory.StoreKey, fact_inventory.ProductKey
   )
   SELECT @OutputRowCount = COUNT_BIG(*),
          @OutputChecksum = CHECKSUM_AGG(BINARY_CHECKSUM(StoreKey, ProductKey, QuantityOnHand,
              QuantityAvailable, StockCostValue, IsOutOfStock, IsBelowReorderLevel, IsExcessStock))
   FROM InventoryExposure;');

/* ============================================================================
   1. EXECUTE EACH WORKLOAD THREE TIMES
   ============================================================================ */
DECLARE @BenchmarkID TINYINT = 1;
DECLARE @MaximumBenchmarkID TINYINT = (SELECT MAX(BenchmarkID) FROM #BenchmarkDefinition);
DECLARE @IterationNumber TINYINT;
DECLARE @QueryText NVARCHAR(MAX);
DECLARE @StartedAt DATETIME2(7);
DECLARE @CompletedAt DATETIME2(7);
DECLARE @OutputRowCount BIGINT;
DECLARE @ResultChecksum INT;

WHILE @BenchmarkID <= @MaximumBenchmarkID
BEGIN
    SELECT @QueryText = QueryText
    FROM #BenchmarkDefinition
    WHERE BenchmarkID = @BenchmarkID;

    SET @IterationNumber = 1;

    WHILE @IterationNumber <= 3
    BEGIN
        SET @OutputRowCount = NULL;
        SET @ResultChecksum = NULL;
        SET @StartedAt = SYSDATETIME();

        EXEC sys.sp_executesql
            @QueryText,
            N'@OutputRowCount BIGINT OUTPUT, @OutputChecksum INT OUTPUT',
            @OutputRowCount = @OutputRowCount OUTPUT,
            @OutputChecksum = @ResultChecksum OUTPUT;

        SET @CompletedAt = SYSDATETIME();

        INSERT INTO #BenchmarkResult
        (
            BenchmarkID, IterationNumber, StartedAt, CompletedAt,
            ElapsedMilliseconds, OutputRowCount, ResultChecksum
        )
        VALUES
        (
            @BenchmarkID, @IterationNumber, @StartedAt, @CompletedAt,
            DATEDIFF_BIG(MILLISECOND, @StartedAt, @CompletedAt),
            COALESCE(@OutputRowCount, 0), @ResultChecksum
        );

        SET @IterationNumber += 1;
    END;

    SET @BenchmarkID += 1;
END;

/* ============================================================================
   2. BENCHMARK SUMMARY
   ============================================================================ */
;WITH RankedDuration AS
(
    SELECT benchmark_result.*,
           ROW_NUMBER() OVER
           (
               PARTITION BY benchmark_result.BenchmarkID
               ORDER BY benchmark_result.ElapsedMilliseconds,
                        benchmark_result.IterationNumber
           ) AS DurationRank
    FROM #BenchmarkResult AS benchmark_result
),
BenchmarkSummary AS
(
    SELECT
        benchmark_result.BenchmarkID,
        MIN(benchmark_result.ElapsedMilliseconds) AS MinimumMilliseconds,
        MAX(CASE WHEN benchmark_result.DurationRank = 2
                 THEN benchmark_result.ElapsedMilliseconds END) AS MedianMilliseconds,
        MAX(benchmark_result.ElapsedMilliseconds) AS MaximumMilliseconds,
        MAX(CASE WHEN benchmark_result.IterationNumber = 1
                 THEN benchmark_result.ElapsedMilliseconds END) AS FirstRunMilliseconds,
        MAX(CASE WHEN benchmark_result.IterationNumber = 3
                 THEN benchmark_result.ElapsedMilliseconds END) AS FinalRunMilliseconds,
        MIN(benchmark_result.OutputRowCount) AS MinimumOutputRows,
        MAX(benchmark_result.OutputRowCount) AS MaximumOutputRows,
        MIN(benchmark_result.ResultChecksum) AS MinimumChecksum,
        MAX(benchmark_result.ResultChecksum) AS MaximumChecksum
    FROM RankedDuration AS benchmark_result
    GROUP BY benchmark_result.BenchmarkID
)
SELECT
    benchmark_definition.BenchmarkID,
    benchmark_definition.BenchmarkName,
    benchmark_definition.BusinessPurpose,
    benchmark_summary.MinimumMilliseconds,
    benchmark_summary.MedianMilliseconds,
    benchmark_summary.MaximumMilliseconds,
    benchmark_summary.FirstRunMilliseconds,
    benchmark_summary.FinalRunMilliseconds,
    benchmark_summary.MaximumOutputRows AS OutputRowCount,
    benchmark_summary.MaximumChecksum AS ResultChecksum,
    CASE
        WHEN benchmark_summary.MedianMilliseconds < 250 THEN 'EXCELLENT'
        WHEN benchmark_summary.MedianMilliseconds < 1000 THEN 'GOOD'
        WHEN benchmark_summary.MedianMilliseconds < 3000 THEN 'REVIEW'
        ELSE 'INVESTIGATE'
    END AS ObservedPerformanceBand,
    CASE
        WHEN benchmark_summary.MinimumOutputRows = benchmark_summary.MaximumOutputRows
         AND ISNULL(benchmark_summary.MinimumChecksum, -2147483648)
             = ISNULL(benchmark_summary.MaximumChecksum, -2147483648)
            THEN 'CONSISTENT'
        ELSE 'INCONSISTENT'
    END AS ResultConsistency
FROM #BenchmarkDefinition AS benchmark_definition
INNER JOIN BenchmarkSummary AS benchmark_summary
    ON benchmark_summary.BenchmarkID = benchmark_definition.BenchmarkID
ORDER BY benchmark_definition.BenchmarkID;

SELECT
    benchmark_definition.BenchmarkName,
    benchmark_result.IterationNumber,
    benchmark_result.ElapsedMilliseconds,
    benchmark_result.OutputRowCount,
    benchmark_result.ResultChecksum,
    benchmark_result.StartedAt,
    benchmark_result.CompletedAt
FROM #BenchmarkResult AS benchmark_result
INNER JOIN #BenchmarkDefinition AS benchmark_definition
    ON benchmark_definition.BenchmarkID = benchmark_result.BenchmarkID
ORDER BY benchmark_result.BenchmarkID, benchmark_result.IterationNumber;

/* ============================================================================
   3. ANALYTICS TABLE AND INDEX STORAGE INVENTORY
   ============================================================================ */
;WITH IndexStorage AS
(
    SELECT
        object_table.object_id,
        object_index.index_id,
        SUM(CONVERT(BIGINT, partition_stats.row_count)) AS TableRowCount,
        SUM(CONVERT(BIGINT, partition_stats.reserved_page_count)) * 8.0 / 1024 AS ReservedMB,
        SUM(CONVERT(BIGINT, partition_stats.used_page_count)) * 8.0 / 1024 AS UsedMB
    FROM sys.tables AS object_table
    INNER JOIN sys.indexes AS object_index
        ON object_index.object_id = object_table.object_id
    INNER JOIN sys.dm_db_partition_stats AS partition_stats
        ON partition_stats.object_id = object_index.object_id
       AND partition_stats.index_id = object_index.index_id
    WHERE SCHEMA_NAME(object_table.schema_id) = N'analytics'
    GROUP BY object_table.object_id, object_index.index_id
)
SELECT
    SCHEMA_NAME(object_table.schema_id) AS SchemaName,
    object_table.name AS TableName,
    object_index.name AS IndexName,
    object_index.type_desc AS IndexType,
    object_index.is_unique AS IsUnique,
    object_index.has_filter AS HasFilter,
    index_storage.TableRowCount,
    CONVERT(DECIMAL(12,2), index_storage.ReservedMB) AS ReservedMB,
    CONVERT(DECIMAL(12,2), index_storage.UsedMB) AS UsedMB
FROM IndexStorage AS index_storage
INNER JOIN sys.tables AS object_table
    ON object_table.object_id = index_storage.object_id
INNER JOIN sys.indexes AS object_index
    ON object_index.object_id = index_storage.object_id
   AND object_index.index_id = index_storage.index_id
ORDER BY index_storage.ReservedMB DESC, TableName, object_index.index_id;

/* Index usage is useful but requires instance-level visibility. */
IF HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW SERVER STATE') = 1
BEGIN
    SELECT
        SCHEMA_NAME(object_table.schema_id) AS SchemaName,
        object_table.name AS TableName,
        object_index.name AS IndexName,
        COALESCE(index_usage.user_seeks, 0) AS UserSeeks,
        COALESCE(index_usage.user_scans, 0) AS UserScans,
        COALESCE(index_usage.user_lookups, 0) AS UserLookups,
        COALESCE(index_usage.user_updates, 0) AS UserUpdates,
        index_usage.last_user_seek AS LastUserSeek,
        index_usage.last_user_scan AS LastUserScan
    FROM sys.tables AS object_table
    INNER JOIN sys.indexes AS object_index
        ON object_index.object_id = object_table.object_id
       AND object_index.index_id > 0
    LEFT JOIN sys.dm_db_index_usage_stats AS index_usage
        ON index_usage.database_id = DB_ID()
       AND index_usage.object_id = object_index.object_id
       AND index_usage.index_id = object_index.index_id
    WHERE SCHEMA_NAME(object_table.schema_id) = N'analytics'
    ORDER BY TableName, IndexName;
END
ELSE
BEGIN
    SELECT
        'SKIPPED' AS IndexUsageReportStatus,
        'VIEW SERVER STATE permission is not available; core benchmarks are unaffected.' AS DiagnosticMessage;
END;

/* ============================================================================
   4. VALIDATION
   ============================================================================ */
DECLARE @BenchmarkValidation TABLE
(
    TestSequence TINYINT NOT NULL PRIMARY KEY,
    ValidationArea VARCHAR(120) NOT NULL,
    ExceptionCount BIGINT NOT NULL,
    ValidationStatus VARCHAR(10) NOT NULL
);

INSERT INTO @BenchmarkValidation VALUES
(1, 'All five approved workloads executed three times',
 CASE WHEN (SELECT COUNT_BIG(*) FROM #BenchmarkResult) = 15 THEN 0 ELSE 1 END,
 CASE WHEN (SELECT COUNT_BIG(*) FROM #BenchmarkResult) = 15 THEN 'PASSED' ELSE 'FAILED' END),
(2, 'Every workload returned at least one result row',
 (SELECT COUNT_BIG(*) FROM #BenchmarkResult WHERE OutputRowCount <= 0),
 CASE WHEN NOT EXISTS (SELECT 1 FROM #BenchmarkResult WHERE OutputRowCount <= 0)
      THEN 'PASSED' ELSE 'FAILED' END),
(3, 'Row counts are consistent across repeated executions',
 (SELECT COUNT_BIG(*) FROM
    (SELECT BenchmarkID FROM #BenchmarkResult GROUP BY BenchmarkID
     HAVING MIN(OutputRowCount) <> MAX(OutputRowCount)) AS inconsistent_rows),
 CASE WHEN NOT EXISTS
    (SELECT BenchmarkID FROM #BenchmarkResult GROUP BY BenchmarkID
     HAVING MIN(OutputRowCount) <> MAX(OutputRowCount))
      THEN 'PASSED' ELSE 'FAILED' END),
(4, 'Checksum indicators are consistent across repeated executions (collision possible)',
 (SELECT COUNT_BIG(*) FROM
    (SELECT BenchmarkID FROM #BenchmarkResult GROUP BY BenchmarkID
     HAVING ISNULL(MIN(ResultChecksum), -2147483648) <> ISNULL(MAX(ResultChecksum), -2147483648)) AS inconsistent_checksum),
 CASE WHEN NOT EXISTS
    (SELECT BenchmarkID FROM #BenchmarkResult GROUP BY BenchmarkID
     HAVING ISNULL(MIN(ResultChecksum), -2147483648) <> ISNULL(MAX(ResultChecksum), -2147483648))
      THEN 'PASSED' ELSE 'FAILED' END),
(5, 'Elapsed durations are nonnegative',
 (SELECT COUNT_BIG(*) FROM #BenchmarkResult WHERE ElapsedMilliseconds < 0),
 CASE WHEN NOT EXISTS (SELECT 1 FROM #BenchmarkResult WHERE ElapsedMilliseconds < 0)
      THEN 'PASSED' ELSE 'FAILED' END),
(6, 'Approved analytics indexes remain enabled and non-hypothetical',
 (SELECT COUNT_BIG(*) FROM sys.indexes AS object_index
  INNER JOIN sys.tables AS object_table ON object_table.object_id = object_index.object_id
  WHERE SCHEMA_NAME(object_table.schema_id) = N'analytics'
    AND object_index.index_id > 0
    AND (object_index.is_disabled = 1 OR object_index.is_hypothetical = 1)),
 CASE WHEN NOT EXISTS
    (SELECT 1 FROM sys.indexes AS object_index
     INNER JOIN sys.tables AS object_table ON object_table.object_id = object_index.object_id
     WHERE SCHEMA_NAME(object_table.schema_id) = N'analytics'
       AND object_index.index_id > 0
       AND (object_index.is_disabled = 1 OR object_index.is_hypothetical = 1))
      THEN 'PASSED' ELSE 'FAILED' END);

SELECT TestSequence, ValidationArea, ExceptionCount, ValidationStatus
FROM @BenchmarkValidation
ORDER BY TestSequence;

IF EXISTS (SELECT 1 FROM @BenchmarkValidation WHERE ValidationStatus = 'FAILED')
    THROW 51573, 'Performance benchmark validation failed. Review the final validation result set.', 1;

RAISERROR('37_Performance_Benchmarking.sql completed successfully: workloads executed with consistent results.', 10, 1) WITH NOWAIT;
GO
