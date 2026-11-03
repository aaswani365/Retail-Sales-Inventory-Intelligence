# Test Cases and User Acceptance Testing

## Retail Sales & Inventory Intelligence Platform

**Solution:** SQL Server analytical platform and eight-page Power BI dashboard  
**Database:** `RetailIntelligenceDB`  
**Power BI file:** `Retail_Sales_Inventory_Intelligence_Dashboard.pbix` (verify exact local filename before publishing)  
**Test owner:** Akshay Aswani  
**Test status values:** Not Run, Passed, Failed, Blocked  
**Evidence policy:** `Passed` means supported by the attached SQL execution screenshot for the specified check; SQL evidence does not certify Power BI Desktop functionality.  
**Review date:** 2026-11-03

---

## 1. Purpose

This document provides evidence that the solution is:

- Technically deployable
- Data-quality controlled
- Financially and operationally reconciled
- Correctly modeled in Power BI
- Functionally interactive
- Performant and accessible
- Suitable for portfolio demonstration

Testing is divided into SQL acceptance, data reconciliation, semantic-model testing, DAX validation, dashboard functionality, user acceptance, performance, accessibility and release readiness.

---

## 1A. Evidence and interpretation

The following evidence screenshots were supplied from the local `RetailIntelligenceDB` environment. They are historical execution evidence (primarily 23 September 2026), not proof of the current live state or of Power BI Desktop behavior.

| Evidence ID | Screenshot in `deployment/validation_evidence/` | What it establishes |
|---|---|---|
| EV-01 | `01_Database_Creation_Passed.png` | Database creation evidence |
| EV-02 | `02_Schema_Validation_Passed.png` | Schema creation/validation evidence |
| EV-03 | `03_Operational_Tables_Passed.png` | Operational table inventory evidence |
| EV-04 | `04_Constraints_Passed.png` | Constraint validation evidence |
| EV-05 | `05_Indexes_Passed.png` | Index validation evidence |
| EV-06 | `06_Analytics_Model_Passed.png` | Analytics-model validation evidence |
| EV-08 | `08_Data_Quality_19_of_19_Passed.png` | Script 36: 19/19 checks passed, zero failed |
| EV-09 | `09_Performance_Benchmarking_Passed.png` | Script 37: five workloads × three iterations, consistent row counts/checksums |
| EV-10 | `10_PowerBI_Reporting_Views_Passed.png` | Reporting-view creation/inspection evidence |
| EV-11 | `11_PowerBI_Model_15_of_15_Passed.png` | Script 39: 15/15 SQL-side reporting-model checks passed |
| EV-12 | `12_Deployment_Health_17_of_17_Passed.png` | Script 40: 17/17 deployment checks passed, zero failed |

**Evidence limitation:** SQL script 39 validates SQL reporting views and reconciliations; it does **not** inspect the `.pbix` relationships, DAX, slicers, visuals, refresh, or accessibility. Benchmark checksums are consistency indicators, not mathematical proof of result equality. The script 40 screenshot reports `READY FOR POWER BI AND PORTFOLIO RELEASE` for the **SQL deployment gate**, not full dashboard UAT approval.

## 2. Entry criteria

Testing may begin when:

- [x] Historical SQL execution/validation screenshots are available; complete 01–40 sequential-run log not independently verified
- [x] Script 40 historical screenshot reports SQL deployment readiness (17/17)
- [ ] Power BI Desktop connects to `AKKI\SQLEXPRESS`
- [x] SQL deployment evidence shows twelve dimensions and six facts populated
- [x] SQL-side evidence shows eight `pbi_*` reporting views available
- [ ] Star-schema relationships are configured
- [ ] Core DAX measures are created
- [x] Eight report-page screenshots supplied; interactive functionality still requires testing

---

## 3. Severity definitions

| Severity | Definition | Release impact |
|---|---|---|
| Critical | Incorrect totals, broken refresh, missing data, invalid relationship or inaccessible report | Blocks release |
| High | Major page, slicer, navigation or calculation does not work | Blocks release unless formally accepted |
| Medium | Limited functional or formatting issue with a workaround | Fix before portfolio release where practical |
| Low | Cosmetic issue with no analytical impact | May be deferred |

---

## 4. SQL deployment tests

| ID | Test | Procedure | Expected result | Severity | Status |
|---|---|---|---|---|---|
| SQL-001 | Database context | Run `SELECT DB_NAME()` | `RetailIntelligenceDB` | Critical | Passed |
| SQL-002 | Database availability | Review script 40 database-state control | Online and multi-user | Critical | Passed |
| SQL-003 | Compatibility level | Review script 40 | Compatibility level 160 or higher | High | Passed |
| SQL-004 | Required schemas | Review script 40 | Six approved schemas exist | Critical | Passed |
| SQL-005 | Operational tables | Review script 40 | All 25 tables exist | Critical | Passed |
| SQL-006 | Analytics tables | Review script 40 | Twelve dimensions and six facts exist | Critical | Passed |
| SQL-007 | Power BI views | Review script 38/40 | Eight `pbi_*` views exist | Critical | Passed |
| SQL-008 | Procedures and functions | Review script 40 | Seven procedures and three functions exist | Critical | Passed |
| SQL-009 | Foreign-key trust | Review script 40 | No disabled or untrusted foreign keys | Critical | Passed |
| SQL-010 | Check-constraint trust | Review script 40 | No disabled or untrusted check constraints | Critical | Passed |
| SQL-011 | Index health | Review script 40 | No disabled or hypothetical project indexes | Critical | Passed |
| SQL-012 | Heap control | Review script 40 | No unintended heap tables | High | Passed |
| SQL-013 | Analytics validation | Review audit history | Script 26 has a passed run | Critical | Passed |
| SQL-014 | Data-quality validation | Review audit history | Script 36 has a passed run | Critical | Passed |
| SQL-015 | Power BI validation | Review audit history | Script 39 has a passed run | Critical | Passed |
| SQL-016 | Deployment validation | Run script 40 | All 17 checks pass | Critical | Passed |
| SQL-017 | Rerun safety | Rerun scripts 37–40 | No duplicate-object or duplicate-data error | High | Not Run |
| SQL-018 | Benchmark consistency | Review script 37 | All repeated checksums and row counts are consistent | High | Passed |

---

## 5. Source-to-fact reconciliation tests

| ID | Test | Source | Target | Expected result | Severity | Status |
|---|---|---|---|---|---|---|
| REC-001 | Sales row count | `sales.SalesOrderItem` | `analytics.FactSales` | Exact match | Critical | Passed |
| REC-002 | Payment row count | `sales.Payment` | `analytics.FactPayments` | Exact match | Critical | Passed |
| REC-003 | Return row count | `sales.ProductReturnItem` | `analytics.FactReturns` | Exact match | Critical | Passed |
| REC-004 | Refund row count | `sales.Refund` | `analytics.FactRefunds` | Exact match | Critical | Passed |
| REC-005 | Movement row count | `inventory.InventoryMovement` | `analytics.FactInventoryMovement` | Exact match | Critical | Passed |
| REC-006 | Snapshot row count | `inventory.InventoryBalance` | `analytics.FactInventorySnapshot` | Exact match | Critical | Passed |
| REC-007 | Sales value | Order-item net amount | Fact sales net amount | Exact match | Critical | Passed |
| REC-008 | Payment value | Payment amount | Fact payment amount | Exact match | Critical | Passed |
| REC-009 | Refund value | Refund amount | Fact refund amount | Exact match | Critical | Passed |
| REC-010 | Movement units | Signed operational movement | Fact signed quantity | Exact match | Critical | Passed |
| REC-011 | Order header totals | Order items | Sales-order header | Exact match | Critical | Passed |
| REC-012 | Inventory availability | On hand minus reserved | Available quantity | Exact match | Critical | Passed |

---

## 6. Data-quality business-rule tests

| ID | Test | Procedure | Expected result | Severity | Status |
|---|---|---|---|---|---|
| DQ-001 | Mandatory identifiers | Check customer code, SKU, store code and order number | No blank identifiers | Critical | Passed |
| DQ-002 | Natural-key uniqueness | Check codes and document numbers | No duplicates | Critical | Passed |
| DQ-003 | Fact-grain uniqueness | Check all six approved grains | No duplicates | Critical | Passed |
| DQ-004 | Order dates | Check lifecycle chronology | No invalid sequence | High | Passed |
| DQ-005 | Order-item calculations | Recalculate gross, discount, tax and net | Exact match | Critical | Passed |
| DQ-006 | Payment validity | Check amounts, attempts and dates | No exceptions | High | Passed |
| DQ-007 | Return quantities | Check accepted ≤ requested | No exceptions | Critical | Passed |
| DQ-008 | Refund eligibility | Compare completed refunds with eligibility | No over-refund | Critical | Passed |
| DQ-009 | Inventory balance | Check on hand, reserved and available | No invalid balance | Critical | Passed |
| DQ-010 | Movement direction | Check quantity and ±1 direction | No exceptions | Critical | Passed |
| DQ-011 | Unknown dimension use | Review key-zero usage | Only approved unknowns | High | Passed |
| DQ-012 | Fact-load synchronization | Review script 36 | Within approved 30-minute window | Medium | Passed |

---

## 7. Power BI connection and refresh tests

| ID | Test | Procedure | Expected result | Severity | Status |
|---|---|---|---|---|---|
| CON-001 | Desktop connection | Connect to `AKKI\SQLEXPRESS` | Connection succeeds | Critical | Not Run |
| CON-002 | Database selection | Select `RetailIntelligenceDB` | Correct database objects visible | Critical | Not Run |
| CON-003 | Authentication | Use Windows authentication | No credential error | Critical | Not Run |
| CON-004 | Import mode | Inspect storage mode | All core model tables use Import | High | Not Run |
| CON-005 | Initial load | Apply Power Query changes | Load finishes without error | Critical | Not Run |
| CON-006 | Manual refresh | Select Refresh | Refresh completes | Critical | Not Run |
| CON-007 | Post-refresh counts | Compare fact counts with SQL | Exact match | Critical | Not Run |
| CON-008 | Schema change resilience | Refresh without database change | No broken query | High | Not Run |
| CON-009 | Service refresh | Refresh through gateway if published | Refresh succeeds | High | Not Run |
| CON-010 | Credential protection | Review PBIX, screenshots and repository | No password or secret exposed | Critical | Not Run |

---

## 8. Semantic-model tests

| ID | Test | Procedure | Expected result | Severity | Status |
|---|---|---|---|---|---|
| MOD-001 | Date table | Inspect model | `DimDate` marked using `Date` | Critical | Not Run |
| MOD-002 | Month sorting | Sort MonthYearLabel | Chronological order | High | Not Run |
| MOD-003 | Dimension cardinality | Inspect key columns | Unique dimension-side keys | Critical | Not Run |
| MOD-004 | Fact relationships | Inspect model view | Approved 1:* relationships | Critical | Not Run |
| MOD-005 | Filter direction | Inspect relationships | Single direction from dimension to fact | Critical | Not Run |
| MOD-006 | Active sales date | Inspect relationship | Order date active | Critical | Not Run |
| MOD-007 | Inactive sales dates | Inspect relationships | Confirmed, shipped and delivered inactive | High | Not Run |
| MOD-008 | Return dates | Inspect relationships | Request active; others inactive | High | Not Run |
| MOD-009 | Fact isolation | Inspect model | No direct fact-to-fact relationship | Critical | Not Run |
| MOD-010 | Many-to-many control | Inspect model | No unintended many-to-many | Critical | Not Run |
| MOD-011 | Hidden technical fields | Inspect Report view | Keys and load fields hidden | Medium | Not Run |
| MOD-012 | Measure organization | Inspect `_Measures` | Measures use approved folders | Low | Not Run |
| MOD-013 | Auto date/time | Review options | Disabled | Medium | Not Run |
| MOD-014 | Model readability | Review Model view | Star schema is visually understandable | Low | Not Run |

---

## 9. DAX measure tests

| ID | Measure/test | Validation source | Expected result | Severity | Status |
|---|---|---|---|---|---|
| DAX-001 | Total Orders | `pbi_ExecutiveSummary` | Exact match | Critical | Not Run |
| DAX-002 | Delivered Orders | `pbi_ExecutiveSummary` | Exact match | Critical | Not Run |
| DAX-003 | Recognized Revenue | `pbi_ExecutiveSummary` | Difference < ₹0.01 | Critical | Not Run |
| DAX-004 | Recognized Gross Profit | `pbi_ExecutiveSummary` | Difference < ₹0.01 | Critical | Not Run |
| DAX-005 | Completed Refund Value | `pbi_ExecutiveSummary` | Difference < ₹0.01 | Critical | Not Run |
| DAX-006 | Net Revenue | SQL control view | Difference < ₹0.01 | Critical | Not Run |
| DAX-007 | Payment Attempts | SQL control view | Exact match | Critical | Not Run |
| DAX-008 | Accepted Return Units | SQL control view | Exact match | Critical | Not Run |
| DAX-009 | Quantity on Hand | SQL control view | Exact match | Critical | Not Run |
| DAX-010 | Inventory Cost Value | SQL control view | Difference < ₹0.01 | Critical | Not Run |
| DAX-011 | Gross Margin Rate | Manual division | Correct and safe for zero denominator | High | Not Run |
| DAX-012 | Payment Success Rate | Manual division | Correct and within 0–100% | High | Not Run |
| DAX-013 | Unit Return Rate | Manual division | Correct for selected context | High | Not Run |
| DAX-014 | Previous month | Prior-month filter | Correct prior period | High | Not Run |
| DAX-015 | Year-over-year growth | Same period prior year | Correct variance | High | Not Run |
| DAX-016 | Financial YTD | Indian FY starting April | Resets correctly in April | High | Not Run |
| DAX-017 | Delivery-date measure | Inactive relationship | Uses DeliveredDateKey | High | Not Run |
| DAX-018 | Customer recency | Model maximum date | Reproducible; no `TODAY()` dependency | Medium | Not Run |
| DAX-019 | Ranking | Change slicer context | Rank responds correctly | Medium | Not Run |
| DAX-020 | Model Validation Status | QA page | `PASSED` | Critical | Not Run |

---

## 10. Page-level functional tests

| ID | Page | Test | Expected result | Severity | Status |
|---|---|---|---|---|---|
| PG-001 | Executive | Six KPI cards load | Values display without error | Critical | Not Run |
| PG-002 | Executive | Revenue trend | Chronological and filter-responsive | High | Not Run |
| PG-003 | Executive | Risk indicators | Correct semantic status | High | Not Run |
| PG-004 | Sales | Previous-year comparison | Correct period comparison | High | Not Run |
| PG-005 | Sales | Waterfall | Components reconcile to net value | Critical | Not Run |
| PG-006 | Sales | Financial-year matrix | Totals reconcile | Critical | Not Run |
| PG-007 | Customer | Pareto chart | Cumulative contribution behaves correctly | High | Not Run |
| PG-008 | Customer | Value scatter | Correct axes, size and segment | Medium | Not Run |
| PG-009 | Customer | Recency | Uses model date and correct bands | High | Not Run |
| PG-010 | Product | Performance quadrant | Products classified correctly | High | Not Run |
| PG-011 | Product | Top/bottom selector | Visual changes metric/order | Medium | Not Run |
| PG-012 | Product | Return risk | Units and rate reconcile | High | Not Run |
| PG-013 | Store | Store ranking | Rank responds to filters | High | Not Run |
| PG-014 | Store | Employee leaderboard | Store selection filters employees | High | Not Run |
| PG-015 | Store | Opportunity heatmap | Correct store/category context | Medium | Not Run |
| PG-016 | Inventory | Status composition | Status counts reconcile | Critical | Not Run |
| PG-017 | Inventory | Action buttons | Correct status filter applied | High | Not Run |
| PG-018 | Inventory | Movement trend | Inflow/outflow/net reconcile | Critical | Not Run |
| PG-019 | Returns | Reason analysis | Units and values reconcile | Critical | Not Run |
| PG-020 | Returns | Refund funnel | Eligible/completed/pending/failed correct | Critical | Not Run |
| PG-021 | Payments | Method performance | Correct method-level rates | Critical | Not Run |
| PG-022 | Payments | Failure analysis | Correct failure populations | High | Not Run |
| PG-023 | Payments | Retry analysis | Attempt number behaves correctly | High | Not Run |
| PG-024 | All pages | Empty context | No misleading divide-by-zero output | High | Not Run |

---

## 11. Interaction tests

| ID | Test | Procedure | Expected result | Severity | Status |
|---|---|---|---|---|---|
| INT-001 | Navigation | Select each navigation icon | Correct page opens | High | Not Run |
| INT-002 | Active-page state | Navigate across pages | Current page highlighted | Low | Not Run |
| INT-003 | Synced date slicer | Change financial year | Relevant pages update | High | Not Run |
| INT-004 | Synced store slicer | Select one store | Relevant pages update | High | Not Run |
| INT-005 | Product hierarchy | Drill down and up | Hierarchy works | Medium | Not Run |
| INT-006 | Cross-filtering | Select a chart data point | Intended visuals filter | High | Not Run |
| INT-007 | Disabled interaction | Select KPI/control visual | Unrelated visuals remain stable | Medium | Not Run |
| INT-008 | Reset filters | Apply filters then reset | Approved default restored | High | Not Run |
| INT-009 | Filter panel | Open and close | Correct panel state | Medium | Not Run |
| INT-010 | Customer drill-through | Right-click customer | Customer Detail opens with correct context | High | Not Run |
| INT-011 | Product drill-through | Right-click product | Product Detail opens with correct context | High | Not Run |
| INT-012 | Store drill-through | Right-click store | Store Detail opens with correct context | High | Not Run |
| INT-013 | Back button | Use on detail page | Returns to source page | Medium | Not Run |
| INT-014 | Tooltips | Hover supported visuals | Correct diagnostic tooltip displays | Medium | Not Run |
| INT-015 | Field parameters | Change selected metric | Visual and title update | Medium | Not Run |
| INT-016 | Multi-select | Select multiple slicer values | Correct combined context | Medium | Not Run |
| INT-017 | Bookmark state | Change filters then use display bookmark | Filters are preserved when intended | High | Not Run |
| INT-018 | Help panel | Open and close definitions | Panel works without changing data | Low | Not Run |

---

## 12. Visual and formatting tests

| ID | Test | Expected result | Severity | Status |
|---|---|---|---|---|
| VIS-001 | Theme import | Imports without JSON error | High | Not Run |
| VIS-002 | Page size | Every main page is 1280 × 720 | Medium | Not Run |
| VIS-003 | Colour semantics | Success/warning/failure colours consistent | Medium | Not Run |
| VIS-004 | Currency format | Indian rupee and decimals correct | Medium | Not Run |
| VIS-005 | Percentage format | Rates show as percentages | Medium | Not Run |
| VIS-006 | Display units | Large values are readable and unambiguous | Medium | Not Run |
| VIS-007 | Titles | Every visual has a business title | Medium | Not Run |
| VIS-008 | Alignment | Cards and visuals align to grid | Low | Not Run |
| VIS-009 | Overflow | No clipped labels or scroll surprises | Medium | Not Run |
| VIS-010 | Default state | No accidental selected data point | Low | Not Run |
| VIS-011 | Caveat labels | Proxy and analytical assumptions disclosed | High | Not Run |
| VIS-012 | Screenshot readiness | No edit guides or private paths visible | Critical | Not Run |

---

## 13. Performance tests

| ID | Test | Procedure | Acceptance criterion | Severity | Status |
|---|---|---|---|---|---|
| PER-001 | SQL workload benchmark | Run script 37 | All checks consistent | Critical | Passed |
| PER-002 | Initial PBIX open | Open local PBIX | Opens without failure | High | Not Run |
| PER-003 | Page render | Performance Analyzer | Common page < 2 seconds target | Medium | Not Run |
| PER-004 | Slicer response | Change common slicer | Visuals respond near target | Medium | Not Run |
| PER-005 | Drill-through | Open detail page | Context opens without excessive delay | Medium | Not Run |
| PER-006 | Desktop refresh | Refresh full model | Completes without error | Critical | Not Run |
| PER-007 | Visual query count | Review analyzer | No unexplained duplicate queries | Medium | Not Run |
| PER-008 | Custom visuals | Review visual inventory | Only justified visuals used | Low | Not Run |
| PER-009 | High-cardinality tables | Review pages | Tables limited and usable | Medium | Not Run |
| PER-010 | File size | Review PBIX | Reasonable for imported dataset and assets | Low | Not Run |

Record measured results:

| Page | First render (ms) | Interaction (ms) | Result | Notes |
|---|---:|---:|---|---|
| Executive Overview |  |  |  |  |
| Sales Performance |  |  |  |  |
| Customer Analysis |  |  |  |  |
| Product Analysis |  |  |  |  |
| Store Performance |  |  |  |  |
| Inventory Analysis |  |  |  |  |
| Returns Analysis |  |  |  |  |
| Payment Analysis |  |  |  |  |

---

## 14. Accessibility tests

| ID | Test | Expected result | Severity | Status |
|---|---|---|---|---|
| ACC-001 | Alt text | Every meaningful visual has descriptive alt text | Medium | Not Run |
| ACC-002 | Tab order | Logical left-to-right/top-to-bottom sequence | Medium | Not Run |
| ACC-003 | Keyboard navigation | Buttons and slicers are reachable | Medium | Not Run |
| ACC-004 | Colour contrast | Important text remains readable | High | Not Run |
| ACC-005 | Colour independence | Status is not communicated by colour alone | High | Not Run |
| ACC-006 | Font size | Core content remains readable at 100% | Medium | Not Run |
| ACC-007 | Visual titles | Titles describe metric and context | Medium | Not Run |
| ACC-008 | Focus visibility | Current interactive element is identifiable | Low | Not Run |

---

## 15. Security and privacy tests

| ID | Test | Expected result | Severity | Status |
|---|---|---|---|---|
| SEC-001 | Repository secrets | No passwords, tokens or gateway keys | Critical | Not Run |
| SEC-002 | Connection strings | No password-bearing string committed | Critical | Not Run |
| SEC-003 | Screenshots | No private usernames or machine paths exposed | Critical | Not Run |
| SEC-004 | Customer data | Dataset is synthetic and portfolio-safe | Critical | Not Run |
| SEC-005 | Published report access | Workspace permissions appropriate | High | Not Run |
| SEC-006 | Gateway credentials | Stored only in approved service configuration | Critical | Not Run |

---

## 16. User acceptance scenarios

### UAT-001 — Executive health review

**User goal:** Determine enterprise performance and major risks.

**Steps:**

1. Open Executive Overview.
2. Select the latest complete financial year.
3. Review net revenue, margin, orders, payment success and inventory exposure.
4. Select the weakest monthly period using available visuals.
5. Identify the store/category contributing to the decline.

**Acceptance criteria:** The user can identify performance direction and at least one evidence-based action without navigating outside the report.

Status: Not Run

### UAT-002 — Sales decline investigation

**User goal:** Explain a negative monthly revenue movement.

**Steps:**

1. Open Sales Performance.
2. Select the declining month.
3. Compare against the prior month and prior year.
4. Review store, category, discount and margin contribution.
5. Investigate the relevant store or product using available report interactions.

**Acceptance criteria:** All visuals retain the selected context and reconcile to the monthly total.

Status: Not Run

### UAT-003 — High-value customer identification

**User goal:** Identify important customers and potential retention risk.

**Steps:**

1. Open Customer Analysis.
2. Review customer concentration or value distribution using available visuals.
3. Select a high-revenue customer where a customer-level visual supports selection.
4. If a Customer Detail drillthrough exists, open it; otherwise use available customer visuals.
5. Review recency, order history, product mix, payments and returns.

**Acceptance criteria:** Customer totals match the main page and the user can distinguish value from return/payment risk.

Status: Not Run

### UAT-004 — Product assortment decision

**User goal:** Find products to grow, protect or rationalize.

**Steps:**

1. Open Product Analysis.
2. Review product profitability and contribution visuals.
3. Select a low-value or high-return product.
4. If a Product Detail drillthrough exists, open it; otherwise use available product visuals.
5. Review sales, margin, return reasons and inventory exposure.

**Acceptance criteria:** The report supports a clear product action backed by multiple measures.

Status: Not Run

### UAT-005 — Inventory action planning

**User goal:** Prioritize replenishment and excess-stock actions.

**Steps:**

1. Open Inventory Analysis.
2. Filter inventory status to Out of Stock.
3. Identify affected stores and products.
4. Reset and filter inventory status to Excess Stock.
5. Review working-capital exposure.

**Acceptance criteria:** Inventory-status filters work as configured and available visuals provide actionable stock detail.

Status: Not Run

### UAT-006 — Return root-cause analysis

**User goal:** Identify the largest return and refund drivers.

**Steps:**

1. Open Returns Analysis.
2. Select the leading return reason.
3. Identify categories/products with high accepted units.
4. Review reusability and refund exposure.
5. Use available product-level analysis; verify any drillthrough only if implemented.

**Acceptance criteria:** Return quantities, rates and refund values remain reconciled under filtering.

Status: Not Run

### UAT-007 — Payment failure investigation

**User goal:** Find the payment method or failure reason requiring intervention.

**Steps:**

1. Open Payment Analysis.
2. Compare method-level success rates.
3. Select the weakest method.
4. Review payment status, failed attempts, and any available retry indicators.
5. Inspect store and month patterns.

**Acceptance criteria:** The report distinguishes attempt count, successful attempts, failed attempts and collected value correctly.

Status: Not Run

### UAT-008 — Report reset and navigation

**User goal:** Navigate the report without losing control of context.

**Steps:**

1. Apply multiple global slicers.
2. Navigate through every main page.
3. Verify page navigation and any implemented filter-panel controls.
4. Use any implemented drillthrough; otherwise verify the eight-page navigation flow.
5. Clear slicers or use an implemented reset control, if present.

**Acceptance criteria:** Navigation is predictable, intended slicer synchronization works, and available reset/clear actions restore the documented defaults.

Status: Not Run

---

## 17. Defect log template

| Defect ID | Test ID | Description | Severity | Owner | Status | Resolution | Retest result |
|---|---|---|---|---|---|---|---|
| DEF-001 |  |  |  |  | Open |  |  |

Defect statuses:

```text
Open → In Progress → Ready for Retest → Closed
                         ↘ Reopened
```

---

## 18. Test execution summary

The statuses below were updated from the provided **SQL screenshots**. Power BI-specific tests remain **Not Run** pending PBIX inspection and hands-on testing. `Not Run` means not verified by the supplied evidence, not necessarily that the user has never performed the test.

| Test area | Planned | Passed | Failed | Blocked | Not Run |
|---|---:|---:|---:|---:|---:|
| SQL deployment | 18 | 17 | 0 | 0 | 1 |
| Reconciliation | 12 | 12 | 0 | 0 | 0 |
| Data quality | 12 | 12 | 0 | 0 | 0 |
| Connection/refresh | 10 | 0 | 0 | 0 | 10 |
| Semantic model | 14 | 0 | 0 | 0 | 14 |
| DAX | 20 | 0 | 0 | 0 | 20 |
| Page functionality | 24 | 0 | 0 | 0 | 24 |
| Interactions | 18 | 0 | 0 | 0 | 18 |
| Visual formatting | 12 | 0 | 0 | 0 | 12 |
| Performance | 10 | 1 | 0 | 0 | 9 |
| Accessibility | 8 | 0 | 0 | 0 | 8 |
| Security/privacy | 6 | 0 | 0 | 0 | 6 |
| **Total** | **164** | **42** | **0** | **0** | **122** |

The 8 UAT scenarios are tracked separately and remain **Not Run / not evidenced**. No final Power BI UAT sign-off is asserted.

## 19. Exit criteria

The solution is approved when:

- [ ] All Critical tests pass
- [ ] All High tests pass or have documented acceptance
- [ ] No open Critical or High defect remains
- [ ] SQL deployment status is ready
- [ ] DAX reconciliation differences are zero
- [ ] Model Validation Status is `PASSED`
- [ ] All eight UAT scenarios pass
- [ ] Performance is acceptable for portfolio demonstration
- [ ] Accessibility review is complete
- [ ] No credentials or private information are exposed
- [ ] Final screenshots and PBIX backup exist

---

## 20. UAT sign-off

| Role | Name | Decision | Date | Comments |
|---|---|---|---|---|
| Project owner / Data Analyst | Akshay Aswani | Pending |  |  |
| Business reviewer |  | Pending |  |  |
| Technical reviewer |  | Pending |  |  |

Final decision:

```text
[ ] APPROVED
[ ] APPROVED WITH CONDITIONS
[ ] REJECTED
```

---

## Next action

Complete the remaining Power BI Desktop checks, record any defects, attach screenshots or measured evidence, then update test statuses and obtain explicit UAT sign-off. After that, reconcile the repository README and final portfolio claims against this record.
