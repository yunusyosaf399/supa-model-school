import 'package:supabase_flutter/supabase_flutter.dart';

/// DTOs used only for authenticated DB21 JSON RPCs (never direct table writes).
class ExamSection {
  const ExamSection(this.id, this.name);
  final String id, name;
  factory ExamSection.fromJson(Map<String, dynamic> x) =>
      ExamSection(x['id'] as String, x['name'] as String);
}

class ExamSchoolClass {
  const ExamSchoolClass(this.id, this.name, this.sections);
  final String id, name;
  final List<ExamSection> sections;
  factory ExamSchoolClass.fromJson(Map<String, dynamic> x) => ExamSchoolClass(
    x['id'] as String, x['name'] as String,
    [for (final item in (x['sections'] as List? ?? []))
      ExamSection.fromJson(Map<String, dynamic>.from(item as Map))],
  );
}

class ExamSubject {
  const ExamSubject(this.id, this.classId, this.name);
  final String id, classId, name;
  factory ExamSubject.fromJson(Map<String, dynamic> x) => ExamSubject(
    x['id'] as String, x['class_id'] as String, x['name'] as String);
}

class ExamRecord {
  const ExamRecord({
    required this.id, required this.title, required this.kind,
    required this.classId, required this.subjectId, required this.date,
    required this.maxMarks, required this.passMarks, required this.status,
    required this.entered, this.sectionId,
  });
  final String id, title, kind, classId, subjectId, date, status;
  final String? sectionId;
  final double maxMarks, passMarks;
  final int entered;
  bool get published => status == 'published';
  factory ExamRecord.fromJson(Map<String, dynamic> x) => ExamRecord(
    id: x['id'] as String,
    title: x['title'] as String,
    kind: x['kind'] as String,
    classId: x['class_id'] as String,
    sectionId: x['section_id'] as String?,
    subjectId: x['subject_id'] as String,
    date: x['date'] as String,
    maxMarks: (x['max_marks'] as num).toDouble(),
    passMarks: (x['pass_marks'] as num).toDouble(),
    status: x['status'] as String,
    entered: (x['entered'] as num).toInt(),
  );
}

class ExamSnapshot {
  const ExamSnapshot(this.yearId, this.yearLabel, this.classes, this.subjects, this.exams);
  final String yearId, yearLabel;
  final List<ExamSchoolClass> classes;
  final List<ExamSubject> subjects;
  final List<ExamRecord> exams;
  factory ExamSnapshot.fromJson(Map<String, dynamic> x) => ExamSnapshot(
    x['year_id'] as String, x['year_label'] as String,
    [for(final item in (x['classes'] as List? ?? []))
      ExamSchoolClass.fromJson(Map<String, dynamic>.from(item as Map))],
    [for(final item in (x['subjects'] as List? ?? []))
      ExamSubject.fromJson(Map<String, dynamic>.from(item as Map))],
    [for(final item in (x['exams'] as List? ?? []))
      ExamRecord.fromJson(Map<String, dynamic>.from(item as Map))],
  );
}

class ExamStudentMark {
  const ExamStudentMark({
    required this.enrollmentId, required this.name, required this.registrationNo,
    required this.entered, required this.absent, this.rollNo, this.score,
  });
  final String enrollmentId, name, registrationNo;
  final String? rollNo;
  final double? score;
  final bool entered, absent;
  factory ExamStudentMark.fromJson(Map<String, dynamic> x) => ExamStudentMark(
    enrollmentId: x['enrollment_id'] as String,
    name: x['student_name'] as String,
    registrationNo: x['registration_no'] as String,
    rollNo: x['roll_no'] as String?,
    score: (x['score'] as num?)?.toDouble(),
    entered: x['entered'] == true,
    absent: x['absent'] == true,
  );
}

class ExamRoster {
  const ExamRoster(this.status, this.maxMarks, this.passMarks, this.students);
  final String status;
  final double maxMarks, passMarks;
  final List<ExamStudentMark> students;
  bool get published => status == 'published';
  int get entered => students.where((x) => x.entered).length;
  factory ExamRoster.fromJson(Map<String, dynamic> x) => ExamRoster(
    x['status'] as String,
    (x['max_marks'] as num).toDouble(),
    (x['pass_marks'] as num).toDouble(),
    [for(final item in (x['roster'] as List? ?? []))
      ExamStudentMark.fromJson(Map<String, dynamic>.from(item as Map))],
  );
}

abstract class ExamRepository {
  Future<ExamSnapshot> snapshot({
    required String schoolId, required String campusId, String? yearId,
  });
  Future<void> createSubject({
    required String schoolId, required String campusId, required String yearId,
    required String classId, required String name,
  });
  Future<void> createExam({
    required String schoolId, required String campusId, required String yearId,
    required String classId, String? sectionId, required String subjectId,
    required String kind, required String title, required String date,
    required double maxMarks, required double passMarks,
  });
  Future<ExamRoster> roster(String examId);
  Future<void> saveMark({
    required String examId, required String enrollmentId,
    double? score, required bool absent,
  });
  Future<void> publish(String examId);
}

class SupabaseExamRepository implements ExamRepository {
  const SupabaseExamRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> _invoke(String name, Map<String, Object?> params) async {
    if (client.auth.currentSession == null) {
      throw StateError('Sign in to access examinations');
    }
    final result = await client.rpc(name, params: params);
    if (result is! Map) throw StateError('Invalid exam response from server');
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<ExamSnapshot> snapshot({
    required String schoolId, required String campusId, String? yearId,
  }) async => ExamSnapshot.fromJson(await _invoke('sms_exam_snapshot', {
    'p_school': schoolId, 'p_campus': campusId, 'p_year': yearId,
  }));

  @override
  Future<void> createSubject({
    required String schoolId, required String campusId, required String yearId,
    required String classId, required String name,
  }) async {
    await _invoke('sms_exam_create_subject', {
      'p_school': schoolId, 'p_campus': campusId, 'p_year': yearId,
      'p_class': classId, 'p_name': name.trim(),
    });
  }

  @override
  Future<void> createExam({
    required String schoolId, required String campusId, required String yearId,
    required String classId, String? sectionId, required String subjectId,
    required String kind, required String title, required String date,
    required double maxMarks, required double passMarks,
  }) async {
    await _invoke('sms_exam_create', {
      'p_school': schoolId, 'p_campus': campusId, 'p_year': yearId,
      'p_class': classId, 'p_section': sectionId, 'p_subject': subjectId,
      'p_kind': kind, 'p_title': title.trim(), 'p_date': date,
      'p_max': maxMarks, 'p_pass': passMarks,
    });
  }

  @override
  Future<ExamRoster> roster(String examId) async =>
    ExamRoster.fromJson(await _invoke('sms_exam_roster', {'p_exam': examId}));

  @override
  Future<void> saveMark({
    required String examId, required String enrollmentId,
    double? score, required bool absent,
  }) async {
    await _invoke('sms_exam_save_mark', {
      'p_exam': examId, 'p_enrollment': enrollmentId,
      'p_score': score, 'p_absent': absent,
    });
  }

  @override
  Future<void> publish(String examId) async {
    await _invoke('sms_exam_publish', {'p_exam': examId});
  }
}
