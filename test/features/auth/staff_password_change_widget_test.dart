import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/account_password_gateway.dart';
import 'package:supa_model_school/features/auth/data/staff_auth_gateway.dart';
import 'package:supa_model_school/features/auth/presentation/staff_account_home.dart';
import 'package:supa_model_school/features/auth/presentation/account_password_page.dart';

class FakePasswordGateway implements AccountPasswordGateway {
  String? current;
  String? next;
  int count=0;
  @override
  Future<void> changePassword(String old,String nextPassword) async {
    count++;
    current=old;
    next=nextPassword;
  }
}

void main(){
  testWidgets('all staff roles have account password change without Owner navigation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300,1000));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final passwords=FakePasswordGateway();
    var signedOut=false;
    await tester.pumpWidget(MaterialApp(home:StaffAccountHome(
      staff:const SchoolStaffAccess(
        userId:'teacher-test',displayName:'TEST Teacher',
        schoolId:'school-test',schoolName:'Supa Model School',
        campusId:'campus-test',campusName:'Main Campus',
        role:'teacher'),
      passwordGateway:passwords,
      onSignOut:() async {signedOut=true;},
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-account-home')),findsOneWidget);
    expect(find.byKey(const Key('account-password-page')),findsOneWidget);
    expect(find.text('Main Campus'),findsWidgets);
    await tester.enterText(
      find.byKey(const Key('account-current-password')),'OldPass12345!');
    await tester.enterText(
      find.byKey(const Key('account-new-password')),'BrandNewPass12345!');
    await tester.enterText(
      find.byKey(const Key('account-confirm-password')),'BrandNewPass12345!');
    final save=find.byKey(const Key('account-change-password'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(passwords.count,1);
    expect(passwords.current,'OldPass12345!');
    expect(passwords.next,'BrandNewPass12345!');
    expect(signedOut,true);
  });

  testWidgets('password mismatch fails before calling Auth',(tester) async{
    final passwords=FakePasswordGateway();
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:AccountPasswordPage(gateway:passwords,
        onPasswordChanged:() async {}))));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-current-password')),'OldPass12345!');
    await tester.enterText(
      find.byKey(const Key('account-new-password')),'BrandNewPass12345!');
    await tester.enterText(
      find.byKey(const Key('account-confirm-password')),'DifferentPass123!');
    await tester.tap(find.byKey(const Key('account-change-password')));
    await tester.pumpAndSettle();
    expect(passwords.count,0);
    expect(find.text('Passwords do not match'),findsOneWidget);
  });
}
