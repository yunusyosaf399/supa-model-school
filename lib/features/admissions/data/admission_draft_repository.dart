import 'package:supabase_flutter/supabase_flutter.dart';

/// The server authorizes the authenticated actor, school and campus.
/// The caller never supplies a user ID. No document upload or approval here.
class AdmissionDraftSaveRequest {
  const AdmissionDraftSaveRequest({
    required this.schoolId,
    required this.campusId,
    required this.academicYearId,
    required this.operationId,
    required this.applicantName,
    required this.guardians,
    this.applicationId,
    this.expectedRevision,
    this.dateOfBirth,
    this.previousSchool = '',
    this.classId,
    this.sectionId,
  });

  final String schoolId;
  final String campusId;
  final String academicYearId;
  final String operationId;
  final String applicantName;
  final String? applicationId;
  final int? expectedRevision;
  final DateTime? dateOfBirth;
  final String previousSchool;
  final String? classId;
  final String? sectionId;
  final List<Map<String, dynamic>> guardians;
}

class SavedAdmissionDraft {
  const SavedAdmissionDraft({required this.id, required this.revision});
  final String id;
  final int revision;
}

abstract class AdmissionDraftRepository {
  const AdmissionDraftRepository();
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request);
}

class SupabaseAdmissionDraftRepository implements AdmissionDraftRepository {
  const SupabaseAdmissionDraftRepository(this.client);
  final SupabaseClient client;

  static String? _date(DateTime? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

  @override
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request) async {
    if (client.auth.currentSession == null ||
        (await client.auth.getUser()).user == null) {
      throw StateError('Sign in before saving an admission draft');
    }
    final response = await client.rpc('owner_save_admission_draft', params: {
      'p_school_id': request.schoolId,
      'p_campus_id': request.campusId,
      'p_academic_year_id': request.academicYearId,
      'p_application_id': request.applicationId,
      'p_expected_revision': request.expectedRevision,
      'p_operation_id': request.operationId,
      'p_applicant_name': request.applicantName.trim(),
      'p_date_of_birth': _date(request.dateOfBirth),
      'p_previous_school': request.previousSchool.trim(),
      'p_class_id': request.classId,
      'p_section_id': request.sectionId,
      'p_guardians': request.guardians,
    });
    if (response is! Map ||
        response['status'] != 'draft' ||
        response['application_id'] is! String ||
        response['revision'] is! num) {
      throw StateError('Unexpected admission save confirmation');
    }
    return SavedAdmissionDraft(
      id: response['application_id'] as String,
      revision: (response['revision'] as num).toInt(),
    );
  }
}
