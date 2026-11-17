import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All actors are derived by the server from auth.uid(). Clients never
/// supply an actor, student registration number, or approval_state.
class AdmissionSubmitRequest {
  const AdmissionSubmitRequest({
    required this.applicationId,
    required this.expectedRevision,
    required this.operationId,
    this.conditionalDue,
    this.conditionalReason,
  });
  final String applicationId, operationId;
  final int expectedRevision;
  final DateTime? conditionalDue;
  final String? conditionalReason;
}

class AdmissionSubmitResult {
  const AdmissionSubmitResult({
    required this.applicationId, required this.documentState,
    required this.principalRequired,
  });
  final String applicationId, documentState;
  final bool principalRequired;
}

class PrincipalApprovalItem {
  const PrincipalApprovalItem({
    required this.id, required this.name, required this.revision,
    required this.documentState, required this.missingDocuments,
    this.conditionalDue, this.conditionalReason,
  });
  final String id, name, documentState;
  final int revision, missingDocuments;
  final String? conditionalDue, conditionalReason;

  factory PrincipalApprovalItem.fromJson(Map<String, dynamic> json) =>
      PrincipalApprovalItem(
        id: json['id'] as String,
        name: json['name'] as String,
        revision: (json['revision'] as num).toInt(),
        documentState: json['documents_state'] as String,
        missingDocuments: (json['pending_documents'] as num).toInt(),
        conditionalDue: json['conditional_due'] as String?,
        conditionalReason: json['conditional_reason'] as String?,
      );
}

class PrincipalDecisionResult {
  const PrincipalDecisionResult({
    required this.applicationId, required this.status, this.studentId,
  });
  final String applicationId, status;
  final String? studentId;
}

abstract class AdmissionApprovalRepository {
  const AdmissionApprovalRepository();
  Future<AdmissionSubmitResult> submit(AdmissionSubmitRequest request);
  Future<List<PrincipalApprovalItem>> listPending({
    required String schoolId, required String campusId,
  });
  Future<PrincipalDecisionResult> review({
    required String applicationId, required int expectedRevision,
    required String operationId, required String decision, String? reason,
  });
}

class SupabaseAdmissionApprovalRepository implements AdmissionApprovalRepository {
  const SupabaseAdmissionApprovalRepository(this.client);
  final SupabaseClient client;

  static String operationUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((value) =>
        value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-'
        '${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }

  static String? dateOnly(DateTime? value) => value == null ? null :
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _signedIn() async {
    if (client.auth.currentSession == null ||
      (await client.auth.getUser()).user == null) {
      throw StateError('An authenticated school session is required');
    }
  }

  @override
  Future<AdmissionSubmitResult> submit(AdmissionSubmitRequest request) async {
    await _signedIn();
    final data = await client.rpc('owner_submit_admission', params: {
      'p_application_id': request.applicationId,
      'p_expected_revision': request.expectedRevision,
      'p_operation_id': request.operationId,
      'p_conditional_due': dateOnly(request.conditionalDue),
      'p_conditional_reason': request.conditionalReason,
    });
    if (data is! Map || data['status'] != 'submitted' ||
        data['student_id'] != null || data['approval_required'] != true) {
      throw StateError('Server did not confirm queued Principal review');
    }
    return AdmissionSubmitResult(
      applicationId: data['application_id'] as String,
      documentState: data['document_state'] as String,
      principalRequired: true,
    );
  }

  @override
  Future<List<PrincipalApprovalItem>> listPending({
    required String schoolId, required String campusId,
  }) async {
    await _signedIn();
    final results = <PrincipalApprovalItem>[];
    var offset = 0;
    const pageSize = 100;
    while (true) {
      final response = await client.rpc('principal_admission_queue', params: {
        'p_school_id': schoolId,
        'p_campus_id': campusId,
        'p_limit': pageSize,
        'p_offset': offset,
      });
      if (response is! Map || response['total'] is! num ||
          response['applications'] is! List ||
          (response['total'] as num).toInt() > 5000) {
        throw StateError('Invalid Principal queue response');
      }
      final items = response['applications'] as List;
      results.addAll(items.map((row) => PrincipalApprovalItem.fromJson(
        Map<String, dynamic>.from(row as Map))));
      offset += items.length;
      if (offset >= (response['total'] as num).toInt()) break;
      if (items.isEmpty || offset > 5000) {
        throw StateError('Incomplete Principal queue');
      }
    }
    return List.unmodifiable(results);
  }

  @override
  Future<PrincipalDecisionResult> review({
    required String applicationId, required int expectedRevision,
    required String operationId, required String decision, String? reason,
  }) async {
    await _signedIn();
    if (!['approve','return','reject'].contains(decision)) {
      throw ArgumentError.value(decision,'decision','Invalid Principal action');
    }
    final data = await client.rpc('principal_review_admission', params: {
      'p_application_id': applicationId,
      'p_expected_revision': expectedRevision,
      'p_operation_id': operationId,
      'p_decision': decision,
      'p_reason': reason,
    });
    if (data is! Map || data['status'] !=
          (decision == 'approve' ? 'approved' :
           decision == 'return' ? 'returned' : 'rejected')) {
      throw StateError('Principal review was not confirmed by server');
    }
    return PrincipalDecisionResult(
      applicationId: data['application_id'] as String,
      status: data['status'] as String,
      studentId: data['student_id'] as String?,
    );
  }
}
