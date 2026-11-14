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
