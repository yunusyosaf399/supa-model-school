import 'package:flutter/material.dart';
import '../../auth/data/principal_auth_gateway.dart';
import '../data/admission_approval_repository.dart';
import 'principal_approval_page.dart';

/// Separate Principal workspace. Owner navigation is never reused.
/// Every list and mutation is rechecked by Supabase against the current JWT.
class PrincipalAdmissionsHome extends StatefulWidget {
  const PrincipalAdmissionsHome({
    super.key,required this.principal,required this.repository,
    required this.onSignOut,
  });
  final PrincipalAccess principal;
  final AdmissionApprovalRepository repository;
  final Future<void> Function() onSignOut;

  @override
  State<PrincipalAdmissionsHome> createState()=>_PrincipalAdmissionsHomeState();
}

class _PrincipalAdmissionsHomeState extends State<PrincipalAdmissionsHome> {
  late String _campusId;

  @override
  void initState(){
    super.initState();
    _campusId=widget.principal.campuses.first.id;
  }

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
                  setState(()=>_campusId=id);
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
      body:PrincipalApprovalPage(
        key:ValueKey('principal-queue-$_campusId'),
        schoolId:widget.principal.schoolId,
        campusId:_campusId,
        repository:widget.repository,
      ),
    );
  }
}
