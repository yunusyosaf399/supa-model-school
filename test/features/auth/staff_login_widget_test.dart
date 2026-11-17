import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/auth/data/principal_auth_gateway.dart';
import 'package:supa_model_school/features/auth/data/staff_auth_gateway.dart';
import 'package:supa_model_school/features/auth/data/account_password_gateway.dart';

class NoOwner implements OwnerAuthGateway {
  @override bool get configured=>true;
  @override Future<OwnerAccess?> restore() async=>null;
  @override Future<OwnerAccess> signIn(String email,String password) async =>
    throw StateError('No unique authorized Owner membership');
  @override Future<void> signOut() async {}
  @override Future<void> sendRecovery(String email) async {}
  @override Future<void> changePassword(String old,String next) async {}
  @override Future<OwnerAccess> completeInitialSetup(
    OwnerInitialSetupRequest request)=>throw UnimplementedError();
}
class NoPrincipal implements PrincipalAuthGateway {
  @override bool get configured=>true;
  @override Future<PrincipalAccess?> restore() async=>null;
  @override Future<PrincipalAccess> signIn(String email,String password) async=>
    throw StateError('Assigned verified Principal required');
  @override Future<void> signOut() async {}
}
class TeacherLogin implements StaffAuthGateway {
  @override bool get configured=>true;
  int logins=0;
  bool signedOut=false;
  @override Future<SchoolStaffAccess?> restore() async=>null;
  @override Future<SchoolStaffAccess> signIn(String email,String password) async {
    if(email!='teacher@example.test'||password!='TeacherPassword123!') {
      throw StateError('Invalid credentials');
    }
    logins++;
    return const SchoolStaffAccess(
      userId:'teacher-1',displayName:'TEST Teacher',
      schoolId:'school-1',schoolName:'Supa Model School',
      campusId:'campus-1',campusName:'Main Campus',role:'teacher',
    );
  }
  @override Future<void> signOut() async {signedOut=true;}
}
class FakePasswords implements AccountPasswordGateway {
  @override Future<void> changePassword(String old,String next) async {}
}

void main(){
  testWidgets('non-Principal staff gets account panel rather than Owner or Principal',
    (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300,900));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final staff=TeacherLogin();
    await tester.pumpWidget(SupaModelSchoolApp(
      authGateway:NoOwner(),
      principalAuthGateway:NoPrincipal(),
      staffAuthGateway:staff,
      accountPasswordGateway:FakePasswords(),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-email')),
      'teacher@example.test');
    await tester.enterText(find.byKey(const Key('login-password')),
      'TeacherPassword123!');
    await tester.tap(find.byKey(const Key('login-sign-in')));
    await tester.pumpAndSettle();
    expect(staff.logins,1);
    expect(find.byKey(const Key('staff-account-home')),findsOneWidget);
    expect(find.byKey(const Key('account-password-page')),findsOneWidget);
    expect(find.byKey(const Key('owner-control-panel')),findsNothing);
    expect(find.byKey(const Key('principal-approval-page')),findsNothing);
    await tester.tap(find.byKey(const Key('staff-account-sign-out')));
    await tester.pumpAndSettle();
    expect(staff.signedOut,true);
    expect(find.byKey(const Key('login-email')),findsOneWidget);
  });
}
