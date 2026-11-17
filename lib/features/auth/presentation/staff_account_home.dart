import 'package:flutter/material.dart';
import '../../auth/data/staff_auth_gateway.dart';
import '../../auth/data/staff_permission_gateway.dart';
import '../../students/data/student_directory_repository.dart';
import '../../students/presentation/student_directory_page.dart';
import '../../auth/data/account_password_gateway.dart';
import '../../auth/presentation/account_password_page.dart';

/// Safe account workspace for authenticated roles whose operational screens
/// are not implemented yet. Never shows Owner or Principal data.
class StaffAccountHome extends StatelessWidget {
  const StaffAccountHome({
    super.key,required this.staff,required this.onSignOut,
    required this.passwordGateway,
    this.permissionGateway,
    this.studentRepository,
  });
  final SchoolStaffAccess staff;
  final Future<void> Function() onSignOut;
  final AccountPasswordGateway passwordGateway;
  final StaffPermissionGateway? permissionGateway;
  final StudentDirectoryRepository? studentRepository;

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
            const Text('Your account is active. Dedicated operational '
              'screens for this role are being developed. You can change '
              'the password assigned by the school Owner below.'),
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
                    const Text('Sections still in development do not yet '
                      'provide operational screens.'),
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
