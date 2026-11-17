# Supa Model School — Live synthetic dataset and test result

**Date:** 2026-11-17  
**Supabase ref:** `uebzvfzpbqqttbqyxxos`  
**Existing school:** `aaa87efd-ba04-43e1-9fe6-7ad8d6cac654`  
**Campus:** `e2308d36-ff0d-438d-97b4-95ed6d4c13c6`  
**Status:** Test data deliberately committed to LIVE Supabase at user's explicit direction. **Not real pupils, not production-ready.**

## Persisted fixtures

- Completed Owner initial setup using existing verified `public.owner_complete_initial_setup` RPC (PKR, Asia/Karachi, academic year 2026-04-01 to 2027-03-31).
- Created **4 classes** (Nursery, Grade 1, Grade 2, Grade 3) and **2 sections each (A/B)** through the existing Owner atomic RPC.
- Added **32 fictional students**, **32 enrolled records**, **32 synthetic guardians** and **32 student-guardian links**. Registrations `TEST-2026-0001` through `TEST-2026-0032`; student names begin with `TEST `. These were seeded via privileged administrative SQL, **not** the admission UI/approval workflow; never mistake them for proof that admissions submission is implemented.
- Added **5 admission drafts** through `app_private.admission_save_draft` with a verified Owner actor, giving **10 missing-document rows** (birth + transfer) and **5 audit events**. Names begin `TEST Admission Applicant `.
- Deleted the single `app_private.dashboard_demo_snapshots` row for this school and campus, after confirming live dashboard mode.
- School-wide counts and Owner-scoped dashboard API were queried successfully. Authenticated Owner dashboard returned `is_demo=false`, `source=live_db02_summary`, `active_students=32`, `year_label=2026-2027`.
- The existing repository still contains a separate unauthenticated *Flutter UI preview* mode. That mode and the student directory preview are **not** connected to these live rows; this dataset does not prove Windows/Android launch or student-directory rendering.

## Safe verification

Run `supabase/tests/DB10_LIVE_FIXTURE_ASSERTIONS.sql` via an authorized SQL session. This runs assertions in a rollback-only transaction: expected fixture counts, live Owner dashboard, and denied unknown actor. After execution, confirm no data changed.

## Cleanup / migration guidance

All student registrations start with `TEST-2026-`; their name has a `TEST ` prefix. All five admission drafts start with `TEST Admission Applicant `. Guardians are prefixed `TEST Guardian ` or `TEST Admission Guardian `.

**Do not run blanket DELETE/TRUNCATE against school, student, admission or finance tables**: records have foreign keys and append-only audit/operation constraints. Snapshot first, then create an explicit scoped cleanup plan listing dependent rows and confirm it before cleaning. The school, campus, year and classes are now configured and may be used as future non-synthetic school settings.

No payment, fee receipt, payroll, expense or financial ledger transaction was fabricated. Their APIs, posting flows and accounting controls require separate end-to-end testing. Active dashboard financial and attendance metrics legitimately remain null.

## Pending application tests

- Run Flutter on Windows with correct `SUPABASE_URL` and publishable key via `--dart-define`, sign in as the existing Owner, reload Dashboard and confirm live 32 active students.
- The **Students** screen currently uses an isolated demo projection in Flutter: implement the authorized server projection and wire it before claiming those 32 entries show there.
- Run actual admissions, document upload, permissions, offline sync, and accounting end-to-end workflows independently.
