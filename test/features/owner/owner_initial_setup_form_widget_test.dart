import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/owner/presentation/owner_initial_setup_form.dart';

void main() {
  const pendingOwner = OwnerAccess(
    userId: 'fixture',
    displayName: 'Test Owner',
    schoolId: 'school-fixture',
    schoolName: 'Supa Model School',
    currencyCode: 'XXX',
    timezoneName: 'Etc/UTC',
    campuses: [
      OwnerCampus(id: 'campus-fixture',
          name: 'Main Campus (Setup Pending)'),
    ],
  );

  testWidgets('setup requires the Owner to enter real values',
      (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OwnerInitialSetupForm(
            owner: pendingOwner,
            onSave: (request) async {
              saves++;
              return pendingOwner;
            },
            onSaved: (_) {},
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('setup-school-name')), findsOneWidget);
    expect(find.byKey(const Key('setup-campus-name')), findsOneWidget);
    expect(find.byKey(const Key('setup-currency')), findsOneWidget);
    expect(find.byKey(const Key('setup-timezone')), findsOneWidget);
    expect(find.byKey(const Key('setup-year-label')), findsOneWidget);
    expect(find.byKey(const Key('setup-year-start')), findsOneWidget);
    expect(find.byKey(const Key('setup-year-end')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-school-setup')));
    await tester.tap(find.byKey(const Key('save-school-setup')));
    await tester.pump();
    expect(saves, 0);
    expect(find.text('Choose a currency'), findsOneWidget);
    expect(find.text('Choose a timezone'), findsOneWidget);
    expect(find.text('Enter your campus name'), findsOneWidget);
  });
}
