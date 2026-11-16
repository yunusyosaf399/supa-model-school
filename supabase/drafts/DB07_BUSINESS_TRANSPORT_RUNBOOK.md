# DB07 Inventory, Canteen, Uniform and Transport — Local Test Runbook

**SOURCE REVIEW ONLY. No migration to hosted Supabase and no Flutter code.**

## Dependencies and local environment

DB07 is stacked on DB06 draft, which depends on DB05 payroll, DB04
attendance and DB03 fee schema. DB01/DB02 baseline schemas are already
deployed on the user's connected Supabase project, but DB03–DB07 are not.

Use a DISPOSABLE LOCAL Supabase/PostgreSQL instance with Auth schema.
Create fictional user `sms-adm-admin-a@example.invalid`. Apply reviewed,
deployed-equivalent DB01/DB02 and source DB03/04/05/06 in dependency
order to that isolated environment ONLY. Ensure any pre-existing
authoritative migrations and extensions are accounted for.
Do not apply source draft directly to a real school project.

### Source/fixture commands (illustrative)

```powershell
python supabase/tests/check_db07_business.py
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB07_BUSINESS_TRANSPORT_INTEGRATION.sql
```

The SQL fixture begins a transaction and ROLLS BACK all fictional data.
It checks structure and constraints only, not actual business permissions
or cloud accounting posting. Both commands are **NOT RUN** in this task.

## Fictional scenarios covered in fixture

1. School A and B campuses, school inventory catalog, stocked lot,
   approved purchase order and goods receipt; goods receipt is NOT
   itself a cash expense.
2. Signed quantity movements: 10 received in A, transfer 3 A→B,
   canteen sale 2 in A; balances A=5, B=3.
3. Canteen sale price snapshot/total; wrong payment-method-to-wallet
   composite FK rejected; header without lines rejected by deferred
   constraint at `SET CONSTRAINTS ALL IMMEDIATE`.
4. Uniform recipe using 2 metres of fabric per shirt, a batch that
   consumes 4 metres, produces 2 shirts and sells 1; finished balance
   1, raw material balance 16.
5. Cross-campus lot spoofing rejected, stock movement missing its typed
   source rejected, immutable original stock and sale line denied
   UPDATE/DELETE/TRUNCATE.
6. Student enrolled at Campus A can be assigned only to Campus A route/
   stop. Driver requires employee/campus assignment; trip with decreasing
   odometer is invalid.
7. Vehicle maintenance expense links to exactly one DB06 posted expense
   and must not create duplicate cash expense.
8. One canteen sale can be reversed only once; immutable operation
   receipts cannot change.
9. All **37 DB07 public tables have RLS enabled**; ordinary anon and
   authenticated direct table access has no grants.

## Mandatory tests before live acceptance

- **Cross-campus and cross-school:** route/lot/item/product/purchase/
  warehouse references, wrong enrollment/class/year, employee driver
  assigned to another campus, expense linked to wrong campus.
- **Concurrency:** two sales for the final unit cannot both succeed;
  stock never negative after reconciled offline requests. Stock
  transfers reserve, dispatch and receive quantities exactly once.
- **Lot and safety:** expired foods cannot be sold, FIFO/lot and
  unit-of-measure controls, confirmed returns/wastage; finished uniform
  sizes and approved recipes.
- **Prices and accounting:** sales use effective approved prices; sale
  totals match lines; cash/bank revenue is posted exactly once in DB06,
  COGS uses actual stock cost, purchases aren't double-classified as
  expense/COGS. DB06 typed journal/source constraints REQUIRE a reviewed
  DB07 integration extension before migration.
- **Uniform workflow:** BOM version and effective date, production batch
  inputs/outputs match, scrap/waste counts, incomplete batches can't
  declare sales of nonexistent stock.
- **Transport:** vehicle capacity, driver licence status and duty
  effective dates, departure/arrival and local timezone, campus
  transfer with old assignment ended, no student route privacy leak.
- **Reversals:** return/refund transaction keeps original sale/stock
  entries intact, restores inventory only when appropriate and posts
  a new balanced DB06 reversal with authorization reason.
- **Finance:** expense requests await DB08 approval, cashbook
  postings and salary/fee operations committed online; no offline
  approvals. Never trust a UI-only school or campus filter.
- **Offline sync:** Windows assigned-campus device may hold pending
  drafts, but server operation UUID + SHA256 payload and stock/
  balance conflicts must be reconciled once online, per DB09. Android
  is online-only in pilot.
- **RLS:** test Owner vs Store Keeper vs Driver vs Canteen Manager
  vs campus Accountant and Principal and parent; current DB01 role
  enumeration is incomplete; expand roles before enabling DB07 APIs.
- **Runtime:** parse and execute draft in local PostgreSQL, run
  synthetic fixture, check FK indexes/latency, security advisors,
  real user permissions and multi-session transaction tests.

## Scope explicitly NOT completed by DDL

Full inventory balance checks; approved goods-receipt quantity totals;
stock transfer paired-source reconciliation; allocation/COGS valuation;
vehicle route occupancy; accounting posting; fleet/driver licensing;
DB08 approval authority; DB09 sync/backups; actual SQLite and Flutter UI.

**Current count after DB07 authoring: 2 of 9 schema domains remain to
design (DB08–DB09); 7 await deployment (DB03–DB09).**
