# D03-T02 — Conditional admission document acceptance tests

**Status:** SQL draft authored and structurally reviewed only; PostgreSQL / Storage / Auth / RPC tests NOT run.

## Agreed school policy

1. Required documents: **birth certificate**, and **school transfer/leaving certificate if applicable**. Requirements are determined by an authorized admission workflow.
2. Missing required documents must NOT automatically block enrollment. An Admin may submit a **conditional admission** with a documented deadline.
3. `admission_status` and `documents_state` are separate: admission can be approved while required documentation is conditional.
4. Principal approval is controlled by Owner settings; disabling it does not bypass document deadline rules.
5. An uploaded file is NOT automatically a verified document. Only an authorized reviewer may set verified status, tied to an uploaded version.
6. An overdue deadline is derived from the applicable school timezone and current date. It triggers alerts and review, NOT automatic deletion, withdrawal, or blocked attendance.
7. Deadline extensions require a reason, authorized user, and history row. Past values are not erased silently.
8. Actual document files must live in a PRIVATE Supabase Storage bucket. Only metadata belongs in PostgreSQL.

## DDL and relation tests for local Supabase

| ID | Setup and action | Expected |
| --- | --- | --- |
| DOC-01 | Draft application; birth certificate missing; no deadline | Draft allowed |
| DOC-02 | Set documents_state = conditional with deadline NULL | CHECK rejects |
| DOC-03 | Conditional + future deadline; authorized admission finalization | Allowed once role approval and business checks pass |
| DOC-04 | Approved admission with documents_state=incomplete | CHECK rejects |
| DOC-05 | Approved admission with approval_state=pending | CHECK rejects |
| DOC-06 | Transfer certificate non-applicable yet is_required=true | CHECK rejects |
| DOC-07 | Standard birth certificate requirement inserted twice for same application | Unique index rejects |
| DOC-08 | Two distinct labeled 'other' requirements | Allowed |
| DOC-09 | Same 'other' requirement label differing by case | Unique index rejects |
| DOC-10 | Document requirement references application in different school/campus | Composite FK rejects |
| DOC-11 | Document.student_id belongs to another application's student | Composite FK rejects |
| DOC-12 | Uploaded/verified document has NULL storage_path | CHECK rejects |
| DOC-13 | Verified document lacks verified_at or verified_by | CHECK rejects |
| DOC-14 | Rejected document lacks rejection_reason | CHECK rejects |
| DOC-15 | Upload version_no = 0 or duplicate document/version_no | CHECK/unique rejects |
| DOC-16 | Review references upload from another document | Composite FK rejects |
| DOC-17 | Review decision rejected without reason | CHECK rejects |
| DOC-18 | Deadline event old_due_on = new_due_on | CHECK rejects |
| DOC-19 | Deadline event document belongs to different application | Composite FK rejects |
| DOC-20 | RLS and grants for four document tables for anon/authenticated | RLS enabled and direct access denied |
| DOC-21 | Staff member tries to approve or change deadline without server approval | Denied (requires later server operation tests) |
| DOC-22 | Two upload revisions then re-verification | Preserve every upload/review event; final status reflects latest approved server operation |
| DOC-23 | Deadline expires and student is admitted | Alert/overdue report only; do not auto-delete student |
| DOC-24 | Private Storage URL accessed without permission | Denied (requires future Storage bucket policies and tests) |

## Scope boundary
`DOC-01` through `DOC-20` need actual **local** PostgreSQL migration/fixture tests; `DOC-21` through `DOC-24` additionally require validated server operations, scheduling and Storage setup. These are NOT claimed to pass yet.

## Security/data consistency gaps for later implementation
- Do not allow client direct SQL mutations on `student_documents`, `student_document_uploads`, `student_document_reviews`, or deadline events.
- Enforce required-document applicability and whether deadlines are overdue in a **server-side transaction** at admission finalization; a row-level CHECK cannot count all required document rows.
- Enforce `student_documents.storage_path` references an actual version in the matching private bucket (not possible with a plain CHECK).
- Only authorized reviewers can verify/reject a submitted file. Prevent a later rejected revision from being mistaken for a previously verified current version.
- Enforce append-only history for uploads/reviews/deadline events, with audit and no silent hard deletion.
- Decide permitted PDF/image sizes from school Storage settings before accepting uploads.
- Issue signed URLs only after campus/role permission checks, never reveal storage object locations through unreviewed public tables.
