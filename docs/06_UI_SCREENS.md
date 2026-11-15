# UI screen inventory

Windows: Material 3 shell, collapsible sidebar, global search Ctrl+F (configurable), top toolbar, offline/sync indicator. Android: responsive cards and touch navigation, online entry only.

- Login / campus selection
- Owner dashboard / assigned-campus dashboard
- Admissions six-step wizard: student, guardians, academic, documents, fee settings, review
- Admission status vs document completeness tracked separately; configurable conditional document deadline
- Student list, filters, profile, enrollment history and transfer request
- Fee structure, month-wise dues, payment allocation, advance credit, receipt/fee slip
- Student/staff daily attendance and authorized corrections
- Employee directory, monthly payroll, salary advance, payment and slip
- Expense form, account transfers, cashbook and cash closing
- Approval inbox and audit trail
- Search, reporting, print preview, sync center, backup and settings

Design status only; no feature UI implementation claimed.
## D03-T04 — Flutter admission UI authored (unmerged)
A responsive six-step admission preview (Student, Guardians, Academic, Documents, Fees, Review) is implemented on [draft UI PR #7](https://github.com/yunusyosaf399/supa-model-school/pull/7). Entry point: Students → New admission (preview). All selections and entered values are in-memory only; campus/year/class examples are not live data; submission and file upload are disabled. UI tests are written but not executed. See `docs/17_ADMISSION_WIZARD_UI.md` on that branch for field mapping and test plan.

## D03-T05 — Student directory source authored (not merged)
The [draft UI PR #7](https://github.com/yunusyosaf399/supa-model-school/pull/7) now includes a read-only demo directory for Windows/Android: name/registration search, permitted-campus/class/status filters, result counts, empty state, responsive table/cards and profile preview. It contains only four **fictional** students, all from Sample Campus A; no Supabase Auth, RLS, Drift, network search or data caching is connected. See `docs/18_STUDENT_DIRECTORY_UI.md` on the branch. Flutter compilation and tests are pending the developer's laptop.
