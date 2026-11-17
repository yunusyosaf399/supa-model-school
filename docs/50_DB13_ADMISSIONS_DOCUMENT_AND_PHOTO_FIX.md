# DB13 — Admission submission, conditional deadlines and student photo

17 November 2026 — live Supabase project `uebzvfzpbqqttbqyxxos`.

## Fixed Owner workflow

### 1. Certificates uploaded: no conditional deadline required
Previously the wizard and DB02 considered `uploaded` documents **missing**, because only a Principal may change a certificate to `verified`. This incorrectly required a deadline and reason before forwarding every application.

**New distinction:**
- **Missing or rejected required certificate:** Owner must enter a reason and deadline within two calendar months; forwarded to Principal as a **conditional** application.
- **All required certificates uploaded, but not yet Principal-verified:** Owner can forward immediately **without a deadline or reason**. Application document state is `pending_verification`.
- **All required certificates already verified:** Owner can forward immediately; document state is `complete`.
- Principal still **cannot approve an application with `pending_verification` until all required uploaded certificates have actually been verified**. Once verified, the enrollment transaction sets document state to `complete`, creates the student, and links optional photo/document metadata to the student.
- Optional student photos do not affect the required-certificate deadline.

The Documents step and Review step now use actual Supabase document statuses instead of assuming all documents are outstanding. The conditional fields are shown only when a required certificate is missing/rejected (or document metadata has not loaded yet).

### 2. Submission confirmation and safe retries
The old submission RPC returned an **incomplete response object** when retrying an already accepted operation UUID. That could leave the app showing “Submission was not confirmed” even though the operation was completed. The DB13 submission function now returns the full `approval_required` and `document_state` fields on identical-operation retries.

The app displays the actual short server error for a rejected submission, rather than hiding it behind a generic retry message. An immutable operation UUID is still reused for uncertain requests, avoiding duplicate submissions.

### 3. Student photo upload enabled
The student photo panel is now a clickable upload control:
- First click **Save Draft** to get an application ID.
- Click **Upload Photo** on the Student step. Select a JPG, PNG or WebP file **no larger than 2 MiB**.
- The app checks file signature, size and allowed MIME, then uploads to the existing **private**, campus-scoped `sms-admission-documents` Supabase Storage bucket. It registers file metadata through the same audited Owner-only upload API as admission certificates.
- A dedicated `owner_prepare_admission_photo` RPC creates one optional `student_documents` row with `document_kind='photo'` for this application, reusing safe, immutable file revisions. It cannot be created for another Owner’s campus or for an approved application.
- Successful upload changes the photo panel to **Photo Uploaded**. The photo is optional, does not require document verification or deadline, and its metadata is linked to the final student record at Principal approval.

The photo card currently displays a saved/uploaded status rather than a full image thumbnail. Private photo-view thumbnails in Student Profiles are a separate follow-up.

## Windows verification

```powershell
git checkout main
git pull origin main
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

Log in as Owner, create a test draft with valid student, guardian and class fields; save it. Upload the Birth Certificate and, where applicable, Transfer Certificate. Confirm **Uploaded** appears. Without entering any conditional deadline, go to Review and forward for Principal approval. The application should enter **Pending Principal**. If still rejected, the screen will show the underlying server error.

Open a new test draft, save it, click **Upload Photo** and select a small JPG, PNG or WebP. Check the **Photo Uploaded** label and the optional photo metadata persists after reopening the draft.

Log in with a separate Principal account, inspect and verify the required certificates, then approve. Unverified files cannot be silently approved. Do not use real child identity data during testing.

## Automated verification

- `supabase/tests/DB13_ADMISSION_UPLOADED_NO_DEADLINE_INTEGRATION.sql`: rollback-only synthetic cases, uploaded/no-deadline, same-UUID retry, Principal rejection of unverified files, verified approval, optional photo linked after student creation.
- `test/features/admissions/admission_submit_widget_test.dart`: saved document statuses permit no-deadline submission.
- `test/features/admissions/admission_document_upload_widget_test.dart`: certificate status and actual student-photo upload control.

**Not yet device-tested:** an actual Windows image upload and a Principal verification on a real document. No genuine school data or external files were written by these integration tests.
