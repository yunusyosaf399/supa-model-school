# D03-T04 — Admission Wizard UI (Flutter)

**Status:** Source authored and inspected; Flutter compilation and widget tests NOT RUN. UI exists only on branch `ui/d03-admission-wizard`. It is NOT connected to the Supabase project.

## Entry point
The `Students` module displays **New admission (preview)**. The button opens `AdmissionWizardPage` as a separate Flutter route. An exit confirmation warns that all entered data is lost.

## Six stages
| Stage | Fields and behavior | First-stage validation |
| --- | --- | --- |
| 1. Student | Full name, DOB, optional gender, previous school | Name at least two characters, non-future birth date |
| 2. Guardians | One or more parents/guardians, relationship, phone, primary/legal checkboxes | Exactly one primary guardian, a valid primary phone, no duplicate father/mother relationship |
| 3. Academic | Campus, academic year, class, section | Campus/year/class required; all dropdown values are **sample values**, not real UUIDs |
| 4. Documents | Birth certificate; transfer certificate if previous school entered; conditional reason and date | Files remain **outstanding** because upload verification is not implemented; reason and non-past deadline required |
| 5. Fees | Admission fee status placeholder, transport request, discount request | No payment or fee posting |
| 6. Review | Read-only summary and pending checks | **Submit unavailable** until Auth, RLS, Storage and server admission operation pass tests |

## Explicit safety boundaries
- All entered data is held only in Flutter widget memory. No database, device storage, background sync, analytics or HTTP request is performed.
- UI-only document checklists do not claim that files are uploaded or verified. The backend determines document truth from private Storage and authorized verification records.
- Displaying `Paid (verification required)` does **not** post a payment or generate a receipt.
- Campus/year/class values are intentionally **fictional demo options**. Real selections will come from authorized DB01/DB02 records.
- The registration number is not manually entered; backend trusted finalization generates it.
- Principal approval, real duplicate detection, school-local timezone validation and offline outbox are **not** connected. The app's local deadline validation does not replace server enforcement.
- The current module is intentionally English-only; localization support can be added later.

## Source files
- `lib/features/admissions/models/admission_draft.dart`
- `lib/features/admissions/presentation/admission_wizard_page.dart`
- `lib/main.dart` opens the admission preview.
- `test/features/admissions/admission_draft_test.dart`
- `test/features/admissions/admission_wizard_widget_test.dart`

## Laptop verification (Windows)
1. Check installed Flutter/SDK prerequisites: `flutter doctor -v`.
2. Check out `ui/d03-admission-wizard`.
3. Generate missing Windows/Android runners, **after reviewing the diff**:
   `flutter create --project-name supa_model_school --org com.supamodelschool --platforms windows,android .`
4. Run `flutter pub get`, `flutter analyze`, and `flutter test` locally.
5. Run `flutter run -d windows`; navigate to **Students → New admission (preview)**.
6. On Android emulator/device, verify the step chips scroll horizontally and the form remains readable in portrait.

## Manual acceptance checklist
- [ ] Students opens the wizard route from Windows.
- [ ] Student name/DOB validation prevents moving forward.
- [ ] Guardian addition/removal/primary designation works correctly.
- [ ] Class selection resets when campus changes.
- [ ] Previous-school entry adds transfer-certificate requirement.
- [ ] Conditional admission requires a deadline and reason.
- [ ] Fee fields do not create charges, receipts or payments.
- [ ] Review shows all entered information without claiming submission.
- [ ] Submit is disabled, and leaving warns that unsaved values will be discarded.
- [ ] Android portrait and Windows wide layout have no overflow.
- [ ] Widget tests and Flutter analyzer pass.
- [ ] No unintended remote calls, real data or secret credentials.

These checks are **not yet marked passed**. Record their outcomes in `planning/STATUS.md` when tested.

## Next implementation boundaries
D03-T05 student list and searches can be built as a separate UI task.
D05-T01 later connects required document uploads and authenticated draft/submit operations only after reviewed migrations, RLS and Edge tests pass.
