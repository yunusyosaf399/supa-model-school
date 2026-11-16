# Admissions UI — Six-step Flutter reference implementation

**Date:** 2026-11-16  
**Scope:** Windows and Android New Admission UI, Student → Guardians → Academic → Documents → Fees → Review.

## Screens implemented

The source in `lib/features/admissions/presentation/admission_wizard_page.dart` now follows the two supplied desktop/Android screenshot references. This is **native Flutter UI**, not a flattened screenshot.

### Windows desktop
- Uses the existing native Windows title bar rather than stacking another dark-green bar.
- White Supa Model School sidebar with selected **Admissions** menu.
- Compact top toolbar with search preview, campus and academic-year display, notification icon and account display.
- **New Admission** heading, Save Draft (disabled), Submit for Approval (disabled), Cancel, horizontal six-stage numbered stepper.
- Main form and a right-hand column containing Admission Checklist, Required Documents, and Admission Status.
- Separate **Student Details** and **Contact / Identity Information** panels.
- Back/Next Step buttons, secured-status footer.

### Android
- School crest/header, notification icon and New Admission heading with draft indicator.
- Six-stage icon stepper: Student, Guardians, Academic, Documents, Fees, Review.
- Responsive student form with a photo upload placeholder, date-of-birth picker, gender selector, previous school, nationality, religion, language and notes.
- Contact/Identity fields for birth certificate no., identity number, address, city and emergency contact.
- Required Documents card and fixed bottom Save Draft / Next Step actions; no extra bitmap backgrounds.

### Stage-specific functionality
1. **Student:** full name and DOB validation; gender, previous school, nationality, religion, language, notes and contact fields kept in local draft state. Photo is a disabled placeholder pending secure upload service.
2. **Guardians:** add/remove up to eight guardians; name, relationship, phone, exactly one primary contact, optional legal-guardian flag.
3. **Academic:** real Owner-authenticated, campus-scoped Supabase class/section lookup in the active academic year. No fictional school IDs. Changing campus invalidates stale lookups and clears the old class/section; class selection clears section.
4. **Documents:** lists required birth and applicable transfer certificates as **Not uploaded / Not verified**; conditional admission reason and deadline no later than two calendar months (with month-end handling), consistent with backend restrictions. No upload/verification endpoints enabled.
5. **Fees:** admission fee status, transport and discount request preferences. Nothing is charged or paid and no receipt is generated.
6. **Review:** previews the captured student, guardian, academic, certificate and fee information; displays blocking validation notices and an explicit reminder that real submission is unavailable.

The document-level and student-level data provided on this screen **are not saved** in Supabase, local disk or an offline queue. The verified Owner Academic lookups are strictly **read-only**. Save Draft and Submit for Approval are intentionally disabled until the authenticated DB02 API, private file upload, authorization policies and tests have been released.

## Changed source
- `lib/features/admissions/presentation/admission_wizard_page.dart`
- `lib/features/admissions/models/admission_draft.dart`
- `test/features/admissions/admission_wizard_widget_test.dart`
- `test/features/admissions/admission_draft_test.dart`

Existing `test/features/admissions/admission_academic_lookup_widget_test.dart` and other widget tests continue using the established keys (`wizard-next`, `step-chip-*`, `admission-campus-choice`, `class-choice-*`, `section-choice-*`, `document-deadline`).

## Verification status
Source bracket/quote consistency checks and review of widget keys passed. Flutter analysis, widget tests, and actual Windows/Android runtime rendering **have not been executed in the assistant environment**, where the Flutter and Dart SDKs are unavailable. No claims of pixel-perfect visual verification should be made until actual screenshots from target devices have been reviewed.

### Test on laptop

```powershell
git switch main
git pull --ff-only origin main
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

To test Android, use `flutter run -d <android-device-id>` with the same publishable Supabase settings, or open the debug preview to see the non-authorized, read-only UI. Real Academic dropdown data requires the Owner to have completed school setup and created valid classes/sections.

### Remaining release gates
- Secure Auth-protected intake API, private photo/document uploads with server-side file validation and signed download authorization.
- Transactionally persisted admission drafts, audited forwarding and campus Principal approval.
- Only then allow Save Draft and Submit for Approval. All non-UI fields must be reviewed against the final admissions schema before persistence.
