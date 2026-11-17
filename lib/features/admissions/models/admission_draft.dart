/// Admission form state. Authenticated persistence is implemented by the repository;
/// the model itself grants no privileges and performs no direct database writes.
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
  // Additional admission data saved through the Owner-only DB10 v2 draft API.
  // Access is controlled on the server; no direct write to student tables.
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

  // These values are submitted atomically with the Principal review request.
  // Upload does not itself verify certificates; conditional admission may apply.
  DateTime? missingDocumentsDueOn;
  String conditionalReason = '';

  String admissionFeeStatus = 'not_recorded';
  bool usesTransport = false;
  String transportNotes = '';
  bool requestsDiscount = false;
  String discountNotes = '';

  /// Two calendar months, clamping month-end dates as Postgres intervals do.
  static DateTime latestConditionalDeadline(DateTime today) {
    final target = DateTime(today.year, today.month + 2, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    final day = today.day > lastDay ? lastDay : today.day;
    return DateTime(target.year, target.month, day);
  }

  bool get transferCertificateApplicable => previousSchool.trim().isNotEmpty;

  List<String> get requiredDocumentNames => [
        'Birth certificate',
        if (transferCertificateApplicable) 'School leaving / transfer certificate',
      ];

  String? validateStep(AdmissionStep step, {
    DateTime? today, bool documentsOutstanding = true,
  }) {
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
        if (!documentsOutstanding) return null;
        // The server will use the school-configured timezone and actual
        // verified Storage records. The local check is only a UX preview.
        if (missingDocumentsDueOn == null) {
          return 'Choose a deadline for outstanding required documents.';
        }
        final deadline = missingDocumentsDueOn!;
        if (DateTime(deadline.year, deadline.month, deadline.day).isBefore(day)) {
          return 'The document deadline cannot be in the past.';
        }
        final latest = latestConditionalDeadline(day);
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
          final problem = validateStep(previous, today: day,
              documentsOutstanding: documentsOutstanding);
          if (problem != null) return problem;
        }
        return null;
    }
  }
}
