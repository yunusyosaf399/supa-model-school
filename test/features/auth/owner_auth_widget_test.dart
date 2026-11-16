import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

class FakeOwnerAuth implements OwnerAuthGateway {
  FakeOwnerAuth({this.allow = true, this.setupComplete = true});
  final bool allow;
  final bool setupComplete;
  bool signedOut = false;

  @override
  bool get configured => true;

  @override
  Future<OwnerAccess?> restore() async => null;

  @override
  Future<OwnerAccess> signIn(String email, String password) async {
    if (!allow || email != 'owner@example.test' || password != 'valid-passphrase') {
      throw StateError('Denied');
    }
    return OwnerAccess(
      userId: 'fictional-auth-id',
      setupComplete: setupComplete,
      displayName: 'Test School Owner',
      schoolId: 'fictional-school-id',
      schoolName: 'Fictional School',
      campuses: const [
        OwnerCampus(id: 'campus-1', name: 'Main Campus'),
      ],
    );
  }

  @override
  Future<void> signOut() async { signedOut = true; }

  @override
  Future<void> sendRecovery(String email) async =>
      throw StateError('Recovery not configured');

  @override
  Future<OwnerAccess> completeInitialSetup(OwnerInitialSetupRequest request) async =>
      throw StateError('Not implemented in fake');

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    if (currentPassword != 'valid-passphrase' || newPassword.length < 12) {
      throw StateError('Denied');
    }
    signedOut = true;
  }
}

void main() {
  testWidgets('fake verified Owner enters protected shell', (tester) async {
    final auth = FakeOwnerAuth();
    await tester.pumpWidget(SupaModelSchoolApp(authGateway: auth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-page')), findsNothing);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('login-email')), 'owner@example.test');
    await tester.enterText(
        find.byKey(const Key('login-password')), 'valid-passphrase');
    await tester.tap(find.byKey(const Key('login-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner-campus-selector')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-demo-banner')), findsOneWidget);
    // Demo figures are disclosed in a compact badge, without disturbing
    // the reference dashboard card positions.
    expect(find.text('TEST DATA'), findsOneWidget);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, isTrue);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
  });

  testWidgets('pending Owner is directed to the school setup form',
      (tester) async {
    final auth = FakeOwnerAuth(setupComplete: false);
    await tester.pumpWidget(SupaModelSchoolApp(authGateway: auth));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('login-email')), 'owner@example.test');
    await tester.enterText(
        find.byKey(const Key('login-password')), 'valid-passphrase');
    await tester.tap(find.byKey(const Key('login-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner-control-panel')), findsOneWidget);
    expect(find.text('Owner Control Panel'), findsOneWidget);
  });

  testWidgets('failed Owner authorization keeps login visible', (tester) async {
    await tester.pumpWidget(SupaModelSchoolApp(
      authGateway: FakeOwnerAuth(allow: false),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('login-email')), 'owner@example.test');
    await tester.enterText(
        find.byKey(const Key('login-password')), 'valid-passphrase');
    await tester.tap(find.byKey(const Key('login-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-page')), findsNothing);
    expect(find.textContaining('Sign-in failed'), findsOneWidget);
  });
}
