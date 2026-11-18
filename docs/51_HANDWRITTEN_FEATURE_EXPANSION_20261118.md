# Supa Model School — Handwritten feature expansion (18 November 2026)

**Source:** Three provided handwritten notebook photographs; 25 school-app features, 14 fee/income records, and 18 expense/payment entries (**57 line items**).

**Status:** Requirements captured and mapped, **NOT 57 completed features**. Reuse and extend DB01–DB09 and current DB10–DB15 implementations. This document supersedes no deployed migration or real financial transaction history. Machine-readable inventory: `planning/HANDWRITTEN_FEATURE_MATRIX_20261118.csv`.

## Implementation state verified against the repository

- Current Flutter Owner shell has live/developing modules for owner authentication, campus/academic setup, admissions, student directory, and dashboard. Fees, Expenses, Attendance, Employees and Payroll screens presently use non-operational previews.
- DB03 fees, DB04 attendance, DB05 payroll, DB06 cashbook/expenses, DB07 inventory/canteen/uniform/transport, DB08 approvals/permissions/notifications, and DB09 reporting/sync **schemas exist**. Runtime posting, granular RLS/service operations and UI integrations are not finished.
- Authenticated permissions must be enforced by backend; the Owner's future-module permission catalog must not imply that modules are implemented. No new user permission should bypass campus isolation.
- **Do not seed fictitious sales, payments or profits.** The proposed optional financial category seed script is `supabase/seed/20261118_handwritten_financial_categories.sql`; it creates labels only, not operational APIs.

## A. School App Features — 25

| ID | Handwritten requirement | Module | Current state | Next implementation |
|---|---|---|---|---|
| SF01 | Staff management (data) | Employees & Payroll | schema_only | Employee directory, employment, assignment and campus-scoped profiles |
| SF02 | Student management (data) | Students | partial_ui | Extend authenticated student profiles and academic history |
| SF03 | Staff attendance | Attendance | schema_only | Authorized staff attendance, corrections, monthly summary |
| SF04 | Student attendance | Attendance | schema_only | Class/section daily register, corrections and exports |
| SF05 | Communication with parents | Communications | new_scope | Private parent messages, recipients, attachments and delivery audit |
| SF06 | Timetable, examinations, date sheets, results | Academics & Exams | new_scope | Timetable, exam sessions, date sheets, marks and published results |
| SF07 | ID cards, result cards, certificates | Documents | new_scope | Versioned printable templates with issue history and scoped data |
| SF08 | Test and exam results with printing | Exams | new_scope | Exam/test score entry, verification, PDF print/export |
| SF09 | General notices | Communications | new_scope | Campus/class-targeted notices, read receipts, scheduling |
| SF10 | Syllabus management | Academics | new_scope | Subjects, terms, syllabus files, versions and teacher access |
| SF11 | Parent-teacher communication | Communications | new_scope | Permissioned two-way conversations with student context |
| SF12 | Downloading and printing | Documents | new_scope | Authorized PDF/export/printing of relevant records |
| SF13 | Admissions | Admissions | partial_ui | Complete verified submission and approval end-to-end checks |
| SF14 | WhatsApp alerts | Communications | new_scope | Opt-in gateway templates, delivery status and consent |
| SF15 | Homework diary | Academics | new_scope | Assigned class/subject homework with due dates and attachments |
| SF16 | Equipment and library record | Library & Inventory | new_scope | Asset register plus books, loans, returns and fines |
| SF17 | Notifications | Communications | schema_only | In-app notification preferences, delivery and read history |
| SF18 | Daily reports management | Reports | schema_only | Date/campus/category reports from verified records only |
| SF19 | Parent portal (optional) | Parent Portal | new_scope | Guardians see only authorized linked children, fees and school updates |
| SF20 | Daily diary | Academics | new_scope | Daily class diary/lesson notes separate from homework |
| SF21 | Question bank | Exams | new_scope | Subject/class/chapter question bank, revision and permissions |
| SF22 | Award list | Exams | new_scope | Exam mark award sheets and approvals, export/print |
| SF23 | General task management | Operations | new_scope | Assigned tasks, due dates, status, audit |
| SF24 | Download center | Documents | new_scope | Permission-filtered published school files and downloads |
| SF25 | Student promotion | Students & Academics | new_scope | Year-end promotion, section allocation and retained enrollment history |

## B. Fee and income records — 14

| ID | Handwritten requirement | Module | Current state | Next implementation |
|---|---|---|---|---|
| FR01 | Fee collection with student + office slip | Fees & Receipts | schema_only | Atomic receipts and two-copy PDF; no local-only posted receipt |
| FR02 | Student/class/whole-school fee record | Fees & Reports | schema_only | Role-authorized drilldowns and totals |
| FR03 | Monthly fee total record | Fees & Reports | schema_only | Month-by-month assessed, paid, due and credit |
| FR04 | Transport fee record | Fees & Transport | schema_only | Monthly transport charge per enrolled rider; route links |
| FR05 | Uniform fee record | Uniform Sales | schema_only | Retail sale or configured fee, never count both for one item |
| FR06 | Fines record | Fees & Library | schema_only | Manual fine category, reason, evidence, waiver |
| FR07 | Books and stationery fee record | Fees & Retail | schema_only | Separate compulsory fee from physical retail sale |
| FR08 | Examination fee record | Fees | schema_only | Configured charge category and receipts |
| FR09 | Promotion fee record | Fees & Promotion | schema_only | Optional one-time assessment tied to promotion |
| FR10 | Tuition fee record | Fees | schema_only | Monthly charge and per-category scholarship, partial payments |
| FR11 | Certificates fee record | Fees & Documents | schema_only | Configured manual charge and linked issuance |
| FR12 | Stationery selling record | Inventory & Retail | new_scope | Additional retail POS sales and stock/cost posting |
| FR13 | Daily canteen selling record | Canteen | schema_only | Daily campus/item/receipt totals from posted sales |
| FR14 | Daily and net profit of canteen items | Canteen & Accounts | schema_only | Profit = posted sales minus verified COGS and allocated operating costs |

## C. Expenses and outgoing payments — 18

| ID | Handwritten requirement | Classification | Current state | Next implementation |
|---|---|---|---|---|
| EX01 | Staff monthly salary | Payroll | schema_only | Use payroll accrual/payment; never duplicate general expense |
| EX02 | Building rent | Expenses | schema_only | Operating rental expense with account and approval |
| EX03 | Hotel expenses | Expenses | schema_only | Hotel/travel business purpose and receipts |
| EX04 | WiFi billing | Expenses | schema_only | Internet/communications bill |
| EX05 | Medical expenses | Expenses | schema_only | Medical expense with privacy-aware attachments |
| EX06 | School stationery expenses (markers/ink/copy paper) | Expenses | schema_only | Consumed school supplies, not resale stock |
| EX07 | Lab equipment expenses | Expenses & Assets | schema_only | Durable equipment vs consumables classification |
| EX08 | Examination expenses | Expenses | schema_only | Exam paper, invigilation and operational costs |
| EX09 | Vehicle oil/fuel expenses | Transport & Expenses | schema_only | Fuel payment linked to vehicle and trip if relevant |
| EX10 | Vehicle maintenance expenses | Transport & Expenses | schema_only | Repair expense linked once to maintenance event |
| EX11 | Tailor payment | Uniforms & Expenses | schema_only | Tailoring service or uniform production cost |
| EX12 | General maintenance expenses | Expenses | schema_only | Repairs and maintenance category |
| EX13 | Stationery purchase for selling | Inventory Procurement | schema_only | Inventory acquisition not immediate COGS |
| EX14 | Canteen item purchases | Inventory Procurement | schema_only | Inventory receipt + payable/payment; COGS only on sale |
| EX15 | Other payments | Expenses | schema_only | Require category, purpose, payee and authorization |
| EX16 | Payment to Principal | Payroll / Reimbursement | schema_only | Salary through payroll; reimbursement through approved expense |
| EX17 | Teacher mobile packages | Expenses / Allowances | schema_only | School business connectivity or approved payroll allowance |
| EX18 | Payment to tuition teachers | Payroll / Contractor | schema_only | Employee salary vs external tutor invoice, not both |

## Consolidated module navigation (retain current responsive shell)

Keep existing Dashboard, Students, Admissions, Fees, Attendance, Employees, Payroll, Expenses, Reports, Sync Center, Settings and Academic Setup navigation stable. New authenticated child sections, when genuinely connected, will include:

- **Academics:** Timetable, Curriculum/Syllabus, Homework Diary, Daily Diary, Promotions.
- **Examinations:** Test/Exam Setup, Date Sheets, Award Lists/Marks, Results & Report Cards, Question Bank, Exam Reports.
- **Communications:** Notices, Parent Messages, Parent–Teacher Conversations, Notifications, WhatsApp Alerts (opt-in).
- **Documents:** ID Cards, Certificates, Printable Reports, Download Center.
- **Finance:** Fee Types & Plans, Monthly Dues, Collections/Receipts, Discounts/Fines, Category Reports, Expenses/Approvals/Cashbook.
- **School Business:** Canteen POS, Stationery Retail POS, Inventory, Uniforms, Suppliers, Purchases, Cost/Profit.
- **Operations:** Library & Lending, Equipment, Transport/Fleet, Staff Tasks, Daily Reports, Parent Portal (optional).

Preserve responsive desktop/Android behavior: permanent desktop sidebar and right-hand content switching; mobile compact navigation. Do **not** show actions as usable if the backend denies them. Owner may grant section/action permissions only when real backend operations support the same rights.

## Required workflow definitions

### Fee collection / income
1. Configure category by campus/class/year and charge frequency. Distinguish recurring tuition/transport from one-time exam/promotion/certificate charges, manual fines and retail sales.
2. Generate verified fee assessments **once** per student/month/category with exact integer minor units, scoped scholarship and clear due date. Never charge one uniform or stationery sale twice.
3. Take partial/multiple fee payments with unique operation IDs; verify uploaded bank receipts. Post receipt + payment allocations + cash/bank journal atomically on the server. Produce **one printable slip containing student and office copies**, immutable receipt number and transaction reference.
4. Student/class/campus/whole-school and month-wise reports must derive from posted charges/receipts, not edited summary counters. Respect year and access filters.

### Canteen / stationery / uniforms
1. Procure physical inventory, record received stock and supplier invoice/payment separately.
2. Confirm price and available campus stock at POS; post each item sale and stock movement with cash/bank ledger exactly once.
3. **Gross profit = sales minus COGS**. **Net profit = gross profit minus applicable operating expenses**; allocate shared costs explicitly or show "not allocated" rather than a misleading net profit. Track day, campus, product, quantity and source receipts.
4. A stock purchase is an asset acquisition and not itself cost of goods sold. Tailoring paid for uniform manufacture can be production cost rather than a generic school repair expense.

### Expense recording and payroll
1. Owner manages expense categories and approvals. Expenses must carry campus, date, amount, category, business purpose, payee, payment account, attachments, operation UUID and approval history.
2. New expense requests remain pending; only authorized online decisions can result in immutable cash/bank postings. A declined or draft entry never reduces the cashbook.
3. Salaries to staff/principal/employed tutors are processed through DB05 payroll, not duplicated as manual DB06 expenses. Principal reimbursements and payments to external tutors require separately documented purposes and classifications.
4. Link vehicle maintenance/fuel to transport, and purchased stock to inventory, using references that prevent second journal posting.

### Academics, communications and printing
1. Exam results: setup -> assigned-teacher marks entry -> validation -> Principal-approved publishing -> grade-based report/award list and PDF export. Maintain recheck/version history.
2. Homeworks, daily diary, syllabus, notices and parent messages must be campus/class/section scoped, with author/time, visibility, due date or published date, file references and edit history.
3. Parent portal and WhatsApp alerts require verified guardian–student linkage, communication preferences, explicit opt-in where applicable, and clear delivery-failure handling. Don't expose students across families.
4. Certificates, IDs, reports and downloads require role-granted access and private storage or server-generated signed access, with printing available only for verified records.

## Delivery order and acceptance criteria

**Phase 1 (highest priority):** Finish admissions and student records, make DB03/DB06 fee collection + dual-copy receipt and month-wise records work end to end; add owner-controlled expense taxonomy and pending expense requests. Test campus isolation, partial payment retries, concurrent receipt allocation and audit.

**Phase 2:** Expense approvals and posted cashbook, DB05 payroll, staff/student attendance, transport monthly billing and vehicle maintenance. Test no duplicate ledger entries or offline approvals.

**Phase 3:** DB07 inventory procurement, stationery retail, canteen and uniforms, COGS and true daily/net profit reports; verify stock/financial reconciliation.

**Phase 4:** Timetable, exams/datesheets/results/award lists, syllabus, homework/diaries, printable cards and certificates, libraries and equipment.

**Phase 5:** Parent/teacher communication, notices, WhatsApp provider integration, task manager, download center, parent portal and extra analytics.

For every newly delivered feature: implement secure school/campus RLS or trusted RPC, authenticated Dart repository, responsive UI, permission-level control, success/error states, real data only, unit/widget/integration tests, and a tested deployment path. Keep current records and IDs intact. This is **not** authorization to auto-deploy untested financial schema changes to production.
