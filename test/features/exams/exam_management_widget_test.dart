import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/exams/data/exam_repository.dart';
import 'package:supa_model_school/features/exams/presentation/exam_management_page.dart';

class FakeExamRepository implements ExamRepository {
  int creates = 0;
  int saves = 0;
  int publications = 0;
  bool published = false;

  @override
  Future<ExamSnapshot> snapshot({
    required String schoolId, required String campusId, String? yearId,
  }) async => ExamSnapshot('year-1', '2026-2027',
    [ExamSchoolClass('class-1', 'Grade 1', [ExamSection('sec-a', 'A')])],
    [ExamSubject('subject-1', 'class-1', 'Mathematics')],
    [ExamRecord(id: 'exam-1', title: 'First Term Mathematics',
      kind: 'test', classId: 'class-1', sectionId: 'sec-a',
      subjectId: 'subject-1', date: '2026-11-20',
      maxMarks: 100, passMarks: 40,
      status: published ? 'published' : 'draft', entered: saves)],
  );

  @override
  Future<void> createSubject({
    required String schoolId, required String campusId,
    required String yearId, required String classId, required String name,
  }) async { creates++; }

  @override
  Future<void> createExam({
    required String schoolId, required String campusId,
    required String yearId, required String classId, String? sectionId,
    required String subjectId, required String kind, required String title,
    required String date, required double maxMarks, required double passMarks,
  }) async { creates++; }

  @override
  Future<ExamRoster> roster(String examId) async => ExamRoster(
    published ? 'published' : 'draft', 100, 40,
    [ExamStudentMark(
      enrollmentId: 'enrollment-1', name: 'Sample Student',
      registrationNo: 'REG-01', rollNo: '1',
      entered: saves > 0, absent: false, score: saves > 0 ? 75 : null)],
  );

  @override
  Future<void> saveMark({
    required String examId, required String enrollmentId,
    double? score, required bool absent,
  }) async { saves++; }

  @override
  Future<void> publish(String examId) async {
    publications++;
    published = true;
  }
}

void main() {
  testWidgets('Owner can see live exam scheduling form and test list',
      (tester) async {
    final fake = FakeExamRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ExamManagementPage(repository: fake,
        schoolId: 'school', campusId: 'campus', yearId: 'year-1'))));
    await tester.pumpAndSettle();
    expect(find.text('Examinations & Tests'), findsOneWidget);
    expect(find.byKey(const Key('exam-add-subject')), findsOneWidget);
    expect(find.text('First Term Mathematics'), findsOneWidget);
  });

  testWidgets('Read-only Principal sees exams but not creation controls',
      (tester) async {
    final fake = FakeExamRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ExamManagementPage(repository: fake,
        schoolId: 'school', campusId: 'campus',
        canCreate: false, canUpdate: false))));
    await tester.pumpAndSettle();
    expect(find.text('First Term Mathematics'), findsOneWidget);
    expect(find.byKey(const Key('exam-create')), findsNothing);
    expect(find.byKey(const Key('exam-add-subject')), findsNothing);
  });

  testWidgets('Marks editor saves then publishes and locks results',
      (tester) async {
    final fake = FakeExamRepository();
    const exam = ExamRecord(id: 'exam-1', title: 'Class Test',
      kind: 'test', classId: 'class-1', subjectId: 'subject-1',
      date: '2026-11-20', maxMarks: 100, passMarks: 40,
      status: 'draft', entered: 0);
    await tester.pumpWidget(MaterialApp(home:
      ExamMarksPage(repository: fake, exam: exam, canUpdate: true)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('exam-score-enrollment-1')), '75');
    await tester.tap(find.byKey(const Key('exam-save-enrollment-1')));
    await tester.pumpAndSettle();
    expect(fake.saves, 1);
    await tester.tap(find.byKey(const Key('exam-publish')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish').last);
    await tester.pumpAndSettle();
    expect(fake.publications, 1);
    expect(find.text('Published'), findsWidgets);
    expect(find.byKey(const Key('exam-save-enrollment-1')), findsNothing);
  });
}
