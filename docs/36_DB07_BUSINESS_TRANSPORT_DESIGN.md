# DB07 — Canteen, Uniform Production, Inventory and Transport

**Design date:** 2026-11-16  
**Status:** PostgreSQL SQL SOURCE DESIGN ONLY — NOT deployed or runtime-tested.  
**Branch:** `db/db07-inventory-canteen-uniform-transport-20261116` stacked on DB06 draft PR #30, which depends on DB05 PR #29, DB04 PR #26 and DB03 PR #25.
**Source:** `supabase/drafts/DB07_INVENTORY_CANTEEN_UNIFORM_TRANSPORT_SCHEMA.sql`
**UI:** No Flutter/Dart changes in this schema-first workstream.

## Goals

One school with distinct campus stores, canteens, uniform production areas
and transport fleets. Stock quantities are an audit-friendly sum of
immutable signed physical movements, not mutable item quantity columns.
Canteen and uniforms have distinct sale history but share an item and lot
catalog to avoid double counting inventory.

DB07 does **not** itself post cash or book profit. DB06 owns the
double-entry ledger; DB03 owns student transport fee obligations and
receipts; DB05 owns employee identity and campus assignments; DB08 will
control approvals; DB09 will own device synchronization and backups.

## 37 new public tables

| # | Table | Main responsibility |
|---:|---|---|
| 1 | `inventory_categories` | School-wide catalog categories |
| 2 | `inventory_items` | Item SKU, type, unit, reorder threshold |
| 3 | `inventory_locations` | Campus store/warehouse location |
| 4 | `inventory_suppliers` | Supplier identity, school-scoped |
| 5 | `inventory_purchase_orders` | Draft, approved or cancelled order |
| 6 | `inventory_purchase_lines` | Item quantity, exact unit cost, line value |
| 7 | `inventory_goods_receipts` | Authoritative goods-received event |
| 8 | `inventory_receipt_lines` | Quantity received per approved order line |
| 9 | `inventory_lots` | Store/campus/item/lot with optional expiry |
| 10 | `inventory_transfers` | Approval request for store-to-store transfer |
| 11 | `inventory_transfer_lines` | Items and quantities in approved transfer |
| 12 | `inventory_counts` | Stocktaking snapshot, pending or approved |
| 13 | `inventory_count_lines` | Expected vs counted and signed variance |
| 14 | `canteen_products` | Campus menu product referencing inventory item |
| 15 | `canteen_prices` | Effective-date price history |
| 16 | `canteen_sales` | Immutable cash/bank canteen sale header |
| 17 | `canteen_sale_lines` | Item, quantity, unit-price, generated line total |
| 18 | `uniform_products` | Finished uniform variant and size |
| 19 | `uniform_recipes` | Versioned bill-of-materials header |
| 20 | `uniform_recipe_lines` | Raw material quantity per finished unit |
| 21 | `uniform_production_batches` | Planned/in-progress/completed production batch |
| 22 | `uniform_material_issues` | Raw material lot consumption by batch |
| 23 | `uniform_production_outputs` | Finished units, lot and cost snapshot |
| 24 | `uniform_sales` | Immutable uniform sale header |
| 25 | `uniform_sale_lines` | Finished uniform variant and units sold |
| 26 | `transport_vehicles` | Campus vehicle registration, capacity, condition |
| 27 | `transport_routes` | Campus route master |
| 28 | `transport_route_stops` | Ordered pickup/dropoff stops |
| 29 | `transport_student_assignments` | Student enrollment linked to campus route/stop |
| 30 | `transport_driver_assignments` | Vehicle driver mapped to real DB05 employee assignment |
| 31 | `transport_trip_logs` | Pickup/dropoff trips, odometer and recorded time |
| 32 | `transport_maintenance_events` | Vehicle maintenance and inspection history |
| 33 | `transport_expense_links` | Links a vehicle repair to ONE DB06 expense |
| 34 | `inventory_stock_movements` | Signed, append-only stock quantity/cost movements |
| 35 | `inventory_movement_sources` | Typed source for each posted stock movement |
| 36 | `retail_sale_reversals` | Audited one-time canteen/uniform sale cancellation |
| 37 | `db07_operation_receipts` | Immutable request-hash/operation result for future trusted service |

The SQL also adds `db07_expense_campus_source_key` on DB06
`public.expenses`, so a vehicle expense cannot link to an expense from
a different school or campus.

## Inventory and canteen integrity

- School SKU is unique, and every stocked lot belongs to exactly one
  school/campus/location/item. Composite FKs reject another-campus
  receipt, lot, or physical store reference.
- Quantities use `numeric(14,3)` and money uses integer minor units
  (`bigint`); do not use floating-point for quantities or monetary
  calculations. Inventory's `delta_qty` is positive for inbound moves,
  negative for consumption/sales/waste/transfer-out.
- A posted physical movement requires one typed source row (receipt
  line, store transfer line, canteen sale line, uniform sale line,
  material issue, finished output, approved stock count or manual
  reason) in its originating transaction. A deferred constraint trigger
  forbids source-less committed movements. Source rows have composite
  school/campus/item FKs.
- Campus A-to-B inventory transfer is **two separate stock movements**:
  outbound negative A and inbound positive B. The future posting
  operation must lock both lots, preserve total quantity, check
  same source/quantity, approvals and shipment handling.
- Purchase order and goods receipt are separate from financial payment.
  Receiving stock does not automatically pay the supplier or record
  an operating expense.
- Canteen sale header total is checked against its line totals
  **at transaction commit** by deferred PostgreSQL constraint triggers.
  Each line must be created with the sale header in the same database
  transaction. The cash/bank payment method must match its assigned
  physical DB06 account via composite FK.
- Products have versioned effective prices. The future server operation
  must choose the latest approved price effective on the school-local
  sale date, prevent sale of expired stock and verify item UOM/stock.

## Uniform production and retail

- A uniform is a finished inventory SKU with a campus variant and size.
  A bill of materials (BOM) defines per-unit quantities of raw
  `uniform_material` items. Only one `approved` recipe per product
  can be active; older versions remain.
- Material issue and production output reference the same school/campus
  batch. Finished output links to a corresponding finished inventory
  item and physical stock lot; sales reference the correct finished
  product/variant.
- Uniform sales use a separate header and lines, like canteen sales,
  with a generated exact line total and a deferred summed-total check.
  Retail sale reversal leaves the original intact and requires a new
  approved event. The future service must post refund/account reversal
  and return-to-stock (if appropriate), not simply delete sales rows.
- **Material yield, actual BOM consumption, production loss/waste and
  cost-per-unit are NOT validated solely by DDL.** A future trusted
  transaction must reconcile batch input/output and assign actual
  production valuation.

## Transport and fleet

- Vehicle registration is unique per school; a vehicle belongs to one
  school campus, with capacity and lifecycle status.
- Routes and stops have composite school/campus keys. Stops are ordered
  within a specific route, and transport pupil assignment references
  the actual DB03 six-column school/campus/year/class enrollment key,
  plus route and stop of the SAME campus. Only one open route per
  student+year is allowed until the old assignment is ended.
- Drivers link to DB05 employees with a matching campus assignment;
  a vehicle trip requires a driver assigned to that vehicle at the
  same school/campus. Completed trip records require odometer and
  departure/arrival timestamps, with nondecreasing readings.
- Maintenance events are separate from money; `transport_expense_links`
  references the same-campus DB06 posted expense. Vehicle spending
  cannot be counted as another independent cash expense.
- The future service must enforce valid driver licence, driver/vehicle
  effective dates, fitness status, passenger capacity, school-local
  trip times, cancellation and parent data privacy.

**Transport monthly fees are still managed by DB03.** A route assignment
does not itself generate fees or mark a payment received.

## DB06 accounting / inventory cost interface — BLOCKER before migration

The current DB06 draft only accepts its specified `ledger_journals.journal_kind`
and `ledger_source_links` types. It **does not yet accept canteen sales,
uniform sales, inventory asset procurement, consumption/COGS or stock
writeoffs.** This is an explicit cross-domain migration review item:
add validated DB07 accounting source types and same-school typed FKs,
and ensure both journal kinds and source-link checks agree before
any DB06/DB07 deployment.

The future verified posting service must produce:

| DB07 event | DB06 accounting implication |
|---|---|
| Approved goods receipt | Inventory asset/stock and supplier payable or approved purchase treatment |
| Supplier payment | Reduce payable and cash/bank once, **not** another stock expense |
| Canteen sale | Cash/bank or receivable vs canteen revenue |
| Sale inventory consumption | Cost of goods sold vs inventory asset, using approved lot/unit-cost basis |
| Uniform production | Raw material asset to finished goods asset plus validated production costs |
| Uniform sale | Cash/bank vs uniform revenue, plus finished-goods COGS |
| Inter-campus stock movement | Quantity/value transfer, never new school revenue |
| Damage/writeoff | Inventory asset decrease and approved loss expense |
| Vehicle maintenance | Existing DB06 expense only, one posting |
| Retail refund | Correct sale/COGS reversals, bank/cash and stock restoration where applicable |

**Profit = recognized revenue − recognized expense/COGS**, never simply
sale receipts minus purchase-order totals. Choose the stock valuation
policy (FIFO by lot vs weighted-average) and test cost consistency before
posting. `unit_cost_minor` is a historical snapshot, not an automatic
proof of COGS.

## Security and offline operation

- All 37 DB07 `public` tables have row-level security **enabled**.
  Direct table grants to `anon` and `authenticated` are revoked; no
  permissive access policy is created in the design draft.
- Five trigger-only `app_private` functions are `SECURITY INVOKER` and
  have an empty search path. No public callable posting function or
  service-role credential is provided to the Flutter app.
- Sixteen high-impact evidence tables have paired UPDATE/DELETE and
  TRUNCATE rejection triggers. Sale history, original stock movements,
  source links, receipts, original material issues and trip records
  remain immutable; corrections/reversals add new facts.
- DB01 deployed role whitelist does not yet include every Store Keeper,
  Canteen Manager, Transport Manager and Driver role. DB08 role/approval
  design must expand and test authorized campus assignments.
- Windows may stage local pending stock/sales requests as appropriate,
  but no globally posted stock sale, cashbook revenue or inventory
  approval should be treated as final until online trusted server
  acceptance. Android stays online-only in v1.

## Outstanding trusted server / integration controls

1. Atomic, idempotent purchase/receipt/stock posting with active
   approvals and source amount/quantity checks.
2. Transaction locks guaranteeing no negative inventory stock and no
   duplicate material consumption across concurrent point-of-sale
   operations (including offline reconciliation conflicts).
3. Correct linked transfer quantities, lot expiry and stock counts,
   repair approvals, student/employee effective dates, route capacity.
4. Retail sale reversal policy with stock return and matching DB06
   refunds; prohibit multiple accounting postings of one sale.
5. Production input-to-output yield and valuation, supplier invoice
   liability and COGS consistency (DB06 extension needed).
6. DB08 Owner approval rules, audit, role/campus permissions, and
   sensitive student route access controls.
7. DB09 device/campus offline authorization, signed operation receipt,
   conflict management, backups and safe restore.
8. Actual PostgreSQL DDL and rollback-only acceptance fixture, plus
   security and financial concurrency tests on isolated local instance.
9. Real school currency minor-unit and school timezone rules as needed.

## Verification status and next domain

Source SQL: `supabase/drafts/DB07_INVENTORY_CANTEEN_UNIFORM_TRANSPORT_SCHEMA.sql`  
Fictional rollback fixture: `supabase/tests/DB07_BUSINESS_TRANSPORT_INTEGRATION.sql`  
Static checker: `supabase/tests/check_db07_business.py`  
Local runbook: `supabase/drafts/DB07_BUSINESS_TRANSPORT_RUNBOOK.md`

**No PostgreSQL runtime tests, real RLS role tests, stock concurrency,
COGS ledger services, migration/deployment or Flutter changes in this
task.** The source is a review draft and is not production-ready.

**Schema-first count:** 9 domains total. DB01+DB02 baseline deployed;
DB03–DB07 source drafted but not deployed. **2 full domains remain to
design (DB08 Approvals/Controls, DB09 Sync/Backup/Reporting). 7 domains
remain undeployed (DB03–DB09).**
