import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

List<Map<String,dynamic>> _rows(Object? value) {
  if(value is! List) throw const FormatException('Invalid attendance list');
  return List.unmodifiable(value.map((x) =>
    Map<String,dynamic>.from(x as Map)));
}

String attendanceOperationId() {
  final random=Random.secure();
  final b=List<int>.generate(16, (_) => random.nextInt(256));
  b[6]=(b[6]&15)|64;
  b[8]=(b[8]&63)|128;
  final hex=b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
  return hex.substring(0,8)+'-'+hex.substring(8,12)+'-'+
    hex.substring(12,16)+'-'+hex.substring(16,20)+'-'+hex.substring(20);
}

class AttendanceTeacher {
  const AttendanceTeacher({required this.id,required this.name,
    required this.email,this.employeeNo,this.employeeId});
  final String id,name,email;
  final String? employeeNo,employeeId;
  factory AttendanceTeacher.parse(Map<String,dynamic> x)=>AttendanceTeacher(
    id:x['user_id'] as String,name:x['name'] as String,
    email:x['email'] as String,employeeNo:x['linked_employee'] as String?,
    employeeId:x['linked_employee_id'] as String?);
}
class AttendanceEmployee {
  const AttendanceEmployee({required this.id,required this.name,
    required this.number,this.linkedUserId});
  final String id,name,number;
  final String? linkedUserId;
  factory AttendanceEmployee.parse(Map<String,dynamic> x)=>AttendanceEmployee(
    id:x['id'] as String,name:x['name'] as String,
    number:x['number'] as String,
    linkedUserId:x['linked_user_id'] as String?);
}
class AttendanceSection {
  const AttendanceSection({required this.classId,required this.className,
    required this.sectionId,required this.sectionName,
    required this.students,this.teacherId});
  final String classId,className,sectionId,sectionName;
  final int students;
  final String? teacherId;
  factory AttendanceSection.parse(Map<String,dynamic> x)=>AttendanceSection(
    classId:x['class_id'] as String,
    className:x['class_name'] as String,
    sectionId:x['section_id'] as String,
    sectionName:x['section_name'] as String,
    students:(x['students'] as num).toInt(),
    teacherId:x['teacher_id'] as String?);
}
class AttendancePolicy {
  const AttendancePolicy({required this.status,required this.from,
    this.deadline});
  final String status,from;
  final String? deadline;
  factory AttendancePolicy.parse(Map<String,dynamic> x)=>AttendancePolicy(
    status:x['status'] as String,from:x['effective_from'].toString(),
    deadline:x['deadline'] as String?);
}
class AttendanceCalendarDay {
  const AttendanceCalendarDay({required this.date,required this.kind,
    this.title});
  final String date,kind;
  final String? title;
  factory AttendanceCalendarDay.parse(Map<String,dynamic> x)=>
    AttendanceCalendarDay(date:x['date'].toString(),
      kind:x['kind'] as String,title:x['title'] as String?);
}
class OwnerAttendanceSnapshot {
  const OwnerAttendanceSnapshot({
    required this.schoolId,required this.campusId,required this.yearId,
    required this.today,required this.timezone,required this.teachers,
    required this.employees,required this.sections,required this.days,
    this.policy,
  });
  final String schoolId,campusId,yearId,today,timezone;
  final List<AttendanceTeacher> teachers;
  final List<AttendanceEmployee> employees;
  final List<AttendanceSection> sections;
  final List<AttendanceCalendarDay> days;
  final AttendancePolicy? policy;
  factory OwnerAttendanceSnapshot.parse(Map<String,dynamic> x)=>
    OwnerAttendanceSnapshot(
      schoolId:x['school_id'] as String,campusId:x['campus_id'] as String,
      yearId:x['year_id'] as String,today:x['today'].toString(),
      timezone:x['timezone'] as String,
      teachers:List.unmodifiable([
        for(final r in _rows(x['teachers'])) AttendanceTeacher.parse(r)]),
      employees:List.unmodifiable([
        for(final r in _rows(x['employees'])) AttendanceEmployee.parse(r)]),
      sections:List.unmodifiable([
        for(final r in _rows(x['sections'])) AttendanceSection.parse(r)]),
      days:List.unmodifiable([
        for(final r in _rows(x['days'])) AttendanceCalendarDay.parse(r)]),
      policy:x['policy'] is Map?AttendancePolicy.parse(
        Map<String,dynamic>.from(x['policy'] as Map)):null);
}
class AttendanceStudent {
  const AttendanceStudent({required this.enrollmentId,required this.name,
    required this.registration,this.mark});
  final String enrollmentId,name,registration;
  final String? mark;
  factory AttendanceStudent.parse(Map<String,dynamic> x)=>AttendanceStudent(
    enrollmentId:x['enrollment_id'] as String,name:x['name'] as String,
    registration:x['registration'] as String,mark:x['mark'] as String?);
}
class TeacherAttendanceSection {
  const TeacherAttendanceSection({required this.assignmentId,
    required this.className,required this.sectionName,
    required this.students,this.registerId,this.registerStatus});
  final String assignmentId,className,sectionName;
  final List<AttendanceStudent> students;
  final String? registerId,registerStatus;
  factory TeacherAttendanceSection.parse(Map<String,dynamic> x)=>
    TeacherAttendanceSection(
      assignmentId:x['assignment_id'] as String,
      className:x['class_name'] as String,
      sectionName:x['section_name'] as String,
      registerId:x['register_id'] as String?,
      registerStatus:x['register_status'] as String?,
      students:List.unmodifiable([
        for(final r in _rows(x['students'])) AttendanceStudent.parse(r)]));
}
class TeacherAttendanceSnapshot {
  const TeacherAttendanceSnapshot({
    required this.schoolId,required this.campusId,required this.today,
    required this.timezone,required this.policyActive,
    required this.schoolDay,required this.canSubmit,
    required this.sections,this.deadline,
  });
  final String schoolId,campusId,today,timezone;
  final String? deadline;
  final bool policyActive,schoolDay,canSubmit;
  final List<TeacherAttendanceSection> sections;
  factory TeacherAttendanceSnapshot.parse(Map<String,dynamic> x)=>
    TeacherAttendanceSnapshot(
      schoolId:x['school_id'] as String,campusId:x['campus_id'] as String,
      today:x['today'].toString(),timezone:x['timezone'] as String,
      policyActive:x['policy_active']==true,schoolDay:x['school_day']==true,
      canSubmit:x['can_submit']==true,deadline:x['deadline'] as String?,
      sections:List.unmodifiable([
        for(final r in _rows(x['sections']))
          TeacherAttendanceSection.parse(r)]));
}
class AttendanceMarkDraft {
  const AttendanceMarkDraft({required this.enrollmentId,
    required this.status,this.reason});
  final String enrollmentId,status;
  final String? reason;
  Map<String,dynamic> toJson()=>{'enrollment_id':enrollmentId,
    'status':status,'reason':reason};
}
class AttendanceSubmission {
  const AttendanceSubmission({required this.registerId,required this.marked});
  final String registerId;
  final int marked;
}

abstract class AttendanceRepository {
  const AttendanceRepository();
  Future<OwnerAttendanceSnapshot> ownerSetup({
    required String schoolId,required String campusId,required String yearId});
  Future<void> assignTeacher({
    required String schoolId,required String campusId,required String yearId,
    required String classId,required String sectionId,required String teacherId});
  Future<void> linkEmployee({
    required String schoolId,required String campusId,required String teacherId,
    required String employeeId});
  Future<void> activatePolicy({
    required String schoolId,required String campusId,required String yearId,
    required String effectiveDate});
  Future<void> createSchoolDay({
    required String schoolId,required String campusId,required String yearId,
    required String date,required String kind});
  Future<TeacherAttendanceSnapshot> today();
  Future<String> openRegister({required String assignmentId});
  Future<AttendanceSubmission> submit({
    required String registerId,required String operationId,
    required List<AttendanceMarkDraft> marks});
}

class SupabaseAttendanceRepository implements AttendanceRepository {
  const SupabaseAttendanceRepository(this.client);
  final SupabaseClient client;

  Future<Map<String,dynamic>> _rpc(String name,
      Map<String,Object?> params) async {
    if(client.auth.currentSession==null) {
      throw StateError('Signed-in school account required');
    }
    final data=await client.rpc(name,params:params);
    if(data is! Map) throw StateError('Invalid '+name+' response');
    return Map<String,dynamic>.from(data);
  }
  Future<void> _confirmed(String name,Map<String,Object?> params) async {
    final value=await _rpc(name,params);
    if(value['saved']!=true) throw StateError('Operation not confirmed');
  }

  @override
  Future<OwnerAttendanceSnapshot> ownerSetup({
    required String schoolId,required String campusId,
    required String yearId}) async {
    final value=OwnerAttendanceSnapshot.parse(
      await _rpc('owner_teacher_attendance_setup', {
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId}));
    if(value.schoolId!=schoolId||value.campusId!=campusId||value.yearId!=yearId) {
      throw StateError('Unexpected school attendance scope');
    }
    return value;
  }

  @override
  Future<void> assignTeacher({required String schoolId,
    required String campusId,required String yearId,
    required String classId,required String sectionId,
    required String teacherId})=>_confirmed('owner_assign_section_teacher',{
    'p_school':schoolId,'p_campus':campusId,'p_year':yearId,
    'p_class':classId,'p_section':sectionId,'p_teacher':teacherId});

  @override
  Future<void> linkEmployee({required String schoolId,
    required String campusId,required String teacherId,
    required String employeeId})=>_confirmed('owner_link_teacher_employee',{
    'p_school':schoolId,'p_campus':campusId,'p_teacher':teacherId,
    'p_employee':employeeId});

  @override
  Future<void> activatePolicy({required String schoolId,
    required String campusId,required String yearId,
    required String effectiveDate})=>_confirmed('owner_activate_attendance_policy',{
    'p_school':schoolId,'p_campus':campusId,
    'p_year':yearId,'p_effective':effectiveDate});

  @override
  Future<void> createSchoolDay({required String schoolId,
    required String campusId,required String yearId,
    required String date,required String kind})=>_confirmed(
      'owner_create_attendance_day',{'p_school':schoolId,
      'p_campus':campusId,'p_year':yearId,'p_date':date,'p_kind':kind});

  @override
  Future<TeacherAttendanceSnapshot> today() async =>
    TeacherAttendanceSnapshot.parse(
      await _rpc('teacher_attendance_today',const {}));

  @override
  Future<String> openRegister({required String assignmentId}) async {
    final x=await _rpc('teacher_open_attendance_register',{
      'p_assignment':assignmentId});
    if(x['status']!='draft'||x['register_id'] is! String){
      throw StateError('Draft register was not confirmed');
    }
    return x['register_id'] as String;
  }

  @override
  Future<AttendanceSubmission> submit({required String registerId,
    required String operationId,
    required List<AttendanceMarkDraft> marks}) async {
    if(marks.isEmpty) throw const FormatException('No student marks');
    final x=await _rpc('teacher_submit_attendance',{
      'p_register':registerId,'p_operation':operationId,
      'p_marks':[for(final m in marks)m.toJson()]});
    if(x['saved']!=true||x['register_id']!=registerId||
      x['status']!='submitted'||x['marked']!=marks.length){
      throw StateError('Attendance submission was not confirmed');
    }
    return AttendanceSubmission(
      registerId:registerId,marked:(x['marked'] as num).toInt());
  }
}
