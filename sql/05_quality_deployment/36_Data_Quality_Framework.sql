/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      36_Data_Quality_Framework.sql
Purpose:     Run an auditable end-to-end data-quality health check.
Author:      Akshay Aswani
Version:     2.0
Depends on:  35_Advanced_Business_Analysis.sql
Rerunnable:  Yes. Each execution creates a new audit validation run.

Quality dimensions
------------------
- Completeness: required populations and mandatory business attributes
- Uniqueness: natural keys and declared fact grains
- Validity: financial, lifecycle, return and inventory rules
- Integrity: trusted foreign keys and resolved analytical dimension keys
- Reconciliation: operational sources against analytical facts
- Timeliness: synchronized analytical load timestamps
- Reporting readiness: Power BI view grains and accepted model state
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
    THROW 51560, 'Data-quality framework stopped: unexpected database context.', 1;

IF OBJECT_ID(N'audit.ValidationRun', N'U') IS NULL
   OR OBJECT_ID(N'audit.ValidationResult', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactSales', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactPayments', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactReturns', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactRefunds', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventoryMovement', N'U') IS NULL
   OR OBJECT_ID(N'analytics.FactInventorySnapshot', N'U') IS NULL
    THROW 51561, 'Data-quality framework stopped: required audit or analytics tables are missing.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM audit.ValidationRun
    WHERE OverallStatus = 'Passed'
      AND Remarks LIKE 'Analytics model accepted%'
)
    THROW 51562, 'Data-quality framework stopped: run script 26 successfully first.', 1;

DECLARE @ValidationRunID BIGINT;

INSERT INTO audit.ValidationRun
(
    RunStartDate, RunEndDate, EnvironmentName, OverallStatus,
    TotalTests, PassedTests, FailedTests, Remarks
)
VALUES
(
    SYSDATETIME(), NULL, 'LOCAL', 'RUNNING', 0, 0, 0,
    'End-to-end data-quality framework initiated by script 36.'
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
       1. COMPLETENESS
       ====================================================================== */
    DECLARE @EmptyPopulationCount BIGINT =
        CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM core.Customer) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM core.Product) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM core.Store) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM sales.SalesOrder) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM sales.SalesOrderItem) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN NOT EXISTS (SELECT 1 FROM inventory.InventoryBalance) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('DQ-CMP-001', 'COMPLETENESS', 'Required business populations contain data', 'Critical',
     '0 empty populations', CONCAT(@EmptyPopulationCount, ' empty populations'), @EmptyPopulationCount,
     CASE WHEN @EmptyPopulationCount = 0 THEN 'Passed' ELSE 'Failed' END,
     'Customers, products, stores, orders, order items and inventory balances must be populated.');

    DECLARE @MandatoryTextExceptions BIGINT =
        (SELECT COUNT_BIG(*) FROM core.Customer
         WHERE NULLIF(LTRIM(RTRIM(CustomerCode)), '') IS NULL
            OR NULLIF(LTRIM(RTRIM(FirstName)), '') IS NULL
            OR NULLIF(LTRIM(RTRIM(LastName)), '') IS NULL)
      + (SELECT COUNT_BIG(*) FROM core.Product
         WHERE NULLIF(LTRIM(RTRIM(SKU)), '') IS NULL
            OR NULLIF(LTRIM(RTRIM(ProductName)), '') IS NULL)
      + (SELECT COUNT_BIG(*) FROM core.Store
         WHERE NULLIF(LTRIM(RTRIM(StoreCode)), '') IS NULL
            OR NULLIF(LTRIM(RTRIM(StoreName)), '') IS NULL)
      + (SELECT COUNT_BIG(*) FROM sales.SalesOrder
         WHERE NULLIF(LTRIM(RTRIM(OrderNumber)), '') IS NULL);

    INSERT INTO @Results VALUES
    ('DQ-CMP-002', 'COMPLETENESS', 'Mandatory business identifiers and names are populated', 'High',
     '0 exceptions', CONCAT(@MandatoryTextExceptions, ' exceptions'), @MandatoryTextExceptions,
     CASE WHEN @MandatoryTextExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Whitespace-only values are treated as missing.');

    /* ======================================================================
       2. UNIQUENESS AND GRAIN
       ====================================================================== */
    DECLARE @NaturalKeyDuplicates BIGINT =
        (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM core.Customer GROUP BY CustomerCode HAVING COUNT_BIG(*) > 1) AS customer_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM core.Product GROUP BY SKU HAVING COUNT_BIG(*) > 1) AS product_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM core.Store GROUP BY StoreCode HAVING COUNT_BIG(*) > 1) AS store_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM sales.SalesOrder GROUP BY OrderNumber HAVING COUNT_BIG(*) > 1) AS order_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM sales.ProductReturn GROUP BY ReturnNumber HAVING COUNT_BIG(*) > 1) AS return_duplicate);

    INSERT INTO @Results VALUES
    ('DQ-UNI-001', 'UNIQUENESS', 'Operational natural keys are unique', 'Critical',
     '0 duplicates', CONCAT(@NaturalKeyDuplicates, ' duplicates'), @NaturalKeyDuplicates,
     CASE WHEN @NaturalKeyDuplicates = 0 THEN 'Passed' ELSE 'Failed' END,
     'Customer code, SKU, store code, order number and return number are tested.');

    DECLARE @FactGrainDuplicates BIGINT =
        (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM analytics.FactSales GROUP BY SalesOrderItemID HAVING COUNT_BIG(*) > 1) AS sales_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM analytics.FactPayments GROUP BY PaymentID HAVING COUNT_BIG(*) > 1) AS payment_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM analytics.FactReturns GROUP BY ProductReturnItemID HAVING COUNT_BIG(*) > 1) AS return_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM analytics.FactRefunds GROUP BY RefundID HAVING COUNT_BIG(*) > 1) AS refund_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM analytics.FactInventoryMovement GROUP BY InventoryMovementID HAVING COUNT_BIG(*) > 1) AS movement_duplicate)
      + (SELECT COALESCE(SUM(DuplicateCount - 1), 0) FROM
            (SELECT COUNT_BIG(*) AS DuplicateCount FROM analytics.FactInventorySnapshot
             GROUP BY SnapshotDateKey, ProductKey, StoreKey HAVING COUNT_BIG(*) > 1) AS snapshot_duplicate);

    INSERT INTO @Results VALUES
    ('DQ-UNI-002', 'UNIQUENESS', 'Analytical fact grains are unique', 'Critical',
     '0 duplicates', CONCAT(@FactGrainDuplicates, ' duplicates'), @FactGrainDuplicates,
     CASE WHEN @FactGrainDuplicates = 0 THEN 'Passed' ELSE 'Failed' END,
     'All six fact tables are checked against their approved grain.');

    /* ======================================================================
       3. VALIDITY AND BUSINESS RULES
       ====================================================================== */
    DECLARE @OrderLifecycleExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sales.SalesOrder
        WHERE ConfirmedDate < OrderDate
           OR ShippedDate < COALESCE(ConfirmedDate, OrderDate)
           OR DeliveredDate < COALESCE(ShippedDate, ConfirmedDate, OrderDate)
           OR CancelledDate < OrderDate
    );

    INSERT INTO @Results VALUES
    ('DQ-VAL-001', 'VALIDITY', 'Order lifecycle dates are chronological', 'High',
     '0 exceptions', CONCAT(@OrderLifecycleExceptions, ' exceptions'), @OrderLifecycleExceptions,
     CASE WHEN @OrderLifecycleExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Confirmation, shipment, delivery and cancellation cannot precede their lifecycle origin.');

    DECLARE @OrderItemCalculationExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sales.SalesOrderItem
        WHERE Quantity <= 0 OR UnitCost < 0 OR UnitPrice < 0
           OR GrossAmount <> CONVERT(DECIMAL(14,2), Quantity * UnitPrice)
           OR DiscountAmount < 0 OR DiscountAmount > GrossAmount
           OR TaxAmount < 0
           OR NetAmount <> CONVERT(DECIMAL(14,2), GrossAmount - DiscountAmount + TaxAmount)
    );

    INSERT INTO @Results VALUES
    ('DQ-VAL-002', 'VALIDITY', 'Order-item financial calculations are valid', 'Critical',
     '0 exceptions', CONCAT(@OrderItemCalculationExceptions, ' exceptions'), @OrderItemCalculationExceptions,
     CASE WHEN @OrderItemCalculationExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Quantity, prices, gross value, discounts, tax and net value are recalculated.');

    DECLARE @OrderHeaderReconciliationExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sales.SalesOrder AS sales_order
        INNER JOIN
        (
            SELECT SalesOrderID,
                   SUM(GrossAmount) AS GrossAmount,
                   SUM(DiscountAmount) AS DiscountAmount,
                   SUM(TaxAmount) AS TaxAmount,
                   SUM(NetAmount) AS NetAmount
            FROM sales.SalesOrderItem
            GROUP BY SalesOrderID
        ) AS item_total ON item_total.SalesOrderID = sales_order.SalesOrderID
        WHERE sales_order.SubtotalAmount <> item_total.GrossAmount
           OR sales_order.DiscountAmount <> item_total.DiscountAmount
           OR sales_order.TaxAmount <> item_total.TaxAmount
           OR sales_order.NetAmount <> item_total.NetAmount
    );

    INSERT INTO @Results VALUES
    ('DQ-VAL-003', 'VALIDITY', 'Order headers reconcile to order items', 'Critical',
     '0 exceptions', CONCAT(@OrderHeaderReconciliationExceptions, ' exceptions'), @OrderHeaderReconciliationExceptions,
     CASE WHEN @OrderHeaderReconciliationExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Header subtotal, discount, tax and net amount must equal summed line values.');

    DECLARE @PaymentExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sales.Payment AS payment
        INNER JOIN sales.SalesOrder AS sales_order ON sales_order.SalesOrderID = payment.SalesOrderID
        WHERE payment.AttemptNumber <= 0 OR payment.Amount <= 0
           OR payment.PaymentDate < sales_order.OrderDate
    );

    INSERT INTO @Results VALUES
    ('DQ-VAL-004', 'VALIDITY', 'Payment attempts contain valid amounts and dates', 'High',
     '0 exceptions', CONCAT(@PaymentExceptions, ' exceptions'), @PaymentExceptions,
     CASE WHEN @PaymentExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Payment attempts must be positive and cannot precede the order.');

    DECLARE @ReturnExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sales.ProductReturnItem AS return_item
        WHERE return_item.QuantityRequested <= 0
           OR return_item.QuantityAccepted < 0
           OR return_item.QuantityAccepted > return_item.QuantityRequested
           OR return_item.EligibleRefundAmount < 0
    );

    INSERT INTO @Results VALUES
    ('DQ-VAL-005', 'VALIDITY', 'Return quantities and eligible values are valid', 'Critical',
     '0 exceptions', CONCAT(@ReturnExceptions, ' exceptions'), @ReturnExceptions,
     CASE WHEN @ReturnExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Accepted quantity cannot exceed requested quantity and eligible refund cannot be negative.');

    DECLARE @RefundLimitExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM
        (
            SELECT product_return.ProductReturnID,
                   COALESCE(return_total.EligibleRefundAmount, 0) AS EligibleRefundAmount,
                   COALESCE(refund_total.CompletedRefundAmount, 0) AS CompletedRefundAmount
            FROM sales.ProductReturn AS product_return
            LEFT JOIN
            (
                SELECT ProductReturnID, SUM(EligibleRefundAmount) AS EligibleRefundAmount
                FROM sales.ProductReturnItem GROUP BY ProductReturnID
            ) AS return_total ON return_total.ProductReturnID = product_return.ProductReturnID
            LEFT JOIN
            (
                SELECT ProductReturnID, SUM(CASE WHEN RefundStatus = 'Completed' THEN RefundAmount ELSE 0 END) AS CompletedRefundAmount
                FROM sales.Refund GROUP BY ProductReturnID
            ) AS refund_total ON refund_total.ProductReturnID = product_return.ProductReturnID
        ) AS refund_control
        WHERE refund_control.CompletedRefundAmount > refund_control.EligibleRefundAmount + 0.01
    );

    INSERT INTO @Results VALUES
    ('DQ-VAL-006', 'VALIDITY', 'Completed refunds do not exceed return eligibility', 'Critical',
     '0 exceptions', CONCAT(@RefundLimitExceptions, ' exceptions'), @RefundLimitExceptions,
     CASE WHEN @RefundLimitExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Completed refunds are compared with summed eligible refund values by return.');

    DECLARE @InventoryBalanceExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM inventory.InventoryBalance
        WHERE QuantityOnHand < 0 OR QuantityReserved < 0 OR QuantityReserved > QuantityOnHand
    );

    INSERT INTO @Results VALUES
    ('DQ-VAL-007', 'VALIDITY', 'Inventory balances are nonnegative and available', 'Critical',
     '0 exceptions', CONCAT(@InventoryBalanceExceptions, ' exceptions'), @InventoryBalanceExceptions,
     CASE WHEN @InventoryBalanceExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Reserved quantity cannot be negative or exceed quantity on hand.');

    DECLARE @InventoryMovementExceptions BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM inventory.InventoryMovement
        WHERE Quantity <= 0 OR QuantityDirection NOT IN (-1, 1)
    );

    INSERT INTO @Results VALUES
    ('DQ-VAL-008', 'VALIDITY', 'Inventory movement quantities and directions are valid', 'Critical',
     '0 exceptions', CONCAT(@InventoryMovementExceptions, ' exceptions'), @InventoryMovementExceptions,
     CASE WHEN @InventoryMovementExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'Movement quantity must be positive and direction must be minus one or plus one.');

    /* ======================================================================
       4. REFERENTIAL INTEGRITY
       ====================================================================== */
    DECLARE @UntrustedForeignKeys BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM sys.foreign_keys
        WHERE is_disabled = 1 OR is_not_trusted = 1
    );

    INSERT INTO @Results VALUES
    ('DQ-INT-001', 'INTEGRITY', 'Foreign keys are enabled and trusted', 'Critical',
     '0 untrusted keys', CONCAT(@UntrustedForeignKeys, ' untrusted keys'), @UntrustedForeignKeys,
     CASE WHEN @UntrustedForeignKeys = 0 THEN 'Passed' ELSE 'Failed' END,
     'Disabled or untrusted foreign keys weaken referential-integrity guarantees.');

    DECLARE @UnknownFactKeys BIGINT =
        (SELECT COUNT_BIG(*) FROM analytics.FactSales
         WHERE CustomerKey = 0 OR ProductKey = 0 OR StoreKey = 0 OR EmployeeKey = 0 OR OrderStatusKey = 0)
      + (SELECT COUNT_BIG(*) FROM analytics.FactPayments
         WHERE CustomerKey = 0 OR StoreKey = 0 OR PaymentMethodKey = 0 OR PaymentStatusKey = 0 OR OrderStatusKey = 0)
      + (SELECT COUNT_BIG(*) FROM analytics.FactReturns
         WHERE CustomerKey = 0 OR ProductKey = 0 OR StoreKey = 0 OR EmployeeKey = 0
            OR ReturnReasonKey = 0 OR ReturnStatusKey = 0 OR OrderStatusKey = 0)
      + (SELECT COUNT_BIG(*) FROM analytics.FactRefunds
         WHERE CustomerKey = 0 OR StoreKey = 0 OR PaymentMethodKey = 0 OR PaymentStatusKey = 0 OR OrderStatusKey = 0)
      + (SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement
         WHERE ProductKey = 0 OR StoreKey = 0 OR InventoryMovementTypeKey = 0)
      + (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot
         WHERE ProductKey = 0 OR StoreKey = 0);

    INSERT INTO @Results VALUES
    ('DQ-INT-002', 'INTEGRITY', 'Fact dimension keys resolve without unknown members', 'High',
     '0 unknown-key uses', CONCAT(@UnknownFactKeys, ' unknown-key uses'), @UnknownFactKeys,
     CASE WHEN @UnknownFactKeys = 0 THEN 'Passed' ELSE 'Failed' END,
     'Key zero is reserved for genuinely unknown source members; nullable movement creator is permitted.');

    /* ======================================================================
       5. SOURCE-TO-FACT RECONCILIATION
       ====================================================================== */
    DECLARE @RowCountMismatches BIGINT =
        CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM sales.SalesOrderItem) <> (SELECT COUNT_BIG(*) FROM analytics.FactSales) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM sales.Payment) <> (SELECT COUNT_BIG(*) FROM analytics.FactPayments) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM sales.ProductReturnItem) <> (SELECT COUNT_BIG(*) FROM analytics.FactReturns) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM sales.Refund) <> (SELECT COUNT_BIG(*) FROM analytics.FactRefunds) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM inventory.InventoryMovement) <> (SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM inventory.InventoryBalance) <> (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('DQ-REC-001', 'RECONCILIATION', 'Source and fact row counts reconcile', 'Critical',
     '0 mismatched facts', CONCAT(@RowCountMismatches, ' mismatched facts'), @RowCountMismatches,
     CASE WHEN @RowCountMismatches = 0 THEN 'Passed' ELSE 'Failed' END,
     'All six facts are compared with their operational source grain.');

    DECLARE @ValueMismatches BIGINT =
        CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(NetAmount), 0) FROM sales.SalesOrderItem)
                                  <> (SELECT COALESCE(SUM(NetAmount), 0) FROM analytics.FactSales) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(Amount), 0) FROM sales.Payment)
                                  <> (SELECT COALESCE(SUM(Amount), 0) FROM analytics.FactPayments) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(RefundAmount), 0) FROM sales.Refund)
                                  <> (SELECT COALESCE(SUM(RefundAmount), 0) FROM analytics.FactRefunds) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COALESCE(SUM(CONVERT(BIGINT, Quantity) * QuantityDirection), 0) FROM inventory.InventoryMovement)
                                  <> (SELECT COALESCE(SUM(CONVERT(BIGINT, SignedQuantity)), 0) FROM analytics.FactInventoryMovement) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('DQ-REC-002', 'RECONCILIATION', 'Financial values and movement units reconcile', 'Critical',
     '0 mismatched measures', CONCAT(@ValueMismatches, ' mismatched measures'), @ValueMismatches,
     CASE WHEN @ValueMismatches = 0 THEN 'Passed' ELSE 'Failed' END,
     'Sales, payment, refund and signed movement totals are reconciled.');

    /* ======================================================================
       6. TIMELINESS AND REPORTING READINESS
       ====================================================================== */
    DECLARE @MinimumFactLoadDate DATETIME2(0);
    DECLARE @MaximumFactLoadDate DATETIME2(0);

    SELECT
        @MinimumFactLoadDate = MIN(load_control.LoadDate),
        @MaximumFactLoadDate = MAX(load_control.LoadDate)
    FROM
    (
        SELECT MAX(LoadDate) AS LoadDate FROM analytics.FactSales
        UNION ALL SELECT MAX(LoadDate) FROM analytics.FactPayments
        UNION ALL SELECT MAX(LoadDate) FROM analytics.FactReturns
        UNION ALL SELECT MAX(LoadDate) FROM analytics.FactRefunds
        UNION ALL SELECT MAX(LoadDate) FROM analytics.FactInventoryMovement
        UNION ALL SELECT MAX(LoadDate) FROM analytics.FactInventorySnapshot
    ) AS load_control;

    DECLARE @LoadSynchronizationExceptions BIGINT =
        CASE WHEN @MinimumFactLoadDate IS NULL OR @MaximumFactLoadDate IS NULL
                  OR DATEDIFF(MINUTE, @MinimumFactLoadDate, @MaximumFactLoadDate) > 30
             THEN 1 ELSE 0 END;

    INSERT INTO @Results VALUES
    ('DQ-TIM-001', 'TIMELINESS', 'Fact loads belong to one synchronized build window', 'Warning',
     '<=30 minute spread',
     CONCAT(COALESCE(CONVERT(VARCHAR(19), @MinimumFactLoadDate, 120), 'NULL'), ' to ',
            COALESCE(CONVERT(VARCHAR(19), @MaximumFactLoadDate, 120), 'NULL')),
     @LoadSynchronizationExceptions,
     CASE WHEN @LoadSynchronizationExceptions = 0 THEN 'Passed' ELSE 'Failed' END,
     'The latest load timestamp from each fact should fall within one controlled build window.');

    DECLARE @ViewGrainMismatches BIGINT =
        CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM analytics.FactSales) <> (SELECT COUNT_BIG(*) FROM analytics.vw_SalesDetail) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM analytics.FactPayments) <> (SELECT COUNT_BIG(*) FROM analytics.vw_PaymentDetail) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM analytics.FactReturns) <> (SELECT COUNT_BIG(*) FROM analytics.vw_ReturnDetail) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM analytics.FactRefunds) <> (SELECT COUNT_BIG(*) FROM analytics.vw_RefundDetail) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM analytics.FactInventoryMovement) <> (SELECT COUNT_BIG(*) FROM analytics.vw_InventoryMovementDetail) THEN 1 ELSE 0 END)
      + CONVERT(BIGINT, CASE WHEN (SELECT COUNT_BIG(*) FROM analytics.FactInventorySnapshot) <> (SELECT COUNT_BIG(*) FROM analytics.vw_CurrentInventory) THEN 1 ELSE 0 END);

    INSERT INTO @Results VALUES
    ('DQ-RPT-001', 'REPORTING', 'Power BI detail views preserve fact grains', 'Critical',
     '0 mismatched views', CONCAT(@ViewGrainMismatches, ' mismatched views'), @ViewGrainMismatches,
     CASE WHEN @ViewGrainMismatches = 0 THEN 'Passed' ELSE 'Failed' END,
     'Six reporting detail views are reconciled to their underlying facts.');

    DECLARE @AcceptedModelMissing BIGINT = CASE WHEN EXISTS
    (
        SELECT 1 FROM audit.ValidationRun
        WHERE OverallStatus = 'Passed' AND Remarks LIKE 'Analytics model accepted%'
    ) THEN 0 ELSE 1 END;

    INSERT INTO @Results VALUES
    ('DQ-RPT-002', 'REPORTING', 'Accepted analytics-model validation is available', 'Critical',
     'Accepted model found', CASE WHEN @AcceptedModelMissing = 0 THEN 'Accepted model found' ELSE 'Not found' END,
     @AcceptedModelMissing, CASE WHEN @AcceptedModelMissing = 0 THEN 'Passed' ELSE 'Failed' END,
     'Script 26 acceptance is a prerequisite for trusted Power BI reporting.');

    /* ======================================================================
       7. PERSIST RESULTS AND COMPLETE THE AUDIT RUN
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
                       THEN 'Data-quality framework passed: operational and analytical layers are reporting-ready.'
                       ELSE 'Data-quality framework failed: review script 36 validation results.' END
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
        THROW 51563, 'Data-quality framework failed. Review the validation result set and audit tables.', 1;

    RAISERROR('36_Data_Quality_Framework.sql completed successfully: all data-quality controls passed.', 10, 1) WITH NOWAIT;
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
            Remarks = LEFT(CONCAT('Data-quality execution error: ', ERROR_MESSAGE()), 500)
        WHERE ValidationRunID = @ValidationRunID;
    END;

    THROW;
END CATCH;
GO
