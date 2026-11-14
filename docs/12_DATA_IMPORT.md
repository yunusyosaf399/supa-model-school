# School data import plan

No real student/guardian data in GitHub.

1. Obtain source format and documented school authorization before import.
2. Inventory student names/IDs, guardians, campuses/classes, historical fees, arrears, receipts and employee/payroll records.
3. Map legacy identifiers to stable UUIDs while preserving original source references.
4. Detect duplicates and ambiguous fee records for manual review; never fabricate or silently merge them.
5. Test import on fictional/staging data first, compare counts and opening balances with paper/Excel originals.
6. Only then run approved authorized import against live school, with pre-import backup and rollback/recovery plan.

Exact templates, source data availability and import permissions are pending.