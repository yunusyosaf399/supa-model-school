/// A UI-only admission draft. No persistence or server privileges are provided.
enum AdmissionStep {
  student,
  guardians,
  academic,
  documents,
  fees,
  review,
}

extension AdmissionStepLabel on AdmissionStep {
  String get label => switch (this) {
        AdmissionStep.student => 'Student',
        AdmissionStep.guardians => 'Guardians',
        AdmissionStep.academic => 'Academic',
        AdmissionStep.documents => 'Documents',
        AdmissionStep.fees => 'Fees',
        AdmissionStep.review => 'Review',
      };
}

class GuardianDraft {
  GuardianDraft({
    required this.localId,
    this.fullName = '',
    this.relationship = 'father',
    this.phone = '',
    this.isPrimary = false,
    this.isLegalGuardian = false,
  });

  final int localId;
  String fullName;
  String relationship;
  String phone;
  bool isPrimary;
  bool isLegalGuardian;
}

class AdmissionDraft {
  String studentName = '';
  DateTime? dateOfBirth;
  String gender = 'unspecified';
  String previousSchool = '';
  // Additional student/contact fields for the six-step UI preview. These
  // values are never persisted before the approved DB02 intake endpoint.
  String nationality = '';
  String religion = '';
  String primaryLanguage = '';
  String notes = '';
  String birthCertificateNumber = '';
  String identityNumber = '';
  String address = '';
  String city = '';
  String emergencyContact = '';

  // When the Owner has completed setup, these IDs come from authorized
  // DB01 campus/active-year/class/section records. They are UI-only draft
  // choices: the server must revalidate them during future DB02 submission.
  String? campusId;
  String? academicYearId;
  String? classId;
  String? sectionId;

  final List<GuardianDraft> guardians = [
    GuardianDraft(localId: 1, isPrimary: true),
  ];

  // The document upload/verification service is not yet connected.
  // Required documents remain unverified regardless of a user's intention
  // to provide them. The preview therefore uses conditional admission.
  DateTime? missingDocumentsDueOn;
  String conditionalReason = '';

  String admissionFeeStatus = 'not_recorded';
  bool usesTransport = false;
  String transportNotes = '';
  bool requestsDiscount = false;
  String discountNotes = '';

  bool get transferCertificateApplicable => previousSchool.trim().isNotEmpty;

  List<String> get requiredDocumentNames => [
        'Birth certificate',
        if (transferCertificateApplicable) 'School leaving / transfer certificate',
      ];

  String? validateStep(AdmissionStep step, {DateTime? today}) {
    final localToday = today ?? DateTime.now();
    final day = DateTime(localToday.year, localToday.month, localToday.day);

    switch (step) {
      case AdmissionStep.student:
        if (studentName.trim().length < 2) {
          return 'Enter the student’s full name.';
        }
        if (dateOfBirth == null) {
          return 'Select the student’s date of birth.';
        }
        if (dateOfBirth!.isAfter(day)) {
          return 'Date of birth cannot be in the future.';
        }
        return null;

      case AdmissionStep.guardians:
        if (guardians.isEmpty) {
          return 'Add at least one parent or guardian.';
        }
        if (guardians.length > 8) {
          return 'A maximum of eight guardians can be listed.';
        }
        if (guardians.where((g) => g.isPrimary).length != 1) {
          return 'Select exactly one primary guardian.';
        }
        for (final g in guardians) {
          if (g.fullName.trim().length < 2) {
            return 'Enter every guardian’s full name.';
          }
          if (g.isPrimary &&
              RegExp(r'\d').allMatches(g.phone).length < 7) {
            return 'Enter a valid phone number for the primary guardian.';
          }
        }
        for (final relationship in ['father', 'mother']) {
          if (guardians.where((g) => g.relationship == relationship).length > 1) {
            return 'Only one $relationship relationship is permitted per student.';
          }
        }
        return null;

      case AdmissionStep.academic:
        if (campusId == null || academicYearId == null || classId == null) {
          return 'Select the campus, academic year and class.';
        }
        return null;

      case AdmissionStep.documents:
        // The server will use the school-configured timezone and actual
        // verified Storage records. The local check is only a UX preview.
        if (missingDocumentsDueOn == null) {
          return 'Choose a deadline for outstanding required documents.';
        }
        final deadline = missingDocumentsDueOn!;
        if (DateTime(deadline.year, deadline.month, deadline.day).isBefore(day)) {
          return 'The document deadline cannot be in the past.';
        }
        final latest = DateTime(day.year, day.month + 2, day.day);
        if (deadline.isAfter(latest)) {
          return 'Choose a document deadline within two calendar months.';
        }
        if (conditionalReason.trim().length < 4) {
          return 'Explain why the documents will be supplied later.';
        }
        return null;

      case AdmissionStep.fees:
        // Collection and fee allocation are separate future modules.
        return null;

      case AdmissionStep.review:
        for (final previous in AdmissionStep.values.take(5)) {
          final problem = validateStep(previous, today: day);
          if (problem != null) return problem;
        }
        return null;
    }
  }
}
