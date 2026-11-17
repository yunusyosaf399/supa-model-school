import 'package:flutter/material.dart';
import '../../auth/data/owner_auth_gateway.dart';
import '../data/owner_user_management_repository.dart';
import 'staff_permissions_dialog.dart';

/// Owner-only user administration. Passwords are transient form inputs and
/// are never saved in school tables, logs or on-device persistent storage.
class OwnerUserControlPanelPage extends StatefulWidget {
  const OwnerUserControlPanelPage({
    super.key,required this.owner,required this.repository,
    required this.onBack,
  });
  final OwnerAccess owner;
  final OwnerUserManagementRepository repository;
  final VoidCallback onBack;
  @override
  State<OwnerUserControlPanelPage> createState()=>_OwnerUserControlPanelPageState();
}

class _OwnerUserControlPanelPageState extends State<OwnerUserControlPanelPage> {
  static const roles=<String,String>{
    'principal':'Principal',
    'vice_principal':'Vice Principal',
    'admin':'Administrator',
    'accountant':'Accountant',
    'hr':'Human Resources',
    'teacher':'Teacher',
    'coordinator':'Coordinator',
    'librarian':'Librarian',
    'transport_manager':'Transport Manager',
    'driver':'Driver',
    'nurse':'Nurse / Medical Staff',
    'store_keeper':'Store Keeper',
    'security_guard':'Security Guard',
    'parent':'Parent / Guardian',
    'attendance_staff':'Attendance Staff',
  };

  final _form=GlobalKey<FormState>();
  final _name=TextEditingController();
  final _email=TextEditingController();
  final _password=TextEditingController();
  final _confirmPassword=TextEditingController();
  final _search=TextEditingController();
  late String _campusId;
  String _role='teacher';
  bool _loading=false;
  bool _creating=false;
  bool _showPassword=false;
  String? _changing;
  String? _error;
  List<OwnerStaffAccount> _staff=const [];
  int _requestId=0;

  @override
  void initState(){
    super.initState();
    _campusId=widget.owner.campuses.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted) _reload();
    });
  }

  @override
  void didUpdateWidget(covariant OwnerUserControlPanelPage oldWidget){
    super.didUpdateWidget(oldWidget);
    if(oldWidget.owner.userId!=widget.owner.userId ||
        oldWidget.owner.schoolId!=widget.owner.schoolId){
      _requestId++;
      _staff=const [];
      _campusId=widget.owner.campuses.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_){
        if(mounted)_reload();
      });
    }
  }

  @override
  void dispose(){
    _requestId++;
    _name.dispose();_email.dispose();_search.dispose();
    _password.dispose();_confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final id=++_requestId;
    setState((){
      _loading=true;
      _error=null;
      _staff=const [];
    });
    try{
      final result=await widget.repository.listUsers(widget.owner.schoolId);
      if(!mounted||id!=_requestId)return;
      setState((){
        _staff=result;
        _loading=false;
      });
    }catch(_){
      if(!mounted||id!=_requestId)return;
      setState((){
        _loading=false;
        _error='Cannot load authorized school users. Check your Owner session.';
      });
    }
  }

  Future<void> _createAccount() async {
    if(_creating||_changing!=null||!_form.currentState!.validate())return;
    final campus=widget.owner.campuses.firstWhere((c)=>c.id==_campusId);
    final confirmed=await showDialog<bool>(context:context,
      builder:(dialogContext)=>AlertDialog(
        title:const Text('Create staff login?'),
        content:Text('Create a login for ${_email.text.trim()} as '
          '${roles[_role]} at ${campus.name}? The initial password you '
          'entered becomes active immediately. Give it privately to the user.'),
        actions:[
          TextButton(
            onPressed:()=>Navigator.pop(dialogContext,false),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('confirm-staff-create'),
            onPressed:()=>Navigator.pop(dialogContext,true),
            child:const Text('Create account')),
        ],
      ));
    if(confirmed!=true||!mounted)return;
    setState((){
      _creating=true;
      _error=null;
    });
    try{
      await widget.repository.createUser(OwnerUserCreation(
        schoolId:widget.owner.schoolId,
        campusId:_campusId,role:_role,
        email:_email.text.trim(),name:_name.text.trim(),
        password:_password.text));
      if(!mounted)return;
      _name.clear();
      _email.clear();
      _password.clear();
      _confirmPassword.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Staff login created. Give the initial password to '
          'the user privately. They can change it in Account Settings.')));
      await _reload();
    }catch(_){
      if(!mounted)return;
      setState(()=>_error='Account creation was not confirmed. Check the '
        'staff list before retrying; the email may already be in use.');
    }finally{
      if(mounted)setState(()=>_creating=false);
    }
  }

  Future<void> _changeStatus(OwnerStaffAccount user) async {
    if(_changing!=null||user.role=='owner'||user.role=='super_admin')return;
    final next=!user.active;
    final answer=await showDialog<bool>(context:context,
      builder:(dialogContext)=>AlertDialog(
        title:Text(next?'Reactivate staff access?':'Deactivate staff access?'),
        content:Text('${user.name} — ${roles[user.role]??user.role} '
          'at ${user.campusName}. '
          '${next?'Restore this campus role?':'Prevent further role-authorized operations?'} '
          'Deactivation does not delete historical records.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext,false),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('confirm-staff-status'),
            onPressed:()=>Navigator.pop(dialogContext,true),
            child:Text(next?'Reactivate':'Deactivate')),
        ],
      ));
    if(answer!=true||!mounted)return;
    setState((){
      _changing=user.roleId;
      _error=null;
    });
    try{
      await widget.repository.setRoleActive(user.roleId,next);
      if(!mounted)return;
      await _reload();
    }catch(_){
      if(!mounted)return;
      setState(()=>_error='Role access could not be updated. Refresh and retry.');
    }finally{
      if(mounted)setState(()=>_changing=null);
    }
  }

  @override
  Widget build(BuildContext context){
    final query=_search.text.trim().toLowerCase();
    final matches=_staff.where((u)=>
      query.isEmpty ||
      u.name.toLowerCase().contains(query) ||
      u.email.toLowerCase().contains(query) ||
      u.role.toLowerCase().contains(query) ||
      u.campusName.toLowerCase().contains(query)).toList(growable:false);
    final theme=Theme.of(context);
    return ListView(
      key:const Key('owner-user-control-panel'),
      padding:const EdgeInsets.all(18),
      children:[
        Row(children:[
          IconButton(
            key:const Key('owner-users-back'),
            tooltip:'Back to Owner Settings',
            onPressed:widget.onBack,
            icon:const Icon(Icons.arrow_back)),
          const SizedBox(width:8),
          Expanded(child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text('User Management',style:theme.textTheme.headlineSmall),
              Text('${widget.owner.schoolName} • Roles & campus access',
                style:theme.textTheme.bodyMedium),
            ],
          )),
          IconButton(
            tooltip:'Refresh users',
            onPressed:_loading||_creating?null:_reload,
            icon:const Icon(Icons.refresh)),
        ]),
        const SizedBox(height:12),
        Card(child:Padding(padding:const EdgeInsets.all(16),
          child:Form(key:_form,child:Column(
            crossAxisAlignment:CrossAxisAlignment.stretch,
            children:[
              Text('Create user login',style:theme.textTheme.titleLarge),
              const SizedBox(height:6),
              const Text('Assign an initial password now. No invitation email '
                'is required. Share the password privately; the user can '
                'change it after logging in.'),
              const SizedBox(height:14),
              TextFormField(
                key:const Key('staff-name'),
                controller:_name,
                textCapitalization:TextCapitalization.words,
                decoration:const InputDecoration(
                  labelText:'Full name',border:OutlineInputBorder()),
                validator:(v)=>(v??'').trim().length<2?
                  'Enter a full name':null),
              const SizedBox(height:10),
              TextFormField(
                key:const Key('staff-email'),
                controller:_email,
                keyboardType:TextInputType.emailAddress,
                decoration:const InputDecoration(
                  labelText:'Email address',border:OutlineInputBorder()),
                validator:(v){
                  final email=(v??'').trim();
                  if(!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                      .hasMatch(email))return 'Enter a valid email';
                  return null;
                }),
              const SizedBox(height:10),
              TextFormField(
                key:const Key('staff-password'),
                controller:_password,
                obscureText:!_showPassword,
                enableSuggestions:false,
                autocorrect:false,
                decoration:InputDecoration(
                  labelText:'Initial password',
                  helperText:'12–128 characters; include letters and numbers',
                  border:const OutlineInputBorder(),
                  suffixIcon:IconButton(
                    tooltip:_showPassword?'Hide passwords':'Show passwords',
                    onPressed:()=>setState(()=>_showPassword=!_showPassword),
                    icon:Icon(_showPassword
                      ? Icons.visibility_off_outlined:Icons.visibility_outlined)),
                ),
                validator:(value){
                  final password=value??'';
                  if(password.length<12 || password.length>128 ||
                     password!=password.trim() ||
                     !RegExp(r'[A-Za-z]').hasMatch(password) ||
                     !RegExp(r'[0-9]').hasMatch(password)) {
                    return 'Use 12–128 characters with letters and numbers';
                  }
                  return null;
                }),
              const SizedBox(height:10),
              TextFormField(
                key:const Key('staff-confirm-password'),
                controller:_confirmPassword,
                obscureText:!_showPassword,
                enableSuggestions:false,
                autocorrect:false,
                decoration:const InputDecoration(
                  labelText:'Confirm initial password',
                  border:OutlineInputBorder()),
                validator:(value)=>value!=_password.text
                  ? 'Passwords do not match':null),
              const SizedBox(height:10),
              DropdownButtonFormField<String>(
                key:const Key('staff-role'),
                value:_role,
                isExpanded:true,
                decoration:const InputDecoration(
                  labelText:'User role',border:OutlineInputBorder()),
                items:[
                  for(final r in roles.entries)
                    DropdownMenuItem(value:r.key,child:Text(r.value)),
                ],
                onChanged:_creating?null:(role){
                  if(role!=null)setState(()=>_role=role);
                }),
              const SizedBox(height:10),
              DropdownButtonFormField<String>(
                key:const Key('staff-campus'),
                value:_campusId,
                isExpanded:true,
                decoration:const InputDecoration(
                  labelText:'Assigned campus',border:OutlineInputBorder()),
                items:[
                  for(final campus in widget.owner.campuses)
                    DropdownMenuItem(value:campus.id,
                      child:Text(campus.name)),
                ],
                onChanged:_creating?null:(campus){
                  if(campus!=null)setState(()=>_campusId=campus);
                }),
              const SizedBox(height:12),
              FilledButton.icon(
                key:const Key('staff-create-account'),
                onPressed:_creating?null:_createAccount,
                icon:const Icon(Icons.person_add_alt_1_outlined),
                label:Text(_creating?'Creating account...':'Create account')),
            ],
          )),
        )),
        const SizedBox(height:12),
        Card(child:Padding(padding:const EdgeInsets.all(14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('School users',style:theme.textTheme.titleLarge),
            const SizedBox(height:8),
            TextField(
              key:const Key('staff-search'),
              controller:_search,
              onChanged:(_)=>setState((){}),
              decoration:const InputDecoration(
                labelText:'Search name, email, role or campus',
                prefixIcon:Icon(Icons.search),
                border:OutlineInputBorder()),
            ),
            if(_loading) const Padding(
              padding:EdgeInsets.only(top:8),
              child:LinearProgressIndicator()),
            if(_error!=null) Padding(
              padding:const EdgeInsets.only(top:10),
              child:Text(_error!,
                style:TextStyle(color:theme.colorScheme.error))),
            const SizedBox(height:10),
            Text('${matches.length} of ${_staff.length} user roles',
              key:const Key('staff-count')),
            if(!_loading && matches.isEmpty)
              const ListTile(title:Text('No users match this view'))
            else
              for(final user in matches)
                Card.outlined(child:ListTile(
                  key:Key('staff-entry-${user.roleId}'),
                  leading:Icon(user.active
                    ? Icons.verified_user_outlined:Icons.person_off_outlined),
                  title:Text(user.name),
                  subtitle:Text('${user.email}\n'
                    '${roles[user.role]??user.role} • ${user.campusName}\n'
                    '${user.emailConfirmed?'Email verified':'Email not verified'} '
                    '• ${user.active?'Active':'Inactive'}'),
                  isThreeLine:true,
                  trailing:user.role=='owner'||user.role=='super_admin'
                     ? const Icon(Icons.lock_outline)
                     : Row(mainAxisSize:MainAxisSize.min,children:[
                       IconButton(
                         key:Key('staff-permissions-${user.roleId}'),
                         tooltip:'Configure account permissions',
                         onPressed:()=>showStaffPermissionsDialog(
                           context,user,widget.repository),
                         icon:const Icon(Icons.tune_outlined)),
                       TextButton(
                         key:Key('staff-toggle-${user.roleId}'),
                         onPressed:_changing==null?()=>_changeStatus(user):null,
                         child:Text(user.active?'Deactivate':'Reactivate')),
                     ]),
                )),
          ]),
        )),
      ],
    );
  }
}
