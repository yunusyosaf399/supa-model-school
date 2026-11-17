import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/presentation/login_page.dart';

Widget _screen() => MaterialApp(
      home: LoginPage(
        themeMode: ThemeMode.light,
        onThemeChanged: (_) {},
        onOpenDemo: () {},
        authConfigured: true,
        onSignIn: (_, __) async {},
        onRecoverPassword: (_) async {},
      ),
    );

void main() {
  testWidgets('Android portrait uses the uploaded mobile art and overlay card',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 850));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_screen());
    expect(find.byKey(const Key('login-mobile-background')), findsOneWidget);
    expect(find.byKey(const Key('login-desktop-background')), findsNothing);
    expect(find.byKey(const Key('login-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('login-form-card')), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);
    expect(find.byKey(const Key('login-sign-in')), findsOneWidget);
    expect(find.text('Campus selected securely after sign-in'), findsOneWidget);
  });

  testWidgets('Windows landscape uses the desktop art and right-side card',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1536, 864));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_screen());
    expect(find.byKey(const Key('login-desktop-background')), findsOneWidget);
    expect(find.byKey(const Key('login-mobile-background')), findsNothing);
    expect(find.byKey(const Key('login-desktop-layout')), findsOneWidget);
    expect(find.text('Sign In to Supa Model School'), findsOneWidget);
    expect(find.byKey(const Key('login-form-card')), findsOneWidget);
    expect(find.byTooltip('Change appearance'), findsOneWidget);

    final card = tester.getRect(find.byKey(const Key('login-form-card')));
    expect(card.left, greaterThan(900));
    // Card must be below both top-right theme and preview icon controls.
    expect(card.top, greaterThanOrEqualTo(90));
    expect(card.width, lessThanOrEqualTo(470));
    expect(card.right, lessThanOrEqualTo(1536));
    expect(card.bottom, lessThan(864));
  });

  testWidgets('Campus is not guessed before sign-in; password is maskable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 850));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_screen());
    expect(find.text('Sample Campus A (demo)'), findsNothing);
    expect(find.byKey(const Key('login-campus')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('toggle-password')));
    await tester.tap(find.byKey(const Key('toggle-password')));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });
}
