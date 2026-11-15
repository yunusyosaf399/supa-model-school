# DB01 / DB02 schema review checklist

- [x] DB01 draft hardened to limit sensitive settings to Owners and restrict device access.
- [x] Explicit default-deny role/action permission definitions added.
- [x] Trusted Owner bootstrap runbook authored.
- [x] Two-campus RLS acceptance matrix and negative tests documented.
- [ ] Run Supabase CLI migration new db01_foundation, use its generated migration filename.
- [ ] Apply reviewed DB01 SQL to local PostgreSQL and inspect constraints.
- [ ] Create fictional Auth users and bootstrap test Owner via trusted admin.
- [ ] Verify Owner, Principal, Admin, Accountant, Attendance Staff, inactive accounts and two-campus RLS.
- [ ] Confirm clients cannot mutate membership, settings or device data.
- [ ] Review SECURITY DEFINER helper logic and granted EXECUTE.
- [ ] Validate DB02 and add tested students/admissions security.
- [ ] Run local database advisors and record evidence.
- [ ] Merge PR only with reviewed evidence; deploy version-controlled migrations separately.

**DB01 schema authoring: improved, but NOT runtime-verified or deployed.**
**DB02 remains a draft.**

## D03-T02 — Conditional documents (2026-11-15)
- [x] Admission and document status kept independent; approved admission can be conditional with a deadline.
- [x] Missing, uploaded, verified, rejected and applicable/not-applicable document states represented.
- [x] Separate document upload versions, review decisions and deadline-change audit tables added.
- [x] Composite school/campus/application foreign keys and unique requirement indexes added.
- [x] Static review confirms **10 DB02 public tables / 10 RLS-enable statements** and no direct document client grants.
- [x] Created `supabase/tests/DB02_DOCUMENT_ACCEPTANCE.md` (24 acceptance cases).
- [x] Prepared `supabase/drafts/DB02_DOCUMENT_STORAGE_PLAN.md`.
- [ ] Real PostgreSQL migration, foreign-key checks, file Storage RLS and server transitions NOT tested.
