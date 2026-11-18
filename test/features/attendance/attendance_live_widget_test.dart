import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/attendance/data/attendance_repository.dart';
import 'package:supa_model_school/features/attendance/presentation/owner_attendance_setup_page.dart';
import 'package:supa_model_school/features/attendance/presentation/teacher_attendance_page.dart';

const owner=OwnerAccess(
  userId:'owner-1',displayName:'School Owner',schoolId:'school-1',
  schoolName:'Supa Model School',
  campuses:[OwnerCampus(id:'campus-1',name:'Main')],
  activeYearId:'year-1',activeYearLabel:'2026-2027',
  activeYearEndsOn:'2027-03-31',setupComplete:true,
);

class FakeAttendanceRepo implements AttendanceRepository {
  int teacherCount=1,assigned=0,linked=0,opened=0,submitted=0;
  bool denyTeacher=false,canSubmit=true,failOnce=false;
  final operations=<String>[];
  String? assignedUser;
  @override
  Future<OwnerAttendanceSnapshot> ownerSetup({
    required String schoolId,required String campusId,
    required String yearId}) async =>OwnerAttendanceSnapshot(
    schoolId:schoolId,campusId:campusId,yearId:yearId,
    today:'2026-11-18',timezone:'Asia/Karachi',
    teachers:[
      if(teacherCount>0)const AttendanceTeacher(
        id:'teacher-1',name:'Teacher One',email:'teacher@example.test'),
    ],
    employees:const [
      AttendanceEmployee(id:'emp-1',name:'SAMPLE Shazia Khan',
        number:'SAMPLE-EMP-002'),
    ],
    sections:[
      AttendanceSection(
        classId:'class-1',className:'Grade 1',
        sectionId:'section-1',sectionName:'A',
        students:2,teacherId:assignedUser),
    ],
    days:const [
      AttendanceCalendarDay(
        date:'2026-11-18',kind:'instructional',
        title:'SAMPLE instructional day'),
    ],
    policy:const AttendancePolicy(
      status:'draft',from:'2026-11-16',deadline:'09:15:00'),
  );
  @override
  Future<void> assignTeacher({
    required String schoolId,required String campusId,
    required String yearId,required String classId,
    required String sectionId,required String teacherId}) async {
    expect(schoolId,'school-1');
    expect(campusId,'campus-1');
    expect(yearId,'year-1');
    expect(sectionId,'section-1');
    expect(teacherId,'teacher-1');
    assignedUser=teacherId;assigned++;
  }
  @override
  Future<void> linkEmployee({
    required String schoolId,required String campusId,
    required String teacherId,required String employeeId}) async {linked++;}
  @override
  Future<void> activatePolicy({
    required String schoolId,required String campusId,
    required String yearId,required String effectiveDate}) async {}
  @override
  Future<void> createSchoolDay({
    required String schoolId,required String campusId,
    required String yearId,required String date,
    required String kind}) async {}
  @override
  Future<TeacherAttendanceSnapshot> today() async {
    if(denyTeacher)throw StateError('Teacher grant denied');
    return TeacherAttendanceSnapshot(
      schoolId:'school-1',campusId:'campus-1',today:'2026-11-18',
      timezone:'Asia/Karachi',policyActive:true,schoolDay:true,
      canSubmit:canSubmit,deadline:'09:15:00',
      sections:const [
        TeacherAttendanceSection(assignmentId:'a1',
          className:'Grade 1',sectionName:'A',students:[
            AttendanceStudent(enrollmentId:'e1',name:'Areeba Fatima',
              registration:'SAMPLE-2026-0003'),
            AttendanceStudent(enrollmentId:'e2',name:'Hamza Yousaf',
              registration:'SAMPLE-2026-0006'),
          ]),
      ],
    );
  }
  @override
  Future<String> openRegister({required String assignmentId}) async {
    expect(assignmentId,'a1');opened++;
    return 'r1';
  }
  @override
  Future<AttendanceSubmission> submit({
    required String registerId,required String operationId,
    required List<AttendanceMarkDraft> marks}) async {
    operations.add(operationId);
    expect(registerId,'r1');
    expect(marks.length,2);
    expect(marks.map((m)=>m.enrollmentId).toSet(),{'e1','e2'});
    submitted++;
    if(failOnce){
      failOnce=false;
      throw StateError('Network response lost');
    }
    return const AttendanceSubmission(registerId:'r1',marked:2);
  }
}

Future<void> pumpOwner(WidgetTester t,FakeAttendanceRepo fake) async {
  await t.binding.setSurfaceSize(const Size(1100,950));
  addTearDown(()=>t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home:Scaffold(
    body:OwnerAttendanceSetupPage(
      owner:owner,repository:fake,selectedCampusId:'campus-1'))));
  await t.pumpAndSettle();
}

Future<void> pumpTeacher(WidgetTester t,FakeAttendanceRepo fake) async {
  await t.binding.setSurfaceSize(const Size(430,850));
  addTearDown(()=>t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home:TeacherAttendancePage(repository:fake)));
  await t.pumpAndSettle();
}

void main(){
  test('attendance operation IDs are independent version-4 UUIDs',(){
    final a=attendanceOperationId(),b=attendanceOperationId();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
      .hasMatch(a),true);
    expect(a,isNot(b));
  });

  testWidgets('Owner displays assignments and saves only selected teacher',
    (t) async {
    final repo=FakeAttendanceRepo();
    await pumpOwner(t,repo);
    expect(find.byKey(const Key('owner-attendance-setup-page')),findsOneWidget);
    expect(find.text('Teacher One'),findsWidgets);
    expect(find.text('Status: draft'),findsOneWidget);
    expect(find.textContaining('Grade 1 • Section A'),findsOneWidget);
    await t.tap(find.byKey(const Key('owner-attendance-teacher-section-1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Teacher One').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('owner-save-teacher-section-1')));
    await t.pumpAndSettle();
    expect(repo.assigned,1);
    expect(t.takeException(),isNull);
  });

  testWidgets('Owner with no Teacher users sees onboarding rather than demo account',
    (t) async {
    final repo=FakeAttendanceRepo()..teacherCount=0;
    await pumpOwner(t,repo);
    expect(find.textContaining('No active Teacher accounts'),findsOneWidget);
    expect(find.byKey(const Key('owner-save-teacher-section-1')),findsOneWidget);
    expect(repo.assigned,0);
    expect(t.takeException(),isNull);
  });

  testWidgets('Teacher cannot submit until every student has a mark',
    (t) async {
    final repo=FakeAttendanceRepo();
    await pumpTeacher(t,repo);
    expect(find.byKey(const Key('teacher-attendance-live-page')),findsOneWidget);
    await t.tap(find.byKey(const Key('teacher-attendance-take-a1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('teacher-attendance-register-page')),findsOneWidget);
    expect(find.text('Unmarked: 2. Every student requires an explicit mark.'),
      findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('teacher-submit-attendance')));
    await t.tap(find.byKey(const Key('teacher-submit-attendance')));
    await t.pumpAndSettle();
    expect(find.textContaining('Mark every student'),findsOneWidget);
    expect(repo.submitted,0);
    expect(repo.opened,0);
    expect(t.takeException(),isNull);
  });

  testWidgets('Confirmed two-student register is submitted once with safe retry',
    (t) async {
    final repo=FakeAttendanceRepo()..failOnce=true;
    await pumpTeacher(t,repo);
    await t.tap(find.byKey(const Key('teacher-attendance-take-a1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('teacher-status-e1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Present').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('teacher-status-e2')));
    await t.tap(find.byKey(const Key('teacher-status-e2')));
    await t.pumpAndSettle();
    await t.tap(find.text('Absent').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('teacher-submit-attendance')));
    await t.tap(find.byKey(const Key('teacher-submit-attendance')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('teacher-confirm-submit')));
    await t.pumpAndSettle();
    expect(repo.submitted,1);
    expect(find.textContaining('Network response lost'),findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('teacher-submit-attendance')));
    await t.tap(find.byKey(const Key('teacher-submit-attendance')));
    await t.pumpAndSettle();
    expect(repo.opened,1);
    expect(repo.submitted,2);
    expect(repo.operations[0],repo.operations[1]);
    expect(find.textContaining('Submitted marks are permanent evidence'),findsOneWidget);
    expect(t.takeException(),isNull);
  });

  testWidgets('Teacher read denied or deadline passed cannot record attendance',
    (t) async {
    final repo=FakeAttendanceRepo()..denyTeacher=true;
    await pumpTeacher(t,repo);
    expect(find.textContaining('Teacher grant denied'),findsOneWidget);
    expect(find.byKey(const Key('teacher-attendance-take-a1')),findsNothing);
    expect(t.takeException(),isNull);
  });
}
