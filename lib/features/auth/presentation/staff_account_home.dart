import 'package:flutter/material.dart';
import '../../auth/data/staff_auth_gateway.dart';
import '../../auth/data/staff_permission_gateway.dart';
import '../../students/data/student_directory_repository.dart';
import '../../students/presentation/student_directory_page.dart';
import '../../auth/data/account_password_gateway.dart';
import '../../exams/data/exam_repository.dart';
import '../../exams/presentation/exam_management_page.dart';
import '../../auth/presentation/account_password_page.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/presentation/teacher_attendance_page.dart';
import '../../fees/data/fee_payment_repository.dart';
import '../../fees/data/fee_billing_repository.dart';
import '../../fees/data/fee_cashbook_repository.dart';
import '../../fees/presentation/fee_collection_page.dart';

/// Safe account workspace for authenticated roles whose operational screens
/// are not implemented yet. Never shows Owner or Principal data.
class StaffAccountHome extends StatelessWidget {
  const StaffAccountHome({
    super.key,required this.staff,required this.onSignOut,
    required this.passwordGateway,
    this.permissionGateway,
    this.studentRepository,
    this.attendanceRepository,
    this.examRepository,
    this.feePaymentRepository,
    this.feeBillingRepository,
    this.feeCashbookRepository,
  });
  final SchoolStaffAccess staff;
  final Future<void> Function() onSignOut;
  final AccountPasswordGateway passwordGateway;
  final StaffPermissionGateway? permissionGateway;
  final StudentDirectoryRepository? studentRepository;
  final AttendanceRepository? attendanceRepository;
  final ExamRepository? examRepository;
  final FeePaymentRepository? feePaymentRepository;
  final FeeBillingRepository? feeBillingRepository;
  final FeeCashbookRepository? feeCashbookRepository;

  @override
  Widget build(BuildContext context)=>Scaffold(
    key:const Key('staff-account-home'),
    appBar:AppBar(
      title:Text('${staff.schoolName} • ${staff.role.replaceAll('_',' ')}'),
      actions:[
        IconButton(
          key:const Key('staff-account-sign-out'),
          tooltip:'Sign out',
          icon:const Icon(Icons.logout_outlined),
          onPressed:onSignOut,
        ),
      ],
    ),
    body:Column(
      children:[
        Padding(
          padding:const EdgeInsets.fromLTRB(16,16,16,0),
          child:Card(child:Padding(padding:const EdgeInsets.all(16),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Welcome, ${staff.displayName}',
              style:Theme.of(context).textTheme.titleLarge),
            const SizedBox(height:7),
            Text('Assigned role: ${staff.role.replaceAll('_',' ')}'),
            Text('Campus: ${staff.campusName}'),
            const SizedBox(height:8),
            const Text('Your account is active. The school Owner controls '
              'your permissions and assigned modules. You can change '
              'your Owner-issued password below.'),
          ]),
        )),
        ),
        if (permissionGateway != null) Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: FutureBuilder<Set<String>>(
              future: permissionGateway!.allowedActions(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text(
                  'Assigned permissions could not be loaded.');
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final sections = snapshot.data!
                  .map(StaffPermissionTitles.title).toSet().toList()..sort();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Assigned sections', style:
                      TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (sections.isEmpty)
                      const Text('No operational modules have been granted.'),
                    if (sections.isNotEmpty) Wrap(spacing: 6, children: [
                      for (final section in sections) Chip(label: Text(section)),
                    ]),
                    if (snapshot.data!.contains('students.read') &&
                        studentRepository != null)
                      TextButton.icon(
                        key: const Key('staff-open-students'),
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Students')),
                            body: StudentDirectoryPage(
                              onNewAdmission: () {},
                              allowNewAdmission: false,
                              staffSchoolId: staff.schoolId,
                              staffCampusId: staff.campusId,
                              repository: studentRepository,
                            ),
                          ))),
                        icon: const Icon(Icons.groups_outlined),
                        label: const Text('View Students'),
                      ),
                    if ((staff.role == 'accountant' || staff.role == 'admin') &&
                        snapshot.data!.contains('fees.read') &&
                        feePaymentRepository != null)
                      TextButton.icon(
                        key: const Key('staff-open-fees'),
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Fees & Quick Pay')),
                            body: FeeCollectionPage(
                              repository: feePaymentRepository!,
                              billingRepository: feeBillingRepository,
                              cashbookRepository: feeCashbookRepository,
                              schoolId: staff.schoolId,
                              campusId: staff.campusId,
                            ),
                          ))),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Fee Collection & Quick Pay'),
                      ),
                    if (staff.role == 'teacher' &&
                        snapshot.data!.contains('attendance.read') &&
                        attendanceRepository != null)
                      TextButton.icon(
                        key: const Key('teacher-open-attendance'),
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) =>
                            TeacherAttendancePage(
                              repository: attendanceRepository!,
                            ))),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Take Attendance'),
                      ),
                    if (staff.role == 'teacher' &&
                        !snapshot.data!.contains('attendance.read'))
                      const Text('Attendance permission has not been granted '
                        'by the Owner.'),
                    if (staff.role != 'teacher' &&
                        snapshot.data!.contains('exams.read') &&
                        examRepository != null)
                      TextButton.icon(
                        key: const Key('staff-open-exams'),
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Examinations')),
                            body: ExamManagementPage(
                              repository: examRepository!,
                              schoolId: staff.schoolId,
                              campusId: staff.campusId,
                              canCreate: snapshot.data!.contains('exams.create'),
                              canUpdate: snapshot.data!.contains('exams.update'),
                            ),
                          ))),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Manage Exams & Tests'),
                      ),
                    const Text('Other operational sections may still '
                      'be under development.'),
                  ],
                );
              },
            ),
          )),
        ),
        Expanded(child:AccountPasswordPage(
          gateway:passwordGateway,
          onPasswordChanged:onSignOut,
        )),
      ],
    ),
  );
}
