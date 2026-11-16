import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';

void main() {
  testWidgets('default startup is login and never grants automatic access',
      (tester) async {
    await tester.pumpWidget(const SupaModelSchoolApp());
    expect(find.text('Supa Model School'), findsOneWidget);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-page')), findsNothing);
    await tester.tap(find.byKey(const Key('open-demo-dashboard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
    expect(find.textContaining('DEMO PREVIEW'), findsOneWidget);
  });
}
