import 'package:flutter/material.dart';
import '../../auth/data/principal_auth_gateway.dart';
import '../../auth/data/staff_permission_gateway.dart';
import '../../students/data/student_directory_repository.dart';
import '../../students/presentation/student_directory_page.dart';
import '../data/admission_approval_repository.dart';
import 'principal_approval_page.dart';
import '../../auth/data/account_password_gateway.dart';
import '../../auth/presentation/account_password_page.dart';

/// Separate Principal workspace. Owner navigation is never reused.
/// Every list and mutation is rechecked by Supabase against the current JWT.
class PrincipalAdmissionsHome extends StatefulWidget {
  const PrincipalAdmissionsHome({
    super.key,required this.principal,required this.repository,
    required this.onSignOut,
    this.passwordGateway,
    this.permissionGateway,
    this.studentRepository,
  });
  final PrincipalAccess principal;
  final AdmissionApprovalRepository repository;
  final Future<void> Function() onSignOut;
  final AccountPasswordGateway? passwordGateway;
  final StaffPermissionGateway? permissionGateway;
  final StudentDirectoryRepository? studentRepository;

  @override
  State<PrincipalAdmissionsHome> createState()=>_PrincipalAdmissionsHomeState();
}

class _PrincipalAdmissionsHomeState extends State<PrincipalAdmissionsHome> {
  late String _campusId;
  bool _showPassword=false;
  bool _showStudents=false;
  Future<Set<String>>? _actions;

  @override
  void initState(){
    super.initState();
    _campusId=widget.principal.campuses.first.id;
    _actions=widget.permissionGateway?.allowedActions();
  }

  Widget _authorizedWorkspace() {
    if (widget.permissionGateway == null) return _approvalQueue();
    return FutureBuilder<Set<String>>(
      future: _actions,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Could not load access permissions.'),
            TextButton(onPressed: () => setState(() =>
              _actions=widget.permissionGateway!.allowedActions()),
              child: const Text('Retry')),
          ]),
        ));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allowed = snapshot.data!;
        final sections = allowed.map(StaffPermissionTitles.title).toSet().toList()
          ..sort();
        return Column(children: [
          Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Text('My assigned sections',
                    style: TextStyle(fontWeight: FontWeight.w700))),
                  IconButton(
                    key: const Key('principal-reload-permissions'),
                    tooltip: 'Refresh access permissions',
                    onPressed: () => setState(() =>
                      _actions=widget.permissionGateway!.allowedActions()),
                    icon: const Icon(Icons.refresh)),
                ]),
                if (sections.isEmpty)
                  const Text('No school modules are currently assigned.'),
                if (sections.isNotEmpty)
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final section in sections)
                      Chip(label: Text(section)),
                  ]),
                const Text('Other enabled sections are reserved for future '
                  'modules. Actions require their own authorized backend.'),
              ],
            ),
          )),
          if (allowed.contains('admissions.review') ||
              (allowed.contains('students.read') && widget.studentRepository != null))
            Padding(padding: const EdgeInsets.all(7),
              child: Row(children: [
                if (allowed.contains('admissions.review'))
                  TextButton.icon(
                    key: const Key('principal-approvals-tab'),
                    onPressed: () => setState(() => _showStudents=false),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Approvals')),
                if (allowed.contains('students.read') &&
                    widget.studentRepository != null)
                  TextButton.icon(
                    key: const Key('principal-students-tab'),
                    onPressed: () => setState(() => _showStudents=true),
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Students')),
              ])),
          Expanded(child: _showStudents &&
                  allowed.contains('students.read') &&
                  widget.studentRepository != null
              ? StudentDirectoryPage(
                  key: ValueKey('principal-students-$_campusId'),
                  onNewAdmission: () {},
                  allowNewAdmission: false,
                  staffSchoolId: widget.principal.schoolId,
                  staffCampusId: _campusId,
                  repository: widget.studentRepository,
                )
              : allowed.contains('admissions.review')
                ? _approvalQueue()
                : const Center(child: Text(
                  'No available operational section is enabled.'))),
        ]);
      },
    );
  }

  Widget _approvalQueue() => PrincipalApprovalPage(
    key: ValueKey('principal-queue-$_campusId'),
    schoolId: widget.principal.schoolId,
    campusId: _campusId,
    repository: widget.repository,
  );

  @override
  Widget build(BuildContext context) {
    final campuses=widget.principal.campuses;
    return Scaffold(
      key:const Key('principal-admissions-home'),
      appBar:AppBar(
        title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.principal.schoolName,
            style:Theme.of(context).textTheme.titleMedium),
          Text('Principal • ${widget.principal.displayName}',
            style:Theme.of(context).textTheme.bodySmall),
        ]),
        actions:[
          if(widget.passwordGateway!=null)
            IconButton(
              key:const Key('principal-account-password'),
              tooltip:_showPassword?'Back to Admissions':'Change Password',
              icon:Icon(_showPassword
                ? Icons.fact_check_outlined:Icons.manage_accounts_outlined),
              onPressed:()=>setState(()=>_showPassword=!_showPassword),
            ),
          if(campuses.length>1)
            DropdownButton<String>(
              key:const Key('principal-campus-selector'),
              value:_campusId,
              items:[
                for(final c in campuses)
                  DropdownMenuItem(value:c.id,child:Text(c.name)),
              ],
              onChanged:(id){
                if(id!=null && campuses.any((c)=>c.id==id)) {
                  setState(() { _campusId=id; _showStudents=false; });
                }
              },
            )
          else
            Padding(
              padding:const EdgeInsets.symmetric(horizontal:12),
              child:Center(child:Text(campuses.first.name)),
            ),
          IconButton(
            key:const Key('principal-sign-out'),
            tooltip:'Sign out',
            icon:const Icon(Icons.logout),
            onPressed:() async {
              final logout=await showDialog<bool>(context:context,
                builder:(dialogContext)=>AlertDialog(
                  title:const Text('Sign out?'),
                  content:const Text('Close your Principal session?'),
                  actions:[
                    TextButton(onPressed:()=>
                      Navigator.of(dialogContext).pop(false),
                      child:const Text('Cancel')),
                    FilledButton(onPressed:()=>
                      Navigator.of(dialogContext).pop(true),
                      child:const Text('Sign out')),
                  ],
                ));
              if(logout==true && mounted) await widget.onSignOut();
            },
          ),
        ],
      ),
      body:_showPassword && widget.passwordGateway!=null
        ? AccountPasswordPage(
            gateway:widget.passwordGateway!,
            onPasswordChanged:widget.onSignOut,
          )
         : _authorizedWorkspace(),
    );
  }
}
