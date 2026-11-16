import 'package:supabase_flutter/supabase_flutter.dart';

class SchoolSectionRecord {
  const SchoolSectionRecord({required this.id, required this.name});
  final String id;
  final String name;
}

class SchoolClassRecord {
  const SchoolClassRecord({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.sections,
  });

  final String id;
  final String name;
  final int sortOrder;
  final List<SchoolSectionRecord> sections;
}

/// RLS protects reads and a private, role-checked SQL function protects writes.
/// This interface makes UI widget tests possible without contacting Supabase.
abstract class AcademicStructureRepository {
  Future<List<SchoolClassRecord>> listClasses({
    required String campusId,
    required String academicYearId,
  });

  Future<void> createClassWithSections({
    required String schoolId,
    required String campusId,
    required String academicYearId,
    required String className,
    required int sortOrder,
    required List<String> sectionNames,
  });
}

class UnconfiguredAcademicStructureRepository
    implements AcademicStructureRepository {
  const UnconfiguredAcademicStructureRepository();

  @override
  Future<List<SchoolClassRecord>> listClasses({
    required String campusId,
    required String academicYearId,
  }) async => const [];

  @override
  Future<void> createClassWithSections({
    required String schoolId,
    required String campusId,
    required String academicYearId,
    required String className,
    required int sortOrder,
    required List<String> sectionNames,
  }) async {
    throw StateError('Academic structure is not connected');
  }
}

class SupabaseAcademicStructureRepository
    implements AcademicStructureRepository {
  const SupabaseAcademicStructureRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<SchoolClassRecord>> listClasses({
    required String campusId,
    required String academicYearId,
  }) async {
    if (client.auth.currentSession == null) {
      throw StateError('Owner sign-in required');
    }

    final rows = await client
        .from('classes')
        .select('id,name,sort_order')
        .eq('campus_id', campusId)
        .eq('academic_year_id', academicYearId)
        .order('sort_order')
        .order('name');
    if (rows.isEmpty) return const [];

    final classIds = [
      for (final row in rows) row['id'] as String,
    ];
    final sectionRows = await client
        .from('sections')
        .select('id,class_id,name')
        .inFilter('class_id', classIds)
        .order('name');

    final sectionsByClass = <String, List<SchoolSectionRecord>>{};
    for (final row in sectionRows) {
      final classId = row['class_id'] as String;
      sectionsByClass.putIfAbsent(classId, () => []).add(
        SchoolSectionRecord(
          id: row['id'] as String,
          name: row['name'] as String,
        ),
      );
    }

    return [
      for (final row in rows)
        SchoolClassRecord(
          id: row['id'] as String,
          name: row['name'] as String,
          sortOrder: (row['sort_order'] as num).toInt(),
          sections: sectionsByClass[row['id'] as String] ?? const [],
        ),
    ];
  }

  @override
  Future<void> createClassWithSections({
    required String schoolId,
    required String campusId,
    required String academicYearId,
    required String className,
    required int sortOrder,
    required List<String> sectionNames,
  }) async {
    if (client.auth.currentSession == null) {
      throw StateError('Owner sign-in required');
    }

    await client.rpc('owner_create_class_with_sections', params: {
      'p_school_id': schoolId,
      'p_campus_id': campusId,
      'p_academic_year_id': academicYearId,
      'p_class_name': className.trim(),
      'p_sort_order': sortOrder,
      'p_sections': [for (final name in sectionNames) name.trim()],
    });
  }
}
