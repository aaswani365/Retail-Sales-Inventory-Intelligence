/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      39_PowerBI_Model_Validation.sql
Purpose:     Execute the final SQL-side acceptance gate for the Power BI model.
Author:      Akshay Aswani
Version:     2.0
Depends on:  38_PowerBI_Reporting_Views.sql
Rerunnable:  Yes. Each execution creates a new auditable validation run.

Acceptance coverage
-------------------
1. Required Power BI view inventory and metadata
2. Declared view grains and business-key completeness
3. Enterprise, monthly, store, product and customer reconciliations
4. Inventory, return and payment reconciliations
5. Calculated-rate validity and time-series ordering
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51590, 'Power BI model validation stopped: unexpected database context.', 1;

IF OBJECT_ID(N'audit.ValidationRun', N'U') IS NULL
   OR OBJECT_ID(N'audit.ValidationResult', N'U') IS NULL
    THROW 51591, 'Power BI model validation stopped: audit tables are missing.', 1;

DECLARE @RequiredViews TABLE
(
    ViewName SYSNAME NOT NULL PRIMARY KEY,
    MinimumColumnCount SMALLINT NOT NULL
);

INSERT INTO @RequiredViews VALUES
('pbi_ExecutiveSummary', 30),
('pbi_SalesTrend', 25),
('pbi_StorePerformance', 25),
('pbi_ProductPerformance', 25),
('pbi_CustomerPerformance', 24),
('pbi_InventoryPosition', 30),
('pbi_ReturnsPerformance', 14),
('pbi_PaymentPerformance', 15);

DECLARE @MissingViewCount BIGINT =
(
    SELECT COUNT_BIG(*)
    FROM @RequiredViews AS required_view
    WHERE OBJECT_ID(N'analytics.' + QUOTENAME(required_view.ViewName), N'V') IS NULL
);

IF @MissingViewCount > 0
    THROW 51592, 'Power BI model validation stopped: one or more script 38 reporting views are missing.', 1;

DECLARE @ValidationRunID BIGINT;

INSERT INTO audit.ValidationRun
(
    RunStartDate, RunEndDate, EnvironmentName, OverallStatus,
    TotalTests, PassedTests, FailedTests, Remarks
)
VALUES
(
    SYSDATETIME(), NULL, 'LOCAL', 'Running', 0, 0, 0,
    'Power BI semantic-model acceptance validation initiated by script 39.'
);

SET @ValidationRunID = SCOPE_IDENTITY();

DECLARE @Results TABLE
(
    TestSequence SMALLINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TestCode VARCHAR(50) NOT NULL UNIQUE,
    TestCategory VARCHAR(30) NOT NULL,
    TestName VARCHAR(200) NOT NULL,
    Severity VARCHAR(10) NOT NULL,
    ExpectedValue VARCHAR(100) NULL,
    ActualValue VARCHAR(100) NULL,
    ExceptionCount BIGINT NOT NULL,
    TestStatus VARCHAR(10) NOT NULL,
    DiagnosticMessage VARCHAR(1000) NULL
);

BEGIN TRY
    /* ======================================================================
       1. OBJECTS AND METADATA
       ====================================================================== */
    INSERT INTO @Results VALUES
    ('PBI-OBJ-001', 'OBJECTS', 'All approved Power BI reporting views exist', 'Critical',
     '8 views', CONCAT(8 - @MissingViewCount, ' views'), @MissingViewCount,
     CASE WHEN @MissingViewCount = 0 THEN 'Passed' ELSE 'Failed' END,
     'The semantic layer requires eight analytics.pbi_* views.');

    DECLARE @InsufficientColumnViews BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM @RequiredViews AS required_view
        CROSS APPLY
        (
            SELECT COUNT_BIG(*) AS ExistingColumnCount
            FROM sys.columns
            WHERE object_id = OBJECT_ID(N'analytics.' + QUOTENAME(required_view.ViewName))
        ) AS column_control
        WHERE column_control.ExistingColumnCount < required_view.MinimumColumnCount
    );

    INSERT INTO @Results VALUES
    ('PBI-OBJ-002', 'OBJECTS', 'Reporting views expose approved minimum metadata', 'Critical',
     '0 underspecified views', CONCAT(@InsufficientColumnViews, ' underspecified views'), @InsufficientColumnViews,
     CASE WHEN @InsufficientColumnViews = 0 THEN 'Passed' ELSE 'Failed' END,
     'Minimum column counts protect the Power BI contract from accidental breaking changes.');

    DECLARE @NonSchemaBoundCount BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM @RequiredViews AS required_view
        INNER JOIN sys.views AS object_view
            ON object_view.object_id = OBJECT_ID(N'analytics.' + QUOTENAME(required_view.ViewName))
        WHERE object_view.is_ms_shipped = 1
    );

    INSERT INTO @Results VALUES
    ('PBI-OBJ-003', 'OBJECTS', 'Reporting views are user-defined portfolio objects', 'High',
     '0 system views', CONCAT(@NonSchemaBoundCount, ' system views'), @NonSchemaBoundCount,
     CASE WHEN @NonSchemaBoundCount = 0 THEN 'Passed' ELSE 'Failed' END,
     'Every reporting view must remain a user-defined database object.');

    /* ======================================================================
       2. VIEW GRAINS
       ====================================================================== */
    DECLARE @ExecutiveRowExceptions BIGINT =
        ABS(CONVERT(BIGINT, 1) - (SELECT COUNT_BIG(*) FROM analytics.pbi_ExecutiveSummary));

    INSERT INTO @Results VALUES
    ('PBI-GRN-001', 'GRAIN', 'Executive summary contains one enterprise row', 'Critical',
     '1 row', CONCAT((SELECT COUNT_BIG(*) FROM analytics.pbi_ExecutiveSummary), ' rows'),
     @ExecutiveRowExceptions,
     CASE WHEN @ExecutiveRowExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'The executive KPI page requires one unfiltered enterprise control row.');

    DECLARE @DuplicateGrains BIGINT =
        (SELECT COUNT_BIG(*) FROM
            (SELECT YearMonthNumber FROM analytics.pbi_SalesTrend
             GROUP BY YearMonthNumber HAVING COUNT_BIG(*) > 1) AS duplicate_month)
      + (SELECT COUNT_BIG(*) FROM
            (SELECT StoreKey FROM analytics.pbi_StorePerformance
             GROUP BY StoreKey HAVING COUNT_BIG(*) > 1) AS duplicate_store)
      + (SELECT COUNT_BIG(*) FROM
            (SELECT ProductKey FROM analytics.pbi_ProductPerformance
             GROUP BY ProductKey HAVING COUNT_BIG(*) > 1) AS duplicate_product)
      + (SELECT COUNT_BIG(*) FROM
            (SELECT CustomerKey FROM analytics.pbi_CustomerPerformance
             GROUP BY CustomerKey HAVING COUNT_BIG(*) > 1) AS duplicate_customer)
      + (SELECT COUNT_BIG(*) FROM
            (SELECT InventoryBalanceID FROM analytics.pbi_InventoryPosition
             GROUP BY InventoryBalanceID HAVING COUNT_BIG(*) > 1) AS duplicate_inventory)
      + (SELECT COUNT_BIG(*) FROM
            (SELECT YearMonthNumber, ReturnReasonCode, CategoryName
             FROM analytics.pbi_ReturnsPerformance
             GROUP BY YearMonthNumber, ReturnReasonCode, CategoryName HAVING COUNT_BIG(*) > 1) AS duplicate_return)
      + (SELECT COUNT_BIG(*) FROM
            (SELECT YearMonthNumber, PaymentMethodCode, PaymentStatusCode
             FROM analytics.pbi_PaymentPerformance
             GROUP BY YearMonthNumber, PaymentMethodCode, PaymentStatusCode HAVING COUNT_BIG(*) > 1) AS duplicate_payment);

    INSERT INTO @Results VALUES
    ('PBI-GRN-002', 'GRAIN', 'All reporting-view grains are unique', 'Critical',
     '0 duplicate groups', CONCAT(@DuplicateGrains, ' duplicate groups'), @DuplicateGrains,
     CASE WHEN @DuplicateGrains = 0 THEN 'Passed' ELSE 'Failed' END,
     'Month, store, product, customer, inventory, return and payment grains are tested.');

    DECLARE @BlankBusinessKeys BIGINT =
        (SELECT COUNT_BIG(*) FROM analytics.pbi_StorePerformance
         WHERE NULLIF(LTRIM(RTRIM(StoreCode)), '') IS NULL)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_ProductPerformance
         WHERE NULLIF(LTRIM(RTRIM(SKU)), '') IS NULL)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_CustomerPerformance
         WHERE NULLIF(LTRIM(RTRIM(CustomerCode)), '') IS NULL)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_InventoryPosition
         WHERE NULLIF(LTRIM(RTRIM(StoreCode)), '') IS NULL OR NULLIF(LTRIM(RTRIM(SKU)), '') IS NULL)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_ReturnsPerformance
         WHERE NULLIF(LTRIM(RTRIM(ReturnReasonCode)), '') IS NULL)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_PaymentPerformance
         WHERE NULLIF(LTRIM(RTRIM(PaymentMethodCode)), '') IS NULL
            OR NULLIF(LTRIM(RTRIM(PaymentStatusCode)), '') IS NULL);

    INSERT INTO @Results VALUES
    ('PBI-GRN-003', 'GRAIN', 'Power BI business keys are complete', 'Critical',
     '0 blank keys', CONCAT(@BlankBusinessKeys, ' blank keys'), @BlankBusinessKeys,
     CASE WHEN @BlankBusinessKeys = 0 THEN 'Passed' ELSE 'Failed' END,
     'Power BI relationships and drill-through depend on complete business keys.');

    /* ======================================================================
       3. SALES RECONCILIATIONS
       ====================================================================== */
    DECLARE @FactRevenue DECIMAL(38,2) =
        (SELECT COALESCE(SUM(RecognizedRevenueAmount), 0) FROM analytics.FactSales);
    DECLARE @FactProfit DECIMAL(38,2) =
        (SELECT COALESCE(SUM(RecognizedGrossProfitAmount), 0) FROM analytics.FactSales);
    DECLARE @FactOrders BIGINT =
        (SELECT COALESCE(SUM(CONVERT(BIGINT, OrderCount)), 0) FROM analytics.FactSales);

    DECLARE @ExecutiveSalesMismatch BIGINT =
    (
        SELECT CASE WHEN RecognizedRevenue = @FactRevenue
                      AND RecognizedGrossProfit = @FactProfit
                      AND TotalOrders = @FactOrders
                    THEN 0 ELSE 1 END
        FROM analytics.pbi_ExecutiveSummary
    );

    INSERT INTO @Results VALUES
    ('PBI-REC-001', 'RECONCILIATION', 'Executive sales KPIs reconcile to FactSales', 'Critical',
     'Exact match', CASE WHEN @ExecutiveSalesMismatch = 0 THEN 'Exact match' ELSE 'Mismatch' END,
     @ExecutiveSalesMismatch,
     CASE WHEN @ExecutiveSalesMismatch = 0 THEN 'Passed' ELSE 'Failed' END,
     'Revenue, profit and additive order count are reconciled.');

    DECLARE @SalesAggregateMismatches BIGINT =
        CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RecognizedRevenue), 0) FROM analytics.pbi_SalesTrend) <> @FactRevenue THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RecognizedRevenue), 0) FROM analytics.pbi_StorePerformance) <> @FactRevenue THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RecognizedRevenue), 0) FROM analytics.pbi_ProductPerformance) <> @FactRevenue THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RecognizedRevenue), 0) FROM analytics.pbi_CustomerPerformance) <> @FactRevenue THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('PBI-REC-002', 'RECONCILIATION', 'Sales aggregates reconcile across reporting views', 'Critical',
     '0 mismatched views', CONCAT(@SalesAggregateMismatches, ' mismatched views'), @SalesAggregateMismatches,
     CASE WHEN @SalesAggregateMismatches = 0 THEN 'Passed' ELSE 'Failed' END,
     'Monthly, store, product and customer revenue must each reconcile to FactSales.');

    DECLARE @ProfitAggregateMismatches BIGINT =
        CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RecognizedGrossProfit), 0) FROM analytics.pbi_SalesTrend) <> @FactProfit THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RecognizedGrossProfit), 0) FROM analytics.pbi_StorePerformance) <> @FactProfit THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RecognizedGrossProfit), 0) FROM analytics.pbi_ProductPerformance) <> @FactProfit THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RecognizedGrossProfit), 0) FROM analytics.pbi_CustomerPerformance) <> @FactProfit THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('PBI-REC-003', 'RECONCILIATION', 'Profit aggregates reconcile across reporting views', 'Critical',
     '0 mismatched views', CONCAT(@ProfitAggregateMismatches, ' mismatched views'), @ProfitAggregateMismatches,
     CASE WHEN @ProfitAggregateMismatches = 0 THEN 'Passed' ELSE 'Failed' END,
     'Monthly, store, product and customer profit must each reconcile to FactSales.');

    /* ======================================================================
       4. INVENTORY, RETURN AND PAYMENT RECONCILIATIONS
       ====================================================================== */
    DECLARE @InventoryMismatches BIGINT =
        CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM analytics.pbi_InventoryPosition)
                                  <> (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(QuantityOnHand), 0) FROM analytics.pbi_InventoryPosition)
                                  <> (SELECT COALESCE(SUM(CONVERT(BIGINT, QuantityOnHand)), 0) FROM analytics.FactInventorySnapshot) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(StockCostValue), 0) FROM analytics.pbi_InventoryPosition)
                                  <> (SELECT COALESCE(SUM(StockCostValue), 0) FROM analytics.FactInventorySnapshot) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('PBI-REC-004', 'RECONCILIATION', 'Inventory reporting view reconciles to snapshot fact', 'Critical',
     '0 mismatched controls', CONCAT(@InventoryMismatches, ' mismatched controls'), @InventoryMismatches,
     CASE WHEN @InventoryMismatches = 0 THEN 'Passed' ELSE 'Failed' END,
     'Row count, on-hand quantity and stock cost are reconciled.');

    DECLARE @ReturnMismatches BIGINT =
        CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RequestedReturnUnits), 0) FROM analytics.pbi_ReturnsPerformance)
                                  <> (SELECT COALESCE(SUM(CONVERT(BIGINT, QuantityRequested)), 0) FROM analytics.FactReturns) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(AcceptedReturnUnits), 0) FROM analytics.pbi_ReturnsPerformance)
                                  <> (SELECT COALESCE(SUM(CONVERT(BIGINT, QuantityAccepted)), 0) FROM analytics.FactReturns) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(EligibleRefundAmount), 0) FROM analytics.pbi_ReturnsPerformance)
                                  <> (SELECT COALESCE(SUM(EligibleRefundAmount), 0) FROM analytics.FactReturns) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('PBI-REC-005', 'RECONCILIATION', 'Returns reporting view reconciles to return fact', 'Critical',
     '0 mismatched controls', CONCAT(@ReturnMismatches, ' mismatched controls'), @ReturnMismatches,
     CASE WHEN @ReturnMismatches = 0 THEN 'Passed' ELSE 'Failed' END,
     'Requested units, accepted units and eligible refund amount are reconciled.');

    DECLARE @PaymentMismatches BIGINT =
        CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(PaymentAttempts), 0) FROM analytics.pbi_PaymentPerformance)
                                  <> (SELECT COALESCE(SUM(CONVERT(BIGINT, AttemptCount)), 0) FROM analytics.FactPayments) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(AttemptedValue), 0) FROM analytics.pbi_PaymentPerformance)
                                  <> (SELECT COALESCE(SUM(Amount), 0) FROM analytics.FactPayments) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(CollectedValue), 0) FROM analytics.pbi_PaymentPerformance)
                                  <> (SELECT COALESCE(SUM(CollectedAmount), 0) FROM analytics.FactPayments) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('PBI-REC-006', 'RECONCILIATION', 'Payment reporting view reconciles to payment fact', 'Critical',
     '0 mismatched controls', CONCAT(@PaymentMismatches, ' mismatched controls'), @PaymentMismatches,
     CASE WHEN @PaymentMismatches = 0 THEN 'Passed' ELSE 'Failed' END,
     'Attempts, attempted value and collected value are reconciled.');

    /* ======================================================================
       5. CALCULATED RATES AND TIME SERIES
       ====================================================================== */
    DECLARE @InvalidRateCount BIGINT =
        (SELECT COUNT_BIG(*) FROM analytics.pbi_ExecutiveSummary
         WHERE DeliveryRate NOT BETWEEN 0 AND 1
            OR CancellationRate NOT BETWEEN 0 AND 1
            OR PaymentSuccessRate NOT BETWEEN 0 AND 1
            OR UnitReturnRate NOT BETWEEN 0 AND 1
            OR InventoryAvailabilityRate NOT BETWEEN 0 AND 1)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_SalesTrend
         WHERE DeliveryRate NOT BETWEEN 0 AND 1
            OR CancellationRate NOT BETWEEN 0 AND 1
            OR UnitReturnRate NOT BETWEEN 0 AND 1)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_StorePerformance
         WHERE UnitReturnRate NOT BETWEEN 0 AND 1)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_ProductPerformance
         WHERE UnitReturnRate NOT BETWEEN 0 AND 1 OR SellThroughRate NOT BETWEEN 0 AND 1)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_CustomerPerformance
         WHERE UnitReturnRate NOT BETWEEN 0 AND 1)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_InventoryPosition
         WHERE AvailabilityRate NOT BETWEEN 0 AND 1)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_ReturnsPerformance
         WHERE AcceptanceRate NOT BETWEEN 0 AND 1 OR ReusabilityRate NOT BETWEEN 0 AND 1)
      + (SELECT COUNT_BIG(*) FROM analytics.pbi_PaymentPerformance
         WHERE PaymentSuccessRate NOT BETWEEN 0 AND 1 OR CollectionRate NOT BETWEEN 0 AND 1);

    INSERT INTO @Results VALUES
    ('PBI-CAL-001', 'CALCULATIONS', 'Calculated rates remain within valid bounds', 'Critical',
     '0 invalid rates', CONCAT(@InvalidRateCount, ' invalid rates'), @InvalidRateCount,
     CASE WHEN @InvalidRateCount = 0 THEN 'Passed' ELSE 'Failed' END,
     'Operational rates must be between zero and one; margin rates are excluded because losses are valid.');

    DECLARE @InvalidInventoryStatus BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM analytics.pbi_InventoryPosition
        WHERE InventoryStatus NOT IN ('OUT OF STOCK', 'LOW STOCK', 'EXCESS STOCK', 'HEALTHY')
           OR (InventoryStatus = 'OUT OF STOCK' AND IsOutOfStock <> 1)
           OR (InventoryStatus = 'LOW STOCK' AND (IsOutOfStock = 1 OR IsBelowReorderLevel <> 1))
           OR (InventoryStatus = 'EXCESS STOCK' AND (IsOutOfStock = 1 OR IsBelowReorderLevel = 1 OR IsExcessStock <> 1))
           OR (InventoryStatus = 'HEALTHY' AND (IsOutOfStock = 1 OR IsBelowReorderLevel = 1 OR IsExcessStock = 1))
    );

    INSERT INTO @Results VALUES
    ('PBI-CAL-002', 'CALCULATIONS', 'Inventory status follows approved priority logic', 'High',
     '0 exceptions', CONCAT(@InvalidInventoryStatus, ' exceptions'), @InvalidInventoryStatus,
     CASE WHEN @InvalidInventoryStatus = 0 THEN 'Passed' ELSE 'Failed' END,
     'Priority is out of stock, low stock, excess stock, then healthy.');

    DECLARE @InvalidMonthSequence BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM
        (
            SELECT YearMonthNumber,
                   LAG(YearMonthNumber) OVER (ORDER BY YearMonthNumber) AS PreviousYearMonthNumber
            FROM analytics.pbi_SalesTrend
        ) AS month_sequence
        WHERE PreviousYearMonthNumber IS NOT NULL
          AND YearMonthNumber <= PreviousYearMonthNumber
    );

    INSERT INTO @Results VALUES
    ('PBI-TIM-001', 'TIME SERIES', 'Sales trend month key is strictly increasing', 'High',
     '0 ordering exceptions', CONCAT(@InvalidMonthSequence, ' ordering exceptions'), @InvalidMonthSequence,
     CASE WHEN @InvalidMonthSequence = 0 THEN 'Passed' ELSE 'Failed' END,
     'YearMonthNumber is the approved numeric sort key for MonthYearLabel in Power BI.');

    /* ======================================================================
       6. PERSIST AND COMPLETE VALIDATION
       ====================================================================== */
    INSERT INTO audit.ValidationResult
    (
        ValidationRunID, TestCode, TestName, Severity, ExpectedValue,
        ActualValue, ExceptionCount, TestStatus, ExecutedDate, DiagnosticMessage
    )
    SELECT
        @ValidationRunID, TestCode, TestName, Severity, ExpectedValue,
        ActualValue, ExceptionCount, TestStatus, SYSDATETIME(),
        CONCAT('[', TestCategory, '] ', DiagnosticMessage)
    FROM @Results;

    DECLARE @TotalTests INT = (SELECT COUNT(*) FROM @Results);
    DECLARE @PassedTests INT = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'Passed');
    DECLARE @FailedTests INT = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'Failed');

    UPDATE audit.ValidationRun
    SET RunEndDate = SYSDATETIME(),
        OverallStatus = CASE WHEN @FailedTests = 0 THEN 'Passed' ELSE 'Failed' END,
        TotalTests = @TotalTests,
        PassedTests = @PassedTests,
        FailedTests = @FailedTests,
        Remarks = CASE WHEN @FailedTests = 0
                       THEN 'Power BI model accepted: reporting views are reconciled and connection-ready.'
                       ELSE 'Power BI model rejected: review script 39 validation results.' END
    WHERE ValidationRunID = @ValidationRunID;

    SELECT
        TestSequence, TestCode, TestCategory, TestName, Severity,
        ExpectedValue, ActualValue, ExceptionCount, TestStatus, DiagnosticMessage
    FROM @Results
    ORDER BY TestSequence;

    SELECT
        ValidationRunID, RunStartDate, RunEndDate, EnvironmentName,
        OverallStatus, TotalTests, PassedTests, FailedTests, Remarks
    FROM audit.ValidationRun
    WHERE ValidationRunID = @ValidationRunID;

    IF @FailedTests > 0
        THROW 51593, 'Power BI model validation failed. Review the validation results before connecting Power BI.', 1;

    RAISERROR('39_PowerBI_Model_Validation.sql completed successfully: Power BI semantic layer accepted.', 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH
    IF EXISTS
    (
        SELECT 1 FROM audit.ValidationRun
        WHERE ValidationRunID = @ValidationRunID AND OverallStatus = 'Running'
    )
    BEGIN
        UPDATE audit.ValidationRun
        SET RunEndDate = SYSDATETIME(),
            OverallStatus = 'Failed',
            TotalTests = (SELECT COUNT(*) FROM @Results),
            PassedTests = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'Passed'),
            FailedTests = (SELECT COUNT(*) FROM @Results WHERE TestStatus = 'Failed'),
            Remarks = LEFT(CONCAT('Power BI validation execution error: ', ERROR_MESSAGE()), 500)
        WHERE ValidationRunID = @ValidationRunID;
    END;

    THROW;
END CATCH;
GO
