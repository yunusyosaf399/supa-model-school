# DB02 — Document Storage and permissions plan (not deployed)

Database tables in `supabase/drafts/DB02_admissions.sql`:
- `student_documents`: one requirement/status (birth, applicable transfer, photo, other) per application.
- `student_document_uploads`: immutable metadata for each upload version.
- `student_document_reviews`: append-only reviewer verdict tied to an exact upload.
- `admission_document_deadline_events`: audited deadline changes.

## Proposed Storage model
- A PRIVATE Supabase Storage bucket, created via reviewed deployment script later.
- Path convention: `school_uuid/campus_uuid/application_uuid/document_uuid/upload_uuid.ext`.
- Original filenames are display metadata only, not trusted as a Storage object key.
- Use allow-listed MIME types (PDF, JPEG, PNG, WEBP); enforce actual file signature and configurable byte limits in upload service.
- Do NOT expose bucket publicly or embed service-role secrets in Flutter.
- Document uploads/checks require school and campus authorization, one registered user session and a trusted server-side operation.
- Storage policies must separately enforce access; Postgres RLS on `student_documents` does NOT protect bucket object access automatically.
- Return short-lived signed download URLs only after the server authorizes the user and requested document.
- Replace/restore creates a NEW immutable upload version. Keep historical reviews and deadline audit.
- Deletion/retention is a policy-controlled action subject to audit, retention and legal requirements.

## Admission state machine
- Draft may have missing documents and no deadline.
- Conditional submitted/approved requires an explicit deadline.
- Complete means all *applicable required* documents verified.
- Uploaded but not verified remains outstanding for documentation-completeness checks.
- Overdue is computed using school timezone, not persisted as a mutually exclusive status.
- Principal approval, if enabled, is separate from conditional document acceptance.
- No automatic cancellation/withdrawal solely because the deadline expires.

## Not yet implemented
- Storage buckets and policies
- Signed URL upload/download endpoint
- PDF/image validation and virus checks
- Principal/Owner approval functions
- Server-enforced document status transitions and file-history immutability
- Real notifications and overdue document report

**This document is a design plan, not a claim of deployed functionality.**
