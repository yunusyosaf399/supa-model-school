import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/owner/data/owner_user_management_repository.dart';
import 'package:supa_model_school/features/owner/presentation/staff_permissions_dialog.dart';

const testStaff = OwnerStaffAccount(
  roleId: 'role-1',
  userId: 'staff-1',
  name: 'Test Principal',
  email: 'principal@example.test',
  role: 'principal',
  campusId: 'campus-1',
  campusName: 'Main Campus',
  active: true,
  emailConfirmed: true,
);

class FakePermissionRepository
    implements OwnerUserManagementRepository, OwnerPermissionRepository {
  bool allowed = false;
  bool failSave = false;
  int writes = 0;

  @override
  Future<List<StaffPermission>> permissions(String roleId) async {
    expect(roleId, 'role-1');
    // Production repositories intentionally return List.unmodifiable.
    return List<StaffPermission>.unmodifiable([
      StaffPermission(
        code: 'academic.read',
        section: 'Academics',
        title: 'View Academics',
        action: 'read',
        implemented: false,
        allowed: allowed,
      ),
    ]);
  }

  @override
  Future<void> setPermission(String roleId, String code, bool value) async {
    expect(roleId, 'role-1');
    expect(code, 'academic.read');
    if (failSave) throw StateError('server denied');
    allowed = value;
    writes++;
  }

  @override
  Future<List<OwnerStaffAccount>> listUsers(String schoolId) async => [testStaff];

  @override
  Future<void> createUser(OwnerUserCreation request) async {}

  @override
  Future<void> setRoleActive(String roleId, bool active) async {}
}

Future<void> openPermissions(
    WidgetTester tester, FakePermissionRepository repository) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1050));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () => showStaffPermissionsDialog(
            context, testStaff, repository),
          child: const Text('Configure Permissions'),
        ),
      ),
    )),
  ));
  await tester.tap(find.text('Configure Permissions'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('toggle updates after confirmed save from immutable RPC list',
      (tester) async {
    final repository = FakePermissionRepository();
    await openPermissions(tester, repository);
    final control = find.byKey(const Key('permission-academic.read'));
    expect(control, findsOneWidget);
    expect(tester.widget<SwitchListTile>(control).value, false);

    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(repository.allowed, true);
    expect(repository.writes, 1);
    expect(tester.widget<SwitchListTile>(control).value, true);
    expect(find.textContaining('Could not save this permission'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(repository.allowed, false);
    expect(repository.writes, 2);
    expect(tester.widget<SwitchListTile>(control).value, false);
    expect(find.textContaining('Could not save this permission'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('genuine RPC rejection leaves permission switched off',
      (tester) async {
    final repository = FakePermissionRepository()..failSave = true;
    await openPermissions(tester, repository);
    final control = find.byKey(const Key('permission-academic.read'));

    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(repository.writes, 0);
    expect(repository.allowed, false);
    expect(tester.widget<SwitchListTile>(control).value, false);
    expect(find.textContaining('server denied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
