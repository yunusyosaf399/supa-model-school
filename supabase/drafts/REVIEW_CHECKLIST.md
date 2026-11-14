# DB01 / DB02 review checklist

- [ ] Run `supabase migration new db01_foundation` to obtain proper migration filename.
- [ ] Review and paste DB01 draft into generated migration.
- [ ] Apply/test on a **local** Postgres, not the production Supabase project.
- [ ] Check `auth.users` references, composite foreign keys, unique indexes.
- [ ] Bootstrap test Owner using a trusted admin operation; no client role-granting.
- [ ] Test 2-campus Owner, Principal, Admin, Accountant, Attendance Staff reads.
- [ ] Confirm no unauthorized INSERT/UPDATE/DELETE by any client.
- [ ] Review private SECURITY DEFINER helper semantics and EXECUTE grants.
- [ ] Verify views/Storage/RPCs do not bypass RLS.
- [ ] Review DB02 draft and link student policies only after approval.
- [ ] No personal student data / real payments until all tests pass.
- [ ] Generate DDL migration in actual CLI, record advisors/test evidence and approve release.

**Status: DRAFT ONLY.**