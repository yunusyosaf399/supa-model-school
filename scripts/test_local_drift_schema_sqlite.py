#!/usr/bin/env python3
"""Run the actual .drift DDL through Python's SQLite engine.

This tests SQLite constraints only. It does NOT compile Dart/Drift, verify
Supabase RLS, encrypt the DB, or implement cloud synchronization.
Uses a throwaway in-memory SQLite connection and fictional fixture data.
"""
from pathlib import Path
import sqlite3

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "lib/offline/schema/campus_cache.drift"
OUTBOX_SQL = ROOT / "lib/offline/schema/operation_outbox.drift"

def must_fail(cursor, statement, args=()):
    try:
        cursor.execute(statement, args)
    except sqlite3.IntegrityError:
        return
    raise AssertionError(f"Expected SQLite constraint to reject: {statement}")

def main():
    assert SQL.is_file(), f"Missing schema: {SQL}"
    assert OUTBOX_SQL.is_file(), f"Missing schema: {OUTBOX_SQL}"
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys = ON")
    assert db.execute("PRAGMA foreign_keys").fetchone()[0] == 1
    db.executescript(SQL.read_text(encoding="utf-8"))
    db.executescript(OUTBOX_SQL.read_text(encoding="utf-8"))
    c = db.cursor()
    tables = {row[0] for row in c.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    expected = {
      "local_campus_binding", "local_academic_years", "local_classes",
      "local_sections", "local_students", "local_guardians",
      "local_student_guardians", "local_enrollments", "local_admissions",
      "local_admission_documents", "local_replica_metadata",
      "local_outbox_operations", "local_outbox_events",
    }
    assert expected == tables, f"Unexpected tables {expected ^ tables}"
    assert all(c.execute("PRAGMA foreign_key_list(" + name + ")").fetchall()
               for name in expected if name != "local_campus_binding")

    # An offline DB can pin exactly one campus and device.
    c.execute("INSERT INTO local_campus_binding VALUES (1, 'schoolA', 'campusA', 'device1', 1)")
    must_fail(c, "INSERT INTO local_campus_binding VALUES (2, 'schoolA', 'campusB', 'device2', 1)")
    must_fail(c, "INSERT INTO local_campus_binding VALUES (1, 'schoolB', 'campusB', 'device2', 1)")
    c.execute("INSERT INTO local_replica_metadata(singleton,school_id,campus_id)"
              " VALUES (1,'schoolA','campusA')")
    must_fail(c, "INSERT INTO local_replica_metadata(singleton,school_id,campus_id)"
                 " VALUES (2,'schoolA','campusA')")
    must_fail(c, "INSERT INTO local_replica_metadata(singleton,school_id,campus_id)"
                 " VALUES (1,'schoolA','campusB')")

    # Academic and class structure cannot refer to another campus.
    c.execute("INSERT INTO local_academic_years"
              "(id,school_id,campus_id,label,starts_on,ends_on,is_active)"
              " VALUES ('yearA','schoolA','campusA','2026-27','2026-04-01','2027-03-31',1)")
    must_fail(c, "INSERT INTO local_academic_years"
                 "(id,school_id,campus_id,label,starts_on,ends_on,is_active)"
                 " VALUES ('yearB','schoolA','campusB','2026-27','2026-04-01','2027-03-31',1)")
    c.execute("INSERT INTO local_classes"
              "(id,school_id,campus_id,academic_year_id,name)"
              " VALUES ('classA','schoolA','campusA','yearA','Grade 1')")
    must_fail(c, "INSERT INTO local_classes"
                 "(id,school_id,campus_id,academic_year_id,name)"
                 " VALUES ('classB','schoolA','campusB','yearA','Grade 1')")
    c.execute("INSERT INTO local_sections"
              "(id,school_id,campus_id,class_id,name)"
              " VALUES ('sectionA','schoolA','campusA','classA','A')")

    c.execute("INSERT INTO local_students"
              "(id,school_id,campus_id,registration_no,full_name,updated_at_ms)"
              " VALUES ('studentA','schoolA','campusA','REG-001','Example Child',1)")
    must_fail(c, "INSERT INTO local_students"
                 "(id,school_id,campus_id,registration_no,full_name,updated_at_ms)"
                 " VALUES ('studentB','schoolA','campusA','reg-001','Other Child',1)")
    must_fail(c, "INSERT INTO local_students"
                 "(id,school_id,campus_id,registration_no,full_name,updated_at_ms)"
                 " VALUES ('studentB','schoolA','campusB','REG-002','Other Child',1)")
    must_fail(c, "INSERT INTO local_students"
                 "(id,school_id,campus_id,registration_no,full_name,status,updated_at_ms)"
                 " VALUES ('studentB','schoolA','campusA','REG-002','Other Child','unknown',1)")

    c.execute("INSERT INTO local_guardians"
              "(id,school_id,campus_id,full_name,updated_at_ms)"
              " VALUES ('guardianA','schoolA','campusA','Example Guardian',1)")
    c.execute("INSERT INTO local_student_guardians"
              "(student_id,guardian_id,school_id,campus_id,relationship,is_primary)"
              " VALUES ('studentA','guardianA','schoolA','campusA','father',1)")
    must_fail(c, "INSERT INTO local_student_guardians"
                 "(student_id,guardian_id,school_id,campus_id,relationship,is_primary)"
                 " VALUES ('studentA','guardianA','schoolA','campusB','father',1)")

    c.execute("INSERT INTO local_enrollments"
              "(id,student_id,school_id,campus_id,academic_year_id,class_id,"
              "section_id,admitted_on)"
              " VALUES ('enrollA','studentA','schoolA','campusA','yearA','classA',"
              "'sectionA','2026-04-01')")
    must_fail(c, "INSERT INTO local_enrollments"
                 "(id,student_id,school_id,campus_id,academic_year_id,class_id,admitted_on)"
                 " VALUES ('enrollB','studentA','schoolA','campusA','yearA','classA','2026-04-02')")

    c.execute("INSERT INTO local_admissions"
              "(id,school_id,campus_id,academic_year_id,applicant_name,"
              "documents_state,admission_status,updated_at_ms)"
              " VALUES ('appA','schoolA','campusA','yearA','Example Child',"
              "'incomplete','draft',1)")
    must_fail(c, "INSERT INTO local_admissions"
                 "(id,school_id,campus_id,academic_year_id,applicant_name,"
                 "documents_state,updated_at_ms)"
                 " VALUES ('appB','schoolA','campusA','yearA','Example Child','conditional',1)")
    must_fail(c, "INSERT INTO local_admission_documents"
                 "(id,school_id,campus_id,application_id,document_kind,is_required,is_applicable)"
                 " VALUES ('docB','schoolA','campusB','appA','birth_certificate',1,1)")
    c.execute("INSERT INTO local_admission_documents"
              "(id,school_id,campus_id,application_id,document_kind,is_required,is_applicable)"
              " VALUES ('docA','schoolA','campusA','appA','birth_certificate',1,1)")
    must_fail(c, "INSERT INTO local_admission_documents"
                 "(id,school_id,campus_id,application_id,document_kind,is_required,is_applicable)"
                 " VALUES ('docDup','schoolA','campusA','appA','birth_certificate',1,1)")
    must_fail(c, "UPDATE local_campus_binding SET campus_id = 'campusB' WHERE singleton = 1")
    assert db.execute("PRAGMA foreign_key_check").fetchall() == []

    # Outbox rows are permitted only for an existing bound campus and draft.
    op = "11111111-1111-4111-8111-111111111111"
    c.execute(
        "INSERT INTO local_outbox_operations("
        "operation_id,school_id,campus_id,aggregate_type,aggregate_id,"
        "operation_type,payload_json,local_revision,created_at_ms,updated_at_ms)"
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (op,"schoolA","campusA","admission","appA",
         "admission.save_draft",'{"action":"draft"}',1,2,2))
    must_fail(c, "INSERT INTO local_outbox_operations("
        "operation_id,school_id,campus_id,aggregate_type,aggregate_id,"
        "operation_type,payload_json,local_revision,created_at_ms,updated_at_ms)"
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (op,"schoolA","campusA","admission","appA",
         "admission.save_draft",'{"action":"draft"}',2,2,2))
    must_fail(c, "INSERT INTO local_outbox_operations("
        "operation_id,school_id,campus_id,aggregate_type,aggregate_id,"
        "operation_type,payload_json,local_revision,created_at_ms,updated_at_ms)"
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        ("22222222-2222-4222-8222-222222222222","schoolA","campusB",
         "admission","appA","admission.save_draft",'{}',2,2,2))
    must_fail(c, "INSERT INTO local_outbox_operations("
        "operation_id,school_id,campus_id,aggregate_type,aggregate_id,"
        "operation_type,payload_json,local_revision,created_at_ms,updated_at_ms)"
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        ("33333333-3333-4333-8333-333333333333","schoolA","campusA",
         "admission","appB","admission.save_draft",'{}',2,2,2))
    must_fail(c, "INSERT INTO local_outbox_operations("
        "operation_id,school_id,campus_id,aggregate_type,aggregate_id,"
        "operation_type,payload_json,local_revision,created_at_ms,updated_at_ms)"
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        ("44444444-4444-4444-8444-444444444444","schoolA","campusA",
         "admission","appA","admission.save_draft",'{}',1,2,2))
    must_fail(c, "UPDATE local_outbox_operations SET status='sending' "
                 "WHERE operation_id=?", (op,))
    c.execute("UPDATE local_outbox_operations "
              "SET status='sending', lease_token='TEST-LEASE',"
              "lease_until_ms=30,attempt_count=1 WHERE operation_id=?", (op,))
    must_fail(c, "UPDATE local_outbox_operations "
                 "SET status='acked',lease_token=NULL,lease_until_ms=NULL "
                 "WHERE operation_id=?", (op,))
    c.execute("UPDATE local_outbox_operations "
              "SET status='acked',lease_token=NULL,lease_until_ms=NULL,"
              "acknowledged_at_ms=31 WHERE operation_id=?", (op,))
    c.execute("INSERT INTO local_outbox_events "
              "(operation_id,school_id,campus_id,event_type,event_at_ms)"
              "VALUES (?,?,?,?,?)", (op,"schoolA","campusA","acked",31))
    must_fail(c, "INSERT INTO local_outbox_events "
                 "(operation_id,school_id,campus_id,event_type,event_at_ms)"
                 "VALUES (?,?,?,?,?)",
                 (op,"schoolA","campusB","acked",31))
    must_fail(c, "UPDATE local_outbox_operations SET payload_json='{}' "
                 "WHERE operation_id=?", (op,))
    must_fail(c, "UPDATE local_outbox_events SET event_type='queued' "
                 "WHERE operation_id=?", (op,))
    must_fail(c, "DELETE FROM local_outbox_events WHERE operation_id=?", (op,))
    must_fail(c, "DELETE FROM local_outbox_operations WHERE operation_id=?",
                 (op,))  # explicit no-delete trigger plus FK retention
    assert len(c.execute(
        "SELECT name FROM sqlite_master WHERE type='trigger' "
        "AND name LIKE 'local_outbox_%'").fetchall()) == 4
    assert c.execute("PRAGMA foreign_key_check").fetchall() == []

    db.close()
    print("PASS: actual SQLite v2 schema created; 13 tables; FK containment,
          " one-campus binding, registration/academic/enrollment/document"
          " constraints verified with fictional in-memory records.")

if __name__ == "__main__":
    main()
