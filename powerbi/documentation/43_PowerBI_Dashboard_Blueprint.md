# Power BI Dashboard Blueprint — Implemented Design Alignment

**Project:** Retail Sales & Inventory Intelligence Platform  
**File:** `43_PowerBI_Dashboard_Blueprint.md`  
**Report:** `powerbi/report/Retail_Sales_Inventory_Intelligence_Dashboard.pbix`  
**Background:** `powerbi/theme/background.png`  
**Theme:** `powerbi/theme/44_PowerBI_Theme.json`  
**Review date:** 3 November 2026  
**Evidence basis:** Uploaded 1280×720 background image, existing draft blueprint, and previously described final page/slicer configuration. **PBIX rendering and individual visual values have not been independently certified in this documentation pass.**

## 1. Business story

The report moves from overall retail health to sales, customers, products, stores, inventory, returns and payment performance. It supports executive prioritization and operational investigation across separate transaction grains. Supplier performance is available in SQL analysis but is **not a ninth dashboard page**.

## 2. Visual shell — actual background

The uploaded `background.png` has **1280×720** dimensions and shows:

1. Dark navy-to-blue branded header with project title and retail icon.
2. A horizontal navigation band with eight labels: **Overview | Sales | Customers | Products | Stores | Inventory | Returns | Payments**.
3. A row of **five empty KPI-card containers** beneath navigation.
4. A top row of **five slicer/control containers** between the header and navigation.
5. **Four** larger analysis/chart containers arranged in two columns across two rows.
6. A dark blue footer with a yellow accent line.

This is a **reusable background image**. KPI values, slicers, navigation hitboxes and charts must be placed in the PBIX above it; the image alone does not establish their presence or correctness.

### Report construction rules

- Set canvas to 16:9, **1280 × 720**.
- Use `powerbi/theme/background.png` as the page background at appropriate fit; verify scaling and text readability.
- Place navigation buttons over the eight horizontal labels; verify click targets, current-page indication, and keyboard navigation.
- Keep the five slicer controls aligned with the top containers, with their **page-specific fields** below.
- Use the five KPI placeholders and four chart containers as the default shell; if a page uses a different number of visuals, document the deviation instead of claiming every page is identical.
- Use the provided JSON theme for default chart formatting, but note that its light canvas / white-card defaults may not match the **blue-tinted background art**. Avoid opaque white visual backgrounds that hide the artwork unless intentional.
- No left navigation rail is part of this implementation. Prior instructions for a left rail and a six-KPI strip are **retired**.

## 3. Final eight-page inventory and slicers

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

### Page-level design and business questions

| Page | Decision focus | Suggested validation focus |
|---|---|---|
| 01 Executive Overview | Net revenue, gross profit, margin, delivered orders, AOV, top business drivers | KPI totals and cross-filter behavior |
| 02 Sales Performance | Monthly trends, category/store contribution and sales volume | Date roles, monthly reconciliation and financial-year sorting |
| 03 Customer Analysis | Customer segments, repeat engagement and geographic distribution | Customer distinct counts, unknown keys, state slicer |
| 04 Product Analysis | Category/brand mix, units, profitability and top products | Product granularity, rank filter context and margin |
| 05 Store Performance | Store tiers, geography and store contribution | `DimStore.StateName`, store selection, tier comparisons |
| 06 Inventory Analysis | Available stock, inventory status, exposure and replenishment | Snapshot as-of date; **no FY slicer**; brand/status controls |
| 07 Returns Analysis | Return reasons, product return patterns and refund exposure | **FY2026–27 page filter**; return versus refund date roles |
| 08 Payment Analysis | Payment attempts, status, methods and failures | **Unsynchronized slicers**; attempts versus orders |

The table documents the agreed report design, **not a claim that each visual has been verified in the uploaded PBIX**.

## 4. Navigation and interaction contract

- Navigation labels are **horizontal** and appear in the order listed in the background.
- Clicking a navigation item must open the corresponding page; all eight routes must be tested.
- Sync slicers only where the meaning and data grain are compatible. The **Payment Analysis page must remain independent**.
- The Inventory page intentionally omits Financial Year because the snapshot is not a full historical series.
- Verify reset-filter buttons and visual interactions **if they exist**; do not assume that a feature proposed in the old blueprint was implemented.
- Hidden drillthrough pages, field parameters, report-page tooltips, and bookmark panels remain **optional/unverified** unless inspected in the PBIX.

## 5. KPI and date-role governance

- **Net Revenue** = Recognized Revenue − Completed Refund Value.
- **Gross Margin %** = Recognized Gross Profit ÷ Recognized Revenue.
- **AOV** = Net Revenue ÷ Delivered Orders.
- Confirm delivered-order logic uses the intended distinct-order grain, not accidentally one row per order line.
- Payment events, return requests, refund events and delivery activity may have **different calendar dates**. Never compare monthly totals without confirming date attribution.
- SQL `pbi_*` views are controls/reconciliation sources; they do not replace semantic-model and visual testing.

## 6. Theme and asset governance

- `powerbi/theme/44_PowerBI_Theme.json` contains a light canvas (`#F5F7FA`), blue accent (`#2F6BFF`), and white visual defaults.
- `powerbi/theme/background.png` is the **actual dark-blue branded page artwork**. Its appearance takes precedence when describing the visible design.
- Check whether visual background settings should be transparent to preserve the background containers.
- Do not rename `background.png` to `.pmg`; `.png` is the confirmed file extension.
- Keep logos and decorative assets separate from interactive controls.

## 7. Validation / UAT requirements

| Test | Expected behavior | Current documentation status |
|---|---|---|
| Canvas and background | 1280×720, artwork aligned without cropping | Background image supplied; PBIX application pending |
| Navigation | All eight horizontal page buttons route correctly | Pending manual verification |
| Slicers | Correct four fields on each page | Agreed configuration; pending PBIX verification |
| Inventory | No FY slicer, snapshot date understood | Agreed configuration; pending PBIX verification |
| Returns | FY2026–27 filter enforced | Report design recorded; pending PBIX verification |
| Payments | Slicers not synced to other pages | Report design recorded; pending PBIX verification |
| KPI reconciliation | DAX totals equal SQL controls at matching filters | Pending detailed reconciliation |
| Visual quality | Titles, tooltips, contrast and labels readable | Pending manual verification |
| Accessibility | Keyboard navigation, alternative text where applicable | Pending manual verification |
| Screenshots | Eight final approved page exports available | Verify files and published paths |

See `docs/testing/14_Test_Cases_and_UAT.md` for the formal acceptance record. Do **not** convert SQL checks into Power BI UAT passes.

## 8. Screenshot publication

Store approved final exports under `assets/dashboard/`:

- `assets/dashboard/01_Executive_Overview.jpg`
- `assets/dashboard/02_Sales_Performance.jpg`
- `assets/dashboard/03_Customer_Analysis.jpg`
- `assets/dashboard/04_Product_Analysis.jpg`
- `assets/dashboard/05_Store_Performance.jpg`
- `assets/dashboard/06_Inventory_Analysis.jpg`
- `assets/dashboard/07_Returns_Analysis.jpg`
- `assets/dashboard/08_Payment_Analysis.jpg`


Rename the supplied source files only when copying them into the repository, and check each image actually matches the corresponding final PBIX page.

## 9. Known documentation differences resolved

| Earlier draft | Corrected implemented design |
|---|---|
| Left-side navigation rail | Horizontal top navigation |
| Six KPI cards on every page | Five KPI containers in supplied background; page visuals require verification |
| One shared global slicer specification | Four page-specific slicers; Payments unsynchronized |
| Financial-year filtering on Inventory | No FY slicer; snapshot-specific view |
| “Store & Employee Performance” page | “Store Performance” page |
| “Returns & Refunds” page | “Returns Analysis” page |
| Suggested drillthrough/tooltip pages described as completed | Treat as unverified until PBIX inspection |

## 10. Remaining verification

Before marking this blueprint fully accepted, inspect the actual PBIX for page titles, visual measures, relationships, navigation, slicer synchronization, date filters, tooltip/drillthrough implementation, and refresh behavior. Record screenshots and test outcomes rather than relying on the background artwork alone.
