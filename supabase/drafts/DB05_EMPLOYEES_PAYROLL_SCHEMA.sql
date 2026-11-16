-- DB05 — Employees, multi-campus assignments, payroll and advances.
-- SCHEMA-DESIGN SOURCE ONLY. NOT A LIVE MIGRATION. NO FLUTTER WORK.
-- Depends on DB01/DB02 deployed baseline; DB03/DB04 drafts remain pending.
-- Money = signed BIGINT MINOR units, currency = public.schools.currency_code.
-- A staff member can serve multiple campuses; at most ONE school-wide salary
-- assessment per employee and payroll month, with optional cost allocations.
-- ALL posting/RLS authorization, approvals, active assignments and concurrent
-- net-pay balance limits require separate trusted server operations and tests.
BEGIN;

-- 1. School-wide HR departments; references are school-contained.
CREATE TABLE public.employee_departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  code text NOT NULL CHECK (code ~ '^[A-Z][A-Z0-9_]{1,29}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (school_id,code),
  UNIQUE (id,school_id)
);

-- 2. Positions refer to a department at the SAME school.
CREATE TABLE public.employee_positions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  department_id uuid NOT NULL,
  code text NOT NULL CHECK (code ~ '^[A-Z][A-Z0-9_]{1,29}$'),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 140),
  is_teaching_position boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  FOREIGN KEY (department_id,school_id)
    REFERENCES public.employee_departments(id,school_id) ON DELETE RESTRICT,
  UNIQUE (school_id,code),
  UNIQUE (id,school_id,department_id)
);

-- 3. School-wide employee identity, with OPTIONAL Auth login. Many teachers
-- and other employees may have no login in pilot. Never store raw bank
-- credentials, government ID scans or health information in this table.
CREATE TABLE public.employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  employee_no text NOT NULL
    CHECK (employee_no = btrim(employee_no)
      AND length(employee_no) BETWEEN 1 AND 40),
  full_name text NOT NULL CHECK (length(btrim(full_name)) BETWEEN 2 AND 200),
  full_name_ur text,
  auth_user_id uuid REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
  hired_on date NOT NULL,
  ended_on date,
  employment_type text NOT NULL CHECK (
    employment_type IN ('permanent','fixed_term','part_time','contract')),
  employment_status text NOT NULL DEFAULT 'active' CHECK (
    employment_status IN ('active','on_leave','suspended','terminated')),
  payment_reference_last4 text CHECK (
    payment_reference_last4 IS NULL OR
    payment_reference_last4 ~ '^[A-Za-z0-9]{4}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  CHECK (ended_on IS NULL OR ended_on >= hired_on),
  UNIQUE (school_id,employee_no),
  UNIQUE (id,school_id),
  UNIQUE (id,school_id,auth_user_id)
);
CREATE UNIQUE INDEX one_employee_per_login_per_school
  ON public.employees(school_id,auth_user_id)
  WHERE auth_user_id IS NOT NULL;

-- 4. One employee may serve more than one campus. Each assignment has an
-- effective period and a role/department; overlapping allocation percentages
-- and active-campuses must be validated by a trusted transaction.
CREATE TABLE public.employee_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  department_id uuid NOT NULL,
  position_id uuid NOT NULL,
  starts_on date NOT NULL,
  ends_on date,
  primary_assignment boolean NOT NULL DEFAULT false,
  workload_bps integer NOT NULL DEFAULT 10000
    CHECK (workload_bps BETWEEN 1 AND 10000),
  assignment_status text NOT NULL DEFAULT 'active' CHECK (
    assignment_status IN ('planned','active','ended')),
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (employee_id,school_id)
    REFERENCES public.employees(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (position_id,school_id,department_id)
    REFERENCES public.employee_positions(id,school_id,department_id)
    ON DELETE RESTRICT,
  CHECK (ends_on IS NULL OR ends_on >= starts_on),
  UNIQUE (id,school_id,campus_id,employee_id)
);
CREATE INDEX employee_assignments_effective_idx
  ON public.employee_assignments(school_id,employee_id,starts_on,ends_on);
CREATE UNIQUE INDEX one_open_primary_employee_assignment
  ON public.employee_assignments(school_id,employee_id)
  WHERE primary_assignment AND ends_on IS NULL
    AND assignment_status='active';

-- 5. Assignment of a logged-in teaching employee to a campus class/section
-- and academic year; links DB04 teacher duty through a future trusted
-- function. An unauthenticated employee cannot masquerade as a teacher.
CREATE TABLE public.employee_teaching_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  section_id uuid,
  employee_assignment_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  teacher_user_id uuid NOT NULL,
  subject_label text NOT NULL
    CHECK (length(btrim(subject_label)) BETWEEN 2 AND 120),
  starts_on date NOT NULL,
  ends_on date,
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (employee_assignment_id,school_id,campus_id,employee_id)
    REFERENCES public.employee_assignments(id,school_id,campus_id,employee_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (employee_id,school_id,teacher_user_id)
    REFERENCES public.employees(id,school_id,auth_user_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (academic_year_id,school_id)
    REFERENCES public.academic_years(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (class_id,campus_id,academic_year_id)
    REFERENCES public.classes(id,campus_id,academic_year_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (section_id,class_id)
    REFERENCES public.sections(id,class_id) ON DELETE RESTRICT,
  CHECK (ends_on IS NULL OR ends_on >= starts_on),
  UNIQUE NULLS NOT DISTINCT (
    employee_assignment_id,academic_year_id,class_id,section_id,
    subject_label,starts_on)
);

-- 6. School-defined salary component catalog. Payroll lines must use
-- component of matching kind (earning/deduction), never arbitrary labels.
CREATE TABLE public.payroll_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  code text NOT NULL CHECK (code ~ '^[A-Z][A-Z0-9_]{1,29}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 140),
  component_kind text NOT NULL CHECK (
    component_kind IN ('earning','deduction')),
  is_recurring boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE (school_id,code),
  UNIQUE (id,school_id),
  UNIQUE (id,school_id,component_kind)
);

-- 7. Approved versioned remuneration for employee's paying-campus
-- assignment. An employee with assignments in two campuses still receives
-- only ONE salary assessment per month (payroll_entries school-wide key).
CREATE TABLE public.salary_structures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  employee_assignment_id uuid NOT NULL,
  version_no integer NOT NULL CHECK (version_no > 0),
  pay_basis text NOT NULL CHECK (
    pay_basis IN ('monthly','daily','hourly')),
  effective_from date NOT NULL,
  effective_to date,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','active','retired')),
  approved_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (employee_assignment_id,school_id,campus_id,employee_id)
    REFERENCES public.employee_assignments(id,school_id,campus_id,employee_id)
    ON DELETE RESTRICT,
  CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CHECK (status <> 'active' OR approved_by IS NOT NULL),
  UNIQUE (school_id,employee_id,version_no),
  UNIQUE (id,school_id),
  UNIQUE (id,school_id,campus_id,employee_id)
);
CREATE UNIQUE INDEX one_active_salary_structure_per_employee
  ON public.salary_structures(school_id,employee_id)
  WHERE status='active';

-- 8. Amounts are exact minor units. A future salary computation will
-- multiply daily/hourly values by approved attendance/shift quantities;
-- no payroll calculations happen in the client or in this DDL.
CREATE TABLE public.salary_structure_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  salary_structure_id uuid NOT NULL,
  component_id uuid NOT NULL,
  component_kind text NOT NULL CHECK (
    component_kind IN ('earning','deduction')),
  rate_minor bigint NOT NULL CHECK (rate_minor >= 0),
  FOREIGN KEY (salary_structure_id,school_id)
    REFERENCES public.salary_structures(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (component_id,school_id,component_kind)
    REFERENCES public.payroll_components(id,school_id,component_kind)
    ON DELETE RESTRICT,
  UNIQUE (salary_structure_id,component_id)
);

-- 9. Staff leave REQUEST: approval must come from an authorized DB08
-- operation, not client self-declaration. Status is not a paid-day decision.
CREATE TABLE public.employee_leave_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  employee_assignment_id uuid NOT NULL,
  leave_kind text NOT NULL CHECK (
    leave_kind IN ('annual','sick','unpaid','emergency','other')),
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  request_operation_id uuid NOT NULL,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  requested_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'pending' CHECK (
    status IN ('pending','approved','rejected','withdrawn')),
  reviewed_by uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  FOREIGN KEY (employee_assignment_id,school_id,campus_id,employee_id)
    REFERENCES public.employee_assignments(id,school_id,campus_id,employee_id)
    ON DELETE RESTRICT,
  CHECK (ends_on >= starts_on),
  CHECK ((status IN ('pending','withdrawn') AND reviewed_by IS NULL
         AND reviewed_at IS NULL)
    OR (status IN ('approved','rejected') AND reviewed_by IS NOT NULL
         AND reviewed_at IS NOT NULL)),
  UNIQUE (school_id,request_operation_id),
  UNIQUE (id,school_id,campus_id,employee_id)
);

-- 10. A calendar day granted by a verified leave approval. An employee
-- cannot consume two leave records on the same day across campuses.
CREATE TABLE public.employee_leave_days (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  leave_request_id uuid NOT NULL,
  leave_date date NOT NULL,
  paid_day boolean NOT NULL DEFAULT false,
  recorded_by uuid NOT NULL REFERENCES auth.users(id),
  operation_id uuid NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (leave_request_id,school_id,campus_id,employee_id)
    REFERENCES public.employee_leave_requests
      (id,school_id,campus_id,employee_id) ON DELETE RESTRICT,
  UNIQUE (school_id,employee_id,leave_date),
  UNIQUE (school_id,operation_id)
);

-- 11. One paying campus's payroll cycle. Month is the first calendar day,
-- and status progression/close/reopen decisions need server operations.
CREATE TABLE public.payroll_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  payroll_month date NOT NULL CHECK (
    EXTRACT(DAY FROM payroll_month)=1),
  period_start date NOT NULL,
  period_end date NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (
    status IN ('draft','calculated','approved','closed')),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  closed_by uuid REFERENCES auth.users(id),
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  CHECK (period_end >= period_start),
  CHECK ((status IN ('draft','calculated') AND approved_at IS NULL
           AND approved_by IS NULL AND closed_at IS NULL
           AND closed_by IS NULL)
    OR (status='approved' AND approved_at IS NOT NULL
           AND approved_by IS NOT NULL AND closed_at IS NULL
           AND closed_by IS NULL)
    OR (status='closed' AND approved_at IS NOT NULL
           AND approved_by IS NOT NULL AND closed_at IS NOT NULL
           AND closed_by IS NOT NULL)),
  UNIQUE (campus_id,payroll_month),
  UNIQUE (id,school_id,campus_id,payroll_month)
);

-- 12. Exactly ONE original salary assessment per employee per SCHOOL month;
-- a transfer/multi-campus duty cannot silently pay the same base twice.
-- Further adjustments are separate posted facts and do not rewrite entries.
CREATE TABLE public.payroll_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  employee_assignment_id uuid NOT NULL,
  salary_structure_id uuid NOT NULL,
  payroll_period_id uuid NOT NULL,
  payroll_month date NOT NULL CHECK (
    EXTRACT(DAY FROM payroll_month)=1),
  gross_minor bigint NOT NULL CHECK (gross_minor >= 0),
  regular_deductions_minor bigint NOT NULL DEFAULT 0
    CHECK (regular_deductions_minor >= 0),
  advance_recovery_minor bigint NOT NULL DEFAULT 0
    CHECK (advance_recovery_minor >= 0),
  net_minor bigint GENERATED ALWAYS AS (
    gross_minor - regular_deductions_minor - advance_recovery_minor
  ) STORED,
  operation_id uuid NOT NULL,
  assessed_by uuid NOT NULL REFERENCES auth.users(id),
  assessed_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (employee_assignment_id,school_id,campus_id,employee_id)
    REFERENCES public.employee_assignments(id,school_id,campus_id,employee_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (salary_structure_id,school_id,campus_id,employee_id)
    REFERENCES public.salary_structures(id,school_id,campus_id,employee_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (payroll_period_id,school_id,campus_id,payroll_month)
    REFERENCES public.payroll_periods(id,school_id,campus_id,payroll_month)
    ON DELETE RESTRICT,
  CHECK (regular_deductions_minor + advance_recovery_minor <= gross_minor),
  UNIQUE (school_id,employee_id,payroll_month),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id,campus_id,employee_id),
  UNIQUE (id,school_id,employee_id)
);
CREATE INDEX payroll_employee_month_idx
  ON public.payroll_entries(school_id,employee_id,payroll_month DESC);

-- 13. Immutable gross/deduction component detail. Sum of earning
-- components / regular deductions must be reconciled to payroll entry
-- snapshots during trusted payroll posting, not in untrusted requests.
CREATE TABLE public.payroll_entry_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  payroll_entry_id uuid NOT NULL,
  component_id uuid NOT NULL,
  component_kind text NOT NULL CHECK (
    component_kind IN ('earning','deduction')),
  amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
  units_quantity numeric(12,4) CHECK (
    units_quantity IS NULL OR units_quantity > 0),
  description text,
  FOREIGN KEY (payroll_entry_id,school_id,campus_id,employee_id)
    REFERENCES public.payroll_entries(id,school_id,campus_id,employee_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (component_id,school_id,component_kind)
    REFERENCES public.payroll_components(id,school_id,component_kind)
    ON DELETE RESTRICT,
  UNIQUE (payroll_entry_id,component_id)
);

-- 14. Accounting COST share when an employee serves multiple campuses.
-- Allocation totals must equal gross salary using locked server transaction;
-- a cost allocation is not a second salary payment or cash transfer.
CREATE TABLE public.payroll_cost_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  payroll_entry_id uuid NOT NULL,
  cost_campus_id uuid NOT NULL,
  allocated_gross_minor bigint NOT NULL CHECK (
    allocated_gross_minor >= 0),
  FOREIGN KEY (payroll_entry_id,school_id,employee_id)
    REFERENCES public.payroll_entries(id,school_id,employee_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (cost_campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  UNIQUE (payroll_entry_id,cost_campus_id)
);

-- 15. Immutable signed net-pay adjustments, never original entry edits.
CREATE TABLE public.payroll_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  payroll_entry_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  delta_net_minor bigint NOT NULL CHECK (delta_net_minor <> 0),
  adjustment_kind text NOT NULL CHECK (
    adjustment_kind IN ('correction','bonus','penalty','reversal')),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  posted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (payroll_entry_id,school_id,employee_id)
    REFERENCES public.payroll_entries(id,school_id,employee_id)
    ON DELETE RESTRICT,
  UNIQUE (school_id,operation_id)
);

-- 16. Salary advance is a separate repayable balance and must have a
-- matching DB06 cash/bank disbursement in the SAME future online transaction.
-- It must NEVER be counted as payroll salary expense a second time.
CREATE TABLE public.salary_advances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  issuing_campus_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  advanced_on date NOT NULL,
  operation_id uuid NOT NULL,
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  issued_by uuid NOT NULL REFERENCES auth.users(id),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  issued_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (employee_id,school_id)
    REFERENCES public.employees(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (issuing_campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id,employee_id)
);

-- 17. Each payroll deduction for an advance must reference exactly one
-- earlier advance belonging to this employee. Future locked server posting
-- enforces SUM(repayments)<=advance amount and SUM(repayments per payroll
-- entry)=advance_recovery_minor; never duplicate salary expense.
CREATE TABLE public.advance_repayments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  payroll_entry_id uuid NOT NULL,
  advance_id uuid NOT NULL,
  recovered_minor bigint NOT NULL CHECK (recovered_minor > 0),
  operation_id uuid NOT NULL,
  recovered_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (payroll_entry_id,school_id,campus_id,employee_id)
    REFERENCES public.payroll_entries(id,school_id,campus_id,employee_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (advance_id,school_id,employee_id)
    REFERENCES public.salary_advances(id,school_id,employee_id)
    ON DELETE RESTRICT,
  UNIQUE (school_id,operation_id),
  UNIQUE (payroll_entry_id,advance_id)
);

-- 18. Multiple partial payments may settle one salary assessment.
-- Actual cash/bank movements belong to DB06 and must be posted atomically.
-- Employee bank account secrets/IBAN are not stored in this table.
CREATE TABLE public.salary_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  payroll_entry_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  method text NOT NULL CHECK (method IN ('cash','bank')),
  bank_reference text,
  operation_id uuid NOT NULL,
  paid_at timestamptz NOT NULL DEFAULT now(),
  paid_by uuid NOT NULL REFERENCES auth.users(id),
  FOREIGN KEY (payroll_entry_id,school_id,campus_id,employee_id)
    REFERENCES public.payroll_entries(id,school_id,campus_id,employee_id)
    ON DELETE RESTRICT,
  CHECK (method<>'bank' OR
    length(btrim(coalesce(bank_reference,''))) >= 3),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id,employee_id)
);
CREATE INDEX salary_payments_entry_idx
  ON public.salary_payments(payroll_entry_id,paid_at);

-- 19. Original payment remains immutable even after a verified reversal.
CREATE TABLE public.salary_payment_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  reversal_operation_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  reversed_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (payment_id,school_id,employee_id)
    REFERENCES public.salary_payments(id,school_id,employee_id)
    ON DELETE RESTRICT,
  UNIQUE (payment_id),
  UNIQUE (school_id,reversal_operation_id)
);

-- 20. Exactly-once cloud operation receipt. Must be committed with salary/
-- payment/advance/repayment journal rows by an authorized future RPC.
-- No payroll service API is exposed in this schema-design stage.
CREATE TABLE public.payroll_operation_receipts (
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  operation_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN (
    'approve_salary','post_payroll','adjust_payroll','issue_advance',
    'recover_advance','post_salary_payment','reverse_salary_payment',
    'approve_leave','close_payroll','reassign_employee')),
  actor_id uuid NOT NULL REFERENCES auth.users(id),
  request_sha256 bytea NOT NULL CHECK (octet_length(request_sha256)=32),
  result_json jsonb NOT NULL CHECK (
    jsonb_typeof(result_json)='object'),
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (school_id,operation_id)
);

-- Posted evidence is immutable, including employee leave days.
CREATE FUNCTION app_private.db05_reject_posted_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
BEGIN
  RAISE EXCEPTION 'Employee/payroll posted evidence cannot be mutated'
    USING ERRCODE='23514';
END;
$$;

CREATE TRIGGER db05_leave_days_immutable
  BEFORE UPDATE OR DELETE ON public.employee_leave_days
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_payroll_entries_immutable
  BEFORE UPDATE OR DELETE ON public.payroll_entries
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_payroll_entry_lines_immutable
  BEFORE UPDATE OR DELETE ON public.payroll_entry_lines
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_payroll_cost_allocations_immutable
  BEFORE UPDATE OR DELETE ON public.payroll_cost_allocations
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_payroll_adjustments_immutable
  BEFORE UPDATE OR DELETE ON public.payroll_adjustments
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_salary_advances_immutable
  BEFORE UPDATE OR DELETE ON public.salary_advances
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_advance_repayments_immutable
  BEFORE UPDATE OR DELETE ON public.advance_repayments
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_salary_payments_immutable
  BEFORE UPDATE OR DELETE ON public.salary_payments
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_salary_payment_reversals_immutable
  BEFORE UPDATE OR DELETE ON public.salary_payment_reversals
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_operation_receipts_immutable
  BEFORE UPDATE OR DELETE ON public.payroll_operation_receipts
  FOR EACH ROW EXECUTE FUNCTION app_private.db05_reject_posted_mutation();

-- TRUNCATE bypasses row-level triggers, so each posted fact rejects it.
CREATE TRIGGER db05_leave_days_no_truncate
  BEFORE TRUNCATE ON public.employee_leave_days
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_payroll_entries_no_truncate
  BEFORE TRUNCATE ON public.payroll_entries
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_payroll_entry_lines_no_truncate
  BEFORE TRUNCATE ON public.payroll_entry_lines
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_payroll_cost_allocations_no_truncate
  BEFORE TRUNCATE ON public.payroll_cost_allocations
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_payroll_adjustments_no_truncate
  BEFORE TRUNCATE ON public.payroll_adjustments
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_salary_advances_no_truncate
  BEFORE TRUNCATE ON public.salary_advances
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_advance_repayments_no_truncate
  BEFORE TRUNCATE ON public.advance_repayments
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_salary_payments_no_truncate
  BEFORE TRUNCATE ON public.salary_payments
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_salary_payment_reversals_no_truncate
  BEFORE TRUNCATE ON public.salary_payment_reversals
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();
CREATE TRIGGER db05_operation_receipts_no_truncate
  BEFORE TRUNCATE ON public.payroll_operation_receipts
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db05_reject_posted_mutation();

-- All twenty tables deny direct SELECT/INSERT/UPDATE/DELETE to anon and
-- authenticated until reviewed campus/HR/payroll read and write operations.
ALTER TABLE public.employee_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_teaching_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_structures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_structure_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_leave_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_entry_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_cost_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_advances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advance_repayments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_payment_reversals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_operation_receipts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON
 public.employee_departments,public.employee_positions,public.employees,
 public.employee_assignments,public.employee_teaching_assignments,
 public.payroll_components,public.salary_structures,
 public.salary_structure_lines,public.employee_leave_requests,
 public.employee_leave_days,public.payroll_periods,public.payroll_entries,
 public.payroll_entry_lines,public.payroll_cost_allocations,
 public.payroll_adjustments,public.salary_advances,
 public.advance_repayments,public.salary_payments,
 public.salary_payment_reversals,public.payroll_operation_receipts
FROM PUBLIC,anon,authenticated;

REVOKE ALL ON FUNCTION app_private.db05_reject_posted_mutation()
  FROM PUBLIC,anon,authenticated;

-- No direct client write policies, no salary or attendance reads, no payroll
-- function and no cash/bank account posting are created here. DB06 will
-- supply cash/bank movements; DB08 will define approval authority; DB09
-- will define secure synchronization and reporting.
COMMIT;
