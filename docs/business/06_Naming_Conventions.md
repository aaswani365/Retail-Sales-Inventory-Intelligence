# Retail Sales & Inventory Intelligence Platform

## Naming Conventions and Coding Standards

| Document attribute | Value |
|---|---|
| Project name | Retail Sales & Inventory Intelligence Platform |
| Project version | 2.0 |
| Document | 06_Naming_Conventions.md |
| Author | Akshay Aswani |
| Database | RetailIntelligenceDB |
| Platform | Microsoft SQL Server and Power BI |
| Status | Approved implementation standard |
| Related documents | 03_Project_Architecture.md, 04_Database_Design.md, 05_Data_Dictionary.md |

---

## 1. Purpose

This document defines the mandatory naming and coding standards for the SQL Server database, analytical model, Power BI solution, repository and documentation. Its goal is to make every project object predictable, searchable and understandable without opening its implementation.

These standards apply to all new Version 2 objects. Existing scripts should be aligned when they are rebuilt; do not rename historical Version 1 files merely to imitate Version 2.

## 2. Core principles

1. Use clear business terms instead of unexplained abbreviations.
2. Use one name for one concept across SQL Server, Power BI and documentation.
3. Prefer singular names for database tables and Power BI entities.
4. Use `PascalCase` for SQL objects and columns.
5. Use `UPPER_SNAKE_CASE` for stable business-code values.
6. Include the object type and business scope in constraint and index names.
7. Avoid spaces, special characters and SQL reserved words in technical objects.
8. Do not encode a data type in a business column name.
9. Keep names concise, but never shorten them until their meaning becomes unclear.
10. Preserve naming consistency even when SQL Server allows multiple valid styles.

## 3. Case and word-separation standards

| Context | Standard | Correct example | Avoid |
|---|---|---|---|
| Database, schema object, table, column | `PascalCase` | `OrderStatusID` | `order_status_id`, `orderstatusid` |
| Schema | Lowercase | `sales` | `Sales`, `SALES` |
| Business-code value | `UPPER_SNAKE_CASE` | `PARTIALLY_RETURNED` | `Partially Returned` |
| Local SQL variable | `PascalCase` after `@` | `@OrderID` | `@order_id` |
| Stored-procedure parameter | `PascalCase` after `@` | `@StartDate` | `@p_StartDate` |
| CTE | `PascalCase` with purpose | `MonthlySales` | `CTE1` |
| Temporary table | `PascalCase` after `#` | `#ValidOrders` | `#tmp1` |
| Power BI measure | Title case with spaces | `Net Sales` | `Net_Sales_Measure` |
| DAX variable | `PascalCase` | `SelectedYear` | `var1` |
| Repository folder/file | Descriptive convention by artifact | `sql/03_tables/` | `misc/` |

SQL Server commonly uses a case-insensitive collation, but this project still treats the documented case as the required presentation standard.

## 4. Database and schema names

### 4.1 Database

Use a descriptive `PascalCase` name ending in `DB`.

```sql
RetailIntelligenceDB
```

Do not use environment-specific database names inside reusable object scripts. Environment suffixes such as `_Dev`, `_Test` or `_Prod` belong to deployment configuration only.

### 4.2 Schemas

Use short lowercase business-layer names.

| Schema | Responsibility |
|---|---|
| `ref` | Controlled classifications and statuses |
| `core` | Master business entities |
| `sales` | Orders, payments, returns and refunds |
| `inventory` | Inventory balances and movement events |
| `audit` | Validation execution history |
| `analytics` | Power BI-ready dimensions, facts and reporting objects |

Always schema-qualify database objects:

```sql
SELECT SalesOrderID, OrderDate
FROM sales.SalesOrder;
```

Avoid relying on the default `dbo` schema for project objects.

## 5. Table names

Use singular `PascalCase` nouns that describe the grain.

| Object purpose | Standard | Example |
|---|---|---|
| Reference entity | Business noun | `ref.OrderStatus` |
| Master entity | Business noun | `core.Customer` |
| Transaction header | Transaction noun | `sales.SalesOrder` |
| Transaction detail | Header plus `Item` | `sales.SalesOrderItem` |
| History table | Entity plus `History` | `sales.OrderStatusHistory` |
| Current balance | Entity plus `Balance` | `inventory.InventoryBalance` |
| Event ledger | Entity plus event noun | `inventory.InventoryMovement` |
| Audit header/detail | Process noun | `audit.ValidationRun`, `audit.ValidationResult` |
| Analytical dimension | `Dim` plus entity | `analytics.DimProduct` |
| Analytical fact | `Fact` plus process | `analytics.FactSales` |
| Periodic snapshot fact | `Fact` + entity + `Snapshot` | `analytics.FactInventorySnapshot` |
| Bridge table | `Bridge` plus both entities | `analytics.BridgeProductSupplier` |

Rules:

- Do not prefix operational tables with `tbl`.
- Do not use plural table names such as `Customers`.
- Do not use reserved words such as `Order`, `User` or `Transaction` alone.
- Do not include the schema in the table name; use `sales.SalesOrder`, not `sales.SalesSalesOrder`.
- A table name must agree with its documented grain.

## 6. Column names

### 6.1 General rules

- Use singular `PascalCase` names.
- Use the same spelling wherever the same business concept appears.
- Use complete words unless an abbreviation is universally understood in the domain.
- Do not include table aliases or schema names in column names.
- Do not use spaces, hyphens, punctuation or bracket-dependent names.
- Do not use generic names such as `Value`, `Type`, `Code` or `Status` without a business qualifier.

| Concept | Required pattern | Examples |
|---|---|---|
| Surrogate key | `<Entity>ID` | `ProductID`, `SalesOrderID` |
| Foreign key | Referenced key name | `CustomerID`, `PaymentStatusID` |
| Stable business code | `<Entity>Code` | `ProductCode`, `OrderStatusCode` |
| Human-readable name | `<Entity>Name` | `StoreName`, `BrandName` |
| Boolean flag | `Is`, `Has` or `Requires` prefix | `IsActive`, `HasWarranty`, `RequiresReference` |
| Calendar date | Business event plus `Date` | `OrderDate`, `HireDate` |
| Timestamp | Event plus `Date` or `At` consistently | `CreatedDate`, `StatusDate` |
| Quantity | `Quantity` plus qualifier if required | `Quantity`, `QuantityOnHand` |
| Monetary amount | Business meaning plus `Amount` | `TaxAmount`, `RefundAmount` |
| Percentage/rate | Business meaning plus `Rate` | `DiscountRate`, `TaxRate` |
| Free text | Business meaning or `Notes` | `CancellationReason`, `Notes` |

### 6.2 Identifier rules

- Surrogate primary keys use `<Entity>ID`.
- Foreign-key columns retain the exact referenced key name.
- Do not use `ID` alone.
- Do not embed meaningful business information in a surrogate key.
- Public-facing business references use explicit names such as `OrderNumber`, not `SalesOrderID`.

### 6.3 Date and time rules

| Meaning | Name | Recommended type |
|---|---|---|
| Business calendar date | `<Event>Date` | `DATE` |
| Event timestamp | `<Event>Date` | `DATETIME2(0)` |
| Row creation timestamp | `CreatedDate` | `DATETIME2(0)` |
| Last modification timestamp | `ModifiedDate` | `DATETIME2(0)` |
| Effective interval | `EffectiveFrom`, `EffectiveTo` | `DATETIME2(0)` |

The data type, data dictionary and business definition distinguish a date from a timestamp. Do not mix `CreatedOn`, `CreateDate`, `CreationDate` and `CreatedDate`.

### 6.4 Monetary and percentage rules

- Use `Amount` for currency values: `PaymentAmount`, `RefundAmount`.
- Use `Price` for per-unit sale prices: `UnitPrice`.
- Use `Cost` for acquisition or operating costs: `UnitCost`.
- Use `Rate` for stored decimal rates: `TaxRate`, `DiscountRate`.
- Do not use ambiguous names such as `Total` without the business component.
- Derived totals should expose their basis: `GrossAmount`, `DiscountAmount`, `NetAmount`.

## 7. Key and constraint names

Constraint names must be explicit rather than system-generated.

| Object | Pattern | Example |
|---|---|---|
| Primary key | `PK_<Table>` | `PK_SalesOrder` |
| Composite primary key | `PK_<Table>` | `PK_InventoryBalance` |
| Foreign key | `FK_<ChildTable>_<ParentTable>[_<Role>]` | `FK_SalesOrder_Customer` |
| Self-referencing FK | `FK_<Table>_<Role>` | `FK_Employee_Manager` |
| Unique constraint | `UQ_<Table>_<ColumnList>` | `UQ_Product_ProductCode` |
| Check constraint | `CK_<Table>_<Rule>` | `CK_Product_UnitPriceNonNegative` |
| Default constraint | `DF_<Table>_<Column>` | `DF_Product_IsActive` |

Rules:

- Omit schema names unless duplicate table names would create ambiguity.
- Use meaningful rule names, not sequential names such as `CK_Product_01`.
- For multi-column uniqueness, include columns in logical key order.
- A foreign-key role suffix is required when one parent is referenced more than once.

Examples:

```sql
CONSTRAINT PK_SalesOrder PRIMARY KEY (SalesOrderID)

CONSTRAINT FK_SalesOrder_Customer
    FOREIGN KEY (CustomerID) REFERENCES core.Customer (CustomerID)

CONSTRAINT CK_SalesOrderItem_QuantityPositive
    CHECK (Quantity > 0)

CONSTRAINT DF_SalesOrder_CreatedDate
    DEFAULT (SYSDATETIME()) FOR CreatedDate
```

## 8. Index names

| Index type | Pattern | Example |
|---|---|---|
| Nonclustered index | `IX_<Table>_<KeyColumns>` | `IX_SalesOrder_OrderDate` |
| Unique index | `UX_<Table>_<KeyColumns>` | `UX_Customer_Email` |
| Filtered index | `IX_<Table>_<Purpose>` | `IX_Customer_ActiveEmail` |
| Columnstore index | `CCI_<Table>` or `NCCI_<Table>_<Purpose>` | `CCI_FactSales` |

Guidelines:

- List index key columns in index order.
- Add a short purpose suffix when a filtered condition or long composite key would otherwise be unclear.
- Do not list included columns in the index name.
- Do not encode `ASC` or `DESC` unless it materially distinguishes two indexes.
- Do not create an index whose name differs but whose definition duplicates another index.

## 9. Views

Use `vw_` followed by a descriptive `PascalCase` name.

| View category | Pattern | Example |
|---|---|---|
| Operational reporting view | `<schema>.vw_<Purpose>` | `sales.vw_OrderSummary` |
| Validation view | `audit.vw_<Purpose>` | `audit.vw_FailedValidation` |
| Analytical source view | `analytics.vw_<Purpose>` | `analytics.vw_FactSalesSource` |

The name should describe the result set, not the implementation. Avoid `View1`, `vw_Data` and version suffixes such as `_Final2`.

## 10. Stored procedures

Use `usp_` followed by an action and business object.

```text
<schema>.usp_<Action><BusinessObject>
```

| Action | Example |
|---|---|
| Insert/create | `sales.usp_CreateSalesOrder` |
| Update | `sales.usp_UpdateOrderStatus` |
| Load | `analytics.usp_LoadFactSales` |
| Validate | `audit.usp_ValidateInventoryBalance` |
| Reconcile | `inventory.usp_ReconcileInventory` |

Rules:

- Do not use the `sp_` prefix because SQL Server reserves it for system procedures.
- Start with a precise action verb.
- Use `Get` only for procedures that return data without a business-state change.
- Procedure parameters use the corresponding column name when meanings match.
- Output parameters use a clear suffix only when necessary, such as `@NewSalesOrderID`.

## 11. Functions, sequences and synonyms

| Object | Pattern | Example |
|---|---|---|
| Scalar function | `ufn_<Purpose>` | `analytics.ufn_FiscalYear` |
| Table-valued function | `ufn_<ResultSet>` | `sales.ufn_OrderItemsByDate` |
| Sequence | `SEQ_<Entity>` | `sales.SEQ_OrderNumber` |
| Synonym | `SYN_<SourceObject>` | `analytics.SYN_ExternalExchangeRate` |

Functions must describe the returned value or row set. Do not name a function with an action that implies a state-changing operation.

## 12. Triggers

Use the table, timing and operation in the name.

```text
TR_<Table>_<Timing>_<Operation>[_<Purpose>]
```

Examples:

```text
TR_SalesOrder_After_Update_StatusHistory
TR_InventoryMovement_After_Insert_UpdateBalance
```

Use triggers only when their requirement cannot be implemented more transparently through constraints, procedures or controlled ETL. Each trigger must have a documented business purpose and must support multi-row statements.

## 13. SQL aliases, variables, CTEs and temporary objects

### 13.1 Table aliases

Use short, recognizable aliases based on the table name.

```sql
SELECT
    so.SalesOrderID,
    c.CustomerName,
    soi.NetAmount
FROM sales.SalesOrder AS so
INNER JOIN core.Customer AS c
    ON c.CustomerID = so.CustomerID
INNER JOIN sales.SalesOrderItem AS soi
    ON soi.SalesOrderID = so.SalesOrderID;
```

Avoid single-letter aliases in complex queries and aliases such as `a`, `b`, `x1` or `temp`.

### 13.2 Variables and parameters

| Type | Standard | Example |
|---|---|---|
| Input parameter | Business name | `@StartDate` |
| Local variable | Business name | `@NetSalesAmount` |
| Row counter | Meaningful counter | `@RowsInserted` |
| Return/status value | Defined result | `@ValidationStatus` |

Do not add Hungarian-style prefixes such as `@intProductID`.

### 13.3 CTEs and temporary tables

- CTEs use a singular or plural noun describing the result: `MonthlySales`, `RankedProducts`.
- Temporary tables use `#` plus `PascalCase`: `#EligibleReturns`.
- Table variables follow parameter-style naming: `@ValidationResults`.
- Never use `CTE1`, `TempData`, `#Test` or `@T` in committed scripts.

## 14. Statuses and business-code values

Stable codes use uppercase ASCII values with underscores:

```text
PENDING
PARTIALLY_PAID
PARTIALLY_RETURNED
STOCK_ADJUSTMENT_IN
STOCK_ADJUSTMENT_OUT
```

Rules:

- Codes are stable integration values and should not change when display labels change.
- Names are user-facing labels, for example `Partially Returned`.
- Do not store several spellings of the same code.
- Do not use numeric magic values in analytical SQL; join to the reference table or use the stable code.
- Avoid abbreviations such as `PR`, `COMP` or `CNCL` unless formally defined by the business.

## 15. SQL script filenames

Use a two-digit execution sequence, an underscore and an action-oriented `PascalCase` description:

```text
NN_Action_Object.sql
```

Recommended Version 2 sequence:

| Range | Purpose | Example |
|---:|---|---|
| `00` | Full-build orchestration | `00_Run_Full_Build.sql` |
| `01–04` | Database, schemas, tables, constraints | `03_Create_Tables.sql` |
| `05–09` | Indexes, views, procedures, triggers | `05_Create_Indexes.sql` |
| `10–19` | Reference and synthetic data | `10_Load_Reference_Data.sql` |
| `20–29` | Validation and reconciliation | `20_Validate_Schema.sql` |
| `30–39` | Business analysis | `30_Sales_Analysis.sql` |
| `40–49` | Analytics model and Power BI source objects | `40_Create_Analytics_Model.sql` |

Rules:

- Preserve execution numbers once published.
- Use leading zeroes so files sort correctly.
- Do not use spaces or parentheses in filenames.
- Do not commit names such as `final.sql`, `new_script.sql`, `query1.sql` or `copy.sql`.
- Put rerunnable cleanup logic in an explicitly named development utility, not in production build scripts.

## 16. SQL formatting standards

- Write SQL keywords in uppercase.
- Place one selected column per line in non-trivial queries.
- Use explicit `INNER JOIN`, `LEFT JOIN` and join conditions.
- Terminate statements with semicolons.
- Use four spaces for indentation; do not mix tabs and spaces.
- Always specify the target column list in `INSERT` statements.
- Never use `SELECT *` in committed views, procedures or analytical queries.
- Use `CREATE OR ALTER` where supported for rerunnable programmable objects.
- Use `TRY...CATCH`, transaction handling and `SET XACT_ABORT ON` for multi-step state changes.
- Prefix Unicode string literals with `N` when the target is `NVARCHAR`.
- Comment the reason for complex logic, not the obvious syntax.

Example:

```sql
SELECT
    s.StoreName,
    CAST(so.OrderDate AS DATE) AS OrderDate,
    SUM(soi.NetAmount) AS NetSalesAmount
FROM sales.SalesOrder AS so
INNER JOIN sales.SalesOrderItem AS soi
    ON soi.SalesOrderID = so.SalesOrderID
INNER JOIN core.Store AS s
    ON s.StoreID = so.StoreID
WHERE so.OrderDate >= @StartDate
  AND so.OrderDate < DATEADD(DAY, 1, @EndDate)
GROUP BY
    s.StoreName,
    CAST(so.OrderDate AS DATE);
```

## 17. Power BI model naming

### 17.1 Tables and fields

| Object | Standard | Example |
|---|---|---|
| Dimension table | Business-friendly singular name | `Product`, `Customer`, `Date` |
| Fact table | Business process name | `Sales`, `Inventory Snapshot` |
| Hidden technical key | Retain source meaning | `ProductID` |
| Display attribute | Friendly title | `Product Name` |
| Date hierarchy | Explicit business hierarchy | `Year > Quarter > Month > Date` |
| Measure table | `_Measures` | `_Measures` |

Technical source objects may use `DimProduct` and `FactSales`; the semantic model may expose friendly table names. Never mix operational and analytical columns without a documented transformation.

### 17.2 Measures

Measures use concise business language with spaces.

| Metric | Preferred name | Avoid |
|---|---|---|
| Sales before returns | `Gross Sales` | `Sum_of_Sales` |
| Sales after returns/refunds | `Net Sales` | `Sales Final` |
| Count of orders | `Total Orders` | `Order Count Measure` |
| Average order value | `Average Order Value` | `AOV_M` |
| Returned quantity rate | `Return Rate %` | `ReturnPct` |
| Prior-year comparison | `Net Sales PY` | `LastYearSales1` |
| Year-over-year change | `Net Sales YoY %` | `% Growth` |

Measure suffixes:

| Suffix | Meaning |
|---|---|
| `PY` | Previous year |
| `PM` | Previous month |
| `YTD` | Year to date |
| `MTD` | Month to date |
| `%` | Percentage result |
| `Target` | Target value |
| `Variance` | Absolute difference from target/baseline |
| `Variance %` | Percentage difference from target/baseline |

Do not prefix measures with `M_` or suffix every measure with `Measure`.

### 17.3 DAX formatting

```DAX
Net Sales =
VAR GrossSalesAmount =
    SUM ( Sales[Gross Amount] )
VAR RefundAmount =
    SUM ( Refund[Refund Amount] )
RETURN
    GrossSalesAmount - RefundAmount
```

- Use `PascalCase` DAX variables.
- Format complex expressions across multiple lines.
- Qualify columns with table names.
- Do not qualify measures with table names unless ambiguity requires it.
- Organize measures into display folders such as `Sales`, `Orders`, `Returns`, `Inventory` and `Time Intelligence`.

### 17.4 Report pages and visuals

Use numbered, business-oriented page names:

```text
01 Executive Summary
02 Sales Performance
03 Product Analysis
04 Customer Insights
05 Inventory Management
06 Returns & Refunds
07 Store Performance
08 Drillthrough Details
```

Visual titles should describe the insight or comparison, such as `Net Sales by Month`, not the chart type `Line Chart 1`.

## 18. Repository and documentation names

### 18.1 Repository folders

Use lowercase folder names with underscores only when needed.

```text
docs/
sql/
power_bi/
data/
images/
tests/
```

Recommended SQL subfolders:

```text
sql/01_setup/
sql/02_tables/
sql/03_data/
sql/04_validation/
sql/05_analysis/
sql/06_analytics/
```

### 18.2 Documentation files

Number core project documents in reading order:

```text
01_Business_Requirements.md
02_Business_Rules.md
03_Project_Architecture.md
04_Database_Design.md
05_Data_Dictionary.md
06_Naming_Conventions.md
```

Use `README.md`, `LICENSE` and `CHANGELOG.md` for standard repository files. Avoid duplicate variants such as `README_new.md` and `README_final.md`.

### 18.3 Images and exports

Use lowercase descriptive names with an optional page number:

```text
01_executive_summary.png
02_sales_performance.png
database_er_diagram.png
```

Do not store screenshots with camera-generated or random names.

## 19. Approved abbreviations

Use abbreviations only when they are widely understood or formally approved.

| Abbreviation | Meaning | Approved usage |
|---|---|---|
| `ID` | Identifier | Column suffix |
| `SKU` | Stock Keeping Unit | `SKU` column or label |
| `URL` | Uniform Resource Locator | Column suffix |
| `UTC` | Coordinated Universal Time | Time-zone documentation |
| `YTD` | Year to date | Power BI measure suffix |
| `MTD` | Month to date | Power BI measure suffix |
| `PY` | Previous year | Power BI measure suffix |
| `YoY` | Year over year | Power BI measure suffix |

Avoid organization-specific abbreviations until they are defined in the project glossary.

## 20. Prohibited patterns

| Avoid | Use instead |
|---|---|
| `dbo.tbl_Orders` | `sales.SalesOrder` |
| `[Order]` | `SalesOrder` |
| `Product_Id` | `ProductID` |
| `ActiveFlag` | `IsActive` |
| `CreateDt` | `CreatedDate` |
| `amt`, `qty`, `desc` | `Amount`, `Quantity`, `Description` |
| `sp_GetSales` | `sales.usp_GetSalesSummary` |
| `IX_1` | `IX_SalesOrder_OrderDate` |
| `Status = 3` in analysis | Join/use stable status code |
| `SELECT *` | Explicit column list |
| `Final_Query_v3.sql` | Sequenced, purpose-based filename |
| `Measure 1` | Business metric name |
| `Page 1` | `01 Executive Summary` |

## 21. Review checklist

Before committing a database or Power BI object, confirm:

- [ ] The name communicates its business purpose.
- [ ] The name follows the required case and word-separation style.
- [ ] The schema and table name match the object's responsibility and grain.
- [ ] Primary and foreign keys follow `<Entity>ID` consistently.
- [ ] Dates, amounts, rates, quantities and flags use approved suffixes/prefixes.
- [ ] Constraints and indexes have explicit deterministic names.
- [ ] No SQL reserved word requires bracket escaping.
- [ ] No unexplained abbreviation or generic numbered name is present.
- [ ] The SQL filename communicates execution order and purpose.
- [ ] Power BI measures and pages use business-friendly display names.
- [ ] Documentation, data dictionary and implementation use the same spelling.

## 22. Enforcement

- Pull-request review should reject new objects that violate these standards without a documented exception.
- Validation scripts should test object names, unnamed constraints and prohibited patterns where practical.
- Approved deviations must be documented in the relevant design-decision file.
- Renaming a published analytical field requires checking Power BI dependencies before deployment.
- Business-code values should be treated as integration contracts and changed only through controlled migration.

---

## 23. Next deliverable

The next project document should be:

```text
07_ER_Diagram.md
```

It should present the operational entity relationships, cardinalities, optionality, table grains and a diagram that matches the approved database design.
