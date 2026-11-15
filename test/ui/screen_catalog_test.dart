import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/ui/screen_catalog.dart';

void main() {
  test('design catalog includes all screen groups and unique destinations', () {
    expect(schoolScreenCatalog.length, 19);
    final screens = schoolScreenCatalog.values
        .expand((specs) => specs)
        .toList(growable: false);
    expect(screens.length, 120);
    for (final entry in schoolScreenCatalog.entries) {
      expect(entry.value, isNotEmpty);
      expect(entry.value.map((v) => v.title).toSet().length, entry.value.length,
          reason: 'Duplicate screen in ' + entry.key);
      for (final screen in entry.value) {
        expect(screen.title.trim(), isNotEmpty);
      }
    }
  });

  test('critical operational screens remain discoverable', () {
    expect(schoolScreenCatalog['Admissions']!
        .any((s) => s.title == 'Six-Step Admission'), isTrue);
    expect(schoolScreenCatalog['Fees']!
        .any((s) => s.title == 'Collect Fee'), isTrue);
    expect(schoolScreenCatalog['Attendance']!
        .any((s) => s.title == 'Daily Student Register'), isTrue);
    expect(schoolScreenCatalog['Finance']!
        .any((s) => s.title == 'Daily Cash Closing'), isTrue);
    expect(schoolScreenCatalog['Sync Center']!
        .any((s) => s.title == 'Conflict Review'), isTrue);
    expect(schoolScreenCatalog['Settings']!
        .any((s) => s.title == 'Keyboard Shortcuts'), isTrue);
  });

  test('future exams are not presented as pilot functionality', () {
    expect(schoolScreenCatalog['Examinations (Later)']!
        .every((screen) => screen.later), isTrue);
  });
}
