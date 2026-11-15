# Supa Model School — Complete Windows and Android UI design

Date: 15 November 2026  
Design status: **UI-only navigable prototype, not a live school system**  
Branch: **ui/complete-screen-design-system**

## 1. Design objective

Design one coherent, English-first, responsive Flutter management application for Supa Model School, with optional future Pakistani Urdu translations. The initial pilot must prioritize safe day-to-day campus work over an ambitious but untested feature list.

The UI preview includes **120 named screens across 19 module groups**. It uses shared layout patterns so every destination can be inspected in the Windows and Android applications, while detailed production workflows are implemented module by module after validation.

**A screen appearing in the UI catalog does not mean the related backend feature works.** Demo data are fictional; payment, approval, file upload and sync finalization are intentionally not implemented by this preview.

## 2. Platforms and navigation

### Windows desktop

- Wide layout at width >=950 logical pixels: persistent left Material navigation rail, with labels when >=1360.
- Global top bar: school identity, academic-year choice, sample campus choice, search, notifications and account avatar.
- Main workspace: module heading, horizontally scrollable screen tabs, content with filter/table/form panels.
- Current primary desktop is assigned to exactly one campus for trusted offline access; authorized cross-campus data are online-only and must never be silently cached on the assigned-campus SQLite database.
- Support keyboard-driven operations: Ctrl+F screen/action search, Ctrl+S Students and Ctrl+P Collect Fee are prototype shortcuts. In the production shortcut editor, users need conflict detection, protection of unsaved forms, and explicit shortcuts for Save and Print.

### Android

- Bottom navigation: Home, Students, Fees, Attend and More.
- More opens the entire module catalog.
- Responsive forms wrap into touch-friendly fields; wide tables scroll horizontally where needed.
- Online entry only for pilot. When offline, block live submissions and explain that an internet connection is required. Do not pretend that a local Android draft was saved unless local persistence is explicitly implemented.

### Shared design language

- **Brand:** Supa Model School, academic/financial operations.
- **Primary:** deep teal (approximately #0B7269); **surface:** white; **workspace:** pale #F6F8FB; **text:** slate.
- **Shape:** 10–15 px corners; clear dividers; consistent cards and status chips.
- **Type:** scalable Material text styles, English labels, 12–18 px dense operational controls.
- **Accessibility:** minimum 48 logical px touch targets for essential actions, labeled form inputs, sufficient contrast, keyboard and focus support, semantic button labels.
- **Localization:** externalize text to string keys in the production implementation, support RTL for optional Urdu only after the English pilot works.

## 3. Screen catalog: 19 groups / 120 destinations

| Module | Screens |
| --- | --- |
| Dashboard | Campus Overview; Owner Overview; Notifications & Tasks |
| Students | Student Directory; Student Profile; Enrollment History; Promotions; Campus Transfer; Student Documents |
| Admissions | Admissions Inbox; Six-Step Admission; Principal Review; Missing Documents; Admission Settings |
| Fees | Fee Overview; Collect Fee; Student Fee Ledger; Monthly Fee Generation; Class Fee Plans; Student Fee Settings; Discounts & Waivers; Advance Credits; Fee Receipts & Slips |
| Attendance | Daily Student Register; Staff Attendance; Daily Absentees; Monthly Attendance; Attendance Corrections; Attendance Calendar |
| Employees | Employee Directory; New Employee; Employee Profile; Temporary Assignment |
| Payroll | Payroll Overview; Generate Payroll; Payroll Register; Allowances & Deductions; Salary Advances; Pay Salary; Salary Slips; Salary Payment History |
| Expenses | Expense Overview; Record Expense; Expense Register; Expense Categories; Medical & Examination Costs |
| Finance | Financial Overview; Daily Cashbook; Daily Cash Closing; Cash & Bank Accounts; Account Transfer; Other Income; Owner Investments; Principal Cash Transfers; Transaction History |
| Canteen | Canteen Overview; Products; Purchases & Stock In; Daily Sales; Stock Movements; Canteen Profit Summary |
| Uniforms | Uniform Overview; Cloth & Materials; Material Purchases; Tailoring & Wages; Production Batches; Uniform Stock & Sales; Uniform Costing Analysis (later) |
| Vehicles | Vehicle Directory; Driver Details; Fuel Expense; Maintenance Expense |
| Approvals | Pending Approvals; Approval Review; Correction Requests; Approval History |
| Reports | Reports Center; Student Reports; Fee Collection Report; Outstanding Dues Report; Attendance Report; Payroll Report; Expense Report; Cash & Bank Report; Canteen & Uniform Report; Owner Campus Comparison; Audit Report |
| Sync Center | Synchronization Overview; Pending Uploads; Conflict Review; Synchronization History; Backup & Recovery; Backup History |
| Settings | School Profile; Campuses; Academic Years; Classes & Sections; Users & Roles; Permissions Matrix; Approval Policies; Fee Policies; Payroll Policies; Offline Campus & Devices; Backup Destinations; Keyboard Shortcuts; Printing & Slips; Appearance & Language; Audit & Activity Log |
| Search & Print | Global Search; Action Command Palette; Receipt Preview; Monthly Fee Slip; Salary Slip Preview; Expense Voucher; Bank / Cash Payment Slip |
| Authentication | Sign In; Forgot Password; Offline Session Status |
| Examinations (Later) | Exam Register; Student Exam History |

The six-stage admission wizard and student directory in the current Flutter repository remain authoritative for their already-authored UI. The catalog links into those existing pages; it does not replace them with generic fake production forms.

## 4. Critical workflows and screen-level contracts

### Admission

1. Admin saves draft student, family, guardian, campus, class and fee information.
2. Documents are tracked as pending/verified/overdue, with a conditional admission deadline where the Owner allows it.
3. Principal approves if required by Owner settings; otherwise the trusted service follows the configured direct-activation path.
4. A unique permanent registration number is assigned during trusted finalization.
5. Campus transfer requires Owner approval; academic and financial histories stay attached to the origin campus while outstanding collection responsibility moves without duplicating debts.

### Fee collection

1. Search/select an authorized student, campus and month.
2. Display original charges, category-specific discounts, arrears, advance credits and already paid amounts.
3. Enter cash or bank transfer amount, then preview allocation to charges. Allow full, partial or advance payment.
4. Use stable unique operation IDs and server-side atomic financial posting to prevent duplicates. An offline desktop receipt is clearly **Pending Sync**; no globally confirmed receipt is displayed until server acceptance.
5. Suspected duplicates and sync conflicts show side-by-side records, not silent overwrites.

### Attendance

1. Attendance Staff chooses date (today only), authorized campus, class and section.
2. Mark every student Present, Absent, Leave or Late; incomplete register remains a draft.
3. Leave counts as non-attended; Late counts as attended but is reported separately.
4. Admin can correct prior days with mandatory reason, audit and authorized access.
5. Staff attendance also supports optional check-in and check-out.

### Payroll

1. Fixed monthly salary by employee, with primary campus and temporary assignments.
2. Admin-selected allowances/deductions; no automatic absence deduction.
3. Advance recovery can be scheduled or manually selected.
4. Owner-configured approval policy, full/partial payments, cash/bank and printable salary slips.
5. Preserve payable, paid and outstanding amounts separately.

### Cashbook and approvals

1. Every campus has separate cash/bank accounts.
2. Account transfers and Owner investments are not tuition revenue.
3. Daily cash close shows opening balance, money received/spent/transferred, expected closing, physical cash counted and discrepancy.
4. If relevant offline events are pending, the closing remains **Provisional**.
5. Owner authorization is needed for approved financial corrections; approval-dependent offline actions stay pending until online authorization.

### Sync and backup

1. One designated Windows computer maintains local Drift/SQLite operations for its assigned campus only.
2. Upload local outbox, validate on Supabase, download authorized changes, then display conflicts and sync history.
3. Sync automatically upon restored connectivity and offer Sync Now when actual integration is ready.
4. Owner configures backup destination(s); recovery restores verified cloud records plus available independent backups without blindly overwriting newer data.

## 5. Shared visual components to extract during implementation

AppShell, SchoolAppBar, CampusSwitcher, AcademicYearSwitcher, ModuleRail, MobileModuleSheet, ScreenTabs, GlobalSearchPalette, StatusChip, FinancialAmount, MetricTile, AdaptiveDataTable, FilterBar, RecordFormSection, StudentPicker, EmployeePicker, DocumentStatusCard, ApprovalComparison, CashReconciliationPanel, AttendanceStatusSelector, PrintTemplate, OfflineSyncBanner, EmptyState, ErrorState, PermissionDeniedState, and ConfirmationDialog.

Current preview intentionally reuses generic overview, table, form, attendance, payment, closing, approvals, synchronization, slip and settings patterns. Production screens should be extracted into feature folders and independently tested.

## 6. Pilot priority gates

**P0: build and test for the school pilot.** Login/roles/campus; admissions and students; monthly fees, discounts, arrears, partial/advance collection and receipts; student/staff attendance; employees and fixed payroll; expenses, cash/bank and cash closing; approvals; reports; assigned-campus desktop offline sync; duplicate/conflict review; backup/recovery and essential printed slips.

**P1: simplified operational expansion after P0 safety tests.** Basic canteen stock/sales, uniform purchasing/production/stock, vehicle and fuel expense recording, richer owner analytics and shortcut customization.

**Later:** Full examination/results entry, teacher and parent accounts, advanced manufacturing costing, advanced multi-stage approval and detailed accrual accounting.

The 21-day deadline targets a defensible operational pilot, not production completion of all 120 designs.

## 7. Demo functionality and deliberate limitations

### Available now in the preview branch

- Navigate between all named screen destinations on desktop and Android.
- Search screen/action names.
- View fictional dashboard KPIs and chart bars, filtered sample tables, editable draft form visuals and slip designs.
- Preview fee and salary allocations without posting anything.
- Mark a five-person attendance example and review its counts.
- Enter a physical cash count and see the computed discrepancy.
- Inspect fictional approval requests and synchronization statuses.
- Open the pre-existing detailed Flutter admission wizard and student directory.

### Not available yet

No real credentials/authentication, Supabase read/write, Drift wiring, RLS authorization, real fee posting, receipt issuance, file uploads, approval decisions, sync, backup execution, report exports or production printing. Some forms are deliberately structural mock-ups rather than field-complete business workflows. Existing Flutter and integration tests still need to be run on a compatible development machine.

## 8. Validation checklist before merging

- Flutter pub dependencies resolve with the installed Dart SDK.
- Drift code generation completes before analyzer/test.
- Flutter analyze and Flutter test pass on Windows development environment.
- Screen catalog is complete and names are unique within each module.
- Each module opens on Windows and Android without overflow.
- Six-step admission wizard and student directory still work.
- Form preview never claims a server-side save.
- Demo income or cash calculations are visibly illustrative.
- No real student or guardian information is embedded in source.
- No Supabase migration, user secret, payment, or financial finalization is triggered.
- Preview branch remains separate from production main until verified.
