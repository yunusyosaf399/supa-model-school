import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/config/supabase_connection_config.dart';
import 'package:supa_model_school/features/auth/presentation/login_page.dart';

void main() {
  test('debug build uses the public Supabase test project', () {
    if (kDebugMode) {
      expect(SupabaseConnectionConfig.isConfigured, isTrue);
      expect(SupabaseConnectionConfig.projectUrl,
          'https://uebzvfzpbqqttbqyxxos.supabase.co');
      expect(SupabaseConnectionConfig.publishableKey,
          startsWith('sb_publishable_'));
      expect(() => SupabaseConnectionConfig.validate(), returnsNormally);
    }
  });

  testWidgets('login explains campus is selected after authentication',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1250, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LoginPage(
      themeMode: ThemeMode.light,
      onThemeChanged: (_) {},
      onOpenDemo: () {},
      onSignIn: (email, password) async {},
      onRecoverPassword: (email) async {},
      authConfigured: true,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-campus')), findsOneWidget);
    expect(find.text('Campus selected securely after sign-in'), findsOneWidget);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);
    expect(find.byKey(const Key('login-sign-in')), findsOneWidget);
  });
}
