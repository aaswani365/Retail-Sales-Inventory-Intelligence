# Retail Sales & Inventory Intelligence Platform

## Operational Data Dictionary

| Document attribute | Value |
|---|---|
| Project name | Retail Sales & Inventory Intelligence Platform |
| Project version | 2.0 |
| Document | 05_Data_Dictionary.md |
| Author | Akshay Aswani |
| Database | RetailIntelligenceDB |
| Platform | Microsoft SQL Server |
| Status | Approved column-level baseline |
| Related document | 04_Database_Design.md |

---

## 1. Purpose

This data dictionary defines the operational and validation data structures approved for Version 2. It provides the implementation reference for table creation, constraints, synthetic-data generation, validation and the later analytics model.

The operational/audit database contains **25 tables** across five schemas:

| Schema | Tables | Purpose |
|---|---:|---|
| `ref` | 9 | Controlled classifications and statuses |
| `core` | 5 | Master business entities |
| `sales` | 7 | Orders, payments, returns and refunds |
| `inventory` | 2 | Current inventory and movement ledger |
| `audit` | 2 | Validation execution history |

## 2. Dictionary conventions

| Abbreviation | Meaning |
|---|---|
| PK | Primary key |
| FK | Foreign key |
| UQ | Unique constraint or unique index |
| DF | Default constraint |
| CK | Check constraint |
| Filtered UQ | Unique index applied only to non-null values |
| System timestamp | SQL Server-generated current `DATETIME2` value |

General standards:

- `INT` and `SMALLINT` identify reference/master records.
- `BIGINT` identifies high-volume transactions and events.
- Monetary fields use `DECIMAL`, not floating-point data types.
- Business dates use `DATE`; event timestamps use `DATETIME2(0)`.
- Transaction and event history is not hard-deleted.
- Examples are illustrative synthetic values, not real information.

---

# Reference Schema

## 3. `ref.Category`

**Purpose:** Stores the highest product-classification level.  
**Grain:** One row per category.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| CategoryID | INT | No | PK, identity | Internal category identifier | `1` |
| CategoryCode | VARCHAR(20) | No | UQ | Stable category business code | `CAT-ELEC` |
| CategoryName | VARCHAR(100) | No | UQ | User-facing category name | `Electronics` |
| Description | VARCHAR(255) | Yes |  | Short category description | `Electronic devices and accessories` |
| IsActive | BIT | No | DF `1` | Whether the category can be assigned to new products | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Row creation timestamp | `2026-01-05 10:30:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update timestamp | `NULL` |

## 4. `ref.SubCategory`

**Purpose:** Stores the detailed product classification beneath Category.  
**Grain:** One row per subcategory within one category.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| SubCategoryID | INT | No | PK, identity | Internal subcategory identifier | `11` |
| CategoryID | INT | No | FK → ref.Category | Parent category | `1` |
| SubCategoryCode | VARCHAR(20) | No | UQ | Stable subcategory code | `SUB-MOB` |
| SubCategoryName | VARCHAR(100) | No | UQ with CategoryID | Subcategory name | `Mobile Phones` |
| Description | VARCHAR(255) | Yes |  | Short description | `Smartphones and feature phones` |
| IsActive | BIT | No | DF `1` | Available for new product assignments | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 10:31:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

## 5. `ref.Brand`

**Purpose:** Stores product brands.  
**Grain:** One row per brand.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| BrandID | INT | No | PK, identity | Internal brand identifier | `5` |
| BrandCode | VARCHAR(20) | No | UQ | Stable brand code | `BR-SAM` |
| BrandName | VARCHAR(100) | No | UQ | Brand display name | `Samsung` |
| Description | VARCHAR(255) | Yes |  | Brand description | `Consumer electronics brand` |
| IsActive | BIT | No | DF `1` | Available for new product assignments | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 10:32:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

## 6. `ref.OrderStatus`

**Purpose:** Controls valid order-lifecycle statuses.  
**Grain:** One row per order status.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| OrderStatusID | SMALLINT | No | PK, identity | Internal status identifier | `5` |
| OrderStatusCode | VARCHAR(30) | No | UQ | Stable status code | `DELIVERED` |
| OrderStatusName | VARCHAR(100) | No | UQ | Display label | `Delivered` |
| Description | VARCHAR(255) | Yes |  | Status definition | `Order delivered to customer` |
| SortOrder | TINYINT | No | UQ recommended | Lifecycle display sequence | `5` |
| IsActive | BIT | No | DF `1` | Available for future transitions | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 10:33:00` |

Valid baseline codes:

```text
PENDING, CONFIRMED, PROCESSING, SHIPPED, DELIVERED,
CANCELLED, PARTIALLY_RETURNED, RETURNED
```

## 7. `ref.PaymentMethod`

**Purpose:** Stores supported payment channels.  
**Grain:** One row per payment method.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| PaymentMethodID | SMALLINT | No | PK, identity | Internal method identifier | `2` |
| PaymentMethodCode | VARCHAR(30) | No | UQ | Stable method code | `UPI` |
| PaymentMethodName | VARCHAR(100) | No | UQ | Display label | `UPI` |
| Description | VARCHAR(255) | Yes |  | Method definition | `Unified Payments Interface` |
| SortOrder | TINYINT | No |  | Display sequence | `2` |
| IsActive | BIT | No | DF `1` | Available for new payments | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 10:34:00` |

Recommended baseline codes:

```text
CASH, UPI, CREDIT_CARD, DEBIT_CARD, NET_BANKING, WALLET
```

## 8. `ref.PaymentStatus`

**Purpose:** Controls payment-attempt lifecycle statuses.  
**Grain:** One row per payment status.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| PaymentStatusID | SMALLINT | No | PK, identity | Internal status identifier | `3` |
| PaymentStatusCode | VARCHAR(30) | No | UQ | Stable status code | `COMPLETED` |
| PaymentStatusName | VARCHAR(100) | No | UQ | Display label | `Completed` |
| Description | VARCHAR(255) | Yes |  | Status definition | `Payment successfully collected` |
| SortOrder | TINYINT | No |  | Display sequence | `3` |
| IsActive | BIT | No | DF `1` | Available for future payment events | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 10:35:00` |

Valid baseline codes:

```text
INITIATED, PENDING, COMPLETED, FAILED, CANCELLED,
PARTIALLY_REFUNDED, REFUNDED
```

## 9. `ref.ReturnReason`

**Purpose:** Classifies why a customer returned an item.  
**Grain:** One row per return reason.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| ReturnReasonID | SMALLINT | No | PK, identity | Internal reason identifier | `1` |
| ReturnReasonCode | VARCHAR(30) | No | UQ | Stable reason code | `DAMAGED` |
| ReturnReasonName | VARCHAR(100) | No | UQ | Display label | `Damaged Product` |
| Description | VARCHAR(255) | Yes |  | Reason definition | `Item arrived damaged` |
| SortOrder | TINYINT | No |  | Display sequence | `1` |
| IsActive | BIT | No | DF `1` | Available for new returns | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 10:36:00` |

Recommended baseline codes:

```text
DAMAGED, DEFECTIVE, WRONG_ITEM, NOT_AS_DESCRIBED,
SIZE_OR_FIT, CUSTOMER_CHANGED_MIND, OTHER
```

## 10. `ref.ReturnStatus`

**Purpose:** Controls the return-request lifecycle.  
**Grain:** One row per return status.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| ReturnStatusID | SMALLINT | No | PK, identity | Internal status identifier | `4` |
| ReturnStatusCode | VARCHAR(30) | No | UQ | Stable status code | `RECEIVED` |
| ReturnStatusName | VARCHAR(100) | No | UQ | Display label | `Received` |
| Description | VARCHAR(255) | Yes |  | Status definition | `Returned item received by store` |
| SortOrder | TINYINT | No |  | Display sequence | `4` |
| IsActive | BIT | No | DF `1` | Available for new return processing | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 10:37:00` |

Valid baseline codes:

```text
REQUESTED, APPROVED, REJECTED, RECEIVED, REFUNDED, CLOSED
```

## 11. `ref.InventoryMovementType`

**Purpose:** Defines how an inventory movement changes stock.  
**Grain:** One row per movement type.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| InventoryMovementTypeID | SMALLINT | No | PK, identity | Internal type identifier | `3` |
| InventoryMovementTypeCode | VARCHAR(30) | No | UQ | Stable movement code | `SALE` |
| InventoryMovementTypeName | VARCHAR(100) | No | UQ | Display label | `Sale` |
| Description | VARCHAR(255) | Yes |  | Movement definition | `Stock issued for a customer sale` |
| QuantityDirection | SMALLINT | No | CK in `(-1,1)` | Effect on on-hand balance | `-1` |
| RequiresReference | BIT | No | DF `0` | Whether a source business transaction is required | `1` |
| SortOrder | TINYINT | No |  | Display sequence | `3` |
| IsActive | BIT | No | DF `1` | Available for new movement events | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 10:38:00` |

Baseline codes:

```text
OPENING_STOCK, PURCHASE_RECEIPT, SALE, SALE_CANCELLATION,
CUSTOMER_RETURN, DAMAGE_WRITEOFF, ADJUSTMENT_IN, ADJUSTMENT_OUT,
TRANSFER_IN, TRANSFER_OUT
```

---

# Core Schema

## 12. `core.Store`

**Purpose:** Stores physical retail locations.  
**Grain:** One row per store.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| StoreID | INT | No | PK, identity | Internal store identifier | `1` |
| StoreCode | VARCHAR(20) | No | UQ | Stable store business code | `STR-JAI-01` |
| StoreName | VARCHAR(100) | No | UQ | Store display name | `Jaipur Central` |
| ManagerEmployeeID | INT | Yes | FK → core.Employee | Current store manager | `1` |
| AddressLine | VARCHAR(255) | No |  | Street/building address | `MI Road` |
| City | VARCHAR(100) | No |  | City | `Jaipur` |
| State | VARCHAR(100) | No |  | State | `Rajasthan` |
| PostalCode | VARCHAR(10) | Yes |  | Postal code | `302001` |
| Country | VARCHAR(100) | No | DF `India` | Country | `India` |
| Phone | VARCHAR(20) | Yes |  | Store contact number | `0141-4000001` |
| OpeningDate | DATE | No |  | First operational date | `2020-04-01` |
| ClosingDate | DATE | Yes | CK >= OpeningDate | Final operational date | `NULL` |
| IsActive | BIT | No | DF `1` | Whether the store accepts new activity | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 11:00:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

## 13. `core.Employee`

**Purpose:** Stores retail employees and reporting relationships.  
**Grain:** One row per employee.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| EmployeeID | INT | No | PK, identity | Internal employee identifier | `14` |
| EmployeeCode | VARCHAR(20) | No | UQ | Stable employee code | `EMP-0014` |
| StoreID | INT | No | FK → core.Store | Employee's primary store | `1` |
| ManagerEmployeeID | INT | Yes | Self FK | Direct manager | `1` |
| FirstName | VARCHAR(50) | No |  | First name | `Aarav` |
| LastName | VARCHAR(50) | No |  | Last name | `Sharma` |
| Email | VARCHAR(150) | Yes | Filtered UQ | Synthetic work email | `aarav.sharma14@example.com` |
| Phone | VARCHAR(20) | Yes |  | Synthetic contact number | `9000000014` |
| JobTitle | VARCHAR(100) | No |  | Current job title | `Sales Executive` |
| Salary | DECIMAL(12,2) | No | CK > 0 | Annual or monthly salary as documented in generator | `420000.00` |
| HireDate | DATE | No |  | Employment start date | `2022-08-15` |
| TerminationDate | DATE | Yes | CK >= HireDate | Employment end date | `NULL` |
| IsActive | BIT | No | DF `1` | Active employment flag | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 11:01:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

## 14. `core.Customer`

**Purpose:** Stores synthetic customer master data.  
**Grain:** One row per customer.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| CustomerID | INT | No | PK, identity | Internal customer identifier | `1001` |
| CustomerCode | VARCHAR(20) | No | UQ | Stable customer code | `CUS-001001` |
| FirstName | VARCHAR(50) | No |  | First name | `Ishita` |
| LastName | VARCHAR(50) | No |  | Last name | `Mehta` |
| Email | VARCHAR(150) | Yes | Filtered UQ | Synthetic email | `ishita.mehta1001@example.com` |
| Phone | VARCHAR(20) | Yes |  | Synthetic contact number | `9100001001` |
| AddressLine | VARCHAR(255) | Yes |  | Street/building address | `C Scheme` |
| City | VARCHAR(100) | Yes |  | City | `Jaipur` |
| State | VARCHAR(100) | Yes |  | State | `Rajasthan` |
| PostalCode | VARCHAR(10) | Yes |  | Postal code | `302001` |
| Country | VARCHAR(100) | Yes |  | Country | `India` |
| RegistrationDate | DATE | No |  | Customer registration date | `2023-06-15` |
| LoyaltyPoints | INT | No | DF `0`, CK >= 0 | Current loyalty-points balance | `250` |
| IsActive | BIT | No | DF `1` | Eligible for new orders | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 11:02:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

## 15. `core.Supplier`

**Purpose:** Stores product-supplier master data.  
**Grain:** One row per supplier.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| SupplierID | INT | No | PK, identity | Internal supplier identifier | `7` |
| SupplierCode | VARCHAR(20) | No | UQ | Stable supplier code | `SUP-007` |
| SupplierName | VARCHAR(150) | No | UQ | Supplier legal/display name | `Rajasthan Electronics Supply` |
| ContactName | VARCHAR(100) | Yes |  | Primary synthetic contact | `Rohan Jain` |
| Email | VARCHAR(150) | Yes | Filtered UQ | Synthetic contact email | `contact7@example.com` |
| Phone | VARCHAR(20) | Yes |  | Synthetic contact number | `9200000007` |
| AddressLine | VARCHAR(255) | Yes |  | Street/building address | `Sitapura Industrial Area` |
| City | VARCHAR(100) | Yes |  | City | `Jaipur` |
| State | VARCHAR(100) | Yes |  | State | `Rajasthan` |
| PostalCode | VARCHAR(10) | Yes |  | Postal code | `302022` |
| Country | VARCHAR(100) | Yes |  | Country | `India` |
| IsActive | BIT | No | DF `1` | Available for new product assignments | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 11:03:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

## 16. `core.Product`

**Purpose:** Stores the current product master.  
**Grain:** One row per sellable product.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| ProductID | INT | No | PK, identity | Internal product identifier | `101` |
| SKU | VARCHAR(40) | No | UQ | Stock-keeping unit | `MOB-SAM-0101` |
| ProductName | VARCHAR(150) | No |  | Product display name | `Galaxy A Series 128GB` |
| SubCategoryID | INT | No | FK → ref.SubCategory | Product subcategory | `11` |
| BrandID | INT | No | FK → ref.Brand | Product brand | `5` |
| SupplierID | INT | No | FK → core.Supplier | Current supplier | `7` |
| CostPrice | DECIMAL(12,2) | No | CK > 0 | Current procurement cost | `18000.00` |
| SellingPrice | DECIMAL(12,2) | No | CK > 0 | Current standard selling price | `21999.00` |
| ReorderLevel | INT | No | DF `10`, CK >= 0 | Low-stock threshold | `15` |
| ExcessStockLevel | INT | Yes | CK >= ReorderLevel | Excess-stock threshold | `150` |
| Barcode | VARCHAR(50) | Yes | Filtered UQ | Synthetic barcode | `8900000000101` |
| Description | VARCHAR(500) | Yes |  | Product description | `5G smartphone with 128GB storage` |
| IsActive | BIT | No | DF `1` | Available for new sales/restocking | `1` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2026-01-05 11:04:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

---

# Sales Schema

## 17. `sales.SalesOrder`

**Purpose:** Stores one order header for a customer transaction.  
**Grain:** One row per sales order.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| SalesOrderID | BIGINT | No | PK, identity | Internal order identifier | `50001` |
| OrderNumber | VARCHAR(25) | No | UQ | Human-readable order number | `ORD-2024-050001` |
| CustomerID | INT | No | FK → core.Customer | Customer placing the order | `1001` |
| StoreID | INT | No | FK → core.Store | Fulfilling store | `1` |
| EmployeeID | INT | No | FK → core.Employee | Processing employee | `14` |
| OrderStatusID | SMALLINT | No | FK → ref.OrderStatus | Current order status | `5` |
| OrderDate | DATETIME2(0) | No |  | Order placement timestamp | `2024-11-20 16:45:00` |
| ConfirmedDate | DATETIME2(0) | Yes | >= OrderDate | Confirmation timestamp | `2024-11-20 16:47:00` |
| ShippedDate | DATETIME2(0) | Yes | >= ConfirmedDate | Shipment timestamp | `2024-11-21 10:00:00` |
| DeliveredDate | DATETIME2(0) | Yes | >= ShippedDate | Delivery timestamp | `2024-11-23 14:10:00` |
| CancelledDate | DATETIME2(0) | Yes | >= OrderDate | Cancellation timestamp | `NULL` |
| SubtotalAmount | DECIMAL(14,2) | No | DF `0`, CK >= 0 | Sum of item gross amounts | `23999.00` |
| DiscountAmount | DECIMAL(14,2) | No | DF `0`, CK >= 0 | Sum of item discounts | `2000.00` |
| TaxAmount | DECIMAL(14,2) | No | DF `0`, CK >= 0 | Sum of item tax amounts | `3959.82` |
| NetAmount | DECIMAL(14,2) | No | DF `0`, CK >= 0 | Sum of item net amounts | `25958.82` |
| Remarks | VARCHAR(500) | Yes |  | Optional operational note | `Festival promotion applied` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2024-11-20 16:45:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `2024-11-23 14:10:00` |

## 18. `sales.SalesOrderItem`

**Purpose:** Stores product-level quantities and transaction prices.  
**Grain:** One unique product per sales order.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| SalesOrderItemID | BIGINT | No | PK, identity | Internal item identifier | `145001` |
| SalesOrderID | BIGINT | No | FK → sales.SalesOrder | Parent order | `50001` |
| ProductID | INT | No | FK → core.Product | Product sold | `101` |
| Quantity | INT | No | CK > 0 | Ordered quantity | `1` |
| UnitCost | DECIMAL(12,2) | No | CK > 0 | Cost captured at transaction time | `18000.00` |
| UnitPrice | DECIMAL(12,2) | No | CK > 0 | Selling price before discount/tax | `23999.00` |
| GrossAmount | DECIMAL(14,2) | No | Quantity × UnitPrice | Pre-discount item amount | `23999.00` |
| DiscountAmount | DECIMAL(14,2) | No | DF `0`, 0..GrossAmount | Item discount | `2000.00` |
| TaxRate | DECIMAL(5,2) | No | DF `0`, CK 0..100 | Applied tax percentage | `18.00` |
| TaxAmount | DECIMAL(14,2) | No | DF `0`, CK >= 0 | Tax on amount after discount | `3959.82` |
| NetAmount | DECIMAL(14,2) | No | CK >= 0 | Gross − discount + tax | `25958.82` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2024-11-20 16:45:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

Composite alternate key: `(SalesOrderID, ProductID)`.

## 19. `sales.OrderStatusHistory`

**Purpose:** Records every order-status transition.  
**Grain:** One row per transition event.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| OrderStatusHistoryID | BIGINT | No | PK, identity | Internal transition identifier | `300001` |
| SalesOrderID | BIGINT | No | FK → sales.SalesOrder | Related order | `50001` |
| FromOrderStatusID | SMALLINT | Yes | FK → ref.OrderStatus | Previous status; null for first event | `4` |
| ToOrderStatusID | SMALLINT | No | FK → ref.OrderStatus | New status | `5` |
| StatusChangedDate | DATETIME2(0) | No |  | Transition timestamp | `2024-11-23 14:10:00` |
| ChangedByEmployeeID | INT | Yes | FK → core.Employee | Employee or process responsible | `14` |
| ChangeReason | VARCHAR(255) | Yes |  | Reason or comment | `Delivery confirmed` |
| CreatedDate | DATETIME2(0) | No | System DF | Record creation timestamp | `2024-11-23 14:10:00` |

## 20. `sales.Payment`

**Purpose:** Stores every payment attempt without treating all attempts as collected revenue.  
**Grain:** One row per payment attempt/event.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| PaymentID | BIGINT | No | PK, identity | Internal payment identifier | `70001` |
| SalesOrderID | BIGINT | No | FK → sales.SalesOrder | Related order | `50001` |
| PaymentMethodID | SMALLINT | No | FK → ref.PaymentMethod | Payment channel | `2` |
| PaymentStatusID | SMALLINT | No | FK → ref.PaymentStatus | Payment outcome/status | `3` |
| AttemptNumber | SMALLINT | No | CK > 0; UQ with order | Sequential attempt for the order | `1` |
| PaymentDate | DATETIME2(0) | No | >= OrderDate | Payment event timestamp | `2024-11-20 16:48:00` |
| Amount | DECIMAL(14,2) | No | CK > 0 | Attempted/collected amount | `25958.82` |
| TransactionReference | VARCHAR(100) | Yes | Filtered UQ | External-style synthetic reference | `PAY-20241120-A82F01` |
| FailureReason | VARCHAR(255) | Yes |  | Failure explanation when applicable | `NULL` |
| Remarks | VARCHAR(255) | Yes |  | Operational note | `UPI payment completed` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2024-11-20 16:48:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

## 21. `sales.ProductReturn`

**Purpose:** Stores the header for a customer return request.  
**Grain:** One row per return request for one order.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| ProductReturnID | BIGINT | No | PK, identity | Internal return identifier | `9001` |
| ReturnNumber | VARCHAR(25) | No | UQ | Human-readable return number | `RET-2024-009001` |
| SalesOrderID | BIGINT | No | FK → sales.SalesOrder | Original delivered order | `50001` |
| ReturnStatusID | SMALLINT | No | FK → ref.ReturnStatus | Current return status | `4` |
| RequestDate | DATETIME2(0) | No | >= DeliveredDate | Customer request timestamp | `2024-11-27 11:15:00` |
| ApprovedDate | DATETIME2(0) | Yes | >= RequestDate | Approval timestamp | `2024-11-27 14:00:00` |
| ReceivedDate | DATETIME2(0) | Yes | >= ApprovedDate | Returned-goods receipt timestamp | `2024-11-29 12:30:00` |
| ClosedDate | DATETIME2(0) | Yes | >= RequestDate | Final closure timestamp | `NULL` |
| Remarks | VARCHAR(500) | Yes |  | Return-level note | `One item received for inspection` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2024-11-27 11:15:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `2024-11-29 12:30:00` |

## 22. `sales.ProductReturnItem`

**Purpose:** Stores item-level quantities, reasons and inspection outcomes for a return.  
**Grain:** One sales-order item per return request.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| ProductReturnItemID | BIGINT | No | PK, identity | Internal returned-item identifier | `15001` |
| ProductReturnID | BIGINT | No | FK → sales.ProductReturn | Parent return request | `9001` |
| SalesOrderItemID | BIGINT | No | FK → sales.SalesOrderItem | Original sold item | `145001` |
| ReturnReasonID | SMALLINT | No | FK → ref.ReturnReason | Return cause | `2` |
| QuantityRequested | INT | No | CK > 0 | Quantity customer requested to return | `1` |
| QuantityAccepted | INT | No | DF `0`; 0..requested | Quantity approved/received | `1` |
| EligibleRefundAmount | DECIMAL(14,2) | No | DF `0`, CK >= 0 | Maximum approved refund value | `25958.82` |
| IsReusable | BIT | Yes |  | Whether item can return to sellable inventory | `0` |
| InspectionNotes | VARCHAR(500) | Yes |  | Item-condition notes | `Defective display; not reusable` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2024-11-27 11:15:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `2024-11-29 12:30:00` |

Composite alternate key: `(ProductReturnID, SalesOrderItemID)`.

## 23. `sales.Refund`

**Purpose:** Stores refund cash-out events separately from payment collections.  
**Grain:** One refund event against one payment and one return request.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| RefundID | BIGINT | No | PK, identity | Internal refund identifier | `4001` |
| PaymentID | BIGINT | No | FK → sales.Payment | Original completed payment | `70001` |
| ProductReturnID | BIGINT | No | FK → sales.ProductReturn | Approved return request | `9001` |
| RefundDate | DATETIME2(0) | No | >= PaymentDate | Refund event timestamp | `2024-11-30 10:00:00` |
| RefundAmount | DECIMAL(14,2) | No | CK > 0 | Refund amount | `25958.82` |
| RefundReference | VARCHAR(100) | Yes | Filtered UQ | Synthetic refund reference | `RFD-20241130-B17E20` |
| RefundStatus | VARCHAR(20) | No | CK Pending/Completed/Failed | Refund processing status | `Completed` |
| Remarks | VARCHAR(255) | Yes |  | Refund note | `Refunded to original UPI account` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2024-11-30 10:00:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last material update | `NULL` |

---

# Inventory Schema

## 24. `inventory.InventoryBalance`

**Purpose:** Stores the latest inventory state by product and store.  
**Grain:** One row per product-store combination.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| InventoryBalanceID | BIGINT | No | PK, identity | Internal balance identifier | `2501` |
| ProductID | INT | No | FK → core.Product | Stocked product | `101` |
| StoreID | INT | No | FK → core.Store | Stock-holding store | `1` |
| QuantityOnHand | INT | No | DF `0`, CK >= 0 | Physical sellable/reservable quantity | `42` |
| QuantityReserved | INT | No | DF `0`, CK 0..on hand | Quantity allocated but not yet fulfilled | `3` |
| LastMovementDate | DATETIME2(0) | Yes |  | Most recent stock event timestamp | `2024-11-30 10:00:00` |
| LastRestockedDate | DATETIME2(0) | Yes |  | Most recent qualifying inbound restock | `2024-11-15 09:30:00` |
| CreatedDate | DATETIME2(0) | No | System DF | Creation timestamp | `2023-07-01 00:00:00` |
| ModifiedDate | DATETIME2(0) | Yes |  | Last balance update | `2024-11-30 10:00:00` |

Composite alternate key: `(ProductID, StoreID)`.

Derived value:

```text
QuantityAvailable = QuantityOnHand − QuantityReserved
```

## 25. `inventory.InventoryMovement`

**Purpose:** Provides the immutable audit trail for every stock change.  
**Grain:** One stock-changing event for one product and store.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| InventoryMovementID | BIGINT | No | PK, identity | Internal movement identifier | `810001` |
| ProductID | INT | No | FK → core.Product | Product moved | `101` |
| StoreID | INT | No | FK → core.Store | Store affected | `1` |
| InventoryMovementTypeID | SMALLINT | No | FK → ref.InventoryMovementType | Movement classification | `3` |
| MovementDate | DATETIME2(0) | No |  | Effective movement timestamp | `2024-11-20 16:45:00` |
| Quantity | INT | No | CK > 0 | Absolute movement quantity | `1` |
| QuantityDirection | SMALLINT | No | CK `-1` or `1` | Stock effect | `-1` |
| SalesOrderItemID | BIGINT | Yes | FK → sales.SalesOrderItem | Causing sale/cancellation item | `145001` |
| ProductReturnItemID | BIGINT | Yes | FK → sales.ProductReturnItem | Causing accepted return item | `NULL` |
| ReferenceNumber | VARCHAR(50) | Yes |  | Supporting document/event reference | `ORD-2024-050001` |
| Reason | VARCHAR(255) | Yes | Required for adjustments | Movement explanation | `Customer sale fulfilled` |
| CreatedByEmployeeID | INT | Yes | FK → core.Employee | Responsible employee | `14` |
| CreatedDate | DATETIME2(0) | No | System DF | Record creation timestamp | `2024-11-20 16:45:00` |

Derived value:

```text
SignedQuantity = Quantity × QuantityDirection
```

Movement rows are append-only. Corrections use compensating movements.

---

# Audit Schema

## 26. `audit.ValidationRun`

**Purpose:** Stores one execution of the automated validation suite.  
**Grain:** One row per validation run.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| ValidationRunID | BIGINT | No | PK, identity | Internal validation-run identifier | `15` |
| RunStartDate | DATETIME2(0) | No |  | Validation start timestamp | `2026-01-06 09:00:00` |
| RunEndDate | DATETIME2(0) | Yes | >= start | Validation end timestamp | `2026-01-06 09:02:10` |
| EnvironmentName | VARCHAR(30) | No | DF `Local` | Execution environment | `Local` |
| OverallStatus | VARCHAR(10) | No | CK Running/Passed/Failed | Final run outcome | `Passed` |
| TotalTests | INT | No | DF `0`, CK >= 0 | Number of executed tests | `48` |
| PassedTests | INT | No | DF `0`, CK >= 0 | Successful tests | `48` |
| FailedTests | INT | No | DF `0`, CK >= 0 | Failed tests | `0` |
| Remarks | VARCHAR(500) | Yes |  | Run-level note | `Full post-generation validation` |

## 27. `audit.ValidationResult`

**Purpose:** Stores the outcome of each test within a validation run.  
**Grain:** One validation test per run.

| Column | Data type | Null | Key/rule | Definition | Example |
|---|---|---:|---|---|---|
| ValidationResultID | BIGINT | No | PK, identity | Internal result identifier | `701` |
| ValidationRunID | BIGINT | No | FK → audit.ValidationRun | Parent validation run | `15` |
| TestCode | VARCHAR(50) | No | UQ with run | Stable validation code | `DQ-ORDER-001` |
| TestName | VARCHAR(200) | No |  | Human-readable test name | `Order total reconciliation` |
| Severity | VARCHAR(10) | No | CK Info/Warning/Critical | Failure severity | `Critical` |
| ExpectedValue | VARCHAR(100) | Yes |  | Expected value/condition | `0 exceptions` |
| ActualValue | VARCHAR(100) | Yes |  | Actual measured value | `0 exceptions` |
| ExceptionCount | BIGINT | No | DF `0`, CK >= 0 | Number of invalid records | `0` |
| TestStatus | VARCHAR(10) | No | CK Passed/Failed | Test outcome | `Passed` |
| ExecutedDate | DATETIME2(0) | No | System DF | Test execution timestamp | `2026-01-06 09:01:15` |
| DiagnosticMessage | VARCHAR(1000) | Yes |  | Failure or diagnostic detail | `All order headers reconcile within ₹0.01` |

Composite alternate key: `(ValidationRunID, TestCode)`.

---

# Cross-Table Definitions

## 28. Monetary definitions

| Term | Definition |
|---|---|
| Item Gross Amount | Quantity × UnitPrice |
| Item Taxable Amount | GrossAmount − DiscountAmount |
| Item Tax Amount | TaxableAmount × TaxRate |
| Item Net Amount | GrossAmount − DiscountAmount + TaxAmount |
| Order Subtotal | Sum of item GrossAmount |
| Order Discount | Sum of item DiscountAmount |
| Order Tax | Sum of item TaxAmount |
| Order Net Amount | Sum of item NetAmount |
| Collected Revenue | Completed Payment amounts only |
| Completed Refund | RefundAmount where RefundStatus = Completed |
| Net Cash Collection | Collected Revenue − Completed Refunds |
| Recognized Revenue | Delivered item revenue under documented tax treatment |

## 29. Null interpretation

| Field type | Null meaning |
|---|---|
| ModifiedDate | Record has not been materially updated after creation |
| Closing/Termination date | Entity remains active or has no known end date |
| ManagerEmployeeID | Manager not assigned or top-level employee |
| Transaction/Refund reference | Reference unavailable or not applicable |
| FailureReason | Payment did not fail, or reason not recorded |
| IsReusable | Return item has not yet been inspected |
| Optional geographic value | Unknown/not supplied; Power BI displays `Unknown` |

## 30. Data-quality expectations

| Control | Expected result |
|---|---:|
| Duplicate business keys | 0 |
| Orphan foreign keys | 0 |
| Confirmed orders without items | 0 |
| Duplicate products within an order | 0 |
| Order-header reconciliation exceptions | 0 |
| Over-collected completed payments | 0 |
| Invalid completed refunds | 0 |
| Over-returned accepted quantities | 0 |
| Negative available inventory | 0 |
| Inventory movement reconciliation exceptions | 0 |
| Invalid employee-store order assignments | 0 |
| Invalid lifecycle transitions | 0 |

## 31. Implementation notes

1. The Store manager foreign key is added after both Store and Employee exist.
2. Filtered unique indexes are used for nullable email, barcode and reference fields.
3. `SalesOrderItem` preserves transaction cost and price even when Product prices change later.
4. Status-history and inventory-movement tables are append-only.
5. Cross-table cumulative limits are enforced through procedures and validation, not simple check constraints.
6. Power BI connects to the later `analytics` schema rather than this complete operational model.
7. Exact constraint and index names are defined in the naming-conventions document and SQL scripts.

## 32. Next deliverable

The next document is:

```text
06_Naming_Conventions.md
```

After naming conventions are approved, the ER diagram and initial database-creation scripts can be generated consistently.

