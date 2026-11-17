# DB10 — Private admission certificate uploads (2026-11-17)

## Deployed SQL
- Migration `20261117131250_db10_owner_admission_document_upload_20261117`: Storage `INSERT` policy restricted to verified active school Owner and matching draft/campus/application/document; object paths are immutable and UUID-based. No Storage list/read/update/delete policy is introduced. Files remain in existing **private** `sms-admission-documents` bucket.
- Migration `20261117131429_db10_owner_admission_document_status_20261117`: Owner-only list of document IDs, revisions, requirement flags, statuses and latest upload version. Does **not** return storage paths.
- Upload registration RPC validates caller, object ownership, document revision, file size/MIME/extension metadata; appends `student_document_uploads` version history and sets status `uploaded`, never `verified`.
- Physical file signatures are checked by Flutter before upload, not verified by the server (untrusted client). A server-side byte inspection or malware/content scanner is required before staff can verify documents in production.

## Windows/Android Flutter
- Pinned native file picker for PDF/JPG/PNG/WebP with a 10 MiB maximum.
- Save Draft first; on the Documents step load the persisted requirements and upload certificate(s).
- Each successful upload is marked **Uploaded — awaiting verification**.
- If Storage upload succeeded but SQL registration was interrupted, same in-memory path/operation can be retried without overwriting an existing object. A full device/app restart loses that local pending registration and could leave an orphan file to clean.
- No download, public URL, direct access to child documents or broad table grant was introduced.
- Signed-in Owner login is required. The existing Principal approval and student finalization remain disabled.

## Validation
- Rollback-only database integration test creates a synthetic Storage metadata object in SQL, verifies allowed Owner scope, rejects unknown user/bucket/path, registers file version and tests idempotency, then rolls back every fixture. This **does not** constitute a real uploaded-file HTTP/byte test.
- Document list projection was separately verified for required document IDs and unknown actor denial.
- Flutter unit/widget regression and Dart analyzer run in the GitHub Actions PR workflow.
- No actual school documents, students, finance transactions or credentials are inserted or changed by integration tests.

## Remaining
- Real Storage upload acceptance on signed-in Windows and Android, version reconciliation after restart, malware/file signature validation on server, Principal authorization and formal document verification, conditional-document deadlines, submission, approval and finalization.
- Storage file version retention policies and orphan cleanup after interrupted uploads.
- Offline encrypted cache and sync still pending.

**Do not use a service-role key in Flutter.** Use only the Supabase publishable client key.
