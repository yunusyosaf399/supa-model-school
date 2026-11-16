import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/owner/presentation/owner_control_panel_page.dart';

void main() {
  const owner = OwnerAccess(
    userId: 'sample-owner',
    displayName: 'Sample Owner',
    schoolId: 'sample-school',
    schoolName: 'Supa Model School',
    campuses: [OwnerCampus(id: 'main', name: 'Main Campus (Setup Pending)')],
  );

  testWidgets('Owner Control Panel displays setup-pending fields', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OwnerControlPanelPage(
          owner: owner,
          onChangePassword: (a, b) async {},
          onPasswordChanged: () {},
          onSaveSetup: (request) async => owner,
          onSetupSaved: (_) {},
        ),
      ),
    ));
    expect(find.byKey(const Key('owner-control-panel')), findsOneWidget);
    expect(find.text('Not configured (XXX)'), findsOneWidget);
    expect(find.text('Not configured (Etc/UTC)'), findsOneWidget);
    expect(find.text('Main Campus (Setup Pending)'), findsOneWidget);
  });

  testWidgets('Password form validates and forces sign in after success',
      (tester) async {
    var calls = 0;
    var signedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OwnerControlPanelPage(
          owner: const OwnerAccess(
            userId: 'sample-owner', displayName: 'Sample Owner',
            schoolId: 'sample-school', schoolName: 'Supa Model School',
            setupComplete: true,
            campuses: [OwnerCampus(id: 'main', name: 'Main Campus')],
          ),
          onSaveSetup: (request) async => owner,
          onSetupSaved: (_) {},
          onChangePassword: (current, next) async {
            expect(current, 'old-pass-12345');
            expect(next, 'a-longer-new-password-2026!');
            calls++;
          },
          onPasswordChanged: () => signedOut = true,
        ),
      ),
    ));
    await tester.ensureVisible(find.byKey(const Key('owner-change-password')));
    await tester.tap(find.byKey(const Key('owner-change-password')));
    await tester.pump();
    expect(calls, 0);

    await tester.enterText(
      find.byKey(const Key('owner-current-password')),
      'old-pass-12345',
    );
    await tester.enterText(
      find.byKey(const Key('owner-new-password')),
      'a-longer-new-password-2026!',
    );
    await tester.enterText(
      find.byKey(const Key('owner-confirm-password')),
      'a-longer-new-password-2026!',
    );
    await tester.ensureVisible(find.byKey(const Key('owner-change-password')));
    await tester.tap(find.byKey(const Key('owner-change-password')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(signedOut, isTrue);
  });
}
