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
    this.extraDetails = const {},
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
  final Map<String,dynamic> extraDetails;
  final String? classId;
  final String? sectionId;
  final List<Map<String, dynamic>> guardians;
}

class SavedAdmissionDraft {
  const SavedAdmissionDraft({required this.id, required this.revision});
  final String id;
  final int revision;
}

class AdmissionDraftRecord {
  const AdmissionDraftRecord({
    required this.id, required this.revision, required this.name,
    required this.campusId, required this.academicYearId,
    required this.status, required this.guardians, required this.documents,
    this.dateOfBirth, this.previousSchool = '', this.classId, this.sectionId,
    this.approvalState, this.documentsState, this.studentId,
    this.conditionalDue, this.conditionalReason, this.returnedReason,
    this.extraDetails = const {},
  });
  final String id, name, campusId, academicYearId, status;
  final int revision;
  final DateTime? dateOfBirth;
  final String previousSchool;
  final String? classId, sectionId;
  final String? approvalState, documentsState, studentId;
  final String? conditionalDue, conditionalReason, returnedReason;
  bool get canResume => status == 'draft' || status == 'returned';
  final Map<String,dynamic> extraDetails;
  final List<Map<String, dynamic>> guardians, documents;

  factory AdmissionDraftRecord.fromJson(Map<String, dynamic> value) {
    List<Map<String, dynamic>> array(String key) {
      final items = value[key];
      if (items is! List) throw StateError('Invalid admission details');
      return List.unmodifiable(items.map((item) =>
        Map<String, dynamic>.from(item as Map)));
    }
    final status = value['status'] as String?;
    if (!const {'draft','submitted','approved','returned','rejected'}.contains(status)) {
      throw StateError('Unexpected admission state');
    }
    return AdmissionDraftRecord(
      id: value['id'] as String,
      revision: (value['revision'] as num).toInt(),
      name: value['name'] as String,
      campusId: value['campus_id'] as String,
      academicYearId: value['academic_year_id'] as String,
      status: status!,
      dateOfBirth: DateTime.tryParse(value['date_of_birth']?.toString() ?? ''),
      previousSchool: value['previous_school'] as String? ?? '',
      classId: value['class_id'] as String?,
      sectionId: value['section_id'] as String?,
      studentId: value['student_id'] as String?,
      approvalState: value['approval_state'] as String?,
      documentsState: value['documents_state'] as String?,
      conditionalDue: value['conditional_due'] as String?,
      conditionalReason: value['conditional_reason'] as String?,
      returnedReason: value['returned_reason'] as String?,
      extraDetails: value['extra_details'] is Map
        ? Map<String,dynamic>.from(value['extra_details'] as Map)
        : const {},
      guardians: array('guardians'),
      documents: array('documents'),
    );
  }
}

abstract class AdmissionDraftRepository {
  const AdmissionDraftRepository();
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request);
  Future<List<AdmissionDraftRecord>> listDrafts({
    required String schoolId, required String campusId,
  }) => throw UnimplementedError('Draft listing is not configured');
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
  Future<List<AdmissionDraftRecord>> listDrafts({
    required String schoolId,
    required String campusId,
  }) async {
    if (client.auth.currentSession == null ||
        (await client.auth.getUser()).user == null) {
      throw StateError('Sign in before reading admissions');
    }
    final records = <AdmissionDraftRecord>[];
    const pageSize = 100;
    var offset = 0;
    while (true) {
      final response = await client.rpc('owner_admission_worklist', params: {
        'p_school_id': schoolId,
        'p_campus_id': campusId,
        'p_limit': pageSize,
        'p_offset': offset,
      });
      if (response is! Map) throw StateError('Invalid worklist response');
      final map = Map<String, dynamic>.from(response);
      final total = map['total'];
      final raw = map['applications'];
      if (total is! num || total < 0 || total > 5000 || raw is! List) {
        throw StateError('Admission list too large or malformed');
      }
      for (final item in raw) {
        final record = AdmissionDraftRecord.fromJson(
          Map<String, dynamic>.from(item as Map));
        if (record.campusId != campusId) {
          throw StateError('Server returned another campus admission');
        }
        records.add(record);
      }
      offset += raw.length;
      if (offset >= total.toInt()) break;
      if (raw.isEmpty || records.length > 5000) {
        throw StateError('Incomplete admission list');
      }
    }
    return List.unmodifiable(records);
  }

  @override
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request) async {
    if (client.auth.currentSession == null ||
        (await client.auth.getUser()).user == null) {
      throw StateError('Sign in before saving an admission draft');
    }
    final response = await client.rpc('owner_save_admission_draft_v2', params: {
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
      'p_details': request.extraDetails,
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
