#!/usr/bin/env bash
set -euo pipefail

: "${PGURL:?Set PGURL to an isolated PostgreSQL URL, never hosted credentials}"

case "$PGURL" in
  *"127.0.0.1:54322/"*|*"localhost:54322/"*) ;;
  *) echo >&2 "SECURITY: PGURL must point to local Supabase on port 54322"; exit 2 ;;
esac

echo "== Static source checks =="
for checker in \
  supabase/tests/check_db05_payroll.py \
  supabase/tests/check_db06_finance.py \
  supabase/tests/check_db07_business.py \
  supabase/tests/check_db08_schema.py \
  supabase/tests/check_db09_schema.py
do
  if [[ -f "$checker" ]]; then python3 "$checker"; fi
done

echo "== Baseline schema sanity =="
psql "$PGURL" -X -v ON_ERROR_STOP=1 -qAt -c "select count(*) from public.schools" >/dev/null
psql "$PGURL" -X -v ON_ERROR_STOP=1 -qAt -c "select count(*) from public.student_enrollments" >/dev/null

echo "== Apply DB03–DB09 sequentially to local test database ONLY =="
for name in \
  DB03_FEES_BILLING_SCHEMA.sql \
  DB04_ATTENDANCE_SCHEMA.sql \
  DB05_EMPLOYEES_PAYROLL_SCHEMA.sql \
  DB06_FINANCE_CASHBOOK_SCHEMA.sql \
  DB07_INVENTORY_CANTEEN_UNIFORM_TRANSPORT_SCHEMA.sql \
  DB08_APPROVALS_PERMISSIONS_AUDIT_SCHEMA.sql \
  DB09_SYNC_BACKUP_REPORTING_SCHEMA.sql
do
  echo "Running $name"
  psql "$PGURL" -X -v ON_ERROR_STOP=1 -q -f "supabase/drafts/$name"
done

echo "== Confirm all 7 schema domains and RLS =="
psql "$PGURL" -X -v ON_ERROR_STOP=1 <<'SQL'
DO $verify$
DECLARE
  expected_names text[] := ARRAY[
    'fee_charges','student_attendance_marks','employees','ledger_journals',
    'inventory_stock_movements','db08_approval_decisions','db09_cloud_changes'
  ];
  rel text;
  has_rls boolean;
BEGIN
  FOREACH rel IN ARRAY expected_names LOOP
    SELECT c.relrowsecurity INTO has_rls
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname=rel;
    IF has_rls IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Schema missing table or RLS: %',rel;
    END IF;
  END LOOP;
END;
$verify$;
SQL

echo "PASS: all seven domain DDL scripts applied and RLS smoke checks passed on isolated local database"
