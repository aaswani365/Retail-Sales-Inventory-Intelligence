# Retail Sales & Inventory Intelligence Platform

## 12. Power BI Dashboard Requirements — As-Built Alignment

| Attribute | Value |
|---|---|
| Project | Retail Sales & Inventory Intelligence Platform |
| Version | 2.0 |
| Document | `12_Power_BI_Dashboard_Requirements.md` |
| Author | Akshay Aswani |
| Platform | Microsoft Power BI Desktop |
| Data source | Microsoft SQL Server — `RetailIntelligenceDB` |
| Database schema | `analytics` |
| Status | Updated requirements aligned to the implemented eight-page report; visual-level acceptance requires separate UAT |
| Updated | 2026-11-03 |
| Related documents | `11_KPI_Dictionary.md`, `13_SQL_Implementation_Plan.md`, `14_Test_Cases_and_UAT.md` |

---

## 1. Purpose and business context

Provide a governed, interactive view of retail performance spanning revenue, order fulfillment, customers, products, stores, inventory, returns, and payments. The solution combines a T-SQL-generated operational dataset with a dimensional analytics model and Power BI reporting. This document describes the **implemented page scope** rather than the superseded original page proposal. A feature mentioned here as a requirement is not automatically certified as passing user acceptance testing.

### Decision-making objectives

- Track realized sales, gross profit, net revenue, order volume and average order value.
- Compare performance by financial year, store, category, brand and customer segment.
- Identify customer concentration, repeat purchasing and geographic patterns.
- Investigate product contribution, store performance and inventory risk.
- Monitor return reasons, refunds, payment failures and success rates.
- Maintain consistent financial definitions and prevent duplicated totals across multiple fact tables.

## 2. Data architecture and semantic-model boundary

**Database:** one SQL Server database, `RetailIntelligenceDB`, with operational schemas `ref`, `core`, `sales`, `inventory`, audit schema `audit`, and dimensional/reporting schema `analytics`. Synthetic operational records are generated using T-SQL.

**Analytics model:** 12 dimension tables and six fact tables. The Power BI model has been described as importing 12 dimensions, six facts and eight `analytics.pbi_*` reporting views (26 tables in total), with 41 Power BI relationships. SQL Server foreign-key counts and Power BI relationships are different metrics and must not be conflated.

**Fact grains:**

| Fact | Grain |
|---|---|
| `FactSales` | Sales-order item |
| `FactPayments` | Payment attempt |
| `FactReturns` | Returned order item |
| `FactRefunds` | Refund event |
| `FactInventoryMovement` | Inventory movement |
| `FactInventorySnapshot` | Product-store snapshot date |

**Reporting views created by script 38:** `pbi_ExecutiveSummary`, `pbi_SalesTrend`, `pbi_StorePerformance`, `pbi_ProductPerformance`, `pbi_CustomerPerformance`, `pbi_InventoryPosition`, `pbi_ReturnsPerformance`, `pbi_PaymentPerformance`. These are reporting/control views and must not be joined to underlying facts in a way that multiplies records. SQL-side validation of these views is performed by script 39; it does not by itself validate Power BI DAX or visual interactions.

## 3. Implemented report page inventory

| Page | Actual page title | Primary business question | Scope |
|---|---|---|---|
| 01 | Executive Overview | How is the business performing overall? | Revenue, gross profit, margin, orders, AOV, headline performance and trends |
| 02 | Sales Performance | When and where do sales occur? | Monthly trends, sales mix, delivered orders, sales contribution |
| 03 | Customer Analysis | Which customers and segments drive value? | Customer activity, segmentation, location and purchasing patterns |
| 04 | Product Analysis | Which products and brands drive revenue and profit? | Category, brand and product contribution, profitability |
| 05 | Store Performance | Which stores and tiers perform best? | Store comparisons, geographical performance and efficiency |
| 06 | Inventory Analysis | Where are stock risks and opportunities? | Stock position, availability, reorder risk and inventory value |
| 07 | Returns Analysis | What is being returned and why? | Return volumes, reasons, accepted units and refund-related analysis |
| 08 | Payment Analysis | How reliable are payment attempts? | Payment method, status, successes, failures and retry outcomes |

**Scope correction:** Supplier Analysis and standalone Employee Performance are available as SQL analytical investigations (scripts 34 and 32), but are **not** separate pages in the implemented eight-page Power BI report. The original combined Returns & Payments page has been separated into pages 07 and 08.

## 4. Page-level filter specification

The following filter assignments reflect the finalized report design recorded during development. Verify the final PBIX interactions during UAT.

| Page | Slicers | Special handling |
|---|---|---|
| 01 Executive Overview | Financial Year, Store, Category Name, Customer Segment | Shared business context |
| 02 Sales Performance | Financial Year, Store, Category Name, Customer Segment | Financial-year trend analysis |
| 03 Customer Analysis | Financial Year, Store, Customer Segment, State | Customer geography |
| 04 Product Analysis | Financial Year, Store, Category Name, Brand Name | Brand/category analysis |
| 05 Store Performance | Financial Year, Store, Store Tier, State | State sourced from `DimStore.StateName` |
| 06 Inventory Analysis | Brand Name, Store, Category Name, Inventory Status | No financial-year slicer; snapshot-based inventory |
| 07 Returns Analysis | Financial Year, Store, Return Reason, Category Name | Historical return data constrained to available period; development used FY2026–27 fixed page filter — confirm against final model and actual return dates |
| 08 Payment Analysis | Financial Year, Store, Payment Method, Payment Status | Payment slicers are intentionally unsynchronized with other pages |

Avoid showing governed Unknown dimension members as ordinary business categories. Where appropriate, apply `IsUnknown = 0` or an equivalent documented filter; turning off “Show items with no data” alone does not guarantee removal of every Unknown member.

## 5. KPI governance and time attribution

| Measure family | Rule / interpretation |
|---|---|
| Order demand, cancellations | Attribute to **order date** |
| Delivered sales, recognized revenue, AOV | Attribute to **delivery date** when measuring realized sales |
| Payment attempts and status | Attribute to **payment date** |
| Return requests | Attribute to **return request date** |
| Refund cash activity | Attribute to **refund event date** |
| Inventory position | Attribute to **snapshot date**; do not interpret one snapshot as historical daily stock |

Key calculation definitions must match `11_KPI_Dictionary.md` and the final DAX measures. Distinguish recognized revenue from net revenue after completed refunds, and distinguish pretax revenue from invoice amounts including tax. Avoid calculating a combined ratio from a many-to-many join of fact tables; aggregate facts independently at the correct grain.

**Important date warning:** `pbi_SalesTrend` combines sales-month revenue with refund-event-month outflows to derive calendar-activity net revenue. That is **not** the same as delivery-cohort net revenue. Label the time basis when comparing those measures.

The SQL generation configuration covers 2023-07-01 through 2026-06-30. Calendar dimension coverage, individual fact transaction dates, and inventory snapshot dates must be reported separately rather than assumed identical. Do not infer a full June month of transactions solely from the configured end date.

## 6. Report experience and presentation requirements

- Report canvas: **1280 × 720** pixels, with consistent header, page title, navigation, KPI region and analytical charts.
- Navigation must allow movement across all eight report pages without relying on edit mode.
- Page filters should not inadvertently affect unrelated measures or produce misleading blank comparisons.
- Use readable chart labels, consistent currency/percentage formatting, meaningful titles and accessible contrast.
- Tooltip content must be grounded in the visual's actual grain and filter context.
- Provide synthetic-data disclosure and identify that the report is a portfolio demonstration, not a live production system.
- If screenshots are published, capture the final filter state and verify that displayed KPI cards reconcile to the selected context.

**Not certified without separate PBIX evidence:** drillthrough pages, field parameters, custom report-page tooltips, mobile layouts, dynamic title behavior, and accessibility compliance. These may be enhancements or original intentions; do not claim implementation from the planning document alone.

## 7. Validation and user acceptance

| Control | Evidence / acceptance condition | Status handling |
|---|---|---|
| SQL analytics model | Script 26, audited model tests | Record actual run results |
| SQL data quality | Script 36, audited quality tests | Record actual run results |
| Power BI reporting views | Scripts 38–39, object/grain/reconciliation checks | SQL-side validation only |
| Deployment readiness | Script 40, audited health checks | Database readiness only |
| KPI reconciliation | Power BI filtered DAX totals compared with SQL at matching date role/grain | Requires manual evidence |
| Slicer behavior | Check all page-specific slicers, synchronization and reset behavior | Requires PBIX/UAT evidence |
| Navigation | Check each page button and destination | Requires PBIX/UAT evidence |
| Visual correctness | Check axis, sorting, conditional formatting, totals and tooltips | Requires PBIX/UAT evidence |
| Snapshot interpretation | Verify inventory dates and historical limitations | Requires manual evidence |
| Documentation alignment | Match screenshots, README, page inventory and model definitions | Requires release review |

Do not mark an unexecuted manual test as Passed. Preserve screenshots and results in `deployment/validation_evidence/` and update `docs/testing/14_Test_Cases_and_UAT.md` only for verified checks.

## 8. Out-of-scope and future enhancements

The baseline eight-page report does not require real-time streaming, enterprise row-level security, automated Power BI Service deployment, a standalone supplier dashboard, a standalone employee dashboard, predictive ML forecasts, or a production-grade orchestration service. SQL analysis of suppliers, employees, cohorts, RFM and market-basket behavior can be highlighted in the repository as additional analytical work without presenting them as separate Power BI pages.

## 9. Release checklist

- [ ] Final PBIX page names match the eight-page inventory above.
- [ ] Final slicers and interactions match the approved page design.
- [ ] KPI definitions and date roles are reconciled against SQL.
- [ ] Inventory and returns date limitations are clearly disclosed.
- [ ] Page screenshots represent the final report state.
- [ ] UAT results include evidence for every marked Pass.
- [ ] README links and documentation reflect the implemented design.

---

*Document basis: previously supplied Power BI requirements, the final SQL script sequence and development decisions. This is an as-built requirements alignment, not proof of live PBIX acceptance.*
