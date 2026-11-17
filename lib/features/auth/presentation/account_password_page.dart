import 'package:flutter/material.dart';
import '../data/account_password_gateway.dart';

/// Used by verified Principal and other staff accounts. No password is
/// persisted; both controllers are cleared before returning after success.
class AccountPasswordPage extends StatefulWidget {
  const AccountPasswordPage({
    super.key,
    required this.gateway,
    required this.onPasswordChanged,
  });
  final AccountPasswordGateway gateway;
  final Future<void> Function() onPasswordChanged;

  @override
  State<AccountPasswordPage> createState()=>_AccountPasswordPageState();
}

class _AccountPasswordPageState extends State<AccountPasswordPage> {
  final _form=GlobalKey<FormState>();
  final _old=TextEditingController();
  final _new=TextEditingController();
  final _confirm=TextEditingController();
  bool _busy=false;
  bool _visible=false;
  String? _error;

  @override
  void dispose(){
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if(_busy||!_form.currentState!.validate())return;
    setState((){_busy=true;_error=null;});
    try{
      await widget.gateway.changePassword(_old.text,_new.text);
      if(!mounted)return;
      _old.clear();
      _new.clear();
      _confirm.clear();
      await widget.onPasswordChanged();
    }catch(_){
      if(!mounted)return;
      setState(()=>_error='Password was not changed. Check the current '
        'password, password strength and your account session.');
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  @override
  Widget build(BuildContext context)=>ListView(
    key:const Key('account-password-page'),
    padding:const EdgeInsets.all(20),
    children:[
      Text('Account & Security',
        style:Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height:8),
      const Text('Change the initial password given by the school Owner. '
        'You must enter your current password. After a successful change, '
        'sign in again using the new password.'),
      const SizedBox(height:16),
      Card(child:Padding(
        padding:const EdgeInsets.all(18),
        child:Form(key:_form,child:Column(
          crossAxisAlignment:CrossAxisAlignment.stretch,
          children:[
            TextFormField(
              key:const Key('account-current-password'),
              controller:_old,
              obscureText:!_visible,
              enableSuggestions:false,
              autocorrect:false,
              decoration:const InputDecoration(
                labelText:'Current password',
                border:OutlineInputBorder()),
              validator:(v)=>v==null||v.isEmpty
                ? 'Enter current password':null),
            const SizedBox(height:12),
            TextFormField(
              key:const Key('account-new-password'),
              controller:_new,
              obscureText:!_visible,
              enableSuggestions:false,
              autocorrect:false,
              decoration:const InputDecoration(
                labelText:'New password',
                helperText:'12–128 characters, include letters and numbers',
                border:OutlineInputBorder()),
              validator:(v){
                final pass=v??'';
                if(pass.length<12||pass.length>128||
                   !RegExp(r'[A-Za-z]').hasMatch(pass)||
                   !RegExp(r'[0-9]').hasMatch(pass)) {
                  return 'Use 12–128 characters with letters and numbers';
                }
                if(pass==_old.text)return 'Choose a different password';
                return null;
              }),
            const SizedBox(height:12),
            TextFormField(
              key:const Key('account-confirm-password'),
              controller:_confirm,
              obscureText:!_visible,
              enableSuggestions:false,
              autocorrect:false,
              decoration:const InputDecoration(
                labelText:'Confirm new password',
                border:OutlineInputBorder()),
              validator:(v)=>v!=_new.text
                ? 'Passwords do not match':null),
            CheckboxListTile(
              contentPadding:EdgeInsets.zero,
              title:const Text('Show passwords'),
              value:_visible,
              onChanged:(v)=>setState(()=>_visible=v??false)),
            if(_error!=null) Padding(
              padding:const EdgeInsets.only(bottom:10),
              child:Text(_error!,
                style:TextStyle(color:Theme.of(context).colorScheme.error))),
            FilledButton.icon(
              key:const Key('account-change-password'),
              onPressed:_busy?null:_submit,
              icon:const Icon(Icons.lock_reset),
              label:Text(_busy?'Changing...':'Change Password')),
          ],
        )),
      )),
    ],
  );
}
