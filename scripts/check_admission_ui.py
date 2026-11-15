#!/usr/bin/env python3
"""Static guardrails for admission wizard sources. NOT a Flutter compiler."""
from pathlib import Path

base = Path(__file__).resolve().parent.parent
model = (base / "lib/features/admissions/models/admission_draft.dart").read_text()
page = (base / "lib/features/admissions/presentation/admission_wizard_page.dart").read_text()
shell = (base / "lib/main.dart").read_text()
test_model = (base / "test/features/admissions/admission_draft_test.dart").read_text()
test_widget = (base / "test/features/admissions/admission_wizard_widget_test.dart").read_text()
stages = ("student", "guardians", "academic", "documents", "fees", "review")
for stage in stages:
    assert "AdmissionStep." + stage in model
assert "AdmissionWizardPage()" in shell
assert "New admission (preview)" in shell
assert "No information is saved" in page
assert "Submit unavailable" in page
assert "onPressed: null" in page
assert "validateStep" in page
assert "showDatePicker(" in page
assert "ChoiceChip(" in page
assert "width >= 850" in page
assert "_confirmExit()" in page
assert "find.byKey" in test_widget and "testWidgets" in test_widget
assert "test(" in test_model
for forbidden in ("supabase.from(", "auth.signInWithPassword(", "http.post(", "service_role"):
    assert forbidden not in page, "Unexpected network/auth operation: " + forbidden
print("STATIC PASS: six stages, preview-only guardrails, validation, navigation and tests.")
print("NOT VERIFIED: Flutter compilation, widget test execution, platform layout or backend integration.")
