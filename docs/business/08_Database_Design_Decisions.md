# Retail Sales & Inventory Intelligence Platform

## Database Design Decisions

| Document attribute | Value |
|---|---|
| Project name | Retail Sales & Inventory Intelligence Platform |
| Project version | 2.0 |
| Document | 08_Database_Design_Decisions.md |
| Author | Akshay Aswani |
| Database | RetailIntelligenceDB |
| Platform | Microsoft SQL Server and Power BI |
| Status | Approved decision baseline |
| Related documents | 02_Business_Rules.md, 03_Project_Architecture.md, 04_Database_Design.md, 07_ER_Diagram.md |

---

## 1. Purpose

This document records the important design choices behind Version 2 of the Retail Sales & Inventory Intelligence Platform. Each decision explains the problem, alternatives, selected approach, rationale, consequences and future extension path.

The intent is to demonstrate that the database was designed from explicit business and engineering trade-offs rather than assembled as a collection of unrelated tables and queries.

## 2. Decision method

Each record uses the following structure:

| Field | Meaning |
|---|---|
| Decision ID | Stable reference used in reviews and documentation |
| Status | `Approved`, `Superseded` or `Deferred` |
| Context | Business or technical problem being solved |
| Options considered | Reasonable alternative designs |
| Decision | Selected Version 2 approach |
| Rationale | Why the approach best fits current requirements |
| Consequences | Benefits, costs and risks accepted |
| Future path | Conditions that justify revisiting the decision |

Decision priorities, in order:

1. Financial and operational correctness
2. Auditability and traceability
3. Clear table grain and referential integrity
4. Analytical usability
5. Maintainability and portfolio readability
6. Performance appropriate for the planned data volume
7. Extensibility without premature complexity

## 3. Decision summary

| ID | Decision | Status |
|---|---|---|
| DD-001 | Separate operational and analytical models | Approved |
| DD-002 | Organize operational objects by business schema | Approved |
| DD-003 | Use surrogate primary keys plus business alternate keys | Approved |
| DD-004 | Use singular `PascalCase` table and column names | Approved |
| DD-005 | Use `sales.SalesOrder` instead of reserved word `Order` | Approved |
| DD-006 | Normalize controlled statuses and classifications | Approved |
| DD-007 | Store current order status and full status history | Approved |
| DD-008 | Separate order headers from order items | Approved |
| DD-009 | Preserve unit cost and price on each order item | Approved |
| DD-010 | Store header totals and validate them against item totals | Approved |
| DD-011 | Model payments as attempts/events rather than one order field | Approved |
| DD-012 | Model refunds separately from payments | Approved |
| DD-013 | Separate return headers from return items | Approved |
| DD-014 | Maintain inventory balance plus immutable movement ledger | Approved |
| DD-015 | Track on-hand and reserved quantities separately | Approved |
| DD-016 | Keep one current primary supplier per product | Approved |
| DD-017 | Keep one current primary store per employee | Approved |
| DD-018 | Use soft retirement and lifecycle statuses | Approved |
| DD-019 | Use `DECIMAL` and persisted transaction amounts | Approved |
| DD-020 | Use `DATETIME2(0)` and `DATE` by business meaning | Approved |
| DD-021 | Use explicit named constraints and conservative referential actions | Approved |
| DD-022 | Keep validation execution history inside the database | Approved |
| DD-023 | Use deterministic, scenario-based synthetic data | Approved |
| DD-024 | Build Power BI from curated analytics objects | Approved |

---

## 4. DD-001 — Separate operational and analytical models

**Status:** Approved  
**Scope:** Architecture

### Context

Normalized operational structures protect transactional integrity, while Power BI performs best with simple star schemas and consistent fact grains. Using one model for both purposes would either weaken operational design or make reporting unnecessarily complex.

### Options considered

1. Connect Power BI directly to all normalized operational tables.
2. Use one denormalized database model for transactions and reports.
3. Maintain a normalized operational model and build a separate analytical layer.

### Decision

Use `ref`, `core`, `sales`, `inventory` and `audit` for the normalized operational model. Build separate dimensions, facts and reporting views under `analytics` after operational validation succeeds.

### Rationale

- Preserves transactional integrity and clear ownership.
- Allows Power BI measures to use stable fact grains.
- Demonstrates both relational modeling and dimensional modeling skills.
- Prevents reporting requirements from distorting operational tables.

### Consequences

- Requires a controlled transformation/load step.
- Requires reconciliation between source and analytical objects.
- Adds documentation and refresh dependencies.
- Makes analytical performance and semantic-model design significantly clearer.

### Future path

At larger scale, move the analytical layer to a dedicated warehouse or lakehouse while preserving the same dimensional contracts.

## 5. DD-002 — Organize objects by business schema

**Status:** Approved  
**Scope:** Architecture and security

### Context

A single `dbo` namespace makes ownership, discoverability and permissions unclear as the project grows.

### Options considered

1. Store all objects in `dbo`.
2. Create schemas by technical object type, such as `tables` and `views`.
3. Create schemas by business responsibility.

### Decision

Use `ref`, `core`, `sales`, `inventory`, `audit` and `analytics` schemas.

### Rationale

Business schemas communicate responsibility, simplify navigation and create natural security boundaries. Technical object types are already visible from metadata and naming.

### Consequences

- Every object reference must be schema-qualified.
- Cross-schema dependencies must be created in the correct sequence.
- Permissions can be assigned at schema level in a future production deployment.

### Future path

Add schemas only when a new bounded business responsibility appears; do not create schemas merely to hold a few objects.

## 6. DD-003 — Use surrogate keys plus business alternate keys

**Status:** Approved  
**Scope:** Keys and integration

### Context

Business codes are meaningful but can be long, mutable or sourced from external systems. Pure surrogate keys do not by themselves protect business uniqueness.

### Options considered

1. Use natural/business keys as primary keys.
2. Use surrogate keys without alternate-key enforcement.
3. Use surrogate primary keys and unique business alternate keys.

### Decision

Use integer or bigint identity surrogate primary keys. Enforce stable business identifiers such as `SKU`, `OrderNumber`, `ReturnNumber` and entity codes through unique constraints or indexes.

### Rationale

- Keeps foreign keys compact and joins consistent.
- Separates internal identity from external business meaning.
- Prevents duplicate business records.
- Supports future source-system integration and slowly changing dimensions.

### Consequences

- Every load must resolve business keys to surrogate keys.
- Duplicate handling must occur before insertion.
- Both key types must be documented and validated.

### Future path

If multiple source systems are introduced, add `SourceSystemCode` to relevant alternate keys rather than exposing source-native keys as warehouse identities.

## 7. DD-004 — Use singular `PascalCase` names

**Status:** Approved  
**Scope:** Maintainability

### Context

Inconsistent pluralization, prefixes and casing make SQL harder to review and increase naming drift between documentation and code.

### Options considered

1. Plural snake_case names.
2. Prefix-based names such as `tbl_Order`.
3. Singular `PascalCase` business names within lowercase schemas.

### Decision

Use singular `PascalCase` names for tables and columns, lowercase schema names and explicit object-type prefixes only for programmable objects or indexes.

### Rationale

This style is readable in SQL Server, aligns with the project data dictionary and avoids redundant `tbl` prefixes.

### Consequences

- Existing Version 1 scripts require renaming during rebuild.
- Reviewers must enforce exact spelling even under case-insensitive collation.

### Future path

The standard may be adapted for an external platform only if tooling or organizational conventions require it; mappings must then be documented.

## 8. DD-005 — Use `sales.SalesOrder` instead of `Order`

**Status:** Approved  
**Scope:** Naming and SQL compatibility

### Context

`ORDER` is a SQL keyword and requires bracket escaping. Generic `Order` also fails to distinguish purchase, transfer and sales orders.

### Options considered

1. Use `[Order]`.
2. Use `Orders`.
3. Use `sales.SalesOrder`.

### Decision

Name the customer-order table `sales.SalesOrder` and its detail table `sales.SalesOrderItem`.

### Rationale

The name avoids reserved-word friction and states the business process clearly.

### Consequences

- All V2 SQL, documentation and Power BI source mappings must use the new name.
- Future purchase orders can be added without ambiguity.

### Future path

Introduce `purchasing.PurchaseOrder` if procurement transactions enter scope.

## 9. DD-006 — Normalize controlled statuses and classifications

**Status:** Approved  
**Scope:** Data quality

### Context

Free-text status and category values produce spelling variants, invalid states and inconsistent ordering.

### Options considered

1. Store unrestricted text in transactional tables.
2. Use SQL check constraints for every allowed text value.
3. Use reference tables with stable codes and display names.

### Decision

Use reference tables for product classifications, order/payment/return statuses, payment methods, return reasons and inventory movement types.

### Rationale

- Centralizes allowed values and descriptions.
- Supports active/inactive governance without losing history.
- Separates stable codes from user-facing labels.
- Improves Power BI sort order and filtering.

### Consequences

- Adds joins and reference-data load dependencies.
- Reference rows must be seeded before dependent data.
- Code changes require controlled migration rather than arbitrary text edits.

### Future path

Add effective dating only if status definitions themselves need historical versioning.

## 10. DD-007 — Store current order status and full history

**Status:** Approved  
**Scope:** Order lifecycle

### Context

Operational queries need the current state quickly, while audit and process analysis require every transition.

### Options considered

1. Store only current status on `SalesOrder`.
2. Derive current status only from the latest history row.
3. Store current status and append every transition to history.

### Decision

Keep `SalesOrder.OrderStatusID` as the current state and record each transition in `OrderStatusHistory`.

### Rationale

This provides efficient current-state access and full lifecycle traceability. It also supports time-in-status and bottleneck analysis.

### Consequences

- Current status and latest history row can drift if updates are not atomic.
- Status changes require controlled procedure/transaction logic.
- Validation must compare current status with the latest history destination.

### Future path

Use a status-transition rules table if lifecycle paths become configurable rather than fixed in application or procedure logic.

## 11. DD-008 — Separate order headers from items

**Status:** Approved  
**Scope:** Transaction normalization

### Context

An order contains attributes shared by the transaction and a repeating collection of products.

### Options considered

1. Store one denormalized row per order-product combination with repeated header data.
2. Store products in a delimited order column.
3. Use `SalesOrder` and `SalesOrderItem` at separate grains.

### Decision

Use one header row per order and one detail row per unique product in the order.

### Rationale

- Removes repeated customer/store/order attributes.
- Supports line-level quantity, price, discount, tax and margin analysis.
- Provides a direct source grain for the sales fact table.

### Consequences

- Order totals require aggregation or validated stored totals.
- Header creation and item insertion must be transactional.
- The alternate key `(SalesOrderID, ProductID)` prevents duplicate product lines.

### Future path

If the same product must appear more than once because of promotions or fulfillment splits, add an explicit `LineNumber` and revise the alternate key.

## 12. DD-009 — Preserve unit cost and price on order items

**Status:** Approved  
**Scope:** Financial history

### Context

Product master prices and costs change over time. Historical sales and margin cannot depend on today's product values.

### Options considered

1. Always join historical orders to current product price/cost.
2. Create full product price-history tables immediately.
3. Snapshot actual `UnitCost` and `UnitPrice` on each order item.

### Decision

Persist the actual unit cost and unit selling price used at the time of sale on `SalesOrderItem`.

### Rationale

It preserves historical financial truth with limited complexity and makes margin calculation reproducible.

### Consequences

- Transaction values intentionally duplicate master values.
- Load/generation logic must capture valid point-in-time values.
- The product master remains the current catalogue, not a historical price ledger.

### Future path

Add price and cost history when the business must analyze catalogue changes independent of completed sales.

## 13. DD-010 — Store and reconcile header totals

**Status:** Approved  
**Scope:** Financial consistency

### Context

Deriving totals from items guarantees one source of truth but can add repeated aggregation cost. Persisting header totals improves operational access but introduces duplication.

### Options considered

1. Derive all order totals at query time.
2. Store only header totals and omit line calculations.
3. Store item calculations and persisted header totals with reconciliation.

### Decision

Persist subtotal, discount, tax and net amounts at the order header and require them to reconcile with item totals within ₹0.01.

### Rationale

This reflects common transactional design, supports efficient operational queries and retains detailed calculation evidence.

### Consequences

- Totals must be updated atomically with item changes.
- Validation queries are mandatory.
- Floating-point types are prohibited for monetary calculations.

### Future path

Use computed or maintained summary structures only if performance testing demonstrates a need.

## 14. DD-011 — Model payments as attempts and events

**Status:** Approved  
**Scope:** Payments

### Context

An order may have failed attempts, retries, multiple methods or partial payments. A single payment field on the order loses this history.

### Options considered

1. Store payment method/status directly on the order.
2. Keep only the successful payment.
3. Store one row per payment attempt or event.

### Decision

Use `sales.Payment` with one row per attempt/event, including method, status, amount, timestamp and attempt number.

### Rationale

- Preserves success and failure behavior.
- Supports payment-method and failure analysis.
- Allows multiple attempts and future partial-payment scenarios.

### Consequences

- Revenue must include only qualifying successful events.
- Duplicate attempt and transaction-reference controls are required.
- Order payment state becomes a derived business concept.

### Future path

Add gateway, currency, authorization and settlement attributes if multi-gateway or cross-border payments enter scope.

## 15. DD-012 — Model refunds separately from payments

**Status:** Approved  
**Scope:** Financial events

### Context

A refund is a cash outflow linked to an earlier collection and an approved return. Treating refunds as negative payments obscures their business cause.

### Options considered

1. Store refund amount on the return header.
2. Insert negative rows into `Payment`.
3. Use a dedicated `Refund` event table linked to both payment and return.

### Decision

Use `sales.Refund` with mandatory foreign keys to `Payment` and `ProductReturn`.

### Rationale

- Separates collections from reversals.
- Supports partial and staged refunds.
- Maintains traceability from cash outflow to return and original payment.

### Consequences

- Cross-order consistency cannot be enforced by a simple foreign key.
- Validation must verify that payment and return belong to the same order.
- Refund eligibility and cumulative limits require controlled logic.

### Future path

Replace the text refund status with `ref.RefundStatus` if refund workflows become more complex or externally integrated.

## 16. DD-013 — Separate return headers from return items

**Status:** Approved  
**Scope:** Returns

### Context

One return request can include several products, each with a different reason, accepted quantity and condition.

### Options considered

1. One return row per order.
2. One independent return row per item with repeated request details.
3. Return header plus item detail.

### Decision

Use `ProductReturn` for the request lifecycle and `ProductReturnItem` for item-specific quantities, reasons, eligibility and inspection results.

### Rationale

The design normalizes repeating item information and supports partial acceptance and product-level quality analysis.

### Consequences

- Return processing requires cross-table validation against original order items.
- Cumulative returned quantity must be checked across multiple requests.
- A return request cannot be considered valid without at least one item.

### Future path

Add return-shipment and warehouse-inspection entities if logistics workflows enter scope.

## 17. DD-014 — Maintain balance plus immutable movement ledger

**Status:** Approved  
**Scope:** Inventory

### Context

A balance-only model is fast but not explainable. A ledger-only model is fully traceable but can be expensive for frequent availability queries.

### Options considered

1. Store only current inventory balance.
2. Derive every balance from all movements.
3. Store current balance and append-only movement history with reconciliation.

### Decision

Use `InventoryBalance` for current product-store quantities and `InventoryMovement` as the immutable event ledger.

### Rationale

This combines operational query performance with auditability and supports movement-type, shrinkage, sale and return analysis.

### Consequences

- The balance and ledger can drift if writes are not atomic.
- Reconciliation is a mandatory validation control.
- Corrections require compensating movements rather than destructive updates.

### Future path

Introduce periodic physical-count events, warehouse/bin locations or event streaming when required by scale and operational scope.

## 18. DD-015 — Separate on-hand and reserved inventory

**Status:** Approved  
**Scope:** Inventory availability

### Context

Stock physically present may already be allocated to open orders. A single quantity cannot distinguish possession from availability.

### Options considered

1. Store only available quantity.
2. Store on-hand and available quantities independently.
3. Store on-hand and reserved quantities; derive available quantity.

### Decision

Store `QuantityOnHand` and `QuantityReserved`. Derive `QuantityAvailable = QuantityOnHand - QuantityReserved`.

### Rationale

Two stored components preserve business meaning while avoiding three independently mutable values.

### Consequences

- Reservation and release workflows must be consistent.
- Constraints require nonnegative quantities and reserved quantity not exceeding on-hand quantity.
- Availability is calculated through a view or computed expression.

### Future path

Add a reservation-detail table if allocation must be traced to individual order items.

## 19. DD-016 — Keep one current primary supplier per product

**Status:** Approved  
**Scope:** Product sourcing

### Context

Real products may have several suppliers, but the current portfolio scope focuses on retail sales and inventory analysis rather than procurement optimization.

### Options considered

1. Omit supplier relationships.
2. Direct `Product.SupplierID` relationship.
3. Product-supplier bridge with cost, lead time and effective dates.

### Decision

Use one mandatory current primary supplier on `Product` for the baseline release.

### Rationale

It supports supplier-level product and stock analysis without introducing procurement complexity that is not yet used.

### Consequences

- Multi-sourcing and supplier-specific costs cannot be modeled accurately.
- Supplier analysis represents primary assignment, not all commercial relationships.

### Future path

Replace the direct dependency with a `ProductSupplier` bridge when purchase orders, supplier lead times or source-specific costs enter scope.

## 20. DD-017 — Keep one current primary store per employee

**Status:** Approved  
**Scope:** Workforce assignment

### Context

Employee transfers and multi-store assignments are realistic, but no HR-history or workforce-planning analysis is required in the initial retail model.

### Options considered

1. No employee-store link.
2. Current `Employee.StoreID` only.
3. Effective-dated employee-store assignment history.

### Decision

Store one mandatory current primary store on `Employee`.

### Rationale

This is sufficient for order-processing and store-performance attribution while keeping synthetic-data generation understandable.

### Consequences

- Historical transfers are not represented.
- Old orders retain their order store and employee, but employee master shows only the current assignment.

### Future path

Introduce `EmployeeStoreAssignment` with effective dates when historical workforce analysis becomes a requirement.

## 21. DD-018 — Use soft retirement and lifecycle statuses

**Status:** Approved  
**Scope:** Retention and deletion

### Context

Deleting referenced master or transaction records breaks history and can invalidate financial reporting.

### Options considered

1. Cascade hard deletes.
2. Block all retirement.
3. Use `IsActive` on reusable reference/master entities and lifecycle statuses on transactions.

### Decision

Do not hard-delete referenced business data. Retire reference/master rows through `IsActive`; cancel, fail, close or reverse transactions through controlled lifecycle states and events.

### Rationale

This preserves traceability and makes historical reports reproducible.

### Consequences

- Operational queries must filter active rows when appropriate.
- Unique keys may remain occupied after retirement.
- Privacy-retention requirements would need a separate anonymization strategy.

### Future path

Add archival, legal-retention and personally identifiable information anonymization policies for a production deployment.

## 22. DD-019 — Use decimal monetary values and persisted components

**Status:** Approved  
**Scope:** Data types and finance

### Context

Binary floating-point types can create rounding errors. Financial analysis requires reproducible gross, discount, tax, net, payment and refund values.

### Options considered

1. Use `FLOAT` for calculations.
2. Store only the final amount.
3. Use fixed-precision `DECIMAL` and persist material calculation components.

### Decision

Use `DECIMAL(12,2)` for unit values and `DECIMAL(14,2)` for transaction totals. Persist gross, discount, tax and net components where they are material to reconciliation.

### Rationale

Fixed precision reflects currency behavior and makes financial validation explainable.

### Consequences

- Rounding order must be defined consistently.
- Values are currently INR-oriented and do not include a currency column.
- Check constraints must reject invalid negative values except in intentionally signed analytical calculations.

### Future path

Add `CurrencyCode`, exchange-rate facts and higher precision if multi-currency transactions enter scope.

## 23. DD-020 — Use `DATE` and `DATETIME2(0)` by business meaning

**Status:** Approved  
**Scope:** Temporal data

### Context

Legacy `DATETIME` has lower precision and a narrower range. Storing timestamps for date-only concepts complicates grouping and filtering.

### Options considered

1. Use `DATETIME` everywhere.
2. Store dates as strings.
3. Use `DATE` for calendar-only values and `DATETIME2(0)` for business events.

### Decision

Use `DATE` for values such as hire, registration and opening dates. Use `DATETIME2(0)` for orders, payments, movements, status changes and audit events.

### Rationale

The types communicate business meaning, support reliable date operations and provide sufficient second-level precision for the portfolio dataset.

### Consequences

- Time-zone context is not embedded in `DATETIME2`.
- Production integrations must agree on the stored time standard.

### Future path

Adopt UTC storage conventions or `DATETIMEOFFSET` when the solution spans multiple time zones or externally timestamped events.

## 24. DD-021 — Use named constraints and conservative referential actions

**Status:** Approved  
**Scope:** Integrity and deployment

### Context

System-generated constraint names are difficult to deploy and troubleshoot. Cascade deletes can remove important dependent history unintentionally.

### Options considered

1. Accept system-generated names and default actions.
2. Use cascade deletion broadly.
3. Explicitly name constraints and use `NO ACTION` for protected relationships.

### Decision

Use deterministic `PK_`, `FK_`, `UQ_`, `CK_` and `DF_` names. Use `NO ACTION` for reference/master, transaction, financial, inventory and audit relationships.

### Rationale

Named constraints improve diagnostics and repeatable deployment. Conservative deletion protects the audit trail.

### Consequences

- Cleanup scripts must delete in dependency order when test data is reset.
- Explicit retirement and correction workflows are required.

### Future path

Cascade deletion may be considered only for disposable staging objects, never by default for operational financial records.

## 25. DD-022 — Persist validation execution history

**Status:** Approved  
**Scope:** Data quality and audit

### Context

Printing validation query results proves only the current run. A portfolio-quality data platform should show whether checks ran, when they ran and what failed.

### Options considered

1. Keep standalone validation queries only.
2. Export validation results manually to files.
3. Store run metadata and individual test results in audit tables.

### Decision

Use `audit.ValidationRun` and `audit.ValidationResult` to persist validation outcomes.

### Rationale

- Creates repeatable evidence of data quality.
- Supports trend analysis of failures.
- Provides a clear deployment gate before analytical refresh.

### Consequences

- Validation procedures must update run totals and final status reliably.
- Audit data requires its own retention policy at scale.

### Future path

Integrate run results with orchestration alerts or a monitoring dashboard in a production implementation.

## 26. DD-023 — Use deterministic, scenario-based synthetic data

**Status:** Approved  
**Scope:** Portfolio dataset

### Context

The project cannot use confidential production retail data. Purely random values often create unrealistic distributions, broken relationships and weak business stories.

### Options considered

1. Use a small public dataset unchanged.
2. Generate independent random rows.
3. Generate reproducible synthetic data from documented business scenarios and distributions.

### Decision

Create synthetic data with fixed seeds, valid foreign-key dependency order, realistic seasonality, controlled edge cases and reconciled financial/inventory events.

### Rationale

This protects privacy while producing a dataset suitable for SQL validation, performance testing and meaningful Power BI storytelling.

### Consequences

- Generation logic becomes a project component that must be tested.
- Synthetic patterns must be disclosed and should not be presented as real market findings.
- Data anomalies should be intentional and catalogued rather than accidental.

### Future path

Parameterize row volume and scenario mix so the same generator can produce demo, test and performance datasets.

## 27. DD-024 — Build Power BI from curated analytics objects

**Status:** Approved  
**Scope:** Business intelligence

### Context

Directly importing a complex normalized model into Power BI creates excessive relationships, ambiguous filter paths and duplicated DAX logic.

### Options considered

1. Import all operational tables directly.
2. Build all transformation logic only in Power Query.
3. Publish curated SQL dimensions/facts and use a disciplined Power BI semantic model.

### Decision

Build Power BI from approved `analytics` dimensions, facts and source views. Use a dedicated Date dimension, one-to-many single-direction relationships and centrally defined measures.

### Rationale

- Simplifies the semantic model.
- Improves measure consistency and explainability.
- Moves reusable relational transformation logic closer to the data.
- Supports multiple report pages without duplicating calculation logic.

### Consequences

- Analytical load and refresh dependencies must be orchestrated.
- SQL and DAX responsibilities must be defined clearly.
- Source-to-report reconciliation becomes mandatory.

### Future path

Add incremental refresh, aggregation tables or a governed shared semantic model when data scale or report reuse justifies them.

---

## 28. Deferred decisions

The following capabilities are intentionally deferred, not forgotten:

| Deferred item | Reason for deferral | Trigger for reconsideration |
|---|---|---|
| Product-supplier bridge | Procurement is outside baseline scope | Multiple suppliers, lead time or supplier-specific costs required |
| Employee assignment history | Current assignment is sufficient | Transfer or workforce-history analysis required |
| Product price history | Transaction items preserve actual sale values | Catalogue price-change analysis required |
| Inventory reservation detail | Aggregate reservation is sufficient | Need to trace reservations to orders |
| Warehouse/bin hierarchy | Store-level stock is sufficient | Fulfillment-center or bin-level operations added |
| Multi-currency support | Dataset is INR-only | Cross-border sales introduced |
| Refund-status reference table | Three controlled states are sufficient | Complex refund workflow or external gateway integration |
| Effective-dated reference values | Reference definitions are stable | Historical definition changes required |
| Database partitioning | Planned volume does not justify it | Fact/event size and maintenance windows demand it |
| Temporal/system-versioned tables | Explicit history tables cover requirements | Broader row-level audit history required |
| Row-level security | Single-user portfolio environment | Production multi-role access introduced |

## 29. Decision traceability matrix

| Decision area | Business rule/document impact | Planned implementation evidence |
|---|---|---|
| Schemas and object boundaries | Architecture | Schema-creation and permission scripts |
| Keys and uniqueness | Data dictionary and ER diagram | PK, UQ and filtered unique indexes |
| Status governance | Business rules | Reference seed data and FKs |
| Order lifecycle | Business rules | Current status, history table and transition validation |
| Financial calculations | KPI definitions | Item/header reconciliation checks |
| Payment and refund separation | Revenue rules | Payment/refund views and net-sales analysis |
| Return modeling | Return rules | Header/detail FKs and quantity validation |
| Inventory balance and ledger | Inventory rules | Movement/balance reconciliation |
| Soft retirement | Retention rules | `IsActive` and lifecycle filters |
| Synthetic data | Data-generation strategy | Seeded generator and scenario checks |
| Audit framework | Testing strategy | Validation run/result procedures |
| Analytical separation | Power BI architecture | Star schema, DAX measure catalogue and reconciliation |

## 30. Decision review checklist

Before changing the approved design:

- [ ] Identify the affected decision ID.
- [ ] Confirm the new requirement cannot be met within the existing design.
- [ ] Document alternatives and migration impact.
- [ ] Review table grain, keys and relationship cardinality.
- [ ] Review financial, inventory and audit consequences.
- [ ] Assess SQL scripts, data generator, validations and Power BI dependencies.
- [ ] Update the business rules, database design, data dictionary and ER diagram.
- [ ] Add or change automated validation evidence.
- [ ] Mark the old decision `Superseded` rather than deleting its history.
- [ ] Record the approval date and replacement decision ID.

## 31. Portfolio value demonstrated

These decisions provide evidence of the following capabilities:

- Requirements-to-design traceability
- Normalized operational data modeling
- Dimensional-model separation for BI
- Financial reconciliation design
- Inventory-ledger thinking
- Lifecycle and event modeling
- Referential integrity and data-quality governance
- Deliberate scope control
- Trade-off analysis and future-ready architecture
- Technical documentation suitable for peer review

---

## 32. Next deliverable

The next project document should be:

```text
09_Data_Generation_Strategy.md
```

It should define the synthetic dataset scale, dependency order, distributions, seasonality, business scenarios, intentional edge cases, reconciliation controls and reproducibility requirements before data-generation scripts are written.
