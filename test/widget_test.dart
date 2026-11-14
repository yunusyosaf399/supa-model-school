import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';

void main() {
  testWidgets('app displays school title and scaffold', (tester) async {
    await tester.pumpWidget(const SupaModelSchoolApp());
    expect(find.text('Supa Model School'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
  });
}
