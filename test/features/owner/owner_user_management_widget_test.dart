import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/owner/data/owner_user_management_repository.dart';
import 'package:supa_model_school/features/owner/presentation/owner_user_control_panel_page.dart';
import 'package:supa_model_school/features/owner/presentation/owner_control_panel_page.dart';

const owner=OwnerAccess(
  userId:'owner-1',displayName:'Owner',
  schoolId:'school-1',schoolName:'Supa Model School',
  setupComplete:true,activeYearId:'year-1',activeYearLabel:'2026-2027',
  campuses:[OwnerCampus(id:'campus-1',name:'Main Campus')],
);

class FakeStaff implements OwnerUserManagementRepository {
  bool fail=false;
  int invited=0,changes=0,lists=0;
  OwnerUserInvitation? last;
  bool active=true;
  @override
  Future<List<OwnerStaffAccount>> listUsers(String schoolId) async {
    lists++;
    if(fail) throw StateError('Denied');
    if(schoolId!='school-1')throw StateError('Wrong school');
    return [
      OwnerStaffAccount(
        roleId:'role-1',userId:'principal-1',
        name:'TEST Principal',email:'principal@example.test',
        role:'principal',campusId:'campus-1',campusName:'Main Campus',
        active:active,emailConfirmed:false),
      const OwnerStaffAccount(
        roleId:'role-owner',userId:'owner-1',name:'Owner',
        email:'owner@example.test',role:'owner',
        campusId:null,campusName:'School-wide',
        active:true,emailConfirmed:true),
    ];
  }
  @override
  Future<void> inviteUser(OwnerUserInvitation invitation) async {
    if(fail)throw StateError('Failed invite');
    last=invitation;
    invited++;
  }
  @override
  Future<void> setRoleActive(String id,bool next) async {
    if(fail)throw StateError('Denied');
    if(id!='role-1')throw StateError('Cannot edit Owner');
    changes++;
    active=next;
  }
}

Future<void> showPage(WidgetTester tester,FakeStaff repo) async {
  await tester.binding.setSurfaceSize(const Size(1400,1100));
  addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home:Scaffold(body:OwnerUserControlPanelPage(
      owner:owner,repository:repo,onBack:(){}))));
  await tester.pumpAndSettle();
}

void main(){
  testWidgets('Owner can create verified role assignment invitation',
    (tester) async {
    final repo=FakeStaff();
    await showPage(tester,repo);
    expect(find.text('TEST Principal'),findsOneWidget);
    expect(find.textContaining('Invitation pending'),findsOneWidget);
    await tester.enterText(find.byKey(const Key('staff-name')),'New Teacher');
    await tester.enterText(find.byKey(const Key('staff-email')),
      'teacher@example.test');
    await tester.tap(find.byKey(const Key('staff-send-invite')));
    await tester.pumpAndSettle();
    expect(repo.invited,0);
    await tester.tap(find.byKey(const Key('confirm-staff-invite')));
    await tester.pumpAndSettle();
    expect(repo.invited,1);
    expect(repo.last?.role,'teacher');
    expect(repo.last?.campusId,'campus-1');
    expect(repo.last?.email,'teacher@example.test');
  });

  testWidgets('Owner can deactivate Principal without deleting history',
    (tester) async {
    final repo=FakeStaff();
    await showPage(tester,repo);
    await tester.tap(find.byKey(const Key('staff-toggle-role-1')));
    await tester.pumpAndSettle();
    expect(repo.changes,0);
    await tester.tap(find.byKey(const Key('confirm-staff-status')));
    await tester.pumpAndSettle();
    expect(repo.changes,1);
    expect(repo.active,false);
    expect(find.textContaining('Inactive'),findsWidgets);
    expect(find.byKey(const Key('staff-toggle-role-owner')),findsNothing);
  });

  testWidgets('Unauthorized staff listing fails closed',(tester) async {
    final repo=FakeStaff()..fail=true;
    await showPage(tester,repo);
    expect(find.textContaining('Cannot load authorized school users'),findsOneWidget);
    expect(find.text('TEST Principal'),findsNothing);
  });

  testWidgets('Owner Settings opens user control inside same module',
    (tester) async {
    final repo=FakeStaff();
    await tester.binding.setSurfaceSize(const Size(1400,1100));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:OwnerControlPanelPage(
        owner:owner,
        userManagementRepository:repo,
        onChangePassword:(old,next) async {},
        onPasswordChanged:(){},
        onSaveSetup:(_)=>throw UnimplementedError(),
        onSetupSaved:(_){},
        onOpenAcademicStructure:(){},
      ))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner-open-user-management')),findsOneWidget);
    await tester.tap(find.byKey(const Key('owner-open-user-management')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner-user-control-panel')),findsOneWidget);
    await tester.tap(find.byKey(const Key('owner-users-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner-control-panel')),findsOneWidget);
  });
}
