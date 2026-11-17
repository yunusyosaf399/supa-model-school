import 'package:supabase_flutter/supabase_flutter.dart';

/// Password change for any authenticated, authorized account; the password
/// is used only for Supabase Auth updateUser and is never persisted by the app.
abstract class AccountPasswordGateway {
  const AccountPasswordGateway();
  Future<void> changePassword(String currentPassword,String newPassword);
}

class SupabaseAccountPasswordGateway implements AccountPasswordGateway {
  const SupabaseAccountPasswordGateway(this.client);
  final SupabaseClient client;

  @override
  Future<void> changePassword(String currentPassword,String newPassword) async {
    if(currentPassword.isEmpty||newPassword.length<12||
        newPassword.length>128||newPassword==currentPassword||
        !RegExp(r'[A-Za-z]').hasMatch(newPassword)||
        !RegExp(r'[0-9]').hasMatch(newPassword)) {
      throw const FormatException('Choose a new strong password of 12+ characters');
    }
    final session=client.auth.currentSession;
    final identity=await client.auth.getUser();
    if(session==null||identity.user==null) {
      throw StateError('Please sign in before changing your password');
    }
    final changed=await client.auth.updateUser(UserAttributes(
      password:newPassword,
      currentPassword:currentPassword,
    ));
    if(changed.user?.id!=identity.user!.id) {
      throw StateError('Password update was not confirmed');
    }
    await client.auth.signOut();
  }
}
