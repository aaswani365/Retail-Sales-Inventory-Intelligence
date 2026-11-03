# Retail Sales & Inventory Intelligence Platform

## Business Requirements Document

| Document attribute | Value |
|---|---|
| Project name | Retail Sales & Inventory Intelligence Platform |
| Project version | 2.0 |
| Document | 01_Business_Requirements.md |
| Author | Akshay Aswani |
| Database platform | Microsoft SQL Server |
| Reporting platform | Microsoft Power BI |
| Project type | End-to-end data analytics portfolio project |
| Status | Approved baseline for design |

---

## 1. Executive summary

The Retail Sales & Inventory Intelligence Platform is an end-to-end analytics solution for a multi-store retail company. The company currently operates through disconnected operational reports that make it difficult to obtain a consistent view of sales, customers, products, inventory, stores, employees, suppliers, payments and returns.

The project will create a reliable SQL Server database for operational data, a governed analytical layer for reporting, and a multi-page Power BI dashboard for decision-makers. It will provide consistent KPI definitions, enforce data-quality rules, reconcile commercial transactions and enable management to identify revenue opportunities, operational risks and areas requiring corrective action.

The solution is intended to demonstrate professional skills in requirements analysis, relational database design, T-SQL development, data generation, validation, dimensional modelling, performance optimization, Power BI modelling, DAX and business storytelling.

## 2. Business background

The organization operates multiple physical retail stores across different cities and sells products from multiple categories, brands and suppliers. Each store employs sales personnel, maintains product-level inventory and processes customer orders and payments. Delivered products may later be returned and refunded according to business rules.

Management requires a single analytical solution because existing reporting does not reliably answer questions such as:

- Is the business growing profitably?
- Which stores, products, categories and brands drive revenue and margin?
- Which customers create the greatest long-term value?
- Where are stockouts, excess inventory and replenishment risks occurring?
- Which payment methods have the highest success or failure rates?
- Which products and suppliers contribute disproportionately to returns?
- Which employees and stores are performing above or below expectations?
- How do refunds and returns affect recognized revenue and profit?

## 3. Problem statement

The organization lacks a governed and integrated data platform capable of connecting operational transactions with management reporting. Key business measures are calculated inconsistently, transactional relationships are not fully validated, and direct reporting from normalized operational tables can create duplicate or inflated totals.

Without a trusted analytical model, management may make decisions using inaccurate revenue, payment, inventory or return figures. The company therefore requires a solution that establishes one version of truth and clearly separates operational records from analytical reporting structures.

## 4. Project objectives

The project will:

1. Build a normalized SQL Server operational database covering the complete retail lifecycle.
2. Enforce referential integrity and business rules through constraints, controlled procedures and set-based triggers where appropriate.
3. Generate realistic, reproducible retail data over a fixed reporting period.
4. Implement automated schema, relationship, transaction and financial reconciliation tests.
5. Create a Power BI-ready analytical layer using dimensional modelling principles.
6. Establish authoritative definitions for revenue, profit, payments, returns and inventory KPIs.
7. Develop a multi-page Power BI dashboard supporting executive, commercial and operational decisions.
8. Document the complete solution so another analyst can deploy, validate and understand it.

## 5. Stakeholders and information needs

| Stakeholder | Primary information needs |
|---|---|
| Executive leadership | Revenue, profit, growth, business health, risks and strategic opportunities |
| Sales management | Sales trends, store performance, average order value and employee productivity |
| Marketing and customer teams | Customer value, segmentation, retention, frequency and purchasing behaviour |
| Product/category management | Product, category and brand contribution, profitability and product affinity |
| Inventory operations | Stock availability, stockouts, excess stock, inventory value and reorder priorities |
| Finance | Recognized revenue, collected payments, outstanding payments, refunds and margin |
| Store managers | Store performance, employee results, inventory availability and returns |
| Supplier management | Supplier contribution, dependency, product quality and return exposure |
| Data analysts | Trusted reporting views, dimensional data and consistent KPI definitions |
| Database administrators | Deployable scripts, integrity controls, indexing, validation and maintenance processes |

## 6. Project scope

### 6.1 In scope

- Store, employee, customer, supplier and product master data
- Product categories, subcategories and brands
- Sales orders and sales-order items
- Order lifecycle and status tracking
- Payment attempts, methods and statuses
- Product returns, returned items and refund information
- Store-level inventory balances
- Inventory movement audit history
- Referential, domain and financial integrity controls
- Reproducible synthetic-data generation
- Analytical dimensions and fact datasets
- Business KPI catalogue
- SQL views, procedures and reusable reporting datasets
- Power BI semantic model, DAX measures and multi-page dashboard
- Technical documentation, data dictionary, ER diagram and case study
- Query performance review for major dashboard workloads

### 6.2 Out of scope

- Real customer or personally identifiable production data
- E-commerce website or point-of-sale application development
- Real payment-gateway integration
- Supplier purchase-order and invoice processing
- Payroll, attendance and human-resources administration
- Tax filing, statutory accounting or full general-ledger functionality
- Predictive machine-learning deployment in the initial release
- Real-time streaming and enterprise-scale cloud deployment
- Row-level security implementation unless added as a documented enhancement

## 7. Business process overview

The solution will represent the following process:

1. Products are supplied by approved suppliers and assigned to categories, subcategories and brands.
2. Products are stocked at one or more stores.
3. A customer places an order at a store.
4. A store employee processes the order.
5. One or more unique products are added to the order.
6. The system validates available inventory.
7. A payment attempt is recorded with its method and status.
8. The order progresses through confirmation, processing, shipping and delivery, or is cancelled.
9. Delivered products may be submitted for return.
10. Approved returns may generate refunds and valid inventory restoration.
11. Every inventory increase or decrease is recorded as an inventory movement.
12. Operational records are transformed into governed analytical datasets for Power BI.

## 8. Functional requirements

### 8.1 Master-data management

| ID | Requirement | Priority |
|---|---|---|
| FR-MD-01 | The system shall maintain unique stores with location and operational-status information. | Must |
| FR-MD-02 | The system shall assign employees to stores and optionally to valid managers. | Must |
| FR-MD-03 | The system shall maintain customers with registration, contact and activity information. | Must |
| FR-MD-04 | The system shall maintain suppliers and their associated products. | Must |
| FR-MD-05 | The system shall classify each product by category, subcategory and brand. | Must |
| FR-MD-06 | Every active product shall have a unique SKU, valid supplier, cost price, selling price and reorder level. | Must |
| FR-MD-07 | Historical transactions shall remain valid when a master record becomes inactive. | Must |

### 8.2 Order processing

| ID | Requirement | Priority |
|---|---|---|
| FR-OR-01 | Every order shall have a unique business order number. | Must |
| FR-OR-02 | Every order shall reference one customer, store, processing employee and order status. | Must |
| FR-OR-03 | The processing employee shall belong to the order's store. | Must |
| FR-OR-04 | An order shall contain one or more order items. | Must |
| FR-OR-05 | The same product shall not appear more than once within the same order. | Must |
| FR-OR-06 | Each order item shall retain the cost and selling price applicable at the transaction date. | Must |
| FR-OR-07 | Order header totals shall reconcile with the sum of order-item values. | Must |
| FR-OR-08 | Cancelled orders shall not be classified as recognized sales revenue. | Must |
| FR-OR-09 | Order dates shall fall within the approved reporting period and not precede customer registration. | Must |

### 8.3 Payment processing

| ID | Requirement | Priority |
|---|---|---|
| FR-PY-01 | Every payment attempt shall reference a valid order, method and payment status. | Must |
| FR-PY-02 | Completed payments shall contribute to collected revenue. | Must |
| FR-PY-03 | Pending, failed and cancelled payments shall not contribute to collected revenue. | Must |
| FR-PY-04 | Total completed payments shall not exceed the order amount unless an approved business exception exists. | Must |
| FR-PY-05 | Payment dates shall not precede the related order date. | Must |
| FR-PY-06 | Transaction references shall be unique when populated. | Must |
| FR-PY-07 | Payment and order statuses shall remain logically consistent. | Must |

### 8.4 Return and refund processing

| ID | Requirement | Priority |
|---|---|---|
| FR-RT-01 | Only delivered order items shall be eligible for return. | Must |
| FR-RT-02 | A return shall contain one or more returned items and a valid return reason. | Must |
| FR-RT-03 | Cumulative returned quantity shall not exceed delivered quantity. | Must |
| FR-RT-04 | Return dates shall not precede delivery dates. | Must |
| FR-RT-05 | Rejected returns shall not create a completed refund. | Must |
| FR-RT-06 | Total refund value shall not exceed the amount paid for the returned quantity. | Must |
| FR-RT-07 | Inventory shall be restored only for accepted items classified as reusable. | Must |

### 8.5 Inventory management

| ID | Requirement | Priority |
|---|---|---|
| FR-IN-01 | Inventory shall be maintained at one row per product and store. | Must |
| FR-IN-02 | Inventory quantity shall never become negative. | Must |
| FR-IN-03 | Order fulfilment shall not exceed available stock. | Must |
| FR-IN-04 | Every stock increase or decrease shall create an inventory-movement record. | Must |
| FR-IN-05 | Inventory movements shall identify movement type, date, quantity and related transaction where applicable. | Must |
| FR-IN-06 | Products at or below reorder level shall be identifiable. | Must |
| FR-IN-07 | Stockout, excess-stock and slow-moving-stock conditions shall be reportable. | Should |

### 8.6 Reporting and analytics

| ID | Requirement | Priority |
|---|---|---|
| FR-AN-01 | The solution shall provide a governed analytical layer separate from operational tables. | Must |
| FR-AN-02 | Fact datasets shall have documented and non-ambiguous grains. | Must |
| FR-AN-03 | A shared date dimension shall support day, month, quarter, year and financial-period analysis. | Must |
| FR-AN-04 | SQL and Power BI totals shall reconcile for critical KPIs. | Must |
| FR-AN-05 | The model shall support comparisons by store, customer, employee, product, category, brand and supplier. | Must |
| FR-AN-06 | The model shall support year-over-year, month-over-month and rolling-period analysis. | Must |
| FR-AN-07 | The solution shall support customer RFM, cohort and retention analysis. | Should |
| FR-AN-08 | The solution shall support ABC product and XYZ inventory classifications. | Should |
| FR-AN-09 | The solution shall support product affinity and cross-sell analysis. | Should |

## 9. Order, payment and return lifecycles

### 9.1 Order lifecycle

The supported order progression will be:

```text
Pending → Confirmed → Processing → Shipped → Delivered
    └───────────────→ Cancelled

Delivered → Partially Returned / Returned
```

Invalid backwards transitions shall be prevented when lifecycle enforcement is implemented.

### 9.2 Payment lifecycle

```text
Initiated → Pending → Completed
                  ├→ Failed
                  └→ Cancelled

Completed → Partially Refunded / Refunded
```

### 9.3 Return lifecycle

```text
Requested → Approved → Received → Refunded → Closed
          └→ Rejected
```

## 10. Authoritative business measures

| Measure | Business definition |
|---|---|
| Gross order value | Item value before discount and tax for all non-cancelled orders |
| Booked order value | Net order value for all non-cancelled orders |
| Recognized revenue | Net value of delivered items before subtracting completed refunds |
| Collected revenue | Amount from payments with Completed status |
| Outstanding payment | Amount from valid Pending payment attempts |
| Refund amount | Amount of completed refunds for approved returned items |
| Net revenue | Recognized revenue minus completed refunds |
| Cost of goods sold | Transaction cost price multiplied by delivered quantity, adjusted for accepted returns when applicable |
| Gross profit | Net revenue minus cost of goods sold |
| Gross margin percentage | Gross profit divided by net revenue |
| Average order value | Net revenue divided by distinct delivered orders |
| Payment success rate | Completed payment attempts divided by all valid payment attempts |
| Return rate by quantity | Accepted returned quantity divided by delivered quantity |
| Inventory value at cost | Current stock quantity multiplied by current product cost price |
| Stockout rate | Out-of-stock product-store combinations divided by active product-store combinations |

Detailed formulas and dimensional behaviour will be maintained in `02_Business_Rules.md` and the KPI dictionary.

## 11. Data requirements

### 11.1 Planned data scale

| Entity | Target volume |
|---|---:|
| Stores | 20 |
| Employees | 100 |
| Customers | 10,000 |
| Suppliers | 50 |
| Products | 500 |
| Sales orders | 100,000 |
| Sales-order items | 250,000–400,000 |
| Payment attempts | Approximately 100,000–120,000 |
| Product returns | Approximately 8,000–15,000 |
| Inventory rows | Up to 10,000 product-store combinations |
| Inventory movements | Determined by opening stock, sales, returns and restocking activity |

### 11.2 Reporting period

The baseline reporting period will use fixed dates:

```text
Start date: 01 July 2023
End date:   30 June 2026
```

Fixed dates are required so that SQL outputs, validation results, screenshots and Power BI measures remain reproducible.

### 11.3 Data characteristics

Synthetic data shall include realistic variation in:

- Weekday, weekend and seasonal sales
- Store and regional performance
- Customer purchase frequency and value
- Category, product and brand demand
- Discounts and tax amounts
- Order and payment statuses
- Payment-method preferences
- Return rates and return reasons
- Supplier concentration
- Inventory availability and replenishment

Data-generation logic shall not rely on accidental identity values when business keys or dynamic lookups can be used.

## 12. Power BI requirements

### 12.1 Dashboard pages

| Page | Purpose |
|---|---|
| 01 Executive Summary | Business health, revenue, profit, orders, customers and major risks |
| 02 Sales Performance | Trends, growth, average order value, stores and regions |
| 03 Customer Insights | RFM, value, frequency, retention, cohorts and segments |
| 04 Product Performance | Product, category and brand contribution, margin and affinity |
| 05 Inventory Management | Stock health, value, stockouts, reorder priorities and excess stock |
| 06 Store & Employee Performance | Store comparison, targets, productivity and employee rankings |
| 07 Returns & Payments | Payment success, collections, refunds, returns and quality indicators |
| 08 Supplier Analysis | Supplier contribution, dependency, inventory exposure and return risk |

### 12.2 Interactivity

The report shall provide:

- Date, store, region, category, brand and status filtering
- Page-navigation and reset-filter buttons
- Dynamic titles and selected-period labels
- Drill-through to customer, product, store or order detail where appropriate
- Report-page tooltips
- Field parameters for controlled metric and dimension switching
- Consistent cross-page slicer behaviour
- Clearly documented visual interactions
- Accessible colours and readable labels

### 12.3 Semantic model

The Power BI model shall:

- Use a star-schema-oriented reporting layer.
- Prefer one-to-many, single-direction relationships.
- Avoid ambiguous relationship paths.
- Use a dedicated measure table.
- Hide technical keys and columns not required by report users.
- Mark the shared date table as the model's date table.
- Store business logic primarily in reusable measures rather than calculated columns.
- Reconcile critical measures with SQL control totals.

## 13. Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-01 | All project scripts shall execute on a clean supported SQL Server environment in a documented order. |
| NFR-02 | Deployment scripts shall be modular, consistently named and source-control friendly. |
| NFR-03 | Critical data-quality failures shall raise errors rather than only display diagnostic results. |
| NFR-04 | Set-based operations shall be preferred over row-by-row processing where practical. |
| NFR-05 | Triggers and procedures shall correctly support multi-row operations. |
| NFR-06 | Critical analytical queries shall avoid fan-out and double-counting. |
| NFR-07 | Dashboard pages should respond within a reasonable portfolio-demonstration time on the target laptop. |
| NFR-08 | Indexes shall be justified using query patterns or measured execution-plan evidence. |
| NFR-09 | The database shall use consistent naming, schemas and audit columns. |
| NFR-10 | No real personal, confidential or payment information shall be stored. |
| NFR-11 | Business definitions shall remain consistent between SQL, Power BI and documentation. |
| NFR-12 | The solution shall be understandable and reproducible by another analyst following the execution guide. |

## 14. Data-quality requirements

The validation framework shall test at minimum:

- Expected database-object counts
- Primary, foreign, unique, check and default constraints
- Disabled or untrusted constraints
- Duplicate business keys
- Orphaned records
- Missing mandatory values
- Invalid dates and lifecycle sequences
- Negative prices, quantities or monetary values
- Employee and store inconsistencies
- Duplicate products within an order
- Order-header and order-item reconciliation
- Completed-payment and order-value reconciliation
- Return quantities exceeding delivered quantities
- Refunds exceeding eligible paid amounts
- Negative inventory
- Inventory-balance and movement reconciliation
- SQL and Power BI KPI reconciliation

An overall PASS status may be reported only when all mandatory checks pass.

## 15. Security and privacy requirements

- All data used in the portfolio project shall be synthetic.
- Customer and employee contact information shall be fictitious.
- The GitHub repository shall contain no credentials, connection strings, backups or local secrets.
- Database access shall follow least-privilege principles when demonstrated.
- Any future public Power BI publication shall contain synthetic information only.

## 16. Assumptions

- The business operates primarily through physical retail stores.
- All monetary values use Indian rupees unless otherwise documented.
- Product prices and costs are retained on order items to preserve transaction history.
- A product can be available at multiple stores.
- One employee has one primary store at a time.
- Each order is associated with one store and one processing employee.
- Partial payments and partial returns may be supported by the model.
- The initial release uses batch-generated synthetic data rather than live feeds.
- Power BI will use Import mode for the portfolio implementation unless testing demonstrates a reason to use another mode.

## 17. Constraints and risks

| Risk or constraint | Potential impact | Mitigation |
|---|---|---|
| Synthetic data appears overly random | Insights may not resemble real retail behaviour | Encode seasonality, regional differences and business distributions |
| Inconsistent KPI definitions | SQL and Power BI totals may differ | Maintain an authoritative KPI dictionary and reconciliation tests |
| Join fan-out | Revenue or payment totals may be inflated | Use documented fact grains and pre-aggregated datasets |
| Excessive project scope | Delivery may stall before dashboard completion | Deliver in phases and prioritize decision-focused KPIs |
| Too many indexes | Slower writes and unnecessary complexity | Measure query performance before and after indexing |
| Trigger complexity | Hidden side effects or incorrect batch behaviour | Prefer procedures and test all triggers with multi-row transactions |
| Hardware limitations | Refresh or dashboard performance may degrade | Use efficient data types, star schema, Import mode and optimized measures |
| Documentation drift | README claims may not match implementation | Validate documentation as part of release acceptance |

## 18. Deliverables

The final project shall include:

1. Business requirements and business-rules documents
2. Data model, ER diagram and data dictionary
3. Modular SQL Server deployment scripts
4. Reproducible synthetic-data generation scripts
5. Constraints, indexes, procedures, functions and controlled triggers
6. Automated data-quality and financial-reconciliation tests
7. Analytics schema with dimensions and fact datasets
8. KPI dictionary and selected analytical SQL queries
9. Multi-page Power BI report and semantic model
10. Dashboard screenshots and model diagram
11. Performance-optimization evidence
12. Business case study with findings and recommendations
13. Complete execution guide
14. Portfolio-ready GitHub README

## 19. Success criteria

The project will be considered successful when:

- All deployment scripts execute successfully on a clean SQL Server database.
- All mandatory automated tests pass.
- The operational database contains valid and realistic synthetic data.
- Revenue, payments, returns, profit and inventory figures reconcile.
- No critical analytical query produces duplicated totals through join fan-out.
- The analytical layer contains clearly documented dimensions, facts and grains.
- Power BI measures match SQL control totals.
- All eight dashboard pages are functional, interactive and visually consistent.
- At least five meaningful business findings and corresponding recommendations are documented.
- The repository structure, filenames and README match the actual implementation.
- Another analyst can deploy and understand the project using the supplied documentation.

## 20. Acceptance criteria

| Acceptance area | Acceptance condition |
|---|---|
| Database deployment | Clean deployment completes without unresolved errors |
| Data integrity | Mandatory constraints and relationship checks pass |
| Financial reconciliation | Order, payment, refund, revenue and profit control totals reconcile |
| Inventory integrity | No unexplained negative balance or movement mismatch exists |
| Analytical model | Fact grains and dimension relationships are documented and validated |
| Power BI | Critical measures match SQL and all required pages function correctly |
| Performance | Key dashboard queries and visuals meet documented performance targets |
| Documentation | Required documents exist and accurately describe the delivered solution |
| Portfolio readiness | Repository includes screenshots, insights, recommendations and execution guidance |

## 21. Recommended delivery phases

| Phase | Output |
|---|---|
| 1. Requirements | Approved business requirements, rules and KPI definitions |
| 2. Database design | ER diagram, table definitions, keys and data dictionary |
| 3. Operational database | Database, tables, constraints, indexes and reference data |
| 4. Data generation | Reproducible master and transaction data |
| 5. Database programming | Views, procedures, functions and controlled triggers |
| 6. Quality assurance | Automated validation and reconciliation framework |
| 7. Analytics layer | Dimensions, facts and Power BI-ready reporting datasets |
| 8. Power BI | Semantic model, DAX measures and eight dashboard pages |
| 9. Case study | Findings, recommendations, performance evidence and portfolio packaging |

## 22. Approval baseline

This document establishes the Version 2 business-requirements baseline. Database tables, relationships, synthetic-data generation, SQL analytics and Power BI measures shall be designed to satisfy these requirements. Any material change to transaction lifecycles, reporting definitions, scope or data volume should be reflected in this document and the related business-rules and data-dictionary documents.

