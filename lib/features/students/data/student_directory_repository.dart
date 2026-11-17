import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_directory.dart';

abstract class StudentDirectoryRepository {
  const StudentDirectoryRepository();
  Future<StudentDirectoryProjection> load({
    required String schoolId,
    required String campusId,
  });
}

abstract class StudentProfileUpdateRepository {
  Future<void> updateProfile({
    required String schoolId,required String campusId,
    required StudentSummary student,required String name,
    required StudentStatus status,
  });
}

class SupabaseStudentDirectoryRepository implements StudentDirectoryRepository, StudentProfileUpdateRepository {
  const SupabaseStudentDirectoryRepository(this.client,
    {this.rpcName = 'owner_student_directory'});
  final SupabaseClient client;
  final String rpcName;

  @override
  Future<void> updateProfile({
    required String schoolId,required String campusId,
    required StudentSummary student,required String name,
    required StudentStatus status,
  }) async {
    if (client.auth.currentSession == null) throw StateError('Sign in required');
    if (!{'active','inactive'}.contains(status.name) ||
        name.trim().length < 2 || name.trim().length > 200) {
      throw const FormatException('Enter a valid student name and status');
    }
    final response = await client.rpc('owner_update_student_profile',params:{
      'p_school':schoolId,'p_campus':campusId,
      'p_student':student.id,'p_expected_revision':student.revision,
      'p_full_name':name.trim(),'p_active_status':status.name,
    });
    if (response is! Map || response['student_id'] != student.id ||
        response['revision'] != student.revision + 1) {
      throw StateError('Student change not confirmed; refresh before retrying');
    }
  }

  @override
  Future<StudentDirectoryProjection> load({
    required String schoolId,
    required String campusId,
  }) async {
    if (client.auth.currentSession == null) {
      throw StateError('Owner sign-in is required');
    }
    const pageSize = 200;
    final records = <StudentSummary>[];
    var offset = 0;
    while (true) {
      final response = await client.rpc(rpcName, params: {
        'p_school_id': schoolId,
        'p_campus_id': campusId,
        'p_limit': pageSize,
        'p_offset': offset,
      });
      if (response is! Map) throw StateError('Unexpected student response');
      final data = Map<String, dynamic>.from(response);
      final raw = data['students'];
      final count = data['total'];
      if (raw is! List || count is! num || count < 0 || count > 5000) {
        throw StateError('Student directory response invalid or too large');
      }
      for (final item in raw) {
        if (item is! Map) throw StateError('Invalid student row');
        final row = Map<String, dynamic>.from(item);
        if (row['campus_id'] != campusId) {
          throw StateError('Unexpected campus data from server');
        }
        final status = StudentStatus.values.byName(
          (row['status'] ?? 'active').toString(),
        );
        records.add(StudentSummary(
          id: row['id'].toString(),
          registrationNo: row['registration_no'].toString(),
          fullName: row['full_name'].toString(),
          campusId: row['campus_id'].toString(),
          campusName: row['campus_name'].toString(),
          classId: row['class_id'].toString(),
          className: row['class_name'].toString(),
          sectionName: row['section_name'].toString(),
          academicYear: row['academic_year'].toString(),
          status: status,
          revision: (row['revision'] as num?)?.toInt() ?? 1,
        ));
      }
      offset += raw.length;
      if (offset >= count.toInt()) break;
      if (raw.isEmpty || records.length > 5000) {
        throw StateError('Incomplete student page');
      }
    }
    return StudentDirectoryProjection(
      authorizedCampusIds: {campusId},
      records: List.unmodifiable(records),
    );
  }
}


/// Read-only Principal/staff projection. Separate secure RPC enforces
/// individual students.read action plus assigned campus on every request.
class SupabaseStaffStudentDirectoryRepository
    implements StudentDirectoryRepository {
  const SupabaseStaffStudentDirectoryRepository(this.client);
  final SupabaseClient client;

  @override
  Future<StudentDirectoryProjection> load({
    required String schoolId,
    required String campusId,
  }) => SupabaseStudentDirectoryRepository(
      client, rpcName: 'sms_staff_student_directory',
    ).load(schoolId: schoolId, campusId: campusId);
}
