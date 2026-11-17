import 'package:flutter/material.dart';
import '../../auth/data/staff_auth_gateway.dart';
import '../../auth/data/account_password_gateway.dart';
import '../../auth/presentation/account_password_page.dart';

/// Safe account workspace for authenticated roles whose operational screens
/// are not implemented yet. Never shows Owner or Principal data.
class StaffAccountHome extends StatelessWidget {
  const StaffAccountHome({
    super.key,required this.staff,required this.onSignOut,
    required this.passwordGateway,
  });
  final SchoolStaffAccess staff;
  final Future<void> Function() onSignOut;
  final AccountPasswordGateway passwordGateway;

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
        Expanded(child:AccountPasswordPage(
          gateway:passwordGateway,
          onPasswordChanged:onSignOut,
        )),
      ],
    ),
  );
}
