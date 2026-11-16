-- DB03 — Fees and Billing, schema v1 (DESIGN DRAFT; NOT DEPLOYED).
-- Depends on LIVE DB01 foundation + DB02 restricted admissions schema.
-- Single school, multiple campuses. All money is INTEGER MINOR UNITS.
-- PKR 1,000.00 = 100000 minor units, SAR 1,000.00 likewise (2 decimals).
-- No client INSERT/UPDATE/DELETE/SELECT grants. No financial posting RPC yet.
-- Never use SQLite/Flutter values as authority for posting or approvals.
BEGIN;

-- DB02 currently enforces (id,student_id), but financial records must also
-- enforce one campus/year and school at FK level, not only in client code.
ALTER TABLE public.student_enrollments
  ADD CONSTRAINT db03_enrollment_finance_scope_unique
  UNIQUE (id,student_id,school_id,campus_id,academic_year_id);

CREATE TABLE public.fee_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  code text NOT NULL CHECK (code ~ '^[A-Z][A-Z0-9_]{1,29}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  charge_frequency text NOT NULL
    CHECK (charge_frequency IN ('monthly','one_time','manual')),
  is_discountable boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (school_id,code),
  UNIQUE (id,school_id)
);

CREATE TABLE public.fee_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  version_no integer NOT NULL DEFAULT 1 CHECK (version_no > 0),
  effective_from date NOT NULL,
  effective_to date,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','active','retired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (academic_year_id,school_id)
    REFERENCES public.academic_years(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (class_id,campus_id,academic_year_id)
    REFERENCES public.classes(id,campus_id,academic_year_id)
    ON DELETE RESTRICT,
  CHECK (effective_to IS NULL OR effective_to >= effective_from),
  UNIQUE (campus_id,academic_year_id,class_id,version_no),
  UNIQUE (id,school_id,campus_id),
  UNIQUE (id,school_id,campus_id,academic_year_id)
);

CREATE TABLE public.fee_plan_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  fee_plan_id uuid NOT NULL,
  category_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
  is_optional boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (fee_plan_id,school_id,campus_id)
    REFERENCES public.fee_plans(id,school_id,campus_id) ON DELETE RESTRICT,
  FOREIGN KEY (category_id,school_id)
    REFERENCES public.fee_categories(id,school_id) ON DELETE RESTRICT,
  UNIQUE (fee_plan_id,category_id),
  UNIQUE (id,fee_plan_id,category_id)
);

-- One school-campus academic-year monthly close boundary. The billing month
-- is the FIRST DAY of the month (timezone handled by the trusted server).
CREATE TABLE public.fee_billing_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  billing_month date NOT NULL CHECK (extract(day FROM billing_month)=1),
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','closed')),
  closed_by uuid REFERENCES auth.users(id),
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (academic_year_id,school_id)
    REFERENCES public.academic_years(id,school_id) ON DELETE RESTRICT,
  CHECK ((status='open' AND closed_at IS NULL AND closed_by IS NULL)
      OR (status='closed' AND closed_at IS NOT NULL
          AND closed_by IS NOT NULL)),
  UNIQUE (campus_id,academic_year_id,billing_month),
  UNIQUE (id,school_id,campus_id,academic_year_id,billing_month)
);

-- Configured student transport or category exemption/override; does not
-- rewrite posted fee charges from an earlier month.
CREATE TABLE public.student_fee_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  student_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  category_id uuid NOT NULL,
  rule_kind text NOT NULL CHECK (rule_kind IN ('override','exempt')),
  amount_minor bigint,
  start_month date NOT NULL CHECK (extract(day FROM start_month)=1),
  end_month date CHECK (end_month IS NULL OR
    (extract(day FROM end_month)=1 AND end_month>=start_month)),
  is_active boolean NOT NULL DEFAULT true,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (enrollment_id,student_id,school_id,campus_id,academic_year_id)
    REFERENCES public.student_enrollments(
      id,student_id,school_id,campus_id,academic_year_id) ON DELETE RESTRICT,
  FOREIGN KEY (category_id,school_id)
    REFERENCES public.fee_categories(id,school_id) ON DELETE RESTRICT,
  CHECK ((rule_kind='override' AND amount_minor IS NOT NULL
          AND amount_minor>=0)
     OR (rule_kind='exempt' AND amount_minor IS NULL))
);
CREATE UNIQUE INDEX one_active_student_fee_rule_per_category
  ON public.student_fee_rules(enrollment_id,category_id)
  WHERE is_active;

-- Only one currently active approved discount per enrollment and category.
-- Percentage stored in basis points (5000 = 50%), not floating point.
-- Applied discount is capped at the gross category amount by server logic.
CREATE TABLE public.fee_discounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  student_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  category_id uuid NOT NULL,
  discount_kind text NOT NULL CHECK (discount_kind IN ('percent','fixed')),
  percent_bps integer,
  fixed_minor bigint,
  start_month date NOT NULL CHECK (extract(day FROM start_month)=1),
  end_month date CHECK (end_month IS NULL OR
    (extract(day FROM end_month)=1 AND end_month>=start_month)),
  is_active boolean NOT NULL DEFAULT true,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (enrollment_id,student_id,school_id,campus_id,academic_year_id)
    REFERENCES public.student_enrollments(
      id,student_id,school_id,campus_id,academic_year_id) ON DELETE RESTRICT,
  FOREIGN KEY (category_id,school_id)
    REFERENCES public.fee_categories(id,school_id) ON DELETE RESTRICT,
  CHECK ((discount_kind='percent' AND percent_bps BETWEEN 0 AND 10000
         AND fixed_minor IS NULL)
    OR (discount_kind='fixed' AND fixed_minor>=0
         AND fixed_minor IS NOT NULL AND percent_bps IS NULL))
);
CREATE UNIQUE INDEX one_active_student_discount_per_category
  ON public.fee_discounts(enrollment_id,category_id)
  WHERE is_active;

-- Each charge is an immutable posted fact. No debt is duplicated on campus
-- transfer. Financial balance = net_minor + signed adjustments - receipts
-- allocated - credit applications, calculated in a trusted server projection.
CREATE TABLE public.fee_charges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  student_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  billing_cycle_id uuid NOT NULL,
  billing_month date NOT NULL CHECK (extract(day FROM billing_month)=1),
  category_id uuid NOT NULL,
  fee_plan_id uuid,
  plan_item_id uuid,
  source_kind text NOT NULL CHECK (
    source_kind IN ('scheduled','manual','admission')),
  manual_operation_id uuid,
  gross_minor bigint NOT NULL CHECK (gross_minor>=0),
  discount_minor bigint NOT NULL DEFAULT 0 CHECK (discount_minor>=0),
  net_minor bigint GENERATED ALWAYS AS
    (gross_minor - discount_minor) STORED,
  due_on date NOT NULL,
  description text,
  posted_at timestamptz NOT NULL DEFAULT now(),
  posted_by uuid NOT NULL REFERENCES auth.users(id),
  FOREIGN KEY (enrollment_id,student_id,school_id,campus_id,academic_year_id)
    REFERENCES public.student_enrollments(
      id,student_id,school_id,campus_id,academic_year_id) ON DELETE RESTRICT,
  FOREIGN KEY (billing_cycle_id,school_id,campus_id,academic_year_id,billing_month)
    REFERENCES public.fee_billing_cycles(
      id,school_id,campus_id,academic_year_id,billing_month)
    ON DELETE RESTRICT,
  FOREIGN KEY (category_id,school_id)
    REFERENCES public.fee_categories(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (fee_plan_id,school_id,campus_id,academic_year_id)
    REFERENCES public.fee_plans(id,school_id,campus_id,academic_year_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (plan_item_id,fee_plan_id,category_id)
    REFERENCES public.fee_plan_items(id,fee_plan_id,category_id)
    ON DELETE RESTRICT,
  CHECK (discount_minor <= gross_minor),
  CHECK ((source_kind='scheduled'
          AND fee_plan_id IS NOT NULL AND plan_item_id IS NOT NULL
          AND manual_operation_id IS NULL)
    OR (source_kind IN ('manual','admission')
          AND fee_plan_id IS NULL AND plan_item_id IS NULL
          AND manual_operation_id IS NOT NULL)),
  UNIQUE (id,school_id),
  UNIQUE (id,school_id,student_id)
);
CREATE UNIQUE INDEX one_scheduled_fee_per_student_month_category
  ON public.fee_charges(enrollment_id,billing_month,category_id)
  WHERE source_kind='scheduled';
CREATE UNIQUE INDEX one_manual_fee_source_operation
  ON public.fee_charges(school_id,manual_operation_id)
  WHERE manual_operation_id IS NOT NULL;
CREATE INDEX fee_charges_student_due_idx
  ON public.fee_charges(school_id,student_id,due_on);

-- Correct by a NEW signed posting, never editing original charge.
CREATE TABLE public.fee_charge_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  student_id uuid NOT NULL,
  charge_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  delta_minor bigint NOT NULL CHECK (delta_minor<>0),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  posted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (charge_id,school_id,student_id)
    REFERENCES public.fee_charges(id,school_id,student_id)
    ON DELETE RESTRICT,
  UNIQUE (school_id,operation_id)
);

-- Online-confirmed receipt only. Parent-uploaded proof stays a PENDING
-- submission; it is NOT posted cash/bank revenue.
CREATE TABLE public.fee_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  collection_campus_id uuid NOT NULL,
  student_id uuid NOT NULL,
  receipt_no text NOT NULL CHECK (length(btrim(receipt_no)) BETWEEN 3 AND 50),
  operation_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor>0),
  payment_method text NOT NULL CHECK (payment_method IN ('cash','bank')),
  bank_reference text,
  issued_by uuid NOT NULL REFERENCES auth.users(id),
  issued_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (student_id,school_id)
    REFERENCES public.students(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (collection_campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  CHECK (payment_method<>'bank' OR
    length(btrim(coalesce(bank_reference,'')))>=3),
  UNIQUE (school_id,receipt_no),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id,student_id)
);
CREATE INDEX fee_receipts_student_idx
  ON public.fee_receipts(school_id,student_id,issued_at DESC);

-- Partial payments are NORMAL. The same charge can be settled by several
-- different receipt IDs; one receipt can be distributed to several charges.
CREATE TABLE public.fee_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  student_id uuid NOT NULL,
  receipt_id uuid NOT NULL,
  charge_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor>0),
  allocated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (receipt_id,school_id,student_id)
    REFERENCES public.fee_receipts(id,school_id,student_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (charge_id,school_id,student_id)
    REFERENCES public.fee_charges(id,school_id,student_id)
    ON DELETE RESTRICT,
  UNIQUE (receipt_id,charge_id)
);
CREATE INDEX fee_allocations_charge_idx
  ON public.fee_allocations(charge_id);

-- Positive entry creates student credit; negative entry reverses/refunds it.
-- Available balance and no-double-spend require transactionally locked server
-- calculations (not a CHECK across independent ledger rows).
CREATE TABLE public.student_credit_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  student_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  entry_kind text NOT NULL CHECK (entry_kind IN (
    'receipt_excess','manual_grant','reversal_debit','refund_debit')),
  receipt_id uuid,
  delta_minor bigint NOT NULL CHECK (delta_minor<>0),
  operation_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
  posted_by uuid NOT NULL REFERENCES auth.users(id),
  posted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (student_id,school_id)
    REFERENCES public.students(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (receipt_id,school_id,student_id)
    REFERENCES public.fee_receipts(id,school_id,student_id)
    ON DELETE RESTRICT,
  CHECK ((entry_kind IN ('receipt_excess','manual_grant') AND delta_minor>0)
       OR (entry_kind IN ('reversal_debit','refund_debit') AND delta_minor<0)),
  CHECK (entry_kind<>'receipt_excess' OR receipt_id IS NOT NULL),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id,student_id)
);

CREATE TABLE public.fee_credit_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  student_id uuid NOT NULL,
  credit_entry_id uuid NOT NULL,
  charge_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor>0),
  operation_id uuid NOT NULL,
  posted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (credit_entry_id,school_id,student_id)
    REFERENCES public.student_credit_entries(id,school_id,student_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (charge_id,school_id,student_id)
    REFERENCES public.fee_charges(id,school_id,student_id)
    ON DELETE RESTRICT,
  UNIQUE (school_id,operation_id)
);

-- Full reversal is a NEW permanent event. A separate DB06 cash/bank posting
-- must offset the original money movement in the SAME trusted transaction.
CREATE TABLE public.fee_receipt_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  student_id uuid NOT NULL,
  receipt_id uuid NOT NULL,
  reversal_operation_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  reversed_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (receipt_id,school_id,student_id)
    REFERENCES public.fee_receipts(id,school_id,student_id)
    ON DELETE RESTRICT,
  UNIQUE (receipt_id),
  UNIQUE (school_id,reversal_operation_id)
);

-- Parent bank receipt uploads are PENDING claims, not posted receipts.
-- Verified claims link to a separately issued trusted receipt.
CREATE TABLE public.fee_payment_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  student_id uuid NOT NULL,
  submitted_by uuid NOT NULL REFERENCES auth.users(id),
  claimed_amount_minor bigint NOT NULL CHECK (claimed_amount_minor>0),
  proof_storage_path text NOT NULL
    CHECK (length(btrim(proof_storage_path)) BETWEEN 5 AND 600),
  claimed_bank_reference text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','verified','rejected')),
  reviewed_by uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  rejection_reason text,
  verified_receipt_id uuid,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (student_id,school_id)
    REFERENCES public.students(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (verified_receipt_id,school_id,student_id)
    REFERENCES public.fee_receipts(id,school_id,student_id)
    ON DELETE RESTRICT,
  CHECK ((status='pending' AND reviewed_by IS NULL
          AND reviewed_at IS NULL AND verified_receipt_id IS NULL)
    OR (status='verified' AND reviewed_by IS NOT NULL
          AND reviewed_at IS NOT NULL AND verified_receipt_id IS NOT NULL)
    OR (status='rejected' AND reviewed_by IS NOT NULL
          AND reviewed_at IS NOT NULL AND verified_receipt_id IS NULL
          AND length(btrim(coalesce(rejection_reason,'')))>=4))
);
CREATE UNIQUE INDEX one_verified_receipt_per_bank_submission
  ON public.fee_payment_submissions(verified_receipt_id)
  WHERE verified_receipt_id IS NOT NULL;

-- Transfer *collection responsibility*, never duplicate original charges.
CREATE TABLE public.fee_collection_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  charge_id uuid NOT NULL,
  from_campus_id uuid NOT NULL,
  to_campus_id uuid NOT NULL,
  effective_on date NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
  operation_id uuid NOT NULL,
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (charge_id,school_id)
    REFERENCES public.fee_charges(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (from_campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (to_campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  CHECK (from_campus_id<>to_campus_id),
  UNIQUE (school_id,operation_id)
);

-- Admission fee CASH/BANK collection before principal approval does not yet
-- have a student_id. Link to the approved student only through a future
-- trusted reconciliation transaction; never forge a permanent student.
CREATE TABLE public.admission_fee_deposits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  application_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor>0),
  payment_method text NOT NULL CHECK (payment_method IN ('cash','bank')),
  bank_reference text,
  operation_id uuid NOT NULL,
  received_by uuid NOT NULL REFERENCES auth.users(id),
  received_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (application_id,school_id,campus_id)
    REFERENCES public.admission_applications(id,school_id,campus_id)
    ON DELETE RESTRICT,
  CHECK (payment_method<>'bank' OR
    length(btrim(coalesce(bank_reference,'')))>=3),
  UNIQUE (school_id,operation_id)
);

-- Atomic school-wide receipt-number service is future server work.
CREATE TABLE public.fee_receipt_counters (
  school_id uuid PRIMARY KEY REFERENCES public.schools(id) ON DELETE RESTRICT,
  next_serial bigint NOT NULL DEFAULT 1
    CHECK (next_serial BETWEEN 1 AND 999999999)
);

-- All server financial commands must record immutable exact replay results
-- in the SAME transaction as the posting; client operation UUID alone is not
-- authorization. No service or Edge Function is implemented in this draft.
CREATE TABLE public.fee_operation_receipts (
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  operation_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN (
    'generate_charges','manual_charge','post_receipt',
    'apply_credit','adjust_charge','reverse_receipt',
    'admission_deposit','reassign_collection','verify_bank_submission')),
  actor_id uuid NOT NULL REFERENCES auth.users(id),
  request_sha256 bytea NOT NULL
    CHECK (octet_length(request_sha256)=32),
  result_json jsonb NOT NULL CHECK (jsonb_typeof(result_json)='object'),
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (school_id,operation_id)
);

-- Posted financial journal lines must NEVER be silently updated/deleted.
-- Only new corrective events may reverse them; immutable receipts serve as
-- evidence of exactly-once accepted operation processing.
CREATE FUNCTION app_private.db03_reject_posted_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
BEGIN
  RAISE EXCEPTION 'Posted fee transaction is immutable: create a correction'
    USING ERRCODE='23514';
END;
$$;
CREATE TRIGGER fee_charges_immutable
  BEFORE UPDATE OR DELETE ON public.fee_charges
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER fee_charge_adjustments_immutable
  BEFORE UPDATE OR DELETE ON public.fee_charge_adjustments
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER fee_receipts_immutable
  BEFORE UPDATE OR DELETE ON public.fee_receipts
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER fee_allocations_immutable
  BEFORE UPDATE OR DELETE ON public.fee_allocations
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER student_credit_entries_immutable
  BEFORE UPDATE OR DELETE ON public.student_credit_entries
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER fee_credit_applications_immutable
  BEFORE UPDATE OR DELETE ON public.fee_credit_applications
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER fee_receipt_reversals_immutable
  BEFORE UPDATE OR DELETE ON public.fee_receipt_reversals
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER fee_collection_assignments_immutable
  BEFORE UPDATE OR DELETE ON public.fee_collection_assignments
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER admission_fee_deposits_immutable
  BEFORE UPDATE OR DELETE ON public.admission_fee_deposits
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();
CREATE TRIGGER fee_operation_receipts_immutable
  BEFORE UPDATE OR DELETE ON public.fee_operation_receipts
  FOR EACH ROW EXECUTE FUNCTION app_private.db03_reject_posted_mutation();

-- Intentional deny-by-default on every public finance table. No permissive
-- policies or grants for authenticated/anon; trusted server functions with
-- specific current role+campus checks must be reviewed separately.
ALTER TABLE public.fee_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_plan_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_billing_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_fee_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_charge_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_credit_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_credit_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_receipt_reversals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_payment_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_collection_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admission_fee_deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_receipt_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_operation_receipts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON
 public.fee_categories, public.fee_plans, public.fee_plan_items,
 public.fee_billing_cycles, public.student_fee_rules, public.fee_discounts,
 public.fee_charges, public.fee_charge_adjustments, public.fee_receipts,
 public.fee_allocations, public.student_credit_entries,
 public.fee_credit_applications, public.fee_receipt_reversals,
 public.fee_payment_submissions, public.fee_collection_assignments,
 public.admission_fee_deposits, public.fee_receipt_counters,
 public.fee_operation_receipts
FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db03_reject_posted_mutation()
FROM PUBLIC,anon,authenticated;

-- Important limits before live deployment:
-- 1. No trusted server posting, authorization/fee calculation or payment RPC.
-- 2. No transactional SUM constraints for over-allocation, credits,
--    account movements or partial-payment reversals yet.
-- 3. No finance report grants or exposed dashboard metrics.
-- 4. Financial account movements + cross-campus cash reconciliation DB06.
-- 5. Parent role + private bank proof upload authorization DB08.
-- 6. No offline financial posting/finalized receipts until secure sync.
COMMIT;
