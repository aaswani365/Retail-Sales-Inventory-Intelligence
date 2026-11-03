/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      07_Create_Stored_Procedures.sql
Purpose:     Create controlled procedures for financial, lifecycle, inventory and validation operations.
Author:      Akshay Aswani
Version:     2.0
Depends on:  04_Create_Constraints.sql
Rerunnable:  Yes. CREATE OR ALTER replaces definitions without dropping permissions.
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51060, 'Procedure creation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'sales.SalesOrder', N'U') IS NULL
   OR OBJECT_ID(N'inventory.InventoryBalance', N'U') IS NULL
   OR OBJECT_ID(N'audit.ValidationRun', N'U') IS NULL
BEGIN
    THROW 51061, 'Procedure creation stopped: required tables are missing.', 1;
END;
GO

-- Rebuild persisted order-header totals from their authoritative order-item rows.
CREATE OR ALTER PROCEDURE sales.usp_RecalculateOrderTotals
    @SalesOrderID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SalesOrderID IS NULL OR @SalesOrderID <= 0
        THROW 51100, 'SalesOrderID must be a positive value.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS
        (
            SELECT 1
            FROM sales.SalesOrder WITH (UPDLOCK, HOLDLOCK)
            WHERE SalesOrderID = @SalesOrderID
        )
            THROW 51101, 'The requested sales order does not exist.', 1;

        DECLARE
            @SubtotalAmount DECIMAL(14,2),
            @DiscountAmount DECIMAL(14,2),
            @TaxAmount DECIMAL(14,2),
            @NetAmount DECIMAL(14,2);

        SELECT
            @SubtotalAmount = COALESCE(SUM(GrossAmount), 0),
            @DiscountAmount = COALESCE(SUM(DiscountAmount), 0),
            @TaxAmount = COALESCE(SUM(TaxAmount), 0),
            @NetAmount = COALESCE(SUM(NetAmount), 0)
        FROM sales.SalesOrderItem
        WHERE SalesOrderID = @SalesOrderID;

        UPDATE sales.SalesOrder
        SET SubtotalAmount = @SubtotalAmount,
            DiscountAmount = @DiscountAmount,
            TaxAmount = @TaxAmount,
            NetAmount = @NetAmount,
            ModifiedDate = SYSDATETIME()
        WHERE SalesOrderID = @SalesOrderID;

        COMMIT TRANSACTION;

        SELECT SalesOrderID, OrderNumber, SubtotalAmount, DiscountAmount, TaxAmount, NetAmount
        FROM sales.SalesOrder
        WHERE SalesOrderID = @SalesOrderID;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Apply only approved order-status transitions and retain immutable status history.
CREATE OR ALTER PROCEDURE sales.usp_ChangeOrderStatus
    @SalesOrderID BIGINT,
    @ToOrderStatusCode VARCHAR(30),
    @ChangedByEmployeeID INT = NULL,
    @StatusChangedDate DATETIME2(0) = NULL,
    @ChangeReason VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ToOrderStatusCode = UPPER(LTRIM(RTRIM(@ToOrderStatusCode)));
    SET @StatusChangedDate = COALESCE(@StatusChangedDate, SYSDATETIME());

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @FromOrderStatusID SMALLINT,
            @FromOrderStatusCode VARCHAR(30),
            @ToOrderStatusID SMALLINT;

        SELECT
            @FromOrderStatusID = so.OrderStatusID,
            @FromOrderStatusCode = os.OrderStatusCode
        FROM sales.SalesOrder AS so WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN ref.OrderStatus AS os
            ON os.OrderStatusID = so.OrderStatusID
        WHERE so.SalesOrderID = @SalesOrderID;

        IF @FromOrderStatusID IS NULL
            THROW 51110, 'The requested sales order does not exist.', 1;

        SELECT @ToOrderStatusID = OrderStatusID
        FROM ref.OrderStatus
        WHERE OrderStatusCode = @ToOrderStatusCode
          AND IsActive = 1;

        IF @ToOrderStatusID IS NULL
            THROW 51111, 'The target order status code is invalid or inactive.', 1;

        IF @ChangedByEmployeeID IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM core.Employee WHERE EmployeeID = @ChangedByEmployeeID)
            THROW 51112, 'ChangedByEmployeeID does not exist.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM
            (
                VALUES
                    ('PENDING', 'CONFIRMED'), ('PENDING', 'CANCELLED'),
                    ('CONFIRMED', 'PROCESSING'), ('CONFIRMED', 'CANCELLED'),
                    ('PROCESSING', 'SHIPPED'), ('PROCESSING', 'CANCELLED'),
                    ('SHIPPED', 'DELIVERED'),
                    ('DELIVERED', 'PARTIALLY_RETURNED'), ('DELIVERED', 'RETURNED'),
                    ('PARTIALLY_RETURNED', 'RETURNED')
            ) AS transition (FromCode, ToCode)
            WHERE transition.FromCode = @FromOrderStatusCode
              AND transition.ToCode = @ToOrderStatusCode
        )
            THROW 51113, 'The requested order-status transition is not permitted.', 1;

        UPDATE sales.SalesOrder
        SET OrderStatusID = @ToOrderStatusID,
            ConfirmedDate = CASE WHEN @ToOrderStatusCode = 'CONFIRMED' THEN @StatusChangedDate ELSE ConfirmedDate END,
            ShippedDate = CASE WHEN @ToOrderStatusCode = 'SHIPPED' THEN @StatusChangedDate ELSE ShippedDate END,
            DeliveredDate = CASE WHEN @ToOrderStatusCode = 'DELIVERED' THEN @StatusChangedDate ELSE DeliveredDate END,
            CancelledDate = CASE WHEN @ToOrderStatusCode = 'CANCELLED' THEN @StatusChangedDate ELSE CancelledDate END,
            ModifiedDate = SYSDATETIME()
        WHERE SalesOrderID = @SalesOrderID;

        INSERT INTO sales.OrderStatusHistory
        (
            SalesOrderID, FromOrderStatusID, ToOrderStatusID,
            StatusChangedDate, ChangedByEmployeeID, ChangeReason
        )
        VALUES
        (
            @SalesOrderID, @FromOrderStatusID, @ToOrderStatusID,
            @StatusChangedDate, @ChangedByEmployeeID, NULLIF(LTRIM(RTRIM(@ChangeReason)), '')
        );

        COMMIT TRANSACTION;

        SELECT @SalesOrderID AS SalesOrderID,
               @FromOrderStatusCode AS FromOrderStatusCode,
               @ToOrderStatusCode AS ToOrderStatusCode,
               @StatusChangedDate AS StatusChangedDate;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Record a payment attempt while preventing completed collections above the order value.
CREATE OR ALTER PROCEDURE sales.usp_RecordPayment
    @SalesOrderID BIGINT,
    @PaymentMethodCode VARCHAR(30),
    @PaymentStatusCode VARCHAR(30),
    @Amount DECIMAL(14,2),
    @PaymentDate DATETIME2(0) = NULL,
    @TransactionReference VARCHAR(100) = NULL,
    @FailureReason VARCHAR(255) = NULL,
    @Remarks VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @PaymentMethodCode = UPPER(LTRIM(RTRIM(@PaymentMethodCode)));
    SET @PaymentStatusCode = UPPER(LTRIM(RTRIM(@PaymentStatusCode)));
    SET @PaymentDate = COALESCE(@PaymentDate, SYSDATETIME());

    IF @Amount IS NULL OR @Amount <= 0
        THROW 51120, 'Payment amount must be greater than zero.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @PaymentMethodID SMALLINT,
            @PaymentStatusID SMALLINT,
            @OrderNetAmount DECIMAL(14,2),
            @CompletedAmount DECIMAL(14,2),
            @AttemptNumber SMALLINT,
            @PaymentID BIGINT;

        SELECT @OrderNetAmount = NetAmount
        FROM sales.SalesOrder WITH (UPDLOCK, HOLDLOCK)
        WHERE SalesOrderID = @SalesOrderID;

        IF @OrderNetAmount IS NULL
            THROW 51121, 'The requested sales order does not exist.', 1;

        SELECT @PaymentMethodID = PaymentMethodID
        FROM ref.PaymentMethod
        WHERE PaymentMethodCode = @PaymentMethodCode AND IsActive = 1;

        SELECT @PaymentStatusID = PaymentStatusID
        FROM ref.PaymentStatus
        WHERE PaymentStatusCode = @PaymentStatusCode AND IsActive = 1;

        IF @PaymentMethodID IS NULL THROW 51122, 'Payment method is invalid or inactive.', 1;
        IF @PaymentStatusID IS NULL THROW 51123, 'Payment status is invalid or inactive.', 1;
        IF @PaymentStatusCode = 'FAILED' AND NULLIF(LTRIM(RTRIM(@FailureReason)), '') IS NULL
            THROW 51124, 'A failed payment requires a failure reason.', 1;

        SELECT
            @CompletedAmount = COALESCE(SUM(CASE WHEN ps.PaymentStatusCode = 'COMPLETED' THEN p.Amount ELSE 0 END), 0),
            @AttemptNumber = CONVERT(SMALLINT, COALESCE(MAX(p.AttemptNumber), 0) + 1)
        FROM sales.Payment AS p WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN ref.PaymentStatus AS ps
            ON ps.PaymentStatusID = p.PaymentStatusID
        WHERE p.SalesOrderID = @SalesOrderID;

        IF @PaymentStatusCode = 'COMPLETED' AND @CompletedAmount + @Amount > @OrderNetAmount + 0.01
            THROW 51125, 'Completed payments would exceed the order net amount.', 1;

        INSERT INTO sales.Payment
        (
            SalesOrderID, PaymentMethodID, PaymentStatusID, AttemptNumber,
            PaymentDate, Amount, TransactionReference, FailureReason, Remarks
        )
        VALUES
        (
            @SalesOrderID, @PaymentMethodID, @PaymentStatusID, @AttemptNumber,
            @PaymentDate, @Amount, NULLIF(LTRIM(RTRIM(@TransactionReference)), ''),
            NULLIF(LTRIM(RTRIM(@FailureReason)), ''), NULLIF(LTRIM(RTRIM(@Remarks)), '')
        );

        SET @PaymentID = SCOPE_IDENTITY();
        COMMIT TRANSACTION;

        SELECT @PaymentID AS PaymentID, @SalesOrderID AS SalesOrderID,
               @AttemptNumber AS AttemptNumber, @PaymentStatusCode AS PaymentStatusCode,
               @Amount AS Amount;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Append an inventory-ledger event and update its current product-store balance atomically.
CREATE OR ALTER PROCEDURE inventory.usp_PostInventoryMovement
    @ProductID INT,
    @StoreID INT,
    @InventoryMovementTypeCode VARCHAR(30),
    @Quantity INT,
    @MovementDate DATETIME2(0) = NULL,
    @SalesOrderItemID BIGINT = NULL,
    @ProductReturnItemID BIGINT = NULL,
    @ReferenceNumber VARCHAR(50) = NULL,
    @Reason VARCHAR(255) = NULL,
    @CreatedByEmployeeID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @InventoryMovementTypeCode = UPPER(LTRIM(RTRIM(@InventoryMovementTypeCode)));
    SET @MovementDate = COALESCE(@MovementDate, SYSDATETIME());

    IF @Quantity IS NULL OR @Quantity <= 0
        THROW 51130, 'Movement quantity must be greater than zero.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @InventoryMovementTypeID SMALLINT,
            @QuantityDirection SMALLINT,
            @RequiresReference BIT,
            @NewQuantityOnHand BIGINT,
            @InventoryMovementID BIGINT;

        IF NOT EXISTS (SELECT 1 FROM core.Product WHERE ProductID = @ProductID AND IsActive = 1)
            THROW 51131, 'Product does not exist or is inactive.', 1;
        IF NOT EXISTS (SELECT 1 FROM core.Store WHERE StoreID = @StoreID AND IsActive = 1)
            THROW 51132, 'Store does not exist or is inactive.', 1;

        SELECT
            @InventoryMovementTypeID = InventoryMovementTypeID,
            @QuantityDirection = QuantityDirection,
            @RequiresReference = RequiresReference
        FROM ref.InventoryMovementType
        WHERE InventoryMovementTypeCode = @InventoryMovementTypeCode
          AND IsActive = 1;

        IF @InventoryMovementTypeID IS NULL
            THROW 51133, 'Inventory movement type is invalid or inactive.', 1;
        IF @RequiresReference = 1
           AND @SalesOrderItemID IS NULL
           AND @ProductReturnItemID IS NULL
           AND NULLIF(LTRIM(RTRIM(@ReferenceNumber)), '') IS NULL
            THROW 51134, 'This movement type requires a source reference.', 1;
        IF @SalesOrderItemID IS NOT NULL AND @ProductReturnItemID IS NOT NULL
            THROW 51135, 'A movement cannot reference both an order item and a return item.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM inventory.InventoryBalance WITH (UPDLOCK, HOLDLOCK)
            WHERE ProductID = @ProductID AND StoreID = @StoreID
        )
        BEGIN
            INSERT INTO inventory.InventoryBalance (ProductID, StoreID, QuantityOnHand, QuantityReserved)
            VALUES (@ProductID, @StoreID, 0, 0);
        END;

        SELECT @NewQuantityOnHand = CONVERT(BIGINT, QuantityOnHand) + (CONVERT(BIGINT, @Quantity) * @QuantityDirection)
        FROM inventory.InventoryBalance WITH (UPDLOCK, HOLDLOCK)
        WHERE ProductID = @ProductID AND StoreID = @StoreID;

        IF @NewQuantityOnHand < 0 OR @NewQuantityOnHand > 2147483647
            THROW 51136, 'The movement would create an invalid on-hand balance.', 1;

        INSERT INTO inventory.InventoryMovement
        (
            ProductID, StoreID, InventoryMovementTypeID, MovementDate,
            Quantity, QuantityDirection, SalesOrderItemID, ProductReturnItemID,
            ReferenceNumber, Reason, CreatedByEmployeeID
        )
        VALUES
        (
            @ProductID, @StoreID, @InventoryMovementTypeID, @MovementDate,
            @Quantity, @QuantityDirection, @SalesOrderItemID, @ProductReturnItemID,
            NULLIF(LTRIM(RTRIM(@ReferenceNumber)), ''), NULLIF(LTRIM(RTRIM(@Reason)), ''),
            @CreatedByEmployeeID
        );

        SET @InventoryMovementID = SCOPE_IDENTITY();

        UPDATE inventory.InventoryBalance
        SET QuantityOnHand = CONVERT(INT, @NewQuantityOnHand),
            LastMovementDate = @MovementDate,
            LastRestockedDate = CASE WHEN @QuantityDirection = 1 THEN @MovementDate ELSE LastRestockedDate END,
            ModifiedDate = SYSDATETIME()
        WHERE ProductID = @ProductID AND StoreID = @StoreID;

        COMMIT TRANSACTION;

        SELECT @InventoryMovementID AS InventoryMovementID, @ProductID AS ProductID,
               @StoreID AS StoreID, @InventoryMovementTypeCode AS InventoryMovementTypeCode,
               @NewQuantityOnHand AS QuantityOnHand;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Record a refund only when the payment and return belong to the same order.
CREATE OR ALTER PROCEDURE sales.usp_RecordRefund
    @PaymentID BIGINT,
    @ProductReturnID BIGINT,
    @RefundAmount DECIMAL(14,2),
    @RefundStatus VARCHAR(20),
    @RefundDate DATETIME2(0) = NULL,
    @RefundReference VARCHAR(100) = NULL,
    @Remarks VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @RefundDate = COALESCE(@RefundDate, SYSDATETIME());
    SET @RefundStatus = CONCAT(UPPER(LEFT(LTRIM(RTRIM(@RefundStatus)), 1)), LOWER(SUBSTRING(LTRIM(RTRIM(@RefundStatus)), 2, 19)));

    IF @RefundAmount IS NULL OR @RefundAmount <= 0
        THROW 51140, 'Refund amount must be greater than zero.', 1;
    IF @RefundStatus NOT IN ('Pending', 'Completed', 'Failed')
        THROW 51141, 'Refund status must be Pending, Completed or Failed.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @PaymentOrderID BIGINT,
            @ReturnOrderID BIGINT,
            @PaymentAmount DECIMAL(14,2),
            @PaymentStatusCode VARCHAR(30),
            @ReturnRefundedAmount DECIMAL(14,2),
            @PaymentRefundedAmount DECIMAL(14,2),
            @EligibleRefundAmount DECIMAL(14,2),
            @RefundID BIGINT;

        SELECT
            @PaymentOrderID = p.SalesOrderID,
            @PaymentAmount = p.Amount,
            @PaymentStatusCode = ps.PaymentStatusCode
        FROM sales.Payment AS p WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN ref.PaymentStatus AS ps ON ps.PaymentStatusID = p.PaymentStatusID
        WHERE p.PaymentID = @PaymentID;

        SELECT @ReturnOrderID = SalesOrderID
        FROM sales.ProductReturn WITH (UPDLOCK, HOLDLOCK)
        WHERE ProductReturnID = @ProductReturnID;

        IF @PaymentOrderID IS NULL THROW 51142, 'Payment does not exist.', 1;
        IF @ReturnOrderID IS NULL THROW 51143, 'Product return does not exist.', 1;
        IF @PaymentOrderID <> @ReturnOrderID THROW 51144, 'Payment and return must belong to the same order.', 1;
        IF @PaymentStatusCode <> 'COMPLETED' THROW 51145, 'Refunds require a completed payment.', 1;

        SELECT @EligibleRefundAmount = COALESCE(SUM(EligibleRefundAmount), 0)
        FROM sales.ProductReturnItem
        WHERE ProductReturnID = @ProductReturnID;

        SELECT @ReturnRefundedAmount = COALESCE(SUM(RefundAmount), 0)
        FROM sales.Refund WITH (UPDLOCK, HOLDLOCK)
        WHERE ProductReturnID = @ProductReturnID
          AND RefundStatus = 'Completed';

        SELECT @PaymentRefundedAmount = COALESCE(SUM(RefundAmount), 0)
        FROM sales.Refund WITH (UPDLOCK, HOLDLOCK)
        WHERE PaymentID = @PaymentID
          AND RefundStatus = 'Completed';

        IF @RefundStatus = 'Completed'
           AND (@ReturnRefundedAmount + @RefundAmount > @EligibleRefundAmount + 0.01
                OR @PaymentRefundedAmount + @RefundAmount > @PaymentAmount + 0.01)
            THROW 51146, 'Completed refunds would exceed the eligible return or payment amount.', 1;

        INSERT INTO sales.Refund
        (
            PaymentID, ProductReturnID, RefundDate, RefundAmount,
            RefundReference, RefundStatus, Remarks
        )
        VALUES
        (
            @PaymentID, @ProductReturnID, @RefundDate, @RefundAmount,
            NULLIF(LTRIM(RTRIM(@RefundReference)), ''), @RefundStatus,
            NULLIF(LTRIM(RTRIM(@Remarks)), '')
        );

        SET @RefundID = SCOPE_IDENTITY();
        COMMIT TRANSACTION;

        SELECT @RefundID AS RefundID, @PaymentID AS PaymentID,
               @ProductReturnID AS ProductReturnID, @RefundAmount AS RefundAmount,
               @RefundStatus AS RefundStatus;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Add or replace one test result within a validation run.
CREATE OR ALTER PROCEDURE audit.usp_RecordValidationResult
    @ValidationRunID BIGINT,
    @TestCode VARCHAR(50),
    @TestName VARCHAR(200),
    @Severity VARCHAR(10),
    @ExpectedValue VARCHAR(100) = NULL,
    @ActualValue VARCHAR(100) = NULL,
    @ExceptionCount BIGINT,
    @DiagnosticMessage VARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM audit.ValidationRun WHERE ValidationRunID = @ValidationRunID AND OverallStatus = 'Running')
        THROW 51150, 'Validation run does not exist or is already complete.', 1;
    IF @ExceptionCount IS NULL OR @ExceptionCount < 0
        THROW 51151, 'ExceptionCount cannot be negative.', 1;
    IF @Severity NOT IN ('Critical', 'High', 'Medium', 'Warning', 'Info')
        THROW 51152, 'Validation severity is invalid.', 1;

    DECLARE @TestStatus VARCHAR(10) = CASE WHEN @ExceptionCount = 0 THEN 'Passed' ELSE 'Failed' END;

    UPDATE audit.ValidationResult
    SET TestName = @TestName,
        Severity = @Severity,
        ExpectedValue = @ExpectedValue,
        ActualValue = @ActualValue,
        ExceptionCount = @ExceptionCount,
        TestStatus = @TestStatus,
        ExecutedDate = SYSDATETIME(),
        DiagnosticMessage = @DiagnosticMessage
    WHERE ValidationRunID = @ValidationRunID
      AND TestCode = @TestCode;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO audit.ValidationResult
        (
            ValidationRunID, TestCode, TestName, Severity, ExpectedValue,
            ActualValue, ExceptionCount, TestStatus, ExecutedDate, DiagnosticMessage
        )
        VALUES
        (
            @ValidationRunID, @TestCode, @TestName, @Severity, @ExpectedValue,
            @ActualValue, @ExceptionCount, @TestStatus, SYSDATETIME(), @DiagnosticMessage
        );
    END;

    SELECT ValidationResultID, ValidationRunID, TestCode, TestStatus, ExceptionCount
    FROM audit.ValidationResult
    WHERE ValidationRunID = @ValidationRunID AND TestCode = @TestCode;
END;
GO

-- Finalize a validation run using its recorded test results.
CREATE OR ALTER PROCEDURE audit.usp_CompleteValidationRun
    @ValidationRunID BIGINT,
    @Remarks VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS
        (
            SELECT 1 FROM audit.ValidationRun WITH (UPDLOCK, HOLDLOCK)
            WHERE ValidationRunID = @ValidationRunID AND OverallStatus = 'Running'
        )
            THROW 51160, 'Validation run does not exist or is already complete.', 1;

        DECLARE @TotalTests INT, @PassedTests INT, @FailedTests INT;

        SELECT
            @TotalTests = COUNT(*),
            @PassedTests = COALESCE(SUM(CASE WHEN TestStatus = 'Passed' THEN 1 ELSE 0 END), 0),
            @FailedTests = COALESCE(SUM(CASE WHEN TestStatus = 'Failed' THEN 1 ELSE 0 END), 0)
        FROM audit.ValidationResult
        WHERE ValidationRunID = @ValidationRunID;

        UPDATE audit.ValidationRun
        SET RunEndDate = SYSDATETIME(),
            OverallStatus = CASE WHEN @FailedTests = 0 THEN 'Passed' ELSE 'Failed' END,
            TotalTests = @TotalTests,
            PassedTests = @PassedTests,
            FailedTests = @FailedTests,
            Remarks = COALESCE(NULLIF(LTRIM(RTRIM(@Remarks)), ''), Remarks)
        WHERE ValidationRunID = @ValidationRunID;

        COMMIT TRANSACTION;

        SELECT ValidationRunID, RunStartDate, RunEndDate, EnvironmentName,
               OverallStatus, TotalTests, PassedTests, FailedTests, Remarks
        FROM audit.ValidationRun
        WHERE ValidationRunID = @ValidationRunID;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

DECLARE @ExpectedProcedures TABLE
(
    ProcedureSequence TINYINT NOT NULL PRIMARY KEY,
    SchemaName SYSNAME NOT NULL,
    ProcedureName SYSNAME NOT NULL,
    Purpose VARCHAR(150) NOT NULL
);

INSERT INTO @ExpectedProcedures VALUES
(1, N'sales', N'usp_RecalculateOrderTotals', 'Reconcile order header totals from order items'),
(2, N'sales', N'usp_ChangeOrderStatus', 'Enforce order lifecycle transitions and history'),
(3, N'sales', N'usp_RecordPayment', 'Record controlled payment attempts'),
(4, N'inventory', N'usp_PostInventoryMovement', 'Post inventory ledger and balance changes atomically'),
(5, N'sales', N'usp_RecordRefund', 'Record controlled refund events'),
(6, N'audit', N'usp_RecordValidationResult', 'Upsert one validation result'),
(7, N'audit', N'usp_CompleteValidationRun', 'Finalize validation control totals');

IF EXISTS
(
    SELECT 1
    FROM @ExpectedProcedures AS ep
    WHERE OBJECT_ID(QUOTENAME(ep.SchemaName) + N'.' + QUOTENAME(ep.ProcedureName), N'P') IS NULL
)
    THROW 51062, 'Procedure validation failed: one or more approved procedures are missing.', 1;

SELECT
    ep.ProcedureSequence,
    ep.SchemaName,
    ep.ProcedureName,
    ep.Purpose,
    COUNT(p.parameter_id) AS ParameterCount,
    CASE WHEN OBJECT_ID(QUOTENAME(ep.SchemaName) + N'.' + QUOTENAME(ep.ProcedureName), N'P') IS NOT NULL
         THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus
FROM @ExpectedProcedures AS ep
LEFT JOIN sys.parameters AS p
    ON p.object_id = OBJECT_ID(QUOTENAME(ep.SchemaName) + N'.' + QUOTENAME(ep.ProcedureName), N'P')
   AND p.parameter_id > 0
GROUP BY ep.ProcedureSequence, ep.SchemaName, ep.ProcedureName, ep.Purpose
ORDER BY ep.ProcedureSequence;

RAISERROR('07_Create_Stored_Procedures.sql completed successfully: 7 approved procedures validated.', 10, 1) WITH NOWAIT;
GO
