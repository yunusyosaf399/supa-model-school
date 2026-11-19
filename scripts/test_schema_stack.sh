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

echo "== Apply/verify DB03–DB09 in isolated local test database =="
if compgen -G 'supabase/migrations/*_db09_sync_backup_reporting_20261117.sql' >/dev/null; then
  echo "Using versioned SQL migrations already loaded by supabase db start"
else
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
fi

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

echo "== Seed fictional LOCAL Auth identities for rollback-only domain fixtures =="
psql "$PGURL" -X -v ON_ERROR_STOP=1 -q -f supabase/tests/CI_FAKE_AUTH_USERS.sql

echo "== Run DB03–DB09 fictional rollback-only PostgreSQL fixtures =="
for name in \
  DB03_FEES_SCHEMA_INTEGRATION.sql \
  DB04_ATTENDANCE_SCHEMA_INTEGRATION.sql \
  DB05_PAYROLL_SCHEMA_INTEGRATION.sql \
  DB06_FINANCE_SCHEMA_INTEGRATION.sql \
  DB07_BUSINESS_TRANSPORT_INTEGRATION.sql \
  DB08_APPROVALS_INTEGRATION.sql \
  DB09_SYNC_BACKUP_INTEGRATION.sql
do
  echo "Testing $name"
  psql "$PGURL" -X -v ON_ERROR_STOP=1 -q -f "supabase/tests/$name"
done

echo "== Verify DB30 private expense evidence, RLS and permissioned RPC grants =="
psql "$PGURL" -X -v ON_ERROR_STOP=1 -q -f supabase/tests/DB30_EXPENSE_EVIDENCE_INTEGRATION.sql

echo "== Verify DB31 direct expense recording and optional evidence permissions =="
psql "$PGURL" -X -v ON_ERROR_STOP=1 -q -f supabase/tests/DB31_DIRECT_EXPENSE_INTEGRATION.sql

echo "== Verify DB31 all-category billing RPC security =="
psql "$PGURL" -X -v ON_ERROR_STOP=1 -q -f supabase/tests/DB31_ALL_CATEGORY_BILLING_INTEGRATION.sql

echo "== Verify DB34 recurring student rate override, exemption, reset and replay =="
psql "$PGURL" -X -v ON_ERROR_STOP=1 -q -f supabase/tests/DB34_STUDENT_RATES_INTEGRATION.sql

echo "PASS: DB03-DB09 domain fixtures plus DB30-DB31 expense and fee security regressions succeeded on isolated local database"
