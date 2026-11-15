#!/usr/bin/env python3
"""Static UI integration guardrails; NOT a Flutter compiler or RLS test."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
model = (root / "lib/features/students/models/student_directory.dart").read_text()
page = (root / "lib/features/students/presentation/student_directory_page.dart").read_text()
shell = (root / "lib/main.dart").read_text()
unit = (root / "test/features/students/student_directory_model_test.dart").read_text()
widget = (root / "test/features/students/student_directory_widget_test.dart").read_text()

for enum_name in ("active", "inactive", "withdrawn", "graduated"):
    assert "StudentStatus." + enum_name in model, "Status missing: " + enum_name
assert "authorizedCampusIds.contains(student.campusId)" in model
assert "StudentDirectoryDemo.projection" in page
assert "DEMO MODE" in page
assert "No school database" in page
assert "Profile (preview)" in page
assert "DataTable(" in page and "_mobileCard(" in page
assert "constraints.maxWidth >= 850" in page
assert "Search name or registration number" in page
assert "Clear filters" in page
assert "onNewAdmission" in page and "AdmissionWizardPage()" in shell
assert "StudentDirectoryPage(" in shell
assert "testWidgets(" in widget and "test(" in unit
assert "unauthorized campus" in unit.lower() or "forbidden" in unit.lower()

for forbidden in ("supabase.from(", "http.post(", "service_role", "SUPABASE_DB_URL"):
    assert forbidden not in page, "Unexpected remote/secret operation: " + forbidden

print("STATIC PASS: scoped sample directory, search, statuses, profile shell, responsive layouts.")
print("NOT VERIFIED: Flutter analyze/test, real RLS isolation, backend pagination or sync.")
