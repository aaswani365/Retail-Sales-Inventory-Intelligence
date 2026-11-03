# Retail Sales & Inventory Intelligence Platform

## KPI Dictionary

| Document attribute | Value |
|---|---|
| Project name | Retail Sales & Inventory Intelligence Platform |
| Project version | 2.0 |
| Document | 11_KPI_Dictionary.md |
| Author | Akshay Aswani |
| Database | RetailIntelligenceDB |
| Reporting platform | Power BI |
| Reporting period | 1 July 2023–30 June 2026 |
| Status | Approved metric-definition baseline |
| Related documents | 01_Business_Requirements.md, 02_Business_Rules.md, 09_Data_Generation_Strategy.md, 10_Testing_and_Validation_Strategy.md |

---

## 1. Purpose

This document is the authoritative definition of business metrics used in SQL analysis and Power BI. It prevents different pages, queries or analysts from assigning different meanings to the same KPI.

Every implemented KPI must identify:

- Business purpose
- Natural grain
- Formula
- Date context
- Inclusion and exclusion rules
- Null and division behavior
- SQL control source
- Power BI measure name and format
- Intended dashboard use

If a dashboard calculation differs from this dictionary, either the calculation must be corrected or this document and its governing business rule must be formally updated.

## 2. Metric design principles

1. Calculate each metric at its natural fact grain before combining facts.
2. Distinguish orders placed, orders delivered, payments collected and refunds completed.
3. Exclude pass-through tax from revenue and profit metrics unless the label explicitly includes tax.
4. Use transaction-time unit price and unit cost, not current product values, for historical sales.
5. Use accepted return quantities for return impact; requested quantities measure demand for returns only.
6. Use completed payments and completed refunds for cash metrics.
7. Use the shared Date dimension for report filtering and time intelligence.
8. Return blank for undefined ratios unless a business rule explicitly requires zero.
9. Aggregate first and round last except where transaction rules require line-level rounding.
10. Never use `DISTINCTCOUNT` to conceal a duplicated join.

## 3. Transaction classifications

| Classification | Included records |
|---|---|
| All orders | Every `SalesOrder` regardless of status |
| Active orders | `PENDING`, `CONFIRMED`, `PROCESSING`, `SHIPPED` |
| Cancelled orders | `CANCELLED` |
| Delivered orders | `DELIVERED`, `PARTIALLY_RETURNED`, `RETURNED` |
| Non-cancelled orders | Every status except `CANCELLED` |
| Valid payment attempts | `INITIATED`, `PENDING`, `COMPLETED`, `FAILED`, `CANCELLED` payment attempts on valid orders |
| Completed payments | Payment events with status `COMPLETED`, `PARTIALLY_REFUNDED` or `REFUNDED`, using original completed payment amount once |
| Accepted return items | Return-item accepted quantity greater than zero |
| Completed refunds | Refund events with refund status `Completed` |
| Active product-store combinations | Active product and active store combinations present in `InventoryBalance` |

Payment lifecycle statuses `PARTIALLY_REFUNDED` and `REFUNDED` still represent a payment that completed before refund activity. The original payment amount must not be omitted from gross collections; refunds are subtracted separately.

## 4. Date-role policy

| Metric family | Default date role | Reason |
|---|---|---|
| Order demand/bookings | Order date | Measures when demand was placed |
| Recognized sales/revenue | Delivered date | Measures when fulfillment completed |
| Payments/collections | Payment date | Measures cash collection timing |
| Returns | Request date for request volume; received/accepted date for operational outcome | Separates customer request from processing |
| Refunds | Refund date | Measures cash outflow timing |
| Inventory movements | Movement date | Measures stock flow timing |
| Current inventory | Snapshot/as-of date | Measures point-in-time position |
| Customer acquisition/cohort | First delivered-order date | Measures first realized customer activity |

Power BI should use one active relationship per fact and inactive role-playing relationships activated explicitly with `USERELATIONSHIP` when a different business date is required.

## 5. Fact-grain policy

| Analytical object | Grain | Primary metric families |
|---|---|---|
| `analytics.FactSales` | One row per sales-order item | Sales, revenue, units, COGS, profit |
| `analytics.FactPayments` | One row per payment attempt/event | Attempts, completed payments, success rate |
| `analytics.FactReturns` | One row per returned order item | Requested/accepted quantities, reasons, reusable outcome |
| `analytics.FactRefunds` | One row per refund event | Refund value and net cash |
| `analytics.FactInventoryMovement` | One row per inventory movement | Inflow, outflow, adjustments and stock flow |
| `analytics.FactInventorySnapshot` | One row per date-product-store | On hand, reserved, available and stock value |

Do not join fact tables directly for measure calculations. Use conformed dimensions or aggregate each fact to the required common grain first.

## 6. Authoritative KPI catalogue

| ID | KPI | Measure name | Format | Primary page |
|---|---|---|---|---|
| KPI-001 | Total Orders | `Total Orders` | Whole number | Executive Summary |
| KPI-002 | Active Orders | `Active Orders` | Whole number | Sales Performance |
| KPI-003 | Delivered Orders | `Delivered Orders` | Whole number | Executive Summary |
| KPI-004 | Cancelled Orders | `Cancelled Orders` | Whole number | Sales Performance |
| KPI-005 | Gross Order Value | `Gross Order Value` | ₹ currency | Sales Performance |
| KPI-006 | Booked Order Value | `Booked Order Value` | ₹ currency | Sales Performance |
| KPI-007 | Recognized Revenue | `Recognized Revenue` | ₹ currency | Executive Summary |
| KPI-008 | Gross Refund Value | `Gross Refund Value` | ₹ currency | Returns & Payments |
| KPI-009 | Net Revenue | `Net Revenue` | ₹ currency | Executive Summary |
| KPI-010 | COGS | `COGS` | ₹ currency | Product Performance |
| KPI-011 | Gross Profit | `Gross Profit` | ₹ currency | Executive Summary |
| KPI-012 | Gross Margin % | `Gross Margin %` | 0.0% | Executive Summary |
| KPI-013 | Average Order Value | `Average Order Value` | ₹ currency | Sales Performance |
| KPI-014 | Delivered Units | `Delivered Units` | Whole number | Product Performance |
| KPI-015 | Net Units Sold | `Net Units Sold` | Whole number | Product Performance |
| KPI-016 | Completed Payment Value | `Completed Payment Value` | ₹ currency | Returns & Payments |
| KPI-017 | Net Cash Collection | `Net Cash Collection` | ₹ currency | Returns & Payments |
| KPI-018 | Payment Success Rate | `Payment Success Rate %` | 0.0% | Returns & Payments |
| KPI-019 | Order Cancellation Rate | `Order Cancellation Rate %` | 0.0% | Sales Performance |
| KPI-020 | Return Rate by Quantity | `Return Rate by Quantity %` | 0.0% | Returns & Payments |
| KPI-021 | Return Rate by Orders | `Return Rate by Orders %` | 0.0% | Returns & Payments |
| KPI-022 | Inventory Value at Cost | `Inventory Value at Cost` | ₹ currency | Inventory Management |
| KPI-023 | Stockout Rate | `Stockout Rate %` | 0.0% | Inventory Management |
| KPI-024 | Low Stock SKUs | `Low Stock SKUs` | Whole number | Inventory Management |
| KPI-025 | Excess Stock SKUs | `Excess Stock SKUs` | Whole number | Inventory Management |
| KPI-026 | Customer Lifetime Value | `Customer Lifetime Value` | ₹ currency | Customer Insights |
| KPI-027 | Active Customers | `Active Customers` | Whole number | Executive Summary |
| KPI-028 | New Customers | `New Customers` | Whole number | Customer Insights |
| KPI-029 | Repeat Customers | `Repeat Customers` | Whole number | Customer Insights |
| KPI-030 | Repeat Customer Rate | `Repeat Customer Rate %` | 0.0% | Customer Insights |
| KPI-031 | Purchase Frequency | `Purchase Frequency` | 0.00 | Customer Insights |
| KPI-032 | Customer Retention Rate | `Customer Retention Rate %` | 0.0% | Customer Insights |
| KPI-033 | Revenue Growth | `Net Revenue YoY %` | 0.0% | Executive Summary |
| KPI-034 | Profit Growth | `Gross Profit YoY %` | 0.0% | Executive Summary |
| KPI-035 | Units Growth | `Net Units Sold YoY %` | 0.0% | Product Performance |
| KPI-036 | Sales Contribution | `Net Revenue Contribution %` | 0.0% | Product Performance |
| KPI-037 | Product Return Rate | `Product Return Rate %` | 0.0% | Product Performance |
| KPI-038 | Inventory Turnover | `Inventory Turnover` | 0.00× | Inventory Management |
| KPI-039 | Sell-Through Rate | `Sell-Through Rate %` | 0.0% | Inventory Management |
| KPI-040 | Days of Inventory | `Days of Inventory` | 0.0 days | Inventory Management |
| KPI-041 | Store Net Revenue | `Store Net Revenue` | ₹ currency | Store & Employee Performance |
| KPI-042 | Revenue per Employee | `Revenue per Employee` | ₹ currency | Store & Employee Performance |
| KPI-043 | Orders per Employee | `Orders per Employee` | 0.00 | Store & Employee Performance |
| KPI-044 | Supplier Revenue Contribution | `Supplier Revenue Contribution %` | 0.0% | Supplier Analysis |
| KPI-045 | Supplier Return Rate | `Supplier Return Rate %` | 0.0% | Supplier Analysis |
| KPI-046 | Supplier Inventory Exposure | `Supplier Inventory Exposure` | ₹ currency | Supplier Analysis |
| KPI-047 | Failed Payment Attempts | `Failed Payment Attempts` | Whole number | Returns & Payments |
| KPI-048 | Payment Retry Success Rate | `Payment Retry Success Rate %` | 0.0% | Returns & Payments |
| KPI-049 | Refund Rate | `Refund Rate %` | 0.0% | Returns & Payments |
| KPI-050 | Reusable Return Rate | `Reusable Return Rate %` | 0.0% | Returns & Payments |

---

## 7. Order KPIs

### KPI-001 — Total Orders

| Attribute | Definition |
|---|---|
| Business question | How many orders were placed? |
| Formula | Distinct count of `SalesOrderID` |
| Grain | Order header |
| Date basis | Order date |
| Includes | Every valid order status |
| Excludes | Invalid/test rows outside released dataset |
| SQL control | `COUNT_BIG(*)` from `sales.SalesOrder` after date filters |
| DAX measure | `Total Orders` |
| Format | Whole number |
| Blank behavior | `0` when the selected period contains no orders |

### KPI-002 — Active Orders

| Attribute | Definition |
|---|---|
| Business question | How many orders remain in progress at the reporting snapshot? |
| Formula | Distinct orders in `PENDING`, `CONFIRMED`, `PROCESSING`, `SHIPPED` |
| Grain | Order header |
| Date basis | Current/as-of status; order date for trend views |
| Includes | Approved active statuses |
| Excludes | Delivered, cancelled and returned final states |
| DAX measure | `Active Orders` |
| Format | Whole number |

### KPI-003 — Delivered Orders

| Attribute | Definition |
|---|---|
| Business question | How many orders reached delivery? |
| Formula | Distinct orders whose final/current state is `DELIVERED`, `PARTIALLY_RETURNED` or `RETURNED` |
| Grain | Order header |
| Date basis | Delivered date |
| Includes | Delivered orders even when later returned |
| Excludes | Active and cancelled orders |
| DAX measure | `Delivered Orders` |
| Format | Whole number |

### KPI-004 — Cancelled Orders

| Attribute | Definition |
|---|---|
| Business question | How many orders were cancelled? |
| Formula | Distinct orders with final/current status `CANCELLED` |
| Grain | Order header |
| Date basis | Cancelled date for cancellation trend; order date for placed-order cohort analysis |
| Excludes | Failed payment attempts that did not cancel the order |
| DAX measure | `Cancelled Orders` |
| Format | Whole number |

### KPI-019 — Order Cancellation Rate

| Attribute | Definition |
|---|---|
| Business question | What share of placed orders were cancelled? |
| Formula | `Cancelled Orders ÷ Total Orders` |
| Numerator | Distinct cancelled orders |
| Denominator | All distinct placed orders in the same order-date cohort |
| Date basis | Order date by default |
| DAX measure | `Order Cancellation Rate %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

## 8. Sales and revenue KPIs

### KPI-005 — Gross Order Value

| Attribute | Definition |
|---|---|
| Business question | What was the pre-discount merchandise value of non-cancelled demand? |
| Formula | `SUM(Quantity × UnitPrice)` for non-cancelled order items |
| Grain | Sales-order item |
| Date basis | Order date |
| Includes | Active and delivered orders |
| Excludes | Cancelled orders, tax, discount and refund effects |
| SQL control | Sum `SalesOrderItem.GrossAmount` after excluding cancelled orders |
| DAX measure | `Gross Order Value` |
| Format | INR currency, zero or two decimals by visual |

### KPI-006 — Booked Order Value

| Attribute | Definition |
|---|---|
| Business question | What net customer invoice value was booked for non-cancelled demand? |
| Formula | Sum item `NetAmount` for non-cancelled orders |
| Grain | Sales-order item |
| Date basis | Order date |
| Includes | Discount and tax effects in booked invoice value |
| Excludes | Cancelled orders and later refunds |
| DAX measure | `Booked Order Value` |
| Format | INR currency |

### KPI-007 — Recognized Revenue

| Attribute | Definition |
|---|---|
| Business question | How much sales revenue was earned through delivered items before refunds? |
| Formula | Sum delivered taxable amount: `GrossAmount − DiscountAmount`, proportioned to delivered quantity |
| Grain | Delivered sales-order item |
| Date basis | Delivered date |
| Includes | Delivered value from `DELIVERED`, `PARTIALLY_RETURNED`, `RETURNED` orders before refund deduction |
| Excludes | Pass-through tax, cancelled/active orders and completed refund deduction |
| SQL control | Sum pretax delivered amount from `FactSales` |
| DAX measure | `Recognized Revenue` |
| Format | INR currency |

### KPI-008 — Gross Refund Value

| Attribute | Definition |
|---|---|
| Business question | How much cash was refunded? |
| Formula | Sum completed `RefundAmount` |
| Grain | Refund event |
| Date basis | Refund date |
| Includes | Completed refunds only |
| Excludes | Pending and failed refunds |
| DAX measure | `Gross Refund Value` |
| Format | INR currency |

`Gross Refund Value` includes the total completed refund amount, potentially including refunded tax. A pretax refund allocation is required for the `Net Revenue` calculation.

### KPI-009 — Net Revenue

| Attribute | Definition |
|---|---|
| Business question | What revenue remained after completed eligible refunds? |
| Formula | `Recognized Revenue − Completed Pretax Refund Value` |
| Grain | Delivered item plus allocated completed-refund adjustment |
| Date basis | Delivered-date view for sales-period performance; refund-date view must be explicitly labelled cash-adjustment timing |
| Includes | Recognized pretax revenue and completed pretax refund allocations |
| Excludes | Pass-through tax, pending/failed refunds |
| SQL control | Independently aggregate sales and refund facts before combining |
| DAX measure | `Net Revenue` |
| Format | INR currency |

### KPI-013 — Average Order Value

| Attribute | Definition |
|---|---|
| Business question | What was the average net revenue per delivered order? |
| Formula | `Net Revenue ÷ Delivered Orders` |
| Grain | Aggregated delivered-order population |
| Date basis | Delivered date |
| Excludes | Active/cancelled orders and tax |
| DAX measure | `Average Order Value` |
| Format | INR currency |
| Zero denominator | Blank |

### KPI-033 — Net Revenue YoY %

| Attribute | Definition |
|---|---|
| Formula | `(Net Revenue − Net Revenue PY) ÷ Net Revenue PY` |
| Date basis | Delivered date through marked Date dimension |
| Required supporting measure | `Net Revenue PY` |
| DAX measure | `Net Revenue YoY %` |
| Format | Percentage, one decimal |
| Zero/blank prior period | Blank |

### KPI-036 — Net Revenue Contribution %

| Attribute | Definition |
|---|---|
| Business question | What share of selected total net revenue is contributed by the current product/store/category context? |
| Formula | `Net Revenue ÷ Net Revenue with contribution dimension filter removed` |
| Date basis | Same as `Net Revenue` |
| Preserves | Date and report-level filters |
| Removes | Only the dimension whose contribution is being evaluated |
| DAX measure | `Net Revenue Contribution %` |
| Format | Percentage, one decimal |

## 9. Profitability KPIs

### KPI-010 — COGS

| Attribute | Definition |
|---|---|
| Business question | What inventory cost was consumed by recognized net sales? |
| Formula | Delivered quantity × transaction `UnitCost`, less cost restored for accepted reusable returns |
| Grain | Sales-order item adjusted by accepted reusable return quantity |
| Date basis | Delivered date for original cost recognition; return receipt date for operational reversal views |
| Includes | Transaction-time cost of delivered units |
| Excludes | Current master cost, tax and non-reusable returned cost reversal |
| DAX measure | `COGS` |
| Format | INR currency |

Accepted non-reusable returned units remain a cost because they do not restore sellable inventory. Accepted reusable returned units reverse the related transaction cost.

### KPI-011 — Gross Profit

| Attribute | Definition |
|---|---|
| Formula | `Net Revenue − COGS` |
| Date basis | Delivered-date performance context |
| Excludes | Pass-through tax and operating expenses outside project scope |
| DAX measure | `Gross Profit` |
| Format | INR currency |

### KPI-012 — Gross Margin %

| Attribute | Definition |
|---|---|
| Formula | `Gross Profit ÷ Net Revenue` |
| DAX measure | `Gross Margin %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |
| Interpretation | Product/store/customer profitability before operating expenses |

### KPI-034 — Gross Profit YoY %

| Attribute | Definition |
|---|---|
| Formula | `(Gross Profit − Gross Profit PY) ÷ Gross Profit PY` |
| Required supporting measure | `Gross Profit PY` |
| Date basis | Delivered date |
| DAX measure | `Gross Profit YoY %` |
| Format | Percentage, one decimal |
| Zero/blank prior period | Blank |

## 10. Unit KPIs

### KPI-014 — Delivered Units

| Attribute | Definition |
|---|---|
| Formula | Sum delivered item quantity before accepted-return adjustment |
| Grain | Delivered sales-order item |
| Date basis | Delivered date |
| DAX measure | `Delivered Units` |
| Format | Whole number |

### KPI-015 — Net Units Sold

| Attribute | Definition |
|---|---|
| Formula | `Delivered Units − Accepted Returned Units` |
| Grain | Product/order item |
| Date basis | Delivered-period view by default |
| Includes | Accepted returned quantities regardless of refund timing |
| Excludes | Requested but rejected return quantities |
| DAX measure | `Net Units Sold` |
| Format | Whole number |

### KPI-035 — Net Units Sold YoY %

| Attribute | Definition |
|---|---|
| Formula | `(Net Units Sold − Net Units Sold PY) ÷ Net Units Sold PY` |
| Date basis | Delivered date |
| DAX measure | `Net Units Sold YoY %` |
| Format | Percentage, one decimal |
| Zero/blank prior period | Blank |

## 11. Payment and cash KPIs

### KPI-016 — Completed Payment Value

| Attribute | Definition |
|---|---|
| Business question | How much gross customer payment was successfully collected before refunds? |
| Formula | Sum original amount of completed payment events |
| Grain | Payment event |
| Date basis | Payment date |
| Includes | Completed payments later marked partially/fully refunded, counted once |
| Excludes | Initiated, pending, failed and cancelled attempts |
| DAX measure | `Completed Payment Value` |
| Format | INR currency |

### KPI-017 — Net Cash Collection

| Attribute | Definition |
|---|---|
| Business question | What net cash remained after completed refunds? |
| Formula | `Completed Payment Value − Gross Refund Value` |
| Grain | Independently aggregated payment and refund events |
| Date basis | Payment/refund event date under cash view |
| DAX measure | `Net Cash Collection` |
| Format | INR currency |

Net cash collection is a cash-flow measure and can differ from `Net Revenue` because payment, delivery and refund dates differ and tax is treated differently.

### KPI-018 — Payment Success Rate

| Attribute | Definition |
|---|---|
| Formula | `Completed Payment Attempts ÷ Valid Payment Attempts` |
| Grain | Payment attempt |
| Date basis | Payment date |
| Numerator | Attempts that successfully completed payment |
| Denominator | Initiated, pending, completed, failed and cancelled valid attempts |
| Excludes | Refund events because they are not payment attempts |
| DAX measure | `Payment Success Rate %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

### KPI-047 — Failed Payment Attempts

| Attribute | Definition |
|---|---|
| Formula | Count payment attempts with status `FAILED` |
| Date basis | Payment date |
| DAX measure | `Failed Payment Attempts` |
| Format | Whole number |

### KPI-048 — Payment Retry Success Rate

| Attribute | Definition |
|---|---|
| Business question | What share of orders with an initial failed attempt later completed payment? |
| Formula | Orders with initial failure and later completion ÷ orders with initial failure |
| Grain | Order |
| Date basis | Initial failed-attempt date by default |
| DAX measure | `Payment Retry Success Rate %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

### KPI-049 — Refund Rate

| Attribute | Definition |
|---|---|
| Formula | `Gross Refund Value ÷ Completed Payment Value` |
| Date basis | Use a clearly labelled cohort or event-date basis; do not mix silently |
| DAX measure | `Refund Rate %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

## 12. Return KPIs

### KPI-020 — Return Rate by Quantity

| Attribute | Definition |
|---|---|
| Formula | `Accepted Returned Units ÷ Delivered Units` |
| Grain | Product/order item |
| Date basis | Delivered-order cohort by default |
| Includes | Accepted quantity only |
| Excludes | Rejected/requested-only quantity |
| DAX measure | `Return Rate by Quantity %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

### KPI-021 — Return Rate by Orders

| Attribute | Definition |
|---|---|
| Formula | Distinct delivered orders with accepted returns ÷ distinct delivered orders |
| Grain | Order |
| Date basis | Delivered-order cohort by default |
| DAX measure | `Return Rate by Orders %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

### KPI-037 — Product Return Rate

| Attribute | Definition |
|---|---|
| Formula | Accepted returned product units ÷ delivered product units |
| Grain | Product within selected context |
| Date basis | Delivered-order cohort |
| DAX measure | `Product Return Rate %` |
| Format | Percentage, one decimal |

### KPI-050 — Reusable Return Rate

| Attribute | Definition |
|---|---|
| Formula | Accepted reusable returned units ÷ accepted returned units with completed inspection |
| Grain | Return item |
| Date basis | Received/inspection date |
| Excludes | Uninspected rows where `IsReusable` is null |
| DAX measure | `Reusable Return Rate %` |
| Format | Percentage, one decimal |

## 13. Inventory KPIs

### KPI-022 — Inventory Value at Cost

| Attribute | Definition |
|---|---|
| Business question | What is the current cost value of on-hand inventory? |
| Formula | Sum `QuantityOnHand × current Product.CostPrice` |
| Grain | Product-store snapshot |
| Date basis | Current/as-of snapshot date |
| Includes | Active product-store balance rows unless historical view is explicitly requested |
| Excludes | Reserved-status adjustment; on-hand value includes reserved units physically present |
| DAX measure | `Inventory Value at Cost` |
| Format | INR currency |

This metric intentionally uses current master cost for current inventory valuation. Historical COGS uses transaction unit cost.

### KPI-023 — Stockout Rate

| Attribute | Definition |
|---|---|
| Formula | Active product-store combinations with `QuantityAvailable = 0` ÷ all active product-store combinations |
| Grain | Product-store snapshot |
| Date basis | Snapshot/as-of date |
| DAX measure | `Stockout Rate %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

### KPI-024 — Low Stock SKUs

| Attribute | Definition |
|---|---|
| Formula | Count distinct active product-store combinations where available quantity is greater than zero and at/below product reorder level |
| Grain | Product-store snapshot |
| Date basis | Snapshot/as-of date |
| DAX measure | `Low Stock SKUs` |
| Format | Whole number |

The measure counts product-store combinations, even though the display name uses the familiar term SKUs. A product-level distinct version must be labelled `Low Stock Products`.

### KPI-025 — Excess Stock SKUs

| Attribute | Definition |
|---|---|
| Formula | Count active product-store combinations where on-hand quantity is at/above configured `ExcessStockLevel` |
| Grain | Product-store snapshot |
| Date basis | Snapshot/as-of date |
| DAX measure | `Excess Stock SKUs` |
| Format | Whole number |

### KPI-038 — Inventory Turnover

| Attribute | Definition |
|---|---|
| Formula | Period COGS ÷ average inventory value at cost |
| Average inventory | Average of comparable periodic inventory snapshots, not average transaction rows |
| Date basis | Selected period |
| DAX measure | `Inventory Turnover` |
| Format | Decimal with `×` suffix |
| Zero denominator | Blank |

### KPI-039 — Sell-Through Rate

| Attribute | Definition |
|---|---|
| Formula | Net units sold ÷ (`Opening Units + Inbound Units`) |
| Grain | Product/store/selected period |
| Inbound units | Purchase receipts, transfer-in and adjustment-in as approved; exclude customer returns unless explicitly analysed |
| DAX measure | `Sell-Through Rate %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

### KPI-040 — Days of Inventory

| Attribute | Definition |
|---|---|
| Formula | Ending inventory value ÷ average daily COGS |
| Average daily COGS | Selected-period COGS ÷ number of calendar days in selected period |
| Date basis | Ending snapshot and selected period |
| DAX measure | `Days of Inventory` |
| Format | One decimal day |
| Zero denominator | Blank |

## 14. Customer KPIs

### KPI-026 — Customer Lifetime Value

| Attribute | Definition |
|---|---|
| Business question | How much cumulative net revenue has a customer generated? |
| Formula | Customer `Net Revenue` across the explicitly selected lifetime period |
| Grain | Customer |
| Date basis | Delivered date |
| Includes | Delivered net pretax revenue after completed refund adjustment |
| Excludes | Cancelled/active orders and tax |
| DAX measure | `Customer Lifetime Value` |
| Format | INR currency |

This is realized historical value, not a predictive lifetime-value model. Dashboard labels must not imply future expected value.

### KPI-027 — Active Customers

| Attribute | Definition |
|---|---|
| Formula | Distinct customers with at least one delivered order in selected period |
| Grain | Customer |
| Date basis | Delivered date |
| DAX measure | `Active Customers` |
| Format | Whole number |

### KPI-028 — New Customers

| Attribute | Definition |
|---|---|
| Formula | Customers whose first valid delivered order date falls in selected period |
| Grain | Customer |
| Date basis | First delivered-order date |
| Excludes | Registration-only customers without delivered orders |
| DAX measure | `New Customers` |
| Format | Whole number |

### KPI-029 — Repeat Customers

| Attribute | Definition |
|---|---|
| Formula | Distinct customers with at least two delivered orders in the selected analysis period |
| Grain | Customer |
| Date basis | Delivered date |
| DAX measure | `Repeat Customers` |
| Format | Whole number |

If lifetime behavior is used instead, label the measure `Lifetime Repeat Customers`.

### KPI-030 — Repeat Customer Rate

| Attribute | Definition |
|---|---|
| Formula | `Repeat Customers ÷ Active Customers` |
| Date basis | Delivered date |
| DAX measure | `Repeat Customer Rate %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

### KPI-031 — Purchase Frequency

| Attribute | Definition |
|---|---|
| Formula | Delivered orders ÷ active customers |
| Date basis | Delivered date |
| DAX measure | `Purchase Frequency` |
| Format | Decimal, two places |
| Zero denominator | Blank |

### KPI-032 — Customer Retention Rate

| Attribute | Definition |
|---|---|
| Formula | Customers from the starting active population who also purchase in the comparison period ÷ starting active population |
| Grain | Customer cohort |
| Date basis | Delivered-order periods |
| Required label | Must specify comparison, such as monthly, quarterly or annual retention |
| DAX measure | `Customer Retention Rate %` |
| Format | Percentage, one decimal |
| Zero denominator | Blank |

## 15. Store and employee KPIs

### KPI-041 — Store Net Revenue

| Attribute | Definition |
|---|---|
| Formula | `Net Revenue` attributed to the store that fulfilled the order |
| Grain | Store |
| Date basis | Delivered date |
| DAX measure | `Store Net Revenue` |
| Format | INR currency |

### KPI-042 — Revenue per Employee

| Attribute | Definition |
|---|---|
| Formula | Employee-attributed net revenue ÷ active processing employees in context |
| Attribution | Order-processing employee; does not imply sole causation of sale |
| Date basis | Delivered date with employee active-period controls |
| DAX measure | `Revenue per Employee` |
| Format | INR currency |
| Zero denominator | Blank |

For employee-ranking visuals, use employee net revenue directly. Use `Revenue per Employee` primarily for store/workforce normalization.

### KPI-043 — Orders per Employee

| Attribute | Definition |
|---|---|
| Formula | Distinct delivered orders ÷ active processing employees in context |
| Date basis | Delivered date |
| DAX measure | `Orders per Employee` |
| Format | Decimal, two places |
| Zero denominator | Blank |

## 16. Supplier KPIs

### KPI-044 — Supplier Revenue Contribution

| Attribute | Definition |
|---|---|
| Formula | Net revenue from products assigned to supplier ÷ total net revenue |
| Grain | Supplier/product/sales item |
| Date basis | Delivered date |
| DAX measure | `Supplier Revenue Contribution %` |
| Format | Percentage, one decimal |

The baseline uses each product's current primary supplier. Historical interpretation must disclose this limitation until effective-dated product-supplier assignments exist.

### KPI-045 — Supplier Return Rate

| Attribute | Definition |
|---|---|
| Formula | Accepted returned units for supplier products ÷ delivered units for supplier products |
| Grain | Supplier/product |
| Date basis | Delivered-order cohort |
| Excludes | Requested but rejected returns |
| DAX measure | `Supplier Return Rate %` |
| Format | Percentage, one decimal |

### KPI-046 — Supplier Inventory Exposure

| Attribute | Definition |
|---|---|
| Formula | Current inventory value at cost for products assigned to supplier |
| Grain | Supplier/product/store snapshot |
| Date basis | Current/as-of snapshot |
| DAX measure | `Supplier Inventory Exposure` |
| Format | INR currency |

## 17. Supporting measure catalogue

The following measures support core KPIs and drill-down analysis:

| Measure name | Definition | Format |
|---|---|---|
| `Accepted Returned Units` | Sum accepted return quantity | Whole number |
| `Requested Return Units` | Sum requested return quantity | Whole number |
| `Completed Payment Attempts` | Count attempts that completed successfully | Whole number |
| `Valid Payment Attempts` | Count valid attempts in approved attempt statuses | Whole number |
| `Completed Refund Count` | Count completed refund events | Whole number |
| `Orders with Accepted Returns` | Distinct orders with accepted return quantity | Whole number |
| `Inventory On Hand` | Sum current/snapshot on-hand quantity | Whole number |
| `Inventory Reserved` | Sum reserved quantity | Whole number |
| `Inventory Available` | On hand minus reserved | Whole number |
| `Stockout Combinations` | Count active product-store combinations with zero available | Whole number |
| `Average Inventory Value` | Average comparable periodic snapshot value | ₹ currency |
| `Net Revenue PY` | Net revenue in prior-year equivalent period | ₹ currency |
| `Gross Profit PY` | Gross profit in prior-year equivalent period | ₹ currency |
| `Net Units Sold PY` | Net units in prior-year equivalent period | Whole number |
| `Net Revenue YTD` | Net revenue from year start through selected date | ₹ currency |
| `Gross Profit YTD` | Gross profit from year start through selected date | ₹ currency |
| `Selected Period Label` | Human-readable active date range | Text |

## 18. DAX implementation patterns

The exact column names will be finalized with the analytical model, but measure behavior must follow these patterns.

### 18.1 Safe division

```DAX
Gross Margin % =
DIVIDE ( [Gross Profit], [Net Revenue] )
```

Do not provide an alternate result of zero unless zero is the approved business meaning.

### 18.2 Prior-year comparison

```DAX
Net Revenue PY =
CALCULATE (
    [Net Revenue],
    DATEADD ( 'Date'[Date], -1, YEAR )
)

Net Revenue YoY % =
DIVIDE (
    [Net Revenue] - [Net Revenue PY],
    [Net Revenue PY]
)
```

### 18.3 Contribution within selected context

```DAX
Net Revenue Contribution % =
DIVIDE (
    [Net Revenue],
    CALCULATE (
        [Net Revenue],
        REMOVEFILTERS ( Product[Product Name] )
    )
)
```

The production measure must remove only the intended contribution dimension and preserve selected dates, stores and other report filters.

### 18.4 Current inventory availability

```DAX
Inventory Available =
[Inventory On Hand] - [Inventory Reserved]
```

### 18.5 Dynamic selected-period label

```DAX
Selected Period Label =
VAR StartDate = MIN ( 'Date'[Date] )
VAR EndDate = MAX ( 'Date'[Date] )
RETURN
    FORMAT ( StartDate, "dd MMM yyyy" )
        & " – "
        & FORMAT ( EndDate, "dd MMM yyyy" )
```

## 19. SQL control-query rules

Each KPI must have an independent SQL control query or approved analytical view.

Rules:

- Use the same date role and inclusion filters as the DAX measure.
- Aggregate sales, payments, returns and refunds independently before combining.
- Never sum order header totals after joining to multiple order items.
- Never sum payments after joining to order items or returns.
- Never sum refunds after joining to multiple payments or return items.
- Use `COUNT_BIG` for high-volume row controls.
- Use `NULLIF` for ratio denominators.
- Use `DECIMAL`, not `FLOAT`, for financial calculations.
- Reconcile monetary totals within ₹0.01 and counts exactly.

Example control shape:

```sql
WITH SalesByOrder AS
(
    SELECT
        fs.SalesOrderID,
        SUM(fs.RecognizedRevenueAmount) AS RecognizedRevenueAmount
    FROM analytics.FactSales AS fs
    GROUP BY
        fs.SalesOrderID
),
RefundsByOrder AS
(
    SELECT
        fr.SalesOrderID,
        SUM(fr.CompletedPretaxRefundAmount) AS PretaxRefundAmount
    FROM analytics.FactRefunds AS fr
    GROUP BY
        fr.SalesOrderID
)
SELECT
    SUM(s.RecognizedRevenueAmount)
        - SUM(COALESCE(r.PretaxRefundAmount, 0)) AS NetRevenue
FROM SalesByOrder AS s
LEFT JOIN RefundsByOrder AS r
    ON r.SalesOrderID = s.SalesOrderID;
```

## 20. Dashboard-page KPI mapping

### Page 01 — Executive Summary

Primary KPIs:

- Net Revenue
- Gross Profit
- Gross Margin %
- Delivered Orders
- Average Order Value
- Active Customers
- Net Revenue YoY %
- Gross Profit YoY %

Supporting visuals should highlight sales trend, category/store contribution and major risk indicators without mixing booking, recognition and collection concepts.

### Page 02 — Sales Performance

Primary KPIs:

- Total Orders
- Gross Order Value
- Booked Order Value
- Net Revenue
- Average Order Value
- Order Cancellation Rate %
- Net Revenue Contribution %

### Page 03 — Customer Insights

Primary KPIs:

- Active Customers
- New Customers
- Repeat Customers
- Repeat Customer Rate %
- Purchase Frequency
- Customer Lifetime Value
- Customer Retention Rate %

### Page 04 — Product Performance

Primary KPIs:

- Net Revenue
- Net Units Sold
- COGS
- Gross Profit
- Gross Margin %
- Product Return Rate %
- Net Revenue Contribution %

### Page 05 — Inventory Management

Primary KPIs:

- Inventory On Hand
- Inventory Available
- Inventory Value at Cost
- Stockout Rate %
- Low Stock SKUs
- Excess Stock SKUs
- Inventory Turnover
- Sell-Through Rate %
- Days of Inventory

### Page 06 — Store & Employee Performance

Primary KPIs:

- Store Net Revenue
- Delivered Orders
- Gross Profit
- Gross Margin %
- Revenue per Employee
- Orders per Employee
- Order Cancellation Rate %

### Page 07 — Returns & Payments

Primary KPIs:

- Completed Payment Value
- Net Cash Collection
- Payment Success Rate %
- Failed Payment Attempts
- Payment Retry Success Rate %
- Gross Refund Value
- Refund Rate %
- Return Rate by Quantity %
- Return Rate by Orders %
- Reusable Return Rate %

### Page 08 — Supplier Analysis

Primary KPIs:

- Supplier Revenue Contribution %
- Supplier Return Rate %
- Supplier Inventory Exposure
- Net Revenue
- Gross Profit
- Inventory Value at Cost

## 21. Number-format standards

| Metric type | Recommended format |
|---|---|
| INR currency cards | `₹#,0;[Red]-₹#,0` with display units as appropriate |
| INR detailed tables | `₹#,0.00;[Red]-₹#,0.00` |
| Whole-number counts | `#,0` |
| Rates/percentages | `0.0%` |
| Averages/frequency | `0.00` |
| Inventory turnover | `0.00×` |
| Days | `0.0` plus label/suffix |
| Large card units | Use consistent K/M/Cr convention across pages |

Do not mix lakh/crore and K/M notation within the same report unless the display policy explicitly changes for the target audience.

## 22. Blank, zero and negative-value policy

| Situation | Required behavior |
|---|---|
| No underlying activity | Count may display `0`; monetary measure may display blank or `₹0` according to page context |
| Ratio denominator is zero/missing | Return blank |
| Prior-year period unavailable | Growth measure returns blank |
| Negative profit/margin | Display the actual negative value with warning color; do not clamp to zero |
| Negative net cash due to refund timing | Display actual value with clear cash-flow label |
| Missing dimension attribute | Display `Unknown` through governed unknown member |

## 23. Filter-behavior policy

- Date filters use the metric's documented date role.
- Store filters represent fulfilling store for sales and physical location for inventory.
- Product/category/brand filters propagate through the Product dimension.
- Supplier filters use the baseline primary-supplier attribution and must disclose that limitation.
- Order-status filters should not silently alter payment or refund populations unless the report intentionally applies that business context.
- Selecting a return reason should filter return metrics, but should not redefine the denominator of delivered sales unless the visual explicitly shows reason-specific cohorts.
- Contribution measures remove only the relevant comparison dimension, not all report filters.

## 24. KPI validation matrix

| KPI group | SQL control | Power BI check | Tolerance |
|---|---|---|---:|
| Order counts | Operational/FactSales distinct order control | Card and matrix totals | Exact |
| Units | Delivered and accepted-return quantities | Product totals | Exact |
| Revenue | FactSales plus pretax refund allocation | Net Revenue measures | ₹0.01 |
| COGS/profit | Transaction cost and reusable-return adjustment | Profit measures | ₹0.01 |
| Payments | FactPayments at attempt grain | Payment cards | ₹0.01/count exact |
| Refunds | FactRefunds at event grain | Refund cards | ₹0.01 |
| Inventory | Snapshot and movement reconciliation | Current inventory cards | Exact/₹0.01 |
| Customer counts | Delivered-order customer population | Customer cards/cohorts | Exact |
| Ratios | Independently verified numerator/denominator | DAX ratio | 0.01 percentage point |

Required validation filter sets:

1. Full reporting period
2. Each fiscal/calendar year
3. One representative month
4. One store
5. One category and product
6. One customer segment
7. One payment method
8. One return reason where applicable

## 25. KPI governance

Before adding or changing a KPI:

- [ ] Assign a unique KPI ID and approved measure name.
- [ ] Identify the natural grain and authoritative fact.
- [ ] Define the date role.
- [ ] Define numerator and denominator separately for ratios.
- [ ] Document inclusions and exclusions.
- [ ] Specify tax, discount, return and refund treatment.
- [ ] Define blank and zero behavior.
- [ ] Add an independent SQL control query.
- [ ] Add the DAX measure, description, format and display folder.
- [ ] Map the KPI to dashboard pages.
- [ ] Add SQL-to-DAX reconciliation tests.
- [ ] Update affected business rules and README claims.

Metric definitions must not be changed only to make a visual look better or to force a preferred business story.

## 26. Known modelling limitations

| Limitation | KPI impact | Required disclosure/future fix |
|---|---|---|
| One current supplier per product | Historical supplier contribution may reflect current assignment | Disclose; add effective-dated bridge later |
| One current store per employee | Historical workforce normalization may miss transfers | Disclose; add assignment history later |
| Refund table stores total amount only | Pretax/tax refund split must be allocated in analytics | Persist allocation in analytical fact/view |
| Current product cost used for inventory value | Historical snapshot valuation requires stored snapshot cost | Store cost in snapshot fact |
| No operating-expense model | Gross Profit is not operating or net profit | Use precise label |
| Synthetic data | KPI findings are scenario insights, not real company results | Display synthetic-data disclosure |

## 27. Portfolio evidence checklist

- [ ] All 50 catalogue KPIs have unique IDs and measure names.
- [ ] The 18 authoritative business measures from `02_Business_Rules.md` are represented.
- [ ] Revenue, collection and booking metrics are clearly distinguished.
- [ ] Tax treatment is documented.
- [ ] Return and refund timing is documented.
- [ ] COGS uses transaction cost and reusable-return logic.
- [ ] Every ratio defines numerator, denominator and zero behavior.
- [ ] Default date role is defined for every metric family.
- [ ] Dashboard pages use only governed measures.
- [ ] SQL control totals reconcile with DAX within approved tolerance.
- [ ] Measure descriptions and display folders are populated in Power BI.
- [ ] Synthetic-data and modelling limitations are disclosed.

---

## 28. Next deliverable

The next project document should be:

```text
12_Power_BI_Dashboard_Requirements.md
```

It should define the eight dashboard pages, audience, analytical questions, KPIs, visuals, slicers, drillthrough, tooltips, navigation, accessibility, layout standards and page-level acceptance criteria.
