# DAX Measure Library

## Retail Sales & Inventory Intelligence Platform

**Power BI file:** `Retail_Sales_Inventory_Intelligence_Dashboard.pbix`  
**Measure home table:** `_Measures`  
**Model:** Twelve dimensions, six facts, single-direction star schema  
**Prerequisite:** Complete `41_PowerBI_Connection_Guide.md`

---

## Implementation reconciliation notes — review before copying measures

This document is a **DAX reference library**, not a certified export of the measures currently present in the PBIX. The original formulas below are retained for traceability; verify names, data types, relationships, and filter context against the final report before replacing existing working measures.

- The final report has eight pages: **Executive Overview, Sales Performance, Customer Analysis, Product Analysis, Store Performance, Inventory Analysis, Returns Analysis, Payment Analysis**.
- The current implementation previously used **distinct delivered order IDs** (`DISTINCTCOUNT` of the order identifier with `IsDelivered = TRUE()`). The template `[Delivered Orders] = CALCULATE([Total Orders], ...)` below instead sums `FactSales[OrderCount]`. These are **not proven equivalent**: `FactSales` has one row per order item. Validate the `OrderCount` helper's semantics before using the template, and do not overwrite a reconciled PBIX measure merely to match this guide.
- Likewise `[Total Orders]` based on `SUM(FactSales[OrderCount])` must be reconciled to a distinct order count; otherwise AOV, delivery rate, repeat-customer metrics, and rankings may be affected.
- For monthly revenue, check whether the active `OrderDateKey` relationship or an inactive `DeliveredDateKey` relationship is intended. SQL `pbi_SalesTrend` uses its own calendar-activity attribution; an order-date DAX trend is **not automatically comparable**.
- `[Net Revenue]` subtracts completed refunds from recognized revenue, but refund dates may differ from delivery dates. Compare under the same date role and financial-year context.
- Inventory measures refer to the available snapshot, not historical stock levels across every FY. Do not add a Financial Year slicer to the Inventory page without a verified date-aware model.
- Payment Analysis uses **unsynchronized** slicers; the Returns Analysis page has a **FY2026–27 page filter** according to the recorded design. These are report settings, not encoded by the formulas alone.
- SQL-side 15/15 reporting validation does **not** prove that every DAX formula or Power BI interaction has passed UAT.

## 1. Measure design rules

1. Create all explicit measures in the `_Measures` table.
2. Use fact-table additive helpers such as `OrderCount`, `LineCount`, `AttemptCount`, and `RefundCount` through measures only.
3. Do not drag raw monetary columns directly into visuals.
4. Use `DIVIDE()` instead of the `/` operator for business ratios.
5. Return `BLANK()` when a denominator has no meaningful business population.
6. Use the marked `DimDate[Date]` column for time intelligence.
7. Keep base measures simple; build derived measures by referencing base measures.
8. Store rates as decimals and format them as percentages in Power BI.
9. Do not create calculated columns when a measure can produce the required result.
10. Reconcile major measures with the `analytics.pbi_*` SQL views.

---

## 2. Recommended display folders

```text
01 Executive KPIs
02 Sales
03 Time Intelligence
04 Customers
05 Products
06 Stores & Employees
07 Inventory
08 Returns & Refunds
09 Payments
10 Data Quality
```

---

## 3. Executive and sales base measures

Create these first because later measures depend on them.

### Total Orders

```DAX
Total Orders =
SUM ( FactSales[OrderCount] )
```

Format: `#,0`

### Delivered Orders

```DAX
Delivered Orders =
CALCULATE (
    [Total Orders],
    FactSales[IsDelivered] = TRUE ()
)
```

### Cancelled Orders

```DAX
Cancelled Orders =
CALCULATE (
    [Total Orders],
    FactSales[IsCancelled] = TRUE ()
)
```

### Open Orders

```DAX
Open Orders =
[Total Orders] - [Delivered Orders] - [Cancelled Orders]
```

### Total Order Lines

```DAX
Total Order Lines =
SUM ( FactSales[LineCount] )
```

### Ordered Units

```DAX
Ordered Units =
SUM ( FactSales[Quantity] )
```

### Delivered Units

```DAX
Delivered Units =
CALCULATE (
    [Ordered Units],
    FactSales[IsDelivered] = TRUE ()
)
```

### Booked Order Value

```DAX
Booked Order Value =
SUM ( FactSales[NetAmount] )
```

### Gross Sales Value

```DAX
Gross Sales Value =
SUM ( FactSales[GrossAmount] )
```

### Discount Value

```DAX
Discount Value =
SUM ( FactSales[DiscountAmount] )
```

### Tax Value

```DAX
Tax Value =
SUM ( FactSales[TaxAmount] )
```

### Recognized Revenue

```DAX
Recognized Revenue =
SUM ( FactSales[RecognizedRevenueAmount] )
```

### Recognized COGS

```DAX
Recognized COGS =
SUM ( FactSales[RecognizedCostAmount] )
```

### Recognized Gross Profit

```DAX
Recognized Gross Profit =
SUM ( FactSales[RecognizedGrossProfitAmount] )
```

### Gross Margin Rate

```DAX
Gross Margin Rate =
DIVIDE ( [Recognized Gross Profit], [Recognized Revenue] )
```

Format: `0.00%`

### Delivery Rate

```DAX
Delivery Rate =
DIVIDE ( [Delivered Orders], [Total Orders] )
```

### Cancellation Rate

```DAX
Cancellation Rate =
DIVIDE ( [Cancelled Orders], [Total Orders] )
```

### Average Order Value

```DAX
Average Order Value =
DIVIDE ( [Net Revenue], [Delivered Orders] )
```

### Average Selling Price

```DAX
Average Selling Price =
DIVIDE ( [Recognized Revenue], [Delivered Units] )
```

### Discount Rate

```DAX
Discount Rate =
DIVIDE ( [Discount Value], [Gross Sales Value] )
```

---

## 4. Time-intelligence measures

These measures use the active relationship between `DimDate[DateKey]` and `FactSales[OrderDateKey]`.

### Revenue Previous Month

```DAX
Revenue Previous Month =
CALCULATE (
    [Recognized Revenue],
    DATEADD ( DimDate[Date], -1, MONTH )
)
```

### Revenue Month-over-Month Change

```DAX
Revenue MoM Change =
[Recognized Revenue] - [Revenue Previous Month]
```

### Revenue Month-over-Month Growth

```DAX
Revenue MoM Growth =
DIVIDE ( [Revenue MoM Change], [Revenue Previous Month] )
```

### Revenue Previous Year

```DAX
Revenue Previous Year =
CALCULATE (
    [Recognized Revenue],
    SAMEPERIODLASTYEAR ( DimDate[Date] )
)
```

### Revenue Year-over-Year Change

```DAX
Revenue YoY Change =
[Recognized Revenue] - [Revenue Previous Year]
```

### Revenue Year-over-Year Growth

```DAX
Revenue YoY Growth =
DIVIDE ( [Revenue YoY Change], [Revenue Previous Year] )
```

### Revenue Calendar YTD

```DAX
Revenue Calendar YTD =
TOTALYTD (
    [Recognized Revenue],
    DimDate[Date]
)
```

### Revenue Financial YTD

The project uses the Indian financial year ending 31 March.

```DAX
Revenue Financial YTD =
TOTALYTD (
    [Recognized Revenue],
    DimDate[Date],
    "3/31"
)
```

### Rolling 3-Month Revenue

```DAX
Rolling 3M Revenue =
VAR LastVisibleDate = MAX ( DimDate[Date] )
RETURN
    CALCULATE (
        [Recognized Revenue],
        DATESINPERIOD ( DimDate[Date], LastVisibleDate, -3, MONTH )
    )
```

### Rolling 12-Month Revenue

```DAX
Rolling 12M Revenue =
VAR LastVisibleDate = MAX ( DimDate[Date] )
RETURN
    CALCULATE (
        [Recognized Revenue],
        DATESINPERIOD ( DimDate[Date], LastVisibleDate, -12, MONTH )
    )
```

### Delivered Revenue by Delivery Date

Use the inactive delivery-date relationship.

```DAX
Revenue by Delivery Date =
CALCULATE (
    [Recognized Revenue],
    USERELATIONSHIP ( DimDate[DateKey], FactSales[DeliveredDateKey] )
)
```

### Delivered Orders by Delivery Date

```DAX
Delivered Orders by Delivery Date =
CALCULATE (
    [Delivered Orders],
    USERELATIONSHIP ( DimDate[DateKey], FactSales[DeliveredDateKey] )
)
```

---

## 5. Customer measures

### Active Customers

```DAX
Active Customers =
CALCULATE (
    DISTINCTCOUNT ( FactSales[CustomerKey] ),
    FactSales[CustomerKey] <> 0
)
```

### Purchasing Customers

```DAX
Purchasing Customers =
CALCULATE (
    DISTINCTCOUNT ( FactSales[CustomerKey] ),
    FactSales[IsDelivered] = TRUE (),
    FactSales[CustomerKey] <> 0
)
```

### Revenue per Customer

```DAX
Revenue per Customer =
DIVIDE ( [Recognized Revenue], [Purchasing Customers] )
```

### Orders per Customer

```DAX
Orders per Customer =
DIVIDE ( [Delivered Orders], [Purchasing Customers] )
```

### Repeat Customers

```DAX
Repeat Customers =
COUNTROWS (
    FILTER (
        VALUES ( DimCustomer[CustomerKey] ),
        CALCULATE ( [Delivered Orders] ) >= 2
    )
)
```

### Repeat Customer Rate

```DAX
Repeat Customer Rate =
DIVIDE ( [Repeat Customers], [Purchasing Customers] )
```

### Customer Revenue Rank

```DAX
Customer Revenue Rank =
RANKX (
    ALLSELECTED ( DimCustomer[CustomerCode] ),
    [Recognized Revenue],
    ,
    DESC,
    DENSE
)
```

### Days Since Last Order

```DAX
Days Since Last Order =
VAR LastOrderDateKey =
    CALCULATE (
        MAX ( FactSales[OrderDateKey] ),
        REMOVEFILTERS ( DimDate )
    )
VAR ModelAsOfDateKey =
    CALCULATE (
        MAX ( FactSales[OrderDateKey] ),
        REMOVEFILTERS ( DimDate ),
        REMOVEFILTERS ( DimCustomer )
    )
VAR LastOrderDate =
    IF (
        NOT ISBLANK ( LastOrderDateKey ),
        DATE (
            QUOTIENT ( LastOrderDateKey, 10000 ),
            QUOTIENT ( MOD ( LastOrderDateKey, 10000 ), 100 ),
            MOD ( LastOrderDateKey, 100 )
        )
    )
VAR ModelAsOfDate =
    IF (
        NOT ISBLANK ( ModelAsOfDateKey ),
        DATE (
            QUOTIENT ( ModelAsOfDateKey, 10000 ),
            QUOTIENT ( MOD ( ModelAsOfDateKey, 10000 ), 100 ),
            MOD ( ModelAsOfDateKey, 100 )
        )
    )
RETURN
    IF (
        NOT ISBLANK ( LastOrderDate ),
        DATEDIFF ( LastOrderDate, ModelAsOfDate, DAY )
    )
```

Use this measure only in a customer-filtered visual. The model date—not today's system date—is used so the portfolio remains reproducible.

---

## 6. Product measures

### Selling Products

```DAX
Selling Products =
CALCULATE (
    DISTINCTCOUNT ( FactSales[ProductKey] ),
    FactSales[IsDelivered] = TRUE (),
    FactSales[ProductKey] <> 0
)
```

### Product Revenue Rank

```DAX
Product Revenue Rank =
RANKX (
    ALLSELECTED ( DimProduct[SKU] ),
    [Recognized Revenue],
    ,
    DESC,
    DENSE
)
```

### Product Profit Rank

```DAX
Product Profit Rank =
RANKX (
    ALLSELECTED ( DimProduct[SKU] ),
    [Recognized Gross Profit],
    ,
    DESC,
    DENSE
)
```

### Revenue Contribution Rate

```DAX
Revenue Contribution Rate =
DIVIDE (
    [Recognized Revenue],
    CALCULATE (
        [Recognized Revenue],
        ALLSELECTED ( DimProduct )
    )
)
```

### Product Performance Band

```DAX
Product Performance Band =
VAR RevenueValue = [Recognized Revenue]
VAR MarginValue = [Gross Margin Rate]
VAR AverageRevenue =
    AVERAGEX (
        ALLSELECTED ( DimProduct[ProductKey] ),
        [Recognized Revenue]
    )
VAR AverageMargin =
    AVERAGEX (
        ALLSELECTED ( DimProduct[ProductKey] ),
        [Gross Margin Rate]
    )
RETURN
    SWITCH (
        TRUE (),
        RevenueValue >= AverageRevenue && MarginValue >= AverageMargin, "Star",
        RevenueValue >= AverageRevenue, "Volume Driver",
        MarginValue >= AverageMargin, "Niche Profit",
        "Review"
    )
```

---

## 7. Store and employee measures

### Selling Stores

```DAX
Selling Stores =
CALCULATE (
    DISTINCTCOUNT ( FactSales[StoreKey] ),
    FactSales[StoreKey] <> 0
)
```

### Revenue per Store

```DAX
Revenue per Store =
DIVIDE ( [Recognized Revenue], [Selling Stores] )
```

### Store Revenue Rank

```DAX
Store Revenue Rank =
RANKX (
    ALLSELECTED ( DimStore[StoreCode] ),
    [Recognized Revenue],
    ,
    DESC,
    DENSE
)
```

### Selling Employees

```DAX
Selling Employees =
CALCULATE (
    DISTINCTCOUNT ( FactSales[EmployeeKey] ),
    FactSales[EmployeeKey] <> 0
)
```

### Revenue per Employee

```DAX
Revenue per Employee =
DIVIDE ( [Recognized Revenue], [Selling Employees] )
```

### Employee Revenue Rank

```DAX
Employee Revenue Rank =
RANKX (
    ALLSELECTED ( DimEmployee[EmployeeCode] ),
    [Recognized Revenue],
    ,
    DESC,
    DENSE
)
```

---

## 8. Inventory measures

### Quantity on Hand

```DAX
Quantity on Hand =
SUM ( FactInventorySnapshot[QuantityOnHand] )
```

### Quantity Reserved

```DAX
Quantity Reserved =
SUM ( FactInventorySnapshot[QuantityReserved] )
```

### Quantity Available

```DAX
Quantity Available =
SUM ( FactInventorySnapshot[QuantityAvailable] )
```

### Inventory Cost Value

```DAX
Inventory Cost Value =
SUM ( FactInventorySnapshot[StockCostValue] )
```

### Inventory Retail Value

```DAX
Inventory Retail Value =
SUM ( FactInventorySnapshot[StockRetailValue] )
```

### Potential Inventory Margin

```DAX
Potential Inventory Margin =
[Inventory Retail Value] - [Inventory Cost Value]
```

### Inventory Availability Rate

```DAX
Inventory Availability Rate =
DIVIDE ( [Quantity Available], [Quantity on Hand] )
```

### Stockout Product-Store Count

```DAX
Stockout Product-Store Count =
CALCULATE (
    SUM ( FactInventorySnapshot[SnapshotRowCount] ),
    FactInventorySnapshot[IsOutOfStock] = TRUE ()
)
```

### Low-Stock Product-Store Count

```DAX
Low-Stock Product-Store Count =
CALCULATE (
    SUM ( FactInventorySnapshot[SnapshotRowCount] ),
    FactInventorySnapshot[IsBelowReorderLevel] = TRUE ()
)
```

### Excess-Stock Product-Store Count

```DAX
Excess-Stock Product-Store Count =
CALCULATE (
    SUM ( FactInventorySnapshot[SnapshotRowCount] ),
    FactInventorySnapshot[IsExcessStock] = TRUE ()
)
```

### Stockout Rate

```DAX
Stockout Rate =
DIVIDE (
    [Stockout Product-Store Count],
    SUM ( FactInventorySnapshot[SnapshotRowCount] )
)
```

### Sell-Through Rate

```DAX
Sell-Through Rate =
DIVIDE (
    [Delivered Units],
    [Delivered Units] + [Quantity on Hand]
)
```

### Inventory Turnover Proxy

```DAX
Inventory Turnover Proxy =
DIVIDE ( [Recognized COGS], [Inventory Cost Value] )
```

This is a current-balance proxy because the model stores a current inventory snapshot, not daily average inventory. Label it clearly; do not claim it is GAAP average-inventory turnover.

### Inventory Inflow Units

```DAX
Inventory Inflow Units =
SUM ( FactInventoryMovement[InflowQuantity] )
```

### Inventory Outflow Units

```DAX
Inventory Outflow Units =
SUM ( FactInventoryMovement[OutflowQuantity] )
```

### Net Inventory Movement Units

```DAX
Net Inventory Movement Units =
SUM ( FactInventoryMovement[SignedQuantity] )
```

---

## 9. Return and refund measures

### Return Requests

```DAX
Return Requests =
DISTINCTCOUNT ( FactReturns[ProductReturnID] )
```

### Requested Return Units

```DAX
Requested Return Units =
SUM ( FactReturns[QuantityRequested] )
```

### Accepted Return Units

```DAX
Accepted Return Units =
SUM ( FactReturns[QuantityAccepted] )
```

### Rejected Return Units

```DAX
Rejected Return Units =
SUM ( FactReturns[QuantityRejected] )
```

### Reusable Return Units

```DAX
Reusable Return Units =
CALCULATE (
    [Accepted Return Units],
    FactReturns[IsReusable] = TRUE ()
)
```

### Eligible Refund Value

```DAX
Eligible Refund Value =
SUM ( FactReturns[EligibleRefundAmount] )
```

### Unit Return Rate

```DAX
Unit Return Rate =
DIVIDE ( [Accepted Return Units], [Delivered Units] )
```

### Return Acceptance Rate

```DAX
Return Acceptance Rate =
DIVIDE ( [Accepted Return Units], [Requested Return Units] )
```

### Return Reusability Rate

```DAX
Return Reusability Rate =
DIVIDE ( [Reusable Return Units], [Accepted Return Units] )
```

### Refund Events

```DAX
Refund Events =
SUM ( FactRefunds[RefundCount] )
```

### Completed Refund Value

```DAX
Completed Refund Value =
SUM ( FactRefunds[CompletedRefundAmount] )
```

### Pending Refund Value

```DAX
Pending Refund Value =
SUM ( FactRefunds[PendingRefundAmount] )
```

### Failed Refund Value

```DAX
Failed Refund Value =
SUM ( FactRefunds[FailedRefundAmount] )
```

### Refund Completion Rate

```DAX
Refund Completion Rate =
DIVIDE (
    [Completed Refund Value],
    [Completed Refund Value] + [Pending Refund Value] + [Failed Refund Value]
)
```

### Net Revenue

```DAX
Net Revenue =
[Recognized Revenue] - [Completed Refund Value]
```

### Net Revenue Margin

```DAX
Net Revenue Margin =
DIVIDE ( [Recognized Gross Profit] - [Completed Refund Value], [Net Revenue] )
```

The net-revenue margin is a portfolio analytical measure. It treats completed refunds as a direct reduction to profit and should be described as an analytical convention, not an accounting statement.

---

## 10. Payment measures

### Payment Attempts

```DAX
Payment Attempts =
SUM ( FactPayments[AttemptCount] )
```

### Successful Payment Attempts

```DAX
Successful Payment Attempts =
CALCULATE (
    [Payment Attempts],
    FactPayments[IsSuccessful] = TRUE ()
)
```

### Failed Payment Attempts

```DAX
Failed Payment Attempts =
CALCULATE (
    [Payment Attempts],
    FactPayments[IsFailed] = TRUE ()
)
```

### Pending Payment Attempts

```DAX
Pending Payment Attempts =
CALCULATE (
    [Payment Attempts],
    FactPayments[IsPending] = TRUE ()
)
```

### Attempted Payment Value

```DAX
Attempted Payment Value =
SUM ( FactPayments[Amount] )
```

### Collected Value

```DAX
Collected Value =
SUM ( FactPayments[CollectedAmount] )
```

### Payment Success Rate

```DAX
Payment Success Rate =
DIVIDE ( [Successful Payment Attempts], [Payment Attempts] )
```

### Payment Failure Rate

```DAX
Payment Failure Rate =
DIVIDE ( [Failed Payment Attempts], [Payment Attempts] )
```

### Collection Rate

```DAX
Collection Rate =
DIVIDE ( [Collected Value], [Attempted Payment Value] )
```

### Orders with Successful Payment

```DAX
Orders with Successful Payment =
CALCULATE (
    DISTINCTCOUNT ( FactPayments[SalesOrderID] ),
    FactPayments[IsSuccessful] = TRUE ()
)
```

### Average Attempts per Paid Order

```DAX
Average Attempts per Paid Order =
DIVIDE ( [Payment Attempts], [Orders with Successful Payment] )
```

---

## 11. Role-playing return and payment dates

Use these only after the inactive relationships from `DimDate` have been created.

### Returns by Approval Date

```DAX
Accepted Units by Approval Date =
CALCULATE (
    [Accepted Return Units],
    USERELATIONSHIP ( DimDate[DateKey], FactReturns[ApprovedDateKey] )
)
```

### Returns by Received Date

```DAX
Accepted Units by Received Date =
CALCULATE (
    [Accepted Return Units],
    USERELATIONSHIP ( DimDate[DateKey], FactReturns[ReceivedDateKey] )
)
```

### Returns by Closed Date

```DAX
Accepted Units by Closed Date =
CALCULATE (
    [Accepted Return Units],
    USERELATIONSHIP ( DimDate[DateKey], FactReturns[ClosedDateKey] )
)
```

The active return relationship should remain `RequestDateKey`. `PaymentDateKey`, `RefundDateKey`, `MovementDateKey`, and `SnapshotDateKey` are active for their respective facts.

---

## 12. Data-quality and reconciliation measures

Import the eight SQL control views before creating these measures.

### SQL Executive Revenue

```DAX
SQL Executive Revenue =
MAX ( pbi_ExecutiveSummary[RecognizedRevenue] )
```

### Revenue Reconciliation Difference

```DAX
Revenue Reconciliation Difference =
[Recognized Revenue] - [SQL Executive Revenue]
```

### SQL Executive Orders

```DAX
SQL Executive Orders =
MAX ( pbi_ExecutiveSummary[TotalOrders] )
```

### Order Reconciliation Difference

```DAX
Order Reconciliation Difference =
[Total Orders] - [SQL Executive Orders]
```

### SQL Inventory Cost Value

```DAX
SQL Inventory Cost Value =
MAX ( pbi_ExecutiveSummary[StockCostValue] )
```

### Inventory Reconciliation Difference

```DAX
Inventory Reconciliation Difference =
[Inventory Cost Value] - [SQL Inventory Cost Value]
```

### Model Validation Status

```DAX
Model Validation Status =
VAR RevenueDifference = ABS ( [Revenue Reconciliation Difference] )
VAR OrderDifference = ABS ( [Order Reconciliation Difference] )
VAR InventoryDifference = ABS ( [Inventory Reconciliation Difference] )
RETURN
    IF (
        RevenueDifference < 0.01
            && OrderDifference = 0
            && InventoryDifference < 0.01,
        "PASSED",
        "REVIEW"
    )
```

Use this status on a hidden QA page or small report footer, not as a replacement for SQL validation scripts.

---

## 13. Dynamic titles

### Selected Period Title

```DAX
Selected Period Title =
VAR MinimumDate = MIN ( DimDate[Date] )
VAR MaximumDate = MAX ( DimDate[Date] )
RETURN
    "Period: "
        & FORMAT ( MinimumDate, "dd MMM yyyy" )
        & " - "
        & FORMAT ( MaximumDate, "dd MMM yyyy" )
```

### Selected Store Title

```DAX
Selected Store Title =
"Store: "
    & COALESCE ( SELECTEDVALUE ( DimStore[StoreName] ), "All Stores" )
```

### Selected Category Title

```DAX
Selected Category Title =
"Category: "
    & COALESCE ( SELECTEDVALUE ( DimProduct[CategoryName] ), "All Categories" )
```

---

## 14. Recommended formatting

| Measure type | Format |
|---|---|
| Currency values | `₹#,0.00;[Red]-₹#,0.00` |
| Large card currency | Use visual display units: Auto/Millions |
| Counts and quantities | `#,0` |
| Rates | `0.00%` |
| Rankings | `0` |
| Decimal averages | `0.00` |
| Days | `0` |

Do not use `FORMAT()` on numeric KPI measures because it converts numbers to text. Use model formatting or dynamic format strings instead.

---

## 15. Measure validation sequence

Validate measures in this order:

1. `Total Orders`
2. `Recognized Revenue`
3. `Recognized Gross Profit`
4. `Completed Refund Value`
5. `Net Revenue`
6. `Payment Attempts`
7. `Accepted Return Units`
8. `Quantity on Hand`
9. `Inventory Cost Value`
10. `Model Validation Status`

Compare the values with:

```sql
SELECT *
FROM analytics.pbi_ExecutiveSummary;
```

The reconciliation differences should be zero.

---

## 16. Common DAX mistakes to avoid

- Using `COUNTROWS(FactSales)` as total orders when the fact grain is order item.
- Using booked `NetAmount` as recognized revenue without applying delivery status.
- Subtracting pending or failed refunds from net revenue.
- Creating one giant measure instead of reusable base measures.
- Using calculated columns for dynamic rankings or time intelligence.
- Using `TODAY()` for historical portfolio recency calculations.
- Enabling bidirectional relationships to fix an incorrect model.
- Calculating percentages by averaging row-level percentages.
- Ignoring inactive role-playing date relationships.
- Comparing DAX results only visually without SQL control totals.

---

## 17. Interview explanation

> I built reusable DAX measures on top of a validated SQL Server star schema. I separated base measures from derived KPIs, used inactive relationships with `USERELATIONSHIP` for lifecycle dates, implemented Indian financial-year time intelligence, and reconciled executive DAX measures with SQL control views. I also documented analytical assumptions for measures such as inventory-turnover proxy and net-revenue margin.

---

## Next deliverable

```text
43_PowerBI_Dashboard_Blueprint.md
```

It will define the page layout, visuals, slicers, navigation, drill-through, tooltips, and storytelling sequence for the eight-page portfolio dashboard.
