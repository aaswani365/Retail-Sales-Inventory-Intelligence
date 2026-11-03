/*
Project:     Retail Sales & Inventory Intelligence Platform
Database:    RetailIntelligenceDB
Script:      09_Create_Triggers.sql
Purpose:     Document and validate the approved minimal-trigger design.
Author:      Akshay Aswani
Version:     2.0
Depends on:  07_Create_Stored_Procedures.sql
Rerunnable:  Yes. This script performs a non-destructive governance check.

Approved decision: no DML triggers
----------------------------------
The project intentionally creates no DML triggers in the foundation layer.

Reasoning:
1. Order-status changes and history are controlled by
   sales.usp_ChangeOrderStatus.
2. Inventory movements and balances are updated atomically by
   inventory.usp_PostInventoryMovement.
3. Payment and refund limits are controlled by explicit stored procedures.
4. PK, FK, UQ, CK and DF constraints enforce row-level integrity.
5. Data-quality and reconciliation scripts detect cross-table exceptions.
6. Hidden trigger behavior would complicate bulk synthetic-data generation,
   reruns, troubleshooting and interview explanation.

Future trigger acceptance criteria:
- A business rule cannot be expressed clearly through a constraint, procedure
  or scheduled validation.
- The implementation is set-based and correct for multi-row statements.
- Recursion, locking, bulk-load and rerun behavior are documented and tested.
- The trigger name follows TR_<Table>_<Timing>_<Operation>[_<Purpose>].
*/

:ON ERROR EXIT
:setvar DatabaseName "RetailIntelligenceDB"

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(DatabaseName)' OR N'$(DatabaseName)' <> N'RetailIntelligenceDB'
BEGIN
    THROW 51080, 'Trigger-policy validation stopped: unexpected database context.', 1;
END;

IF OBJECT_ID(N'sales.usp_ChangeOrderStatus', N'P') IS NULL
   OR OBJECT_ID(N'inventory.usp_PostInventoryMovement', N'P') IS NULL
   OR OBJECT_ID(N'sales.usp_RecordPayment', N'P') IS NULL
   OR OBJECT_ID(N'sales.usp_RecordRefund', N'P') IS NULL
BEGIN
    THROW 51081, 'Trigger-policy validation stopped: required control procedures are missing.', 1;
END;

DECLARE @ApprovedTriggerCount INT = 0;
DECLARE @ExistingProjectTriggerCount INT;

SELECT @ExistingProjectTriggerCount = COUNT(*)
FROM sys.triggers AS tr
INNER JOIN sys.tables AS t
    ON t.object_id = tr.parent_id
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE tr.is_ms_shipped = 0
  AND s.name IN (N'ref', N'core', N'sales', N'inventory', N'audit', N'analytics');

IF @ExistingProjectTriggerCount <> @ApprovedTriggerCount
BEGIN
    SELECT
        s.name AS SchemaName,
        t.name AS TableName,
        tr.name AS UnexpectedTriggerName,
        tr.is_disabled AS IsDisabled,
        tr.is_instead_of_trigger AS IsInsteadOfTrigger
    FROM sys.triggers AS tr
    INNER JOIN sys.tables AS t
        ON t.object_id = tr.parent_id
    INNER JOIN sys.schemas AS s
        ON s.schema_id = t.schema_id
    WHERE tr.is_ms_shipped = 0
      AND s.name IN (N'ref', N'core', N'sales', N'inventory', N'audit', N'analytics')
    ORDER BY s.name, t.name, tr.name;

    THROW 51082, 'Trigger-policy validation failed: unexpected project triggers exist.', 1;
END;

SELECT
    N'DML trigger policy' AS ValidationArea,
    @ApprovedTriggerCount AS ApprovedTriggerCount,
    @ExistingProjectTriggerCount AS ExistingTriggerCount,
    N'Constraints + explicit stored procedures + validation controls' AS EnforcementStrategy,
    CASE
        WHEN @ExistingProjectTriggerCount = @ApprovedTriggerCount THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus;

SELECT
    ControlObject,
    ControlPurpose,
    CASE
        WHEN OBJECT_ID(ControlObject, ObjectType) IS NOT NULL THEN 'PASSED'
        ELSE 'FAILED'
    END AS ValidationStatus
FROM
(
    VALUES
        (N'sales.usp_ChangeOrderStatus', N'P', N'Order lifecycle and status-history control'),
        (N'inventory.usp_PostInventoryMovement', N'P', N'Atomic inventory ledger and balance control'),
        (N'sales.usp_RecordPayment', N'P', N'Payment collection limit control'),
        (N'sales.usp_RecordRefund', N'P', N'Refund eligibility and limit control'),
        (N'audit.vw_OrderFinancialReconciliation', N'V', N'Order header-to-line reconciliation'),
        (N'audit.vw_InventoryBalanceReconciliation', N'V', N'Inventory balance-to-ledger reconciliation')
) AS controls (ControlObject, ObjectType, ControlPurpose)
ORDER BY ControlObject;

RAISERROR('09_Create_Triggers.sql completed successfully: zero-trigger policy validated.', 10, 1) WITH NOWAIT;
GO
