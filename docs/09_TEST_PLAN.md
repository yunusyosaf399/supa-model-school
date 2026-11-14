# Pilot acceptance tests

- AT01: Conditional admission with missing documents and due date; principal approval state remains separate.
- AT02: Duplicate student application warning; no accidental second active registration.
- AT03: Campus A staff cannot see Campus B students, financial records, search results or Storage files.
- AT04: Monthly scheduled fee generation repeated => one logical charge.
- AT05: Two valid partial payments => both preserved and accurately allocated.
- AT06: Identical retry / lost acknowledgment => one confirmed receipt.
- AT07: Distinct suspicious duplicate => unresolved review without silent merge.
- AT08: Advance credit cannot be consumed twice.
- AT09: Past attendance correction requires reason and audit; Leave/Late percentages correct.
- AT10: Employee advance recovery cannot double count salary cost.
- AT11: Offline expense requiring approval => request only, never posted before approval.
- AT12: Daily close with pending sync cannot be fully finalized; difference explanation required.
- AT13: Owner-approved transfer moves receivable collection responsibility, not new debt.
- AT14: Offline edited record vs newer online record => conflict with evidence.
- AT15: Backup restores confirmed cloud + eligible pending records, no cloud overwrite.
- AT16: Fee and salary slips reflect correct figures and provisional state.

**Status:** Test specification only. None of these tests is proven to pass.