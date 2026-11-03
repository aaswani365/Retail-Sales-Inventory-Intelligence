# Power BI Build Checklist

## Retail Sales & Inventory Intelligence Platform

This is the **implementation-aligned acceptance checklist**. Existing setup and model checks are retained as reference tasks, not assertions of completion. The final report uses a top navigation bar and page-specific slicers. Do not rebuild a completed PBIX just to follow obsolete draft steps.

**Target file:** `Retail_Sales_Inventory_Intelligence_Dashboard.pbix`

---

## Phase 1 — SQL readiness

- [ ] Run `38_PowerBI_Reporting_Views.sql`
- [ ] Confirm all eight `analytics.pbi_*` views pass validation
- [ ] Run `39_PowerBI_Model_Validation.sql`
- [ ] Confirm the Power BI semantic layer is accepted
- [ ] Run `40_Deployment_Health_Check.sql`
- [ ] Confirm status is `READY FOR POWER BI AND PORTFOLIO RELEASE`
- [ ] Save final SQL validation screenshots
- [ ] Confirm SQL Server instance is `AKKI\SQLEXPRESS`
- [ ] Confirm database is `RetailIntelligenceDB`

**Phase completion evidence:** Successful script 40 result grid and message.

---

## Phase 2 — Create and connect the PBIX

- [ ] Open the latest Power BI Desktop
- [ ] Create a blank report
- [ ] Save it as `Retail_Sales_Inventory_Intelligence_Dashboard.pbix`
- [ ] Select **Get data > SQL Server**
- [ ] Enter server `AKKI\SQLEXPRESS`
- [ ] Enter database `RetailIntelligenceDB`
- [ ] Select **Import** mode
- [ ] Select Windows authentication
- [ ] Confirm the connection succeeds
- [ ] Choose **Transform Data** before loading

**Stop condition:** Do not continue if Power BI cannot connect or the `analytics` schema is unavailable.

---

## Phase 3 — Import model objects

### Dimensions

- [ ] `DimDate`
- [ ] `DimCustomer`
- [ ] `DimProduct`
- [ ] `DimStore`
- [ ] `DimEmployee`
- [ ] `DimSupplier`
- [ ] `DimPaymentMethod`
- [ ] `DimOrderStatus`
- [ ] `DimPaymentStatus`
- [ ] `DimReturnReason`
- [ ] `DimReturnStatus`
- [ ] `DimInventoryMovementType`

### Facts

- [ ] `FactSales`
- [ ] `FactPayments`
- [ ] `FactReturns`
- [ ] `FactRefunds`
- [ ] `FactInventoryMovement`
- [ ] `FactInventorySnapshot`

### SQL control views

- [ ] `pbi_ExecutiveSummary`
- [ ] `pbi_SalesTrend`
- [ ] `pbi_StorePerformance`
- [ ] `pbi_ProductPerformance`
- [ ] `pbi_CustomerPerformance`
- [ ] `pbi_InventoryPosition`
- [ ] `pbi_ReturnsPerformance`
- [ ] `pbi_PaymentPerformance`

### Power Query checks

- [ ] Surrogate keys use Whole Number
- [ ] Monetary columns use Fixed Decimal Number
- [ ] Counts and quantities use Whole Number
- [ ] Rates use Decimal Number
- [ ] Calendar fields use Date
- [ ] `YearMonthNumber` uses Whole Number
- [ ] Query names retain SQL object names
- [ ] Queries are grouped into Dimensions, Facts and SQL Control Views
- [ ] No Power Query errors remain
- [ ] Apply changes and load the model

---

## Phase 4 — Configure the date table

- [ ] Mark `DimDate` as the date table
- [ ] Select `DimDate[Date]` as the date column
- [ ] Sort `MonthYearLabel` by `YearMonthNumber`
- [ ] Sort `DayName` by `DayOfWeekNumber`
- [ ] Sort financial month fields by `FinancialMonthNumber`
- [ ] Disable automatic date/time for the current file
- [ ] Confirm no hidden automatic date tables remain

---

## Phase 5 — Build relationships

Use one-to-many cardinality and single-direction filtering from dimensions to facts.

### FactSales

- [ ] `DimDate[DateKey]` → `FactSales[OrderDateKey]` active
- [ ] `DimDate[DateKey]` → `FactSales[ConfirmedDateKey]` inactive
- [ ] `DimDate[DateKey]` → `FactSales[ShippedDateKey]` inactive
- [ ] `DimDate[DateKey]` → `FactSales[DeliveredDateKey]` inactive
- [ ] Customer relationship active
- [ ] Product relationship active
- [ ] Store relationship active
- [ ] Employee relationship active
- [ ] Order-status relationship active

### FactPayments

- [ ] Payment-date relationship active
- [ ] Customer relationship active
- [ ] Store relationship active
- [ ] Payment-method relationship active
- [ ] Payment-status relationship active
- [ ] Order-status relationship active

### FactReturns

- [ ] Request-date relationship active
- [ ] Approved-date relationship inactive
- [ ] Received-date relationship inactive
- [ ] Closed-date relationship inactive
- [ ] Customer relationship active
- [ ] Product relationship active
- [ ] Store relationship active
- [ ] Employee relationship active
- [ ] Return-reason relationship active
- [ ] Return-status relationship active
- [ ] Order-status relationship active

### FactRefunds

- [ ] Refund-date relationship active
- [ ] Customer relationship active
- [ ] Store relationship active
- [ ] Payment-method relationship active
- [ ] Payment-status relationship active
- [ ] Order-status relationship active

### Inventory facts

- [ ] Movement date, product, store, employee and movement-type relationships active
- [ ] Snapshot date, product and store relationships active
- [ ] No fact-to-fact relationship exists
- [ ] No accidental many-to-many relationship exists
- [ ] No unnecessary bidirectional relationship exists
- [ ] Model view is arranged as a readable star schema

---

## Phase 6 — Model hygiene

- [ ] Create `_Measures` table
- [ ] Hide the placeholder column
- [ ] Hide surrogate keys from Report view
- [ ] Hide source IDs and fact identity keys
- [ ] Hide load timestamps
- [ ] Hide additive helper columns from users
- [ ] Hide inactive date foreign keys
- [ ] Set meaningful default summarization
- [ ] Set currency formats
- [ ] Set percentage formats
- [ ] Add business descriptions to important measures
- [ ] Create measure display folders
- [ ] Hide SQL control views after reconciliation where appropriate

---

## Phase 7 — Import the visual theme

- [ ] Select **View > Themes > Browse for themes**
- [ ] Import `44_PowerBI_Theme.json`
- [ ] Confirm the theme imports without an error
- [ ] Confirm the actual branded background.png is applied and aligned
- [ ] Confirm visual backgrounds do not unintentionally obscure blue-tinted card artwork
- [ ] Confirm the primary accent is blue
- [ ] Confirm success, warning and failure colours are consistent
- [ ] Confirm Segoe UI typography is applied

---

## Phase 8 — Create DAX measures

Follow `42_DAX_Measures.md` and create measures by dependency order.

### Base measures

- [ ] Orders and order lines
- [ ] Units
- [ ] Booked and gross values
- [ ] Recognized revenue
- [ ] Recognized COGS
- [ ] Recognized gross profit
- [ ] Gross margin rate

### Operational measures

- [ ] Delivery and cancellation measures
- [ ] Customer measures
- [ ] Product rankings
- [ ] Store and employee rankings
- [ ] Inventory measures
- [ ] Return and refund measures
- [ ] Payment measures

### Time intelligence

- [ ] Previous month
- [ ] Month-over-month growth
- [ ] Previous year
- [ ] Year-over-year growth
- [ ] Calendar YTD
- [ ] Financial YTD
- [ ] Rolling 3-month revenue
- [ ] Rolling 12-month revenue
- [ ] Role-playing date measures

### QA measures

- [ ] SQL Executive Revenue
- [ ] Revenue Reconciliation Difference
- [ ] SQL Executive Orders
- [ ] Order Reconciliation Difference
- [ ] SQL Inventory Cost Value
- [ ] Inventory Reconciliation Difference
- [ ] Model Validation Status

---

## Phase 9 — Reconcile before visual design

- [ ] Add temporary cards for core DAX measures
- [ ] Compare Total Orders with `pbi_ExecutiveSummary`
- [ ] Compare Recognized Revenue
- [ ] Compare Recognized Gross Profit
- [ ] Compare Completed Refund Value
- [ ] Compare Net Revenue
- [ ] Compare Payment Attempts
- [ ] Compare Accepted Return Units
- [ ] Compare Quantity on Hand
- [ ] Compare Inventory Cost Value
- [ ] Confirm revenue difference is zero
- [ ] Confirm order difference is zero
- [ ] Confirm inventory difference is zero
- [ ] Confirm Model Validation Status is `PASSED`

**Stop condition:** Do not build final visuals while any reconciliation difference is non-zero.

---

## Phase 10 — Verify the actual shared report shell

- [ ] All eight main pages use a **1280×720** canvas.
- [ ] `powerbi/theme/background.png` is applied at the correct scale.
- [ ] Dark-blue header, horizontal navigation, five top slicer containers, five KPI containers, four analysis containers, and footer align correctly.
- [ ] No left-side navigation rail is introduced from the superseded blueprint.
- [ ] Each navigation label opens its intended page.
- [ ] Buttons have appropriate hover/selected states where implemented.
- [ ] Visual backgrounds do not hide the artwork unintentionally.

## Phase 11 — Verify eight report pages

### 01 — Executive Overview

- [ ] Page title and purpose are correct.
- [ ] Four slicers match: **Financial Year, Store, Category Name, Customer Segment**.
- [ ] KPI labels and calculation logic are checked against the actual DAX.
- [ ] Charts show meaningful business dimensions and correct filters.
- [ ] Navigation, interactions, and reset behavior (if implemented) are tested.
- [ ] SQL-to-Power BI figures reconcile under matching filters and date roles.
- [ ] Approved final screenshot is captured.

### 02 — Sales Performance

- [ ] Page title and purpose are correct.
- [ ] Four slicers match: **Financial Year, Store, Category Name, Customer Segment**.
- [ ] KPI labels and calculation logic are checked against the actual DAX.
- [ ] Charts show meaningful business dimensions and correct filters.
- [ ] Navigation, interactions, and reset behavior (if implemented) are tested.
- [ ] SQL-to-Power BI figures reconcile under matching filters and date roles.
- [ ] Approved final screenshot is captured.

### 03 — Customer Analysis

- [ ] Page title and purpose are correct.
- [ ] Four slicers match: **Financial Year, Store, Customer Segment, State**.
- [ ] KPI labels and calculation logic are checked against the actual DAX.
- [ ] Charts show meaningful business dimensions and correct filters.
- [ ] Navigation, interactions, and reset behavior (if implemented) are tested.
- [ ] SQL-to-Power BI figures reconcile under matching filters and date roles.
- [ ] Approved final screenshot is captured.

### 04 — Product Analysis

- [ ] Page title and purpose are correct.
- [ ] Four slicers match: **Financial Year, Store, Category Name, Brand Name**.
- [ ] KPI labels and calculation logic are checked against the actual DAX.
- [ ] Charts show meaningful business dimensions and correct filters.
- [ ] Navigation, interactions, and reset behavior (if implemented) are tested.
- [ ] SQL-to-Power BI figures reconcile under matching filters and date roles.
- [ ] Approved final screenshot is captured.

### 05 — Store Performance

- [ ] Page title and purpose are correct.
- [ ] Four slicers match: **Financial Year, Store, Store Tier, State**.
- [ ] KPI labels and calculation logic are checked against the actual DAX.
- [ ] Charts show meaningful business dimensions and correct filters.
- [ ] Navigation, interactions, and reset behavior (if implemented) are tested.
- [ ] SQL-to-Power BI figures reconcile under matching filters and date roles.
- [ ] Approved final screenshot is captured.

### 06 — Inventory Analysis

- [ ] Page title and purpose are correct.
- [ ] Four slicers match: **Brand Name, Store, Category Name, Inventory Status**.
- [ ] KPI labels and calculation logic are checked against the actual DAX.
- [ ] Charts show meaningful business dimensions and correct filters.
- [ ] Navigation, interactions, and reset behavior (if implemented) are tested.
- [ ] SQL-to-Power BI figures reconcile under matching filters and date roles.
- [ ] Approved final screenshot is captured.

### 07 — Returns Analysis

- [ ] Page title and purpose are correct.
- [ ] Four slicers match: **Financial Year, Store, Return Reason, Category Name**.
- [ ] KPI labels and calculation logic are checked against the actual DAX.
- [ ] Charts show meaningful business dimensions and correct filters.
- [ ] Navigation, interactions, and reset behavior (if implemented) are tested.
- [ ] SQL-to-Power BI figures reconcile under matching filters and date roles.
- [ ] Approved final screenshot is captured.

### 08 — Payment Analysis

- [ ] Page title and purpose are correct.
- [ ] Four slicers match: **Financial Year, Store, Payment Method, Payment Status**.
- [ ] KPI labels and calculation logic are checked against the actual DAX.
- [ ] Charts show meaningful business dimensions and correct filters.
- [ ] Navigation, interactions, and reset behavior (if implemented) are tested.
- [ ] SQL-to-Power BI figures reconcile under matching filters and date roles.
- [ ] Approved final screenshot is captured.

### Special page restrictions

- [ ] **Inventory** has no Financial Year slicer and clearly reflects the snapshot date.
- [ ] **Returns** has the intended FY2026–27 page filter, with actual date coverage checked.
- [ ] **Payments** slicers are intentionally unsynchronized with the other pages.
- [ ] There is **no Supplier Analysis dashboard page**; SQL supplier analysis is documented separately.

## Phase 12 — Validate measures and model

- [ ] Compare the actual PBIX measures to `42_DAX_Measures.md` without overwriting validated formulas.
- [ ] Confirm `[Delivered Orders]` counts **distinct delivered orders**, not sales lines.
- [ ] Confirm AOV denominator and revenue numerator use intended business definitions.
- [ ] Verify inactive/active date relationships and `USERELATIONSHIP` measures.
- [ ] Check revenue and refund date-role differences against `pbi_SalesTrend`.
- [ ] Confirm snapshot-based inventory measures do not imply multi-year snapshots.
- [ ] Verify unknown members and visual filter behavior.

## Phase 13 — Check theme, visuals, accessibility

- [ ] `44_PowerBI_Theme.json` imports successfully and is valid JSON.
- [ ] `background.png` renders at 1280×720 without distortion.
- [ ] Chart backgrounds and borders suit the actual blue artwork, not only the light-theme defaults.
- [ ] Visual titles, numbers, units, tooltips, and legends are readable.
- [ ] Keyboard navigation, contrast, and accessible labels are reviewed.
- [ ] All report buttons and cross-filter interactions are tested manually.

## Phase 14 — Validate evidence and release

- [ ] SQL analytics-model validation evidence is retained.
- [ ] SQL data-quality 19/19 screenshot is retained.
- [ ] SQL Power BI model validation 15/15 screenshot is retained.
- [ ] SQL deployment health 17/17 screenshot is retained.
- [ ] Performance benchmark screenshot and environment limitations are retained.
- [ ] Power BI Desktop UAT cases are individually recorded as Passed/Failed/Not Verified in `docs/testing/14_Test_Cases_and_UAT.md`.
- [ ] Eight dashboard screenshots exist under the README's exact paths.
- [ ] README links to all four Power BI documents, the PBIX, JSON theme, and background image.
- [ ] No credentials, connection secrets, or sensitive machine data are published.

## Acceptance rule

**Only mark a task complete when supported by actual PBIX inspection, a reproducible SQL result, or retained evidence.** The uploaded background image proves the layout asset exists; it does not prove DAX values, page interactions, or navigation are correct. Do not treat the original unchecked draft checklist as a record of failures or completed work.
