import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';

void main() {
  testWidgets('login validates fields without pretending to authenticate',
      (tester) async {
    await tester.pumpWidget(const SupaModelSchoolApp());
    await tester.tap(find.byKey(const Key('login-sign-in')));
    await tester.pump();
    expect(find.text('Enter your email or username'), findsWidgets);
    expect(find.byKey(const Key('dashboard-page')), findsNothing);
  });

  testWidgets('theme menu offers light dark system on login', (tester) async {
    await tester.pumpWidget(const SupaModelSchoolApp());
    await tester.tap(find.byTooltip('Change appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Light theme'), findsOneWidget);
    expect(find.text('Dark theme'), findsOneWidget);
    expect(find.text('System theme'), findsOneWidget);
    await tester.tap(find.text('Dark theme'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-email')), findsOneWidget);
  });

  testWidgets('demo navigation reuses student directory', (tester) async {
    await tester.pumpWidget(const SupaModelSchoolApp());
    await tester.tap(find.byKey(const Key('open-demo-dashboard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Students').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('student-directory')), findsOneWidget);
  });
}
