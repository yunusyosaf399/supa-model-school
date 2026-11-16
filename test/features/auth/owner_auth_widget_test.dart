import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

class FakeOwnerAuth implements OwnerAuthGateway {
  FakeOwnerAuth({this.allow = true});
  final bool allow;
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
    return const OwnerAccess(
      userId: 'fictional-auth-id',
      displayName: 'Test School Owner',
      schoolId: 'fictional-school-id',
      schoolName: 'Fictional School',
      campuses: [
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

    expect(find.textContaining('Verified Owner'), findsOneWidget);
    expect(find.byKey(const Key('owner-campus-selector')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
    expect(find.textContaining('Dashboard figures are still fictional'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, isTrue);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
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
