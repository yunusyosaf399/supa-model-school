/// Minimal, read-only student directory projection.
///
/// This is NOT a replacement for Supabase Row Level Security or the local
/// assigned-campus cache boundary. Real records must be authorized by the
/// backend *before* they are delivered to any Flutter client.
enum StudentStatus {
  active,
  inactive,
  withdrawn,
  graduated;

  String get label => switch (this) {
        StudentStatus.active => 'Active',
        StudentStatus.inactive => 'Inactive',
        StudentStatus.withdrawn => 'Withdrawn',
        StudentStatus.graduated => 'Graduated',
      };
}

class StudentSummary {
  const StudentSummary({
    required this.id,
    required this.registrationNo,
    required this.fullName,
    required this.campusId,
    required this.campusName,
    required this.classId,
    required this.className,
    required this.sectionName,
    required this.academicYear,
    required this.status,
    this.revision = 1,
  });

  final String id;
  final String registrationNo;
  final String fullName;
  final String campusId;
  final String campusName;
  final String classId;
  final String className;
  final String sectionName;
  final String academicYear;
  final StudentStatus status;
  final int revision;
}

class StudentDirectoryFilters {
  const StudentDirectoryFilters({
    this.searchText = '',
    this.campusId,
    this.classId,
    this.status,
  });

  final String searchText;
  final String? campusId;
  final String? classId;
  final StudentStatus? status;
}

/// An explicit input contract for an already-authorized data projection.
///
/// A backend must enforce school/campus/role permissions and return ONLY the
/// rows the user is allowed to access. Filtering this list in Flutter is a
/// convenience for UI, not security. Never seed unauthorized campus records
/// into an offline desktop SQLite store.
class StudentDirectoryProjection {
  const StudentDirectoryProjection({
    required this.authorizedCampusIds,
    required this.records,
  });

  final Set<String> authorizedCampusIds;
  final List<StudentSummary> records;

  List<StudentSummary> filter(StudentDirectoryFilters filters) {
    final search = filters.searchText.trim().toLowerCase();
    final matches = records.where((student) {
      if (!authorizedCampusIds.contains(student.campusId)) {
        return false;
      }
      if (filters.campusId != null &&
          student.campusId != filters.campusId) {
        return false;
      }
      if (filters.classId != null && student.classId != filters.classId) {
        return false;
      }
      if (filters.status != null && student.status != filters.status) {
        return false;
      }
      if (search.isNotEmpty &&
          !student.fullName.toLowerCase().contains(search) &&
          !student.registrationNo.toLowerCase().contains(search)) {
        return false;
      }
      return true;
    }).toList();
    matches.sort((a, b) {
      final nameOrder = a.fullName.toLowerCase().compareTo(
            b.fullName.toLowerCase(),
          );
      return nameOrder != 0
          ? nameOrder
          : a.registrationNo.compareTo(b.registrationNo);
    });
    return List.unmodifiable(matches);
  }

  List<StudentSummary> get authorizedRecords =>
      filter(const StudentDirectoryFilters());

  Map<String, String> get campuses {
    final result = <String, String>{};
    for (final record in authorizedRecords) {
      result[record.campusId] = record.campusName;
    }
    return result;
  }

  Map<String, String> classesForCampus(String? campusId) {
    final result = <String, String>{};
    for (final record in authorizedRecords) {
      if (campusId == null || record.campusId == campusId) {
        result[record.classId] = record.className;
      }
    }
    return result;
  }
}

/// Synthetic examples only: not school pupils, not Supabase records.
/// All examples belong to one permitted demonstration campus; no other
/// campus data is bundled in the preview's client-side record list.
class StudentDirectoryDemo {
  static const campusId = 'demo-campus-a';

  static const projection = StudentDirectoryProjection(
    authorizedCampusIds: {campusId},
    records: [
      StudentSummary(
        id: 'demo-student-001',
        registrationNo: 'DEMO-001',
        fullName: 'Example Student Alpha',
        campusId: campusId,
        campusName: 'Sample Campus A',
        classId: 'demo-class-1',
        className: 'Grade 1',
        sectionName: 'A',
        academicYear: '2026–2027',
        status: StudentStatus.active,
      ),
      StudentSummary(
        id: 'demo-student-002',
        registrationNo: 'DEMO-002',
        fullName: 'Example Student Beta',
        campusId: campusId,
        campusName: 'Sample Campus A',
        classId: 'demo-class-5',
        className: 'Grade 5',
        sectionName: 'B',
        academicYear: '2026–2027',
        status: StudentStatus.active,
      ),
      StudentSummary(
        id: 'demo-student-003',
        registrationNo: 'DEMO-003',
        fullName: 'Example Student Gamma',
        campusId: campusId,
        campusName: 'Sample Campus A',
        classId: 'demo-class-5',
        className: 'Grade 5',
        sectionName: 'A',
        academicYear: '2026–2027',
        status: StudentStatus.inactive,
      ),
      StudentSummary(
        id: 'demo-student-004',
        registrationNo: 'DEMO-004',
        fullName: 'Example Student Delta',
        campusId: campusId,
        campusName: 'Sample Campus A',
        classId: 'demo-class-1',
        className: 'Grade 1',
        sectionName: 'B',
        academicYear: '2026–2027',
        status: StudentStatus.graduated,
      ),
    ],
  );
}
