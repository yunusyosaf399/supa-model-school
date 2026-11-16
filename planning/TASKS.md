# Development task tracker

Last verified: 2026-11-16.
**114 tasks: 28 DONE / 85 TODO / 1 IN_PROGRESS / 0 BLOCKED.**
Authoritative machine-readable status: [tasks.csv](tasks.csv).

**Important:** D03-T03–T05 and D04-T01–T04 are DONE for code authoring/static source review only. The user reports Windows Flutter tests and build passed on 2026-11-15; logs were not independently inspected. Schema-first design is now prioritized: DB03 PR #25, DB04 PR #26, and DB05 PR #29 remain DRAFT and NOT deployed, and no Flutter changes are planned in this workstream. Android runtime, Flutter analyzer evidence, PostgreSQL RLS/Edge, offline security, and hosted deployment remain unfinished.

## Setup
- [x] `SETUP-01` Identify Supabase link and organization — **DONE**
- [x] `SETUP-02` Check Supabase project creation cost — **DONE**
- [x] `SETUP-03` Verify GitHub account and connector access — **DONE**
- [x] `SETUP-04` Create local project starter — **DONE**
- [x] `SETUP-05` Draft SRS and architecture documents — **DONE**
- [x] `SETUP-06` Create 21-day task backlog — **DONE**
- [x] `SETUP-07` Compile and run Flutter tests — **DONE (user-reported Windows success)**
- [x] `SETUP-08` Verify new private GitHub repository — **DONE**
- [x] `SETUP-09` Create Supabase project — **DONE**

## Day 01 — Week 1
- [x] `D01-T01` Review project access, cost and region — **DONE**
- [x] `D01-T02` Create Supabase cloud project — **DONE**
- [x] `D01-T03` Create private GitHub repository — **DONE**
- [x] `D01-T04` Commit source scaffold and documents — **DONE**
- [x] `D01-T05` Install and validate Flutter toolchain — **DONE (user-reported Windows success)**

## Day 02 — Week 1
- [x] `D02-T01` Generate Windows and Android Flutter runners — **DONE (not yet compiled)**
- [ ] `D02-T02` Verify Flutter analyze and widget tests — **TODO**
- [ ] `D02-T03` Author and statically review DB01 foundation schema — **DONE**
- [ ] `D02-T04` Verify DB01 migration and two-campus RLS locally — **IN_PROGRESS**
- [ ] `D02-T05` Build authentication and campus selection UI — **TODO**

## Day 03 — Week 1
- [x] `D03-T01` Author and statically review student and guardian schema — **DONE**
- [x] `D03-T02` Author and statically review conditional admission documents schema — **DONE**
- [x] `D03-T03` Author server-side admission workflow SQL and authenticated Edge function — **DONE**
- [x] `D03-T04` Author responsive six-stage Flutter admission wizard screens — **DONE**
- [x] `D03-T05` Author campus-scoped student directory and search UI preview — **DONE**

## Day 04 — Week 1
- [x] `D04-T01` Author 11-table campus-scoped SQLite/Drift v1 schema and Windows database wrapper — **DONE**
- [x] `D04-T02` Author durable UUID operation outbox and atomic local draft writes — **DONE**
- [x] `D04-T03` Author private idempotent admission ingest schema and authenticated Edge endpoint — **DONE (source only)**
- [x] `D04-T04` Author commit-ordered campus admission change log and cursor pull endpoint — **DONE (source only)**
- [ ] `D04-T05` Test assigned campus offline vertical slice — **TODO**

## Day 05 — Week 1
- [ ] `D05-T01` Finish admission wizard and document workflow — **TODO**
- [ ] `D05-T02` Implement Principal approval owner-toggle — **TODO**
- [ ] `D05-T03` Create permanent registration generator — **TODO**
- [ ] `D05-T04` Add academic enrollment history — **TODO**
- [ ] `D05-T05` Build student profile tabs — **TODO**

## Day 06 — Week 1
- [x] `D06-T01` Author DB03 fee category/class plans and complete 18-table fee/billing DDL — **DONE (schema source only)**
- [ ] `D06-T02` Implement student transport and discounts — **TODO**
- [ ] `D06-T03` Generate idempotent monthly charges — **TODO**
- [ ] `D06-T04` Build monthly due ledger UI — **TODO**
- [ ] `D06-T05` Test fee history after promotion — **TODO**

## Day 07 — Week 1
- [ ] `D07-T01` Test admission and fee end-to-end — **TODO**
- [ ] `D07-T02` Verify cross-campus read/write isolation — **TODO**
- [ ] `D07-T03` Configure approved school settings — **TODO**
- [ ] `D07-T04` Write week 1 QA evidence — **TODO**
- [ ] `D07-T05` Review week 1 blockers — **TODO**

## Day 08 — Week 2
- [ ] `D08-T01` Implement receipt schema — **TODO**
- [ ] `D08-T02` Atomic receipt allocation — **TODO**
- [ ] `D08-T03` Implement partial payment UI — **TODO**
- [ ] `D08-T04` Implement cash/bank method mapping — **TODO**
- [ ] `D08-T05` Test identical payment retry — **TODO**

## Day 09 — Week 2
- [ ] `D09-T01` Implement advance-credit ledger — **TODO**
- [ ] `D09-T02` Build advance payment UI — **TODO**
- [ ] `D09-T03` Implement configured credit application — **TODO**
- [ ] `D09-T04` Implement fixed/percentage discounts — **TODO**
- [ ] `D09-T05` Test monthly defaulter report — **TODO**

## Day 10 — Week 2
- [ ] `D10-T01` Build fee slip and receipt template model — **TODO**
- [ ] `D10-T02` Build PDF fee slip preview — **TODO**
- [ ] `D10-T03` Mark provisional offline receipts — **TODO**
- [ ] `D10-T04` Implement receipt numbering service — **TODO**
- [ ] `D10-T05` Test print/export — **TODO**

## Day 11 — Week 2
- [x] `D11-T01` Author DB04 campus attendance schema and immutable correction tables — **DONE (schema source only)**
- [ ] `D11-T02` Build student attendance UI — **TODO**
- [ ] `D11-T03` Implement today-only and backdated rules — **TODO**
- [ ] `D11-T04` Implement attendance correction audit — **TODO**
- [ ] `D11-T05` Build monthly attendance report — **TODO**

## Day 12 — Week 2
- [x] `D12-T01` Author DB05 employee/campus/teaching assignment and payroll schema — **DONE (source only)**
- [ ] `D12-T02` Build employee directory and profile — **TODO**
- [ ] `D12-T03` Generate fixed-salary payroll — **TODO**
- [ ] `D12-T04` Add manual adjustments with reasons — **TODO**
- [ ] `D12-T05` Implement partial salary payment — **TODO**

## Day 13 — Week 2
- [ ] `D13-T01` Implement salary advances and recovery — **TODO**
- [ ] `D13-T02` Build configurable payroll approval — **TODO**
- [ ] `D13-T03` Generate salary slips — **TODO**
- [ ] `D13-T04` Implement categorized expenses schema — **TODO**
- [ ] `D13-T05` Build expense entry and approval status — **TODO**

## Day 14 — Week 2
- [ ] `D14-T01` Implement financial cash/bank accounts — **TODO**
- [ ] `D14-T02` Implement linked account transfers — **TODO**
- [ ] `D14-T03` Build campus cashbook list — **TODO**
- [ ] `D14-T04` Reconcile financial transactions — **TODO**
- [ ] `D14-T05` Week 2 QA and scope review — **TODO**

## Day 15 — Week 3
- [ ] `D15-T01` Implement generic approval requests — **TODO**
- [ ] `D15-T02` Add expense threshold Owner setting — **TODO**
- [ ] `D15-T03` Implement financial correction request — **TODO**
- [ ] `D15-T04` Build Owner approval inbox — **TODO**
- [ ] `D15-T05` Test offline approval cannot bypass server — **TODO**

## Day 16 — Week 3
- [ ] `D16-T01` Implement Owner-approved campus transfer — **TODO**
- [ ] `D16-T02` Move receivable collection responsibility — **TODO**
- [ ] `D16-T03` Block transfer with unsynced receipts — **TODO**
- [ ] `D16-T04` Build transfer request/review UI — **TODO**
- [ ] `D16-T05` Test transfer conflict scenario — **TODO**

## Day 17 — Week 3
- [ ] `D17-T01` Implement sync conflict detection — **TODO**
- [ ] `D17-T02` Build side-by-side conflict review — **TODO**
- [ ] `D17-T03` Implement automatic sync and Sync Now — **TODO**
- [ ] `D17-T04` Test offline/online concurrent edits — **TODO**
- [ ] `D17-T05` Test lost acknowledgment and resume — **TODO**

## Day 18 — Week 3
- [ ] `D18-T01` Build daily closing data model — **TODO**
- [ ] `D18-T02` Build closing/reconciliation UI — **TODO**
- [ ] `D18-T03` Block final close with unresolved sync — **TODO**
- [ ] `D18-T04` Add closed-day approved adjustment — **TODO**
- [ ] `D18-T05` Test inter-campus cash transfers — **TODO**

## Day 19 — Week 3
- [ ] `D19-T01` Configure backup destinations — **TODO**
- [ ] `D19-T02` Build consistent SQLite backups — **TODO**
- [ ] `D19-T03` Record cloud snapshot manifests — **TODO**
- [ ] `D19-T04` Rehearse failed-device restore — **TODO**
- [ ] `D19-T05` Build core reporting and search — **TODO**

## Day 20 — Week 3
- [ ] `D20-T01` Build campus and Owner dashboards — **TODO**
- [ ] `D20-T02` Build configurable shortcut manager — **TODO**
- [ ] `D20-T03` Test Windows build and real printer — **TODO**
- [ ] `D20-T04` Test Android online data entry — **TODO**
- [ ] `D20-T05` Run financial and sync acceptance suite — **TODO**

## Day 21 — Week 3
- [ ] `D21-T01` Fix remaining release-critical defects — **TODO**
- [ ] `D21-T02` Perform final restore rehearsal — **TODO**
- [ ] `D21-T03` Package Windows and Android builds — **TODO**
- [ ] `D21-T04` Pilot handover and operating SOP — **TODO**
- [ ] `D21-T05` Finalize release and remaining backlog — **TODO**

## Links
- [Week 1 issue](https://github.com/yunusyosaf399/supa-model-school/issues/2)
- [Schema review issue](https://github.com/yunusyosaf399/supa-model-school/issues/3)
- [Week 2 issue](https://github.com/yunusyosaf399/supa-model-school/issues/4)
- [Week 3 issue](https://github.com/yunusyosaf399/supa-model-school/issues/5)
- [Schema draft PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1)
