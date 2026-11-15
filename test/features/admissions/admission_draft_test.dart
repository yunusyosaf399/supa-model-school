import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/admissions/models/admission_draft.dart';

void main() {
  group('AdmissionDraft validation', () {
    test('requires student name and date of birth', () {
      final draft = AdmissionDraft();
      final today = DateTime(2026, 11, 15);
      expect(draft.validateStep(AdmissionStep.student, today: today),
          contains('full name'));
      draft.studentName = 'Fictional Child';
      expect(draft.validateStep(AdmissionStep.student, today: today),
          contains('date of birth'));
      draft.dateOfBirth = DateTime(2027, 1, 1);
      expect(draft.validateStep(AdmissionStep.student, today: today),
          contains('future'));
      draft.dateOfBirth = DateTime(2017, 4, 3);
      expect(draft.validateStep(AdmissionStep.student, today: today), isNull);
    });

    test('primary guardian requires name and phone', () {
      final draft = AdmissionDraft();
      expect(draft.validateStep(AdmissionStep.guardians),
          contains('full name'));
      draft.guardians.first.fullName = 'Fictional Parent';
      expect(draft.validateStep(AdmissionStep.guardians),
          contains('phone number'));
      draft.guardians.first.phone = '+92 300 1234567';
      expect(draft.validateStep(AdmissionStep.guardians), isNull);
      draft.guardians.add(GuardianDraft(
        localId: 2, fullName: 'Second Parent',
        relationship: 'mother', phone: '0300 5555555', isPrimary: true,
      ));
      expect(draft.validateStep(AdmissionStep.guardians),
          contains('exactly one'));
    });

    test('same relationship cannot be listed twice for father/mother', () {
      final draft = AdmissionDraft();
      draft.guardians.first
        ..fullName = 'First Father'
        ..phone = '03001234567';
      draft.guardians.add(GuardianDraft(
        localId: 2, fullName: 'Second Father',
        relationship: 'father',
      ));
      expect(draft.validateStep(AdmissionStep.guardians),
          contains('one father'));
    });

    test('previous school makes transfer certificate applicable', () {
      final draft = AdmissionDraft();
      expect(draft.requiredDocumentNames, ['Birth certificate']);
      draft.previousSchool = 'Fictional Previous School';
      expect(draft.transferCertificateApplicable, isTrue);
      expect(draft.requiredDocumentNames, hasLength(2));
    });

    test('campus, year and class required before academic step', () {
      final draft = AdmissionDraft();
      expect(draft.validateStep(AdmissionStep.academic), isNotNull);
      draft
        ..campusId = 'sample-campus-a'
        ..academicYearId = 'sample-year-2026'
        ..classId = 'grade-1';
      expect(draft.validateStep(AdmissionStep.academic), isNull);
    });

    test('conditional documents require deadline and reason', () {
      final draft = AdmissionDraft();
      final today = DateTime(2026, 11, 15);
      expect(draft.validateStep(AdmissionStep.documents, today: today),
          contains('deadline'));
      draft.missingDocumentsDueOn = DateTime(2026, 11, 14);
      expect(draft.validateStep(AdmissionStep.documents, today: today),
          contains('past'));
      draft.missingDocumentsDueOn = DateTime(2027, 1, 14);
      expect(draft.validateStep(AdmissionStep.documents, today: today),
          contains('why'));
      draft.conditionalReason = 'Certificates pending from prior school';
      expect(draft.validateStep(AdmissionStep.documents, today: today), isNull);
    });

    test('review checks incomplete earlier steps', () {
      final draft = AdmissionDraft();
      expect(draft.validateStep(AdmissionStep.review),
          contains('full name'));
      expect(draft.validateStep(AdmissionStep.fees), isNull);
    });
  });
}
