# Power BI Connection Guide

## Retail Sales & Inventory Intelligence Platform

**Database:** `RetailIntelligenceDB`  
**Local SQL Server instance:** `AKKI\SQLEXPRESS`  
**Recommended connectivity mode:** Import  
**Prerequisite:** `40_Deployment_Health_Check.sql` completed with `READY FOR POWER BI AND PORTFOLIO RELEASE`

---

> **Implementation alignment (3 November 2026).** The supplied `background.png` is a **1280 × 720** reusable report-shell image. It has a dark-blue branded header and footer, **horizontal page navigation** (Overview, Sales, Customers, Products, Stores, Inventory, Returns, Payments), one top slicer row, five KPI-card placeholders, and four large chart/analysis placeholders. The image is a *blank layout*, not evidence that any KPI or chart has passed UAT. The report is represented by the eight final page names below. Earlier draft references to a left navigation rail, a six-card KPI strip, synchronized slicers on every page, or a supplier dashboard page are superseded.

## 1. Connection architecture

The project contains three database layers:

1. **Operational layer** — normalized `ref`, `core`, `sales`, and `inventory` tables.
2. **Analytics layer** — Power BI-ready dimensions and fact tables in the `analytics` schema.
3. **Reporting layer** — validated `analytics.pbi_*` views for page-level reporting and reconciliation.

For the final portfolio dashboard, use the **analytics star schema as the core Power BI model**. Use the eight `pbi_*` views as validated summary/control tables, rapid page prototypes, and SQL-to-DAX reconciliation sources.

Do not build the dashboard directly from the operational tables. Doing so would recreate complex joins in Power BI and weaken the approved star-schema design.

---

## 2. Before opening Power BI

Confirm the following in SQL Server Management Studio:

```sql
USE RetailIntelligenceDB;
GO

SELECT TOP (1)
    ValidationRunID,
    OverallStatus,
    TotalTests,
    PassedTests,
    FailedTests,
    Remarks
FROM audit.ValidationRun
WHERE Remarks LIKE 'Deployment health check%'
ORDER BY ValidationRunID DESC;
```

The latest row should show:

```text
OverallStatus: Passed
FailedTests:   0
```

Also confirm that SQL Server is running:

1. Open **SQL Server Configuration Manager** or Windows **Services**.
2. Verify **SQL Server (SQLEXPRESS)** is running.
3. Power BI Desktop and SQL Server are on the same computer for local development.

---

## 3. Connect Power BI Desktop to SQL Server

1. Open **Power BI Desktop**.
2. Select **Home > Get data > SQL Server**.
3. Enter the following values:

| Setting | Value |
|---|---|
| Server | `AKKI\SQLEXPRESS` |
| Database | `RetailIntelligenceDB` |
| Data connectivity mode | `Import` |
| Command timeout | Leave at default initially |

4. Expand **Advanced options** only if needed. Do not enter a native SQL query for the main model.
5. Select **OK**.
6. Choose **Windows authentication**.
7. Select **Connect**.

If your computer or SQL Server instance name changes, obtain the current value in SSMS with:

```sql
SELECT @@SERVERNAME AS SQLServerInstance;
```

---

## 4. Recommended objects to import

### 4.1 Core dimensions

Import these twelve tables from the `analytics` schema:

| Table | Purpose |
|---|---|
| `DimDate` | Calendar and Indian financial-year analysis |
| `DimCustomer` | Customer profile and segmentation |
| `DimProduct` | Product, brand, category and supplier attributes |
| `DimStore` | Store, tier and geographic analysis |
| `DimEmployee` | Employee and job-title analysis |
| `DimSupplier` | Supplier analysis |
| `DimPaymentMethod` | Payment-method slicing |
| `DimOrderStatus` | Order lifecycle slicing |
| `DimPaymentStatus` | Payment outcome slicing |
| `DimReturnReason` | Return-reason analysis |
| `DimReturnStatus` | Return lifecycle analysis |
| `DimInventoryMovementType` | Inventory inflow/outflow analysis |

### 4.2 Core facts

Import these six tables:

| Table | Approved grain |
|---|---|
| `FactSales` | One row per sales-order item |
| `FactPayments` | One row per payment attempt |
| `FactReturns` | One row per returned order item |
| `FactRefunds` | One row per refund event |
| `FactInventoryMovement` | One row per inventory movement |
| `FactInventorySnapshot` | One row per product-store snapshot date |

### 4.3 Reporting and reconciliation views

Import the following views after the star schema is working:

| View | Dashboard use |
|---|---|
| `pbi_ExecutiveSummary` | Enterprise KPI reconciliation |
| `pbi_SalesTrend` | Monthly SQL control totals |
| `pbi_StorePerformance` | Store-ranking control totals |
| `pbi_ProductPerformance` | Product-ranking control totals |
| `pbi_CustomerPerformance` | Customer-value control totals |
| `pbi_InventoryPosition` | Page-ready inventory detail |
| `pbi_ReturnsPerformance` | Page-ready return analysis |
| `pbi_PaymentPerformance` | Page-ready payment analysis |

The aggregate views should normally be hidden from the report field list after reconciliation, except where a page intentionally uses the view directly.

---

## 5. Power Query preparation

In the Navigator, select **Transform Data**, not **Load**, so the model can be reviewed first.

Apply these conventions in Power Query:

1. Keep the SQL object names unchanged for traceability.
2. Set surrogate keys to **Whole number**.
3. Set monetary columns to **Fixed decimal number**.
4. Set quantity and count columns to **Whole number**.
5. Set rate columns to **Decimal number**.
6. Set actual calendar columns to **Date**.
7. Keep `YearMonthNumber` as a whole number.
8. Disable load only for temporary Power Query helper queries—not for model tables.
9. Do not replace database calculations with Power Query calculations unless documented.

Recommended query groups:

```text
01 Dimensions
02 Facts
03 SQL Control Views
04 Parameters
```

Rename the display folders or Power Query groups, but retain the database object names themselves.

---

## 6. Build the star-schema relationships

Create relationships from each dimension's primary key to the corresponding fact foreign key.

Use these settings unless noted otherwise:

- Cardinality: **One-to-many (1:*)**
- Cross-filter direction: **Single**
- Active relationship: **Yes** for the primary business date
- Referential integrity assumption: leave disabled in Import mode

### 6.1 FactSales

| Dimension | Dimension key | Fact key | Relationship |
|---|---|---|---|
| `DimDate` | `DateKey` | `OrderDateKey` | Active |
| `DimDate` | `DateKey` | `ConfirmedDateKey` | Inactive |
| `DimDate` | `DateKey` | `ShippedDateKey` | Inactive |
| `DimDate` | `DateKey` | `DeliveredDateKey` | Inactive |
| `DimCustomer` | `CustomerKey` | `CustomerKey` | Active |
| `DimProduct` | `ProductKey` | `ProductKey` | Active |
| `DimStore` | `StoreKey` | `StoreKey` | Active |
| `DimEmployee` | `EmployeeKey` | `EmployeeKey` | Active |
| `DimOrderStatus` | `OrderStatusKey` | `OrderStatusKey` | Active |

### 6.2 FactPayments

Connect `DimDate`, `DimCustomer`, `DimStore`, `DimPaymentMethod`, `DimPaymentStatus`, and `DimOrderStatus` to their matching keys. Use `PaymentDateKey` as the active date relationship.

### 6.3 FactReturns

Connect the customer, product, store, employee, return-reason, return-status, and order-status dimensions. Use `RequestDateKey` as the active date relationship. Keep `ApprovedDateKey`, `ReceivedDateKey`, and `ClosedDateKey` inactive.

### 6.4 FactRefunds

Connect date, customer, store, payment-method, payment-status, and order-status dimensions. Use `RefundDateKey` as the active date relationship.

### 6.5 FactInventoryMovement

Connect date, product, store, employee, and inventory-movement-type dimensions. Use `MovementDateKey` as the active date relationship.

### 6.6 FactInventorySnapshot

Connect `DimDate`, `DimProduct`, and `DimStore`. Use `SnapshotDateKey` as the active date relationship.

Avoid many-to-many and bidirectional relationships unless a documented business requirement specifically requires one.

---

## 7. Configure the date table

1. Select `DimDate` in Model view.
2. Choose **Table tools > Mark as date table**.
3. Select the `Date` column.
4. Select `MonthYearLabel`.
5. Choose **Column tools > Sort by column > YearMonthNumber**.
6. Sort `DayName` by `DayOfWeekNumber`.
7. Sort financial month labels by `FinancialMonthNumber` where applicable.

Do not use Power BI's automatic date/time tables. Disable the feature under:

```text
File > Options and settings > Options > Current File > Data Load > Auto date/time
```

---

## 8. Model hygiene

Hide technical fields that report consumers should not use directly:

- Surrogate keys
- Source IDs
- Fact identity keys
- Load timestamps
- Additive helper columns such as `LineCount`, `OrderCount`, `AttemptCount`, and `SnapshotRowCount`
- Inactive date foreign keys after relationships are configured

Keep the helper columns available to DAX measures but hidden in Report view.

Create a dedicated measures table:

1. Select **Home > Enter data**.
2. Name the table `_Measures`.
3. Add one placeholder column and one placeholder row.
4. Create measures in `_Measures`.
5. Hide the placeholder column.

Recommended display folders:

```text
01 Executive KPIs
02 Sales
03 Customers
04 Products
05 Stores & Employees
06 Inventory
07 Returns
08 Payments
09 Time Intelligence
10 Data Quality
```

---

## 9. Final dashboard page mapping (as built)

| Page | Final page title | Page-specific slicers |
|---|---|---|
| 01 | Executive Overview | Financial Year · Store · Category Name · Customer Segment |
| 02 | Sales Performance | Financial Year · Store · Category Name · Customer Segment |
| 03 | Customer Analysis | Financial Year · Store · Customer Segment · State |
| 04 | Product Analysis | Financial Year · Store · Category Name · Brand Name |
| 05 | Store Performance | Financial Year · Store · Store Tier · State |
| 06 | Inventory Analysis | Brand Name · Store · Category Name · Inventory Status |
| 07 | Returns Analysis | Financial Year · Store · Return Reason · Category Name |
| 08 | Payment Analysis | Financial Year · Store · Payment Method · Payment Status |

The model uses **12 dimensions, 6 facts**, and eight `analytics.pbi_*` views for SQL-side reconciliation. **Page 06** has no Financial Year slicer because the inventory snapshot is date-specific. **Page 07** has an FY2026–27 page-level filter in the reported PBIX design; verify its data and date context before accepting results. **Page 08** uses unsynchronized payment-specific slicers. A supplier analysis exists in SQL script 34, **not** as a ninth Power BI page.

### Actual report shell

- `powerbi/theme/background.png`: 1280 × 720 branded background with **top horizontal navigation**.
- Five KPI containers and four large analysis containers are visible in the supplied background. Their contents depend on each PBIX page and require separate verification.
- Navigation is across the top, not in a left rail. The header/navigation may be baked into the image; test whether Power BI buttons overlay the correct hit areas.
- The JSON theme provides a separate default color/font configuration. It does **not** reproduce the background image automatically.

## 10. Import mode versus DirectQuery

Use **Import mode** for this portfolio project because it provides:

- Faster report interaction
- Better DAX performance
- Full time-intelligence capability
- Lower dependency on the local SQL Server process during development
- A stronger demonstration of semantic modeling

DirectQuery is not recommended for the first portfolio version. It can be demonstrated later as an advanced deployment alternative.

---

## 11. Validate the Power BI import

After loading, create temporary card visuals and compare them with SQL:

```sql
SELECT *
FROM analytics.pbi_ExecutiveSummary;
```

At minimum, compare:

- Total orders
- Delivered orders
- Recognized revenue
- Net revenue
- Recognized gross profit
- Payment attempts
- Accepted return units
- Quantity on hand
- Stock cost value

Also compare row counts:

```sql
SELECT 'FactSales' AS ObjectName, COUNT_BIG(*) AS RowCount FROM analytics.FactSales
UNION ALL
SELECT 'FactPayments', COUNT_BIG(*) FROM analytics.FactPayments
UNION ALL
SELECT 'FactReturns', COUNT_BIG(*) FROM analytics.FactReturns
UNION ALL
SELECT 'FactRefunds', COUNT_BIG(*) FROM analytics.FactRefunds
UNION ALL
SELECT 'FactInventoryMovement', COUNT_BIG(*) FROM analytics.FactInventoryMovement
UNION ALL
SELECT 'FactInventorySnapshot', COUNT_BIG(*) FROM analytics.FactInventorySnapshot;
```

Do not begin visual formatting until the imported totals reconcile.

---

## 12. Refresh strategy

### Power BI Desktop

Use **Home > Refresh** after rebuilding facts or reporting views in SQL Server.

Recommended development order:

1. Run the required SQL build or refresh scripts.
2. Run scripts 26, 36, 39, and 40.
3. Confirm that all acceptance gates pass.
4. Refresh Power BI Desktop.
5. Recheck executive control totals.

### Power BI Service

`AKKI\SQLEXPRESS` is a local SQL Server instance. Scheduled refresh in Power BI Service requires an **On-premises data gateway** installed on a machine that:

- Can reach the SQL Server instance
- Remains powered on during refresh
- Uses valid Windows or SQL Server credentials
- Has the gateway service running

For a GitHub portfolio, publish dashboard screenshots and documentation. Do not publish database credentials, gateway recovery keys, machine usernames, or connection strings containing passwords.

---

## 13. Troubleshooting

### Server not found

1. Confirm `SQL Server (SQLEXPRESS)` is running.
2. Verify the instance with `SELECT @@SERVERNAME;`.
3. Try `localhost\SQLEXPRESS` or `.\SQLEXPRESS` on the same machine.
4. Confirm the SQL Server Browser service if named-instance discovery is required.

### Windows authentication fails

Open Power BI Desktop under the same Windows account that can connect through SSMS. In Power BI, clear old permissions under:

```text
File > Options and settings > Data source settings
```

Then reconnect.

### Views do not appear

1. Refresh the Navigator.
2. Confirm script 38 executed successfully.
3. Run:

```sql
SELECT SCHEMA_NAME(schema_id) AS SchemaName, name AS ViewName
FROM sys.views
WHERE SCHEMA_NAME(schema_id) = 'analytics'
  AND name LIKE 'pbi[_]%'
ORDER BY name;
```

### Numbers are duplicated

Check for:

- Many-to-many relationships
- Bidirectional filtering
- Dimension-to-dimension relationships
- A fact table related through another fact table
- Measures using raw columns without aggregation

The approved model uses single-direction, one-to-many relationships from dimensions to facts.

### Month names sort alphabetically

Set `MonthYearLabel` to sort by `YearMonthNumber`.

### Refresh is slow

1. Confirm Import mode.
2. Load only required columns.
3. Review script 37 benchmark output.
4. Avoid Power Query transformations that prevent query folding.
5. Keep database joins and approved calculations in SQL.

---

## 14. Connection completion checklist

- [ ] Script 40 reports portfolio-release readiness
- [ ] Power BI connects to `AKKI\SQLEXPRESS`
- [ ] Database selected is `RetailIntelligenceDB`
- [ ] Import mode selected
- [ ] Twelve dimensions loaded
- [ ] Six facts loaded
- [ ] Eight reporting views available for reconciliation
- [ ] `DimDate` marked as the date table
- [ ] `MonthYearLabel` sorted by `YearMonthNumber`
- [ ] One-to-many, single-direction relationships configured
- [ ] Inactive role-playing date relationships configured
- [ ] Technical keys and helper columns hidden
- [ ] `_Measures` table created
- [ ] Power BI KPI totals reconcile with `pbi_ExecutiveSummary`
- [ ] PBIX saved with a portfolio-ready filename

Recommended PBIX filename:

```text
Retail_Sales_Inventory_Intelligence_Dashboard.pbix
```

---

## 15. Interview explanation

> I developed the project in SQL Server using a normalized operational layer and a validated analytics star schema. I connected Power BI in Import mode to twelve dimensions and six fact tables, configured one-to-many single-direction relationships, and used role-playing date relationships for lifecycle analysis. I also created eight SQL reporting views and multiple validation gates to reconcile Power BI KPIs with source facts before building the dashboard.

This explanation demonstrates SQL development, dimensional modeling, data quality, performance validation, Power BI modeling, and reporting governance—not only dashboard formatting.

---

## Next deliverable

The next project file should be:

```text
42_DAX_Measures.md
```

It will define the reusable KPI and time-intelligence measures for all eight Power BI pages.
