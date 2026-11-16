-- DB06 CASHBOOK, BANK, EXPENSES AND DOUBLE-ENTRY ACCOUNTING — DESIGN DRAFT.
-- NOT DEPLOYED. No Flutter or application code in this workstream.
-- Dependency: DB01+DB02 live baseline; DB03 PR #25; DB04 PR #26;
-- DB05 PR #29; then this DB06 SQL. NOT a Supabase migration.
-- All financial amounts = signed BIGINT minor currency units, school-wide
-- currency from public.schools. No gateway/foreign-exchange support in v1.
BEGIN;

-- Existing DB03/05 source rows need an explicit (id,school_id) UNIQUE
-- so financial journal links can enforce the SAME SCHOOL in Postgres FKs.
ALTER TABLE public.fee_receipts ADD CONSTRAINT db06_fee_receipt_school_key
  UNIQUE (id,school_id);
ALTER TABLE public.fee_receipt_reversals
  ADD CONSTRAINT db06_fee_receipt_reversal_school_key UNIQUE (id,school_id);
ALTER TABLE public.admission_fee_deposits
  ADD CONSTRAINT db06_admission_deposit_school_key UNIQUE (id,school_id);
ALTER TABLE public.salary_payments ADD CONSTRAINT db06_salary_payment_school_key
  UNIQUE (id,school_id);
ALTER TABLE public.salary_payment_reversals
  ADD CONSTRAINT db06_salary_reversal_school_key UNIQUE (id,school_id);
ALTER TABLE public.salary_advances ADD CONSTRAINT db06_salary_advance_school_key
  UNIQUE (id,school_id);

-- 01. School chart of accounts, with optional campus cost-center scope.
-- Financial accounts are asset accounts, but income, expenses, equity and
-- advance receivables/employee payables have distinct accounting kinds.
CREATE TABLE public.ledger_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  campus_id uuid,
  code text NOT NULL CHECK (code ~ '^[A-Z0-9][A-Z0-9_-]{1,39}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  account_type text NOT NULL CHECK
    (account_type IN ('asset','liability','equity','income','expense')),
  account_scope text NOT NULL CHECK
    (account_scope IN ('school','campus')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  CHECK ((account_scope='school' AND campus_id IS NULL) OR
         (account_scope='campus' AND campus_id IS NOT NULL)),
  UNIQUE (school_id,code),
  UNIQUE (id,school_id),
  UNIQUE (id,school_id,campus_id,account_type)
);

-- 02. Physical campus cash boxes and bank accounts link to ASSET accounts.
-- Store display name and last 4 reference digits only: no complete IBAN,
-- passwords, routing secrets or online banking credentials.
CREATE TABLE public.financial_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  ledger_account_id uuid NOT NULL,
  ledger_account_type text NOT NULL DEFAULT 'asset'
    CHECK (ledger_account_type='asset'),
  account_kind text NOT NULL CHECK (account_kind IN ('cash','bank')),
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 160),
  masked_reference text CHECK (
    masked_reference IS NULL OR
    length(btrim(masked_reference)) BETWEEN 4 AND 20),
  opened_on date NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK
    (status IN ('active','closed')),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (ledger_account_id,school_id,campus_id,ledger_account_type)
    REFERENCES public.ledger_accounts
      (id,school_id,campus_id,account_type) ON DELETE RESTRICT,
  UNIQUE (school_id,campus_id,display_name),
  UNIQUE (ledger_account_id),
  UNIQUE (id,school_id),
  UNIQUE (id,school_id,campus_id),
  UNIQUE (id,school_id,campus_id,account_kind)
);
CREATE INDEX financial_accounts_campus_kind_idx
  ON public.financial_accounts(school_id,campus_id,account_kind);

-- 03. Expense category taxonomy. Canteen/uniform stock purchase is not
-- automatically cost of goods sold; expenses and inventory get distinct tags.
CREATE TABLE public.expense_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  code text NOT NULL CHECK (code ~ '^[A-Z][A-Z0-9_]{1,29}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  expense_kind text NOT NULL CHECK (
    expense_kind IN ('operating','inventory_procurement','capital_asset')),
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE (school_id,code),
  UNIQUE (id,school_id,expense_kind)
);

-- 04. Expense request is NOT payment or cash movement. Offline Windows
-- approval-requiring requests remain local pending server authorization.
CREATE TABLE public.expense_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  category_id uuid NOT NULL,
  expense_kind text NOT NULL,
  requested_amount_minor bigint NOT NULL CHECK (requested_amount_minor>0),
  expense_date date NOT NULL,
  purpose text NOT NULL CHECK (length(btrim(purpose)) BETWEEN 4 AND 1000),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  requester_id uuid NOT NULL REFERENCES auth.users(id),
  requested_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  rejection_reason text,
  request_operation_id uuid NOT NULL,
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (category_id,school_id,expense_kind)
    REFERENCES public.expense_categories(id,school_id,expense_kind)
    ON DELETE RESTRICT,
  CHECK ((status IN ('pending','cancelled') AND reviewed_by IS NULL
           AND reviewed_at IS NULL)
      OR (status='approved' AND reviewed_by IS NOT NULL
           AND reviewed_at IS NOT NULL)
      OR (status='rejected' AND reviewed_by IS NOT NULL
           AND reviewed_at IS NOT NULL
           AND length(btrim(coalesce(rejection_reason,'')))>=4)),
  UNIQUE (school_id,request_operation_id),
  UNIQUE (id,school_id,campus_id,category_id,expense_kind)
);

-- 05. Immutable expense payment fact. A trusted server must check that
-- the REQUEST is currently approved and amount is eligible, then insert
-- expense + balanced ledger posting + operation receipt atomically.
CREATE TABLE public.expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  category_id uuid NOT NULL,
  expense_kind text NOT NULL,
  request_id uuid NOT NULL,
  financial_account_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor>0),
  paid_on date NOT NULL,
  vendor_name text,
  external_reference text,
  operation_id uuid NOT NULL,
  posted_by uuid NOT NULL REFERENCES auth.users(id),
  posted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (request_id,school_id,campus_id,category_id,expense_kind)
    REFERENCES public.expense_requests
      (id,school_id,campus_id,category_id,expense_kind) ON DELETE RESTRICT,
  FOREIGN KEY (financial_account_id,school_id,campus_id)
    REFERENCES public.financial_accounts(id,school_id,campus_id)
    ON DELETE RESTRICT,
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id)
);
CREATE INDEX expenses_campus_paid_idx
  ON public.expenses(campus_id,paid_on);

-- 06. Cash/Bank A-to-B internal transfers are neither revenue nor expense.
CREATE TABLE public.account_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  from_account_id uuid NOT NULL,
  to_account_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor>0),
  transferred_on date NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
  operation_id uuid NOT NULL,
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  posted_by uuid NOT NULL REFERENCES auth.users(id),
  posted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (from_account_id,school_id)
    REFERENCES public.financial_accounts(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (to_account_id,school_id)
    REFERENCES public.financial_accounts(id,school_id) ON DELETE RESTRICT,
  CHECK (from_account_id<>to_account_id),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id)
);

-- 07. Owner capital additions/withdrawals go to EQUITY, not INCOME.
CREATE TABLE public.capital_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  financial_account_id uuid NOT NULL,
  capital_kind text NOT NULL CHECK (
    capital_kind IN ('owner_injection','owner_withdrawal')),
  amount_minor bigint NOT NULL CHECK (amount_minor>0),
  occurred_on date NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
  operation_id uuid NOT NULL,
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  posted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (financial_account_id,school_id,campus_id)
    REFERENCES public.financial_accounts(id,school_id,campus_id)
    ON DELETE RESTRICT,
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id)
);

-- 08. Opening balances are explicitly posted journals, never hidden
-- mutable account balance columns. Verified opening includes an offset
-- opening equity ledger account via future authorized posting operation.
CREATE TABLE public.account_opening_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  financial_account_id uuid NOT NULL,
  opening_minor bigint NOT NULL CHECK (opening_minor>=0),
  effective_on date NOT NULL,
  operation_id uuid NOT NULL,
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (financial_account_id,school_id,campus_id)
    REFERENCES public.financial_accounts(id,school_id,campus_id)
    ON DELETE RESTRICT,
  UNIQUE (financial_account_id),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id)
);

-- 09. One accounting month per campus; existing posted journals stay
-- immutable when a period closes. Prior-period adjustments are NEW entries.
CREATE TABLE public.accounting_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  period_month date NOT NULL CHECK (EXTRACT(DAY FROM period_month)=1),
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','closed')),
  approved_by uuid REFERENCES auth.users(id),
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  CHECK ((status='open' AND approved_by IS NULL AND closed_at IS NULL)
    OR (status='closed' AND approved_by IS NOT NULL AND closed_at IS NOT NULL)),
  UNIQUE (campus_id,period_month),
  UNIQUE (id,school_id,campus_id,period_month)
);

-- 10. Immutable POSTED double-entry journal header: every journal MUST
-- have >=2 lines with equal positive debit and credit sums by COMMIT.
CREATE TABLE public.ledger_journals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  initiating_campus_id uuid NOT NULL,
  accounting_period_id uuid NOT NULL,
  period_month date NOT NULL CHECK (EXTRACT(DAY FROM period_month)=1),
  journal_date date NOT NULL,
  journal_kind text NOT NULL CHECK (journal_kind IN (
    'fee_collection','fee_refund','salary_payment','salary_refund',
    'salary_advance','admission_deposit','expense_payment','transfer',
    'capital_in','capital_out','opening_balance','journal_reversal')),
  operation_id uuid NOT NULL,
  explanation text NOT NULL CHECK (length(btrim(explanation)) BETWEEN 4 AND 1000),
  posted_by uuid NOT NULL REFERENCES auth.users(id),
  posted_at timestamptz NOT NULL DEFAULT now(),
  -- Prevent later transactions adding lines to an already accepted journal.
  creation_txid bigint NOT NULL DEFAULT pg_catalog.txid_current(),
  FOREIGN KEY (accounting_period_id,school_id,initiating_campus_id,period_month)
    REFERENCES public.accounting_periods
      (id,school_id,campus_id,period_month) ON DELETE RESTRICT,
  CHECK (date_trunc('month',journal_date::timestamp)::date=period_month),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id),
  UNIQUE (id,school_id,journal_kind)
);

-- 11. Debit and credit movements are stored ONCE in ledger lines. A
-- campus cashbook is a signed projection of lines on that campus's
-- financial asset account (debit minus credit), not a second journal.
CREATE TABLE public.ledger_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  journal_id uuid NOT NULL,
  ledger_account_id uuid NOT NULL,
  debit_minor bigint NOT NULL DEFAULT 0 CHECK (debit_minor>=0),
  credit_minor bigint NOT NULL DEFAULT 0 CHECK (credit_minor>=0),
  line_memo text,
  FOREIGN KEY (journal_id,school_id)
    REFERENCES public.ledger_journals(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (ledger_account_id,school_id)
    REFERENCES public.ledger_accounts(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  CHECK ((debit_minor>0 AND credit_minor=0)
      OR (credit_minor>0 AND debit_minor=0)),
  UNIQUE (id,school_id),
  UNIQUE (id,school_id,campus_id),
  UNIQUE (id,school_id,ledger_account_id)
);
CREATE INDEX ledger_lines_account_date_idx
  ON public.ledger_lines(ledger_account_id,journal_id);
CREATE INDEX ledger_lines_journal_idx ON public.ledger_lines(journal_id);

-- 12. A posted journal may be reversed once with a NEW balanced journal.
-- New journal must be exact reversed lines, checked in trusted posting.
CREATE TABLE public.ledger_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  original_journal_id uuid NOT NULL,
  reversal_journal_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  operation_id uuid NOT NULL,
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  reversed_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (original_journal_id,school_id)
    REFERENCES public.ledger_journals(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (reversal_journal_id,school_id)
    REFERENCES public.ledger_journals(id,school_id) ON DELETE RESTRICT,
  CHECK (original_journal_id<>reversal_journal_id),
  UNIQUE (original_journal_id),
  UNIQUE (reversal_journal_id),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id)
);

-- 13. Typed, same-school FK source link. Every posted journal MUST create
-- precisely one such source row in its trusted posting transaction; it
-- prevents posting the same fee/salary/expense/transfer twice. Any absent
-- journal source needs a deferred guard or posting RPC acceptance check.
CREATE TABLE public.ledger_source_links (
  journal_id uuid PRIMARY KEY,
  school_id uuid NOT NULL,
  journal_kind text NOT NULL,
  fee_receipt_id uuid UNIQUE,
  fee_receipt_reversal_id uuid UNIQUE,
  salary_payment_id uuid UNIQUE,
  salary_payment_reversal_id uuid UNIQUE,
  salary_advance_id uuid UNIQUE,
  admission_deposit_id uuid UNIQUE,
  expense_id uuid UNIQUE,
  transfer_id uuid UNIQUE,
  capital_id uuid UNIQUE,
  opening_id uuid UNIQUE,
  reversal_id uuid UNIQUE,
  FOREIGN KEY (journal_id,school_id,journal_kind)
    REFERENCES public.ledger_journals(id,school_id,journal_kind)
    ON DELETE RESTRICT,
  FOREIGN KEY (fee_receipt_id,school_id)
    REFERENCES public.fee_receipts(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (fee_receipt_reversal_id,school_id)
    REFERENCES public.fee_receipt_reversals(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (salary_payment_id,school_id)
    REFERENCES public.salary_payments(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (salary_payment_reversal_id,school_id)
    REFERENCES public.salary_payment_reversals(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (salary_advance_id,school_id)
    REFERENCES public.salary_advances(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (admission_deposit_id,school_id)
    REFERENCES public.admission_fee_deposits(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (expense_id,school_id)
    REFERENCES public.expenses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (transfer_id,school_id)
    REFERENCES public.account_transfers(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (capital_id,school_id)
    REFERENCES public.capital_transactions(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (opening_id,school_id)
    REFERENCES public.account_opening_entries(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (reversal_id,school_id)
    REFERENCES public.ledger_reversals(id,school_id) ON DELETE RESTRICT,
  CHECK (num_nonnulls(
    fee_receipt_id,fee_receipt_reversal_id,salary_payment_id,
    salary_payment_reversal_id,salary_advance_id,admission_deposit_id,
    expense_id,transfer_id,capital_id,opening_id,reversal_id)=1),
  CHECK (
    (journal_kind='fee_collection' AND fee_receipt_id IS NOT NULL) OR
    (journal_kind='fee_refund' AND fee_receipt_reversal_id IS NOT NULL) OR
    (journal_kind='salary_payment' AND salary_payment_id IS NOT NULL) OR
    (journal_kind='salary_refund' AND salary_payment_reversal_id IS NOT NULL) OR
    (journal_kind='salary_advance' AND salary_advance_id IS NOT NULL) OR
    (journal_kind='admission_deposit' AND admission_deposit_id IS NOT NULL) OR
    (journal_kind='expense_payment' AND expense_id IS NOT NULL) OR
    (journal_kind='transfer' AND transfer_id IS NOT NULL) OR
    (journal_kind='capital_in' AND capital_id IS NOT NULL) OR
    (journal_kind='capital_out' AND capital_id IS NOT NULL) OR
    (journal_kind='opening_balance' AND opening_id IS NOT NULL) OR
    (journal_kind='journal_reversal' AND reversal_id IS NOT NULL)
  )
);

-- 14. Daily count for each physical CASH box. Provisional until sync
-- is complete and trusted closer verifies relevant pending operations.
CREATE TABLE public.cash_closings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  financial_account_id uuid NOT NULL,
  account_kind text NOT NULL DEFAULT 'cash'
    CHECK (account_kind='cash'),
  closing_date date NOT NULL,
  book_balance_minor bigint NOT NULL,
  counted_minor bigint NOT NULL CHECK (counted_minor>=0),
  variance_minor bigint GENERATED ALWAYS AS
    (counted_minor - book_balance_minor) STORED,
  unresolved_sync_count integer NOT NULL DEFAULT 0
    CHECK (unresolved_sync_count>=0),
  pending_approval_count integer NOT NULL DEFAULT 0
    CHECK (pending_approval_count>=0),
  status text NOT NULL DEFAULT 'provisional'
    CHECK (status IN ('provisional','final')),
  variance_reason text,
  counted_by uuid NOT NULL REFERENCES auth.users(id),
  verified_by uuid REFERENCES auth.users(id),
  closed_at timestamptz,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision>0),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (financial_account_id,school_id,campus_id,account_kind)
    REFERENCES public.financial_accounts
      (id,school_id,campus_id,account_kind) ON DELETE RESTRICT,
  CHECK (variance_minor=0 OR
    length(btrim(coalesce(variance_reason,'')))>=4),
  CHECK (status='provisional' OR
     (unresolved_sync_count=0 AND pending_approval_count=0
       AND verified_by IS NOT NULL AND closed_at IS NOT NULL)),
  UNIQUE (financial_account_id,closing_date),
  UNIQUE (id,school_id,campus_id)
);

-- 15. Denominations for cash count. A future trusted finalization
-- transaction verifies SUM(subtotal_minor) equals counted_minor.
CREATE TABLE public.cash_closing_counts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  cash_closing_id uuid NOT NULL,
  denomination_minor bigint NOT NULL CHECK (denomination_minor>0),
  piece_count bigint NOT NULL CHECK (piece_count>=0),
  subtotal_minor bigint GENERATED ALWAYS AS
    (denomination_minor * piece_count) STORED,
  FOREIGN KEY (cash_closing_id,school_id,campus_id)
    REFERENCES public.cash_closings(id,school_id,campus_id)
    ON DELETE RESTRICT,
  UNIQUE (cash_closing_id,denomination_minor)
);

-- 16. After closure, adjustment is a NEW approved balanced journal and
-- an auditable explanation; old closing is not rewritten.
CREATE TABLE public.cash_closing_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  cash_closing_id uuid NOT NULL,
  adjustment_journal_id uuid NOT NULL,
  amount_delta_minor bigint NOT NULL CHECK (amount_delta_minor<>0),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  operation_id uuid NOT NULL,
  approved_by uuid NOT NULL REFERENCES auth.users(id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (cash_closing_id,school_id,campus_id)
    REFERENCES public.cash_closings(id,school_id,campus_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (adjustment_journal_id,school_id)
    REFERENCES public.ledger_journals(id,school_id) ON DELETE RESTRICT,
  UNIQUE (adjustment_journal_id),
  UNIQUE (school_id,operation_id)
);

-- 17. Bank statement import metadata/lines; no full customer bank number.
-- The signed flow is from bank viewpoint: credit increases cash account.
CREATE TABLE public.bank_statement_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  bank_account_id uuid NOT NULL,
  account_kind text NOT NULL DEFAULT 'bank'
    CHECK (account_kind='bank'),
  external_line_key text NOT NULL CHECK
    (length(btrim(external_line_key)) BETWEEN 3 AND 160),
  booked_on date NOT NULL,
  description text,
  inflow_minor bigint NOT NULL DEFAULT 0 CHECK (inflow_minor>=0),
  outflow_minor bigint NOT NULL DEFAULT 0 CHECK (outflow_minor>=0),
  imported_by uuid NOT NULL REFERENCES auth.users(id),
  imported_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (bank_account_id,school_id,campus_id,account_kind)
    REFERENCES public.financial_accounts
      (id,school_id,campus_id,account_kind) ON DELETE RESTRICT,
  CHECK ((inflow_minor>0 AND outflow_minor=0)
      OR (outflow_minor>0 AND inflow_minor=0)),
  UNIQUE (bank_account_id,external_line_key),
  UNIQUE (id,school_id,bank_account_id)
);

-- 18. One bank reconciliation per statement-ending date. Bank balance
-- may be negative because overdraft is possible (requires policy review).
CREATE TABLE public.bank_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  bank_account_id uuid NOT NULL,
  account_kind text NOT NULL DEFAULT 'bank'
    CHECK (account_kind='bank'),
  statement_end date NOT NULL,
  book_balance_minor bigint NOT NULL,
  statement_balance_minor bigint NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK
    (status IN ('draft','final')),
  discrepancy_reason text,
  reconciled_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (bank_account_id,school_id,campus_id,account_kind)
    REFERENCES public.financial_accounts
      (id,school_id,campus_id,account_kind) ON DELETE RESTRICT,
  CHECK ((status='draft' AND approved_by IS NULL AND approved_at IS NULL)
      OR (status='final' AND approved_by IS NOT NULL
          AND approved_at IS NOT NULL)),
  UNIQUE (bank_account_id,statement_end),
  UNIQUE (id,school_id,bank_account_id)
);

-- 19. Match a statement item to ONE posted bank-ledger line. A future
-- trusted transaction verifies the line's ledger_account_id is the bank
-- account's chart-of-accounts ID, date/amount matches, and closing allowed.
CREATE TABLE public.bank_reconciliation_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  bank_account_id uuid NOT NULL,
  reconciliation_id uuid NOT NULL,
  bank_statement_line_id uuid NOT NULL,
  ledger_line_id uuid NOT NULL,
  matched_by uuid NOT NULL REFERENCES auth.users(id),
  matched_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (reconciliation_id,school_id,bank_account_id)
    REFERENCES public.bank_reconciliations
      (id,school_id,bank_account_id) ON DELETE RESTRICT,
  FOREIGN KEY (bank_statement_line_id,school_id,bank_account_id)
    REFERENCES public.bank_statement_lines
      (id,school_id,bank_account_id) ON DELETE RESTRICT,
  FOREIGN KEY (ledger_line_id,school_id)
    REFERENCES public.ledger_lines(id,school_id) ON DELETE RESTRICT,
  UNIQUE (bank_statement_line_id),
  UNIQUE (ledger_line_id)
);

-- 20. Replay receipt for a trusted financial operation, same transaction
-- as all journal lines+source and any fee, payroll or expense posting.
CREATE TABLE public.financial_operation_receipts (
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
  operation_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN (
    'open_account','post_fee_receipt','reverse_fee_receipt',
    'post_salary_payment','reverse_salary_payment','issue_advance',
    'post_expense','transfer_cash_bank','inject_capital',
    'withdraw_capital','post_opening_balance','reverse_journal',
    'close_cash','adjust_closed_cash','reconcile_bank','close_period')),
  actor_id uuid NOT NULL REFERENCES auth.users(id),
  request_sha256 bytea NOT NULL CHECK
    (octet_length(request_sha256)=32),
  result_json jsonb NOT NULL CHECK
    (jsonb_typeof(result_json)='object'),
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (school_id,operation_id)
);

-- The initiating campus accounting period must be open before
-- inserting a posted journal header. FOR SHARE prevents concurrent closing
-- from racing a pending posting in this transaction.
CREATE FUNCTION app_private.db06_require_open_journal_period()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $
DECLARE v_status text;
BEGIN
  SELECT p.status INTO v_status FROM public.accounting_periods p
    WHERE p.id=NEW.accounting_period_id
      AND p.school_id=NEW.school_id
      AND p.campus_id=NEW.initiating_campus_id
      AND p.period_month=NEW.period_month
    FOR SHARE;
  IF v_status IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Cannot post journal into closed accounting period'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$;
CREATE TRIGGER db06_journal_open_period
  BEFORE INSERT ON public.ledger_journals
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_require_open_journal_period();

-- PostgreSQL checks account containment at the database level even if a
-- future privileged posting caller forgets to check campus allocation.
CREATE FUNCTION app_private.db06_check_ledger_line_scope()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $
DECLARE
  v_campus uuid;
  v_active boolean;
  v_month date;
  v_period_status text;
  v_created_txid bigint;
BEGIN
  SELECT a.campus_id,a.is_active INTO v_campus,v_active
    FROM public.ledger_accounts a
   WHERE a.id=NEW.ledger_account_id AND a.school_id=NEW.school_id;
  IF NOT FOUND OR NOT v_active OR
     (v_campus IS NOT NULL AND v_campus<>NEW.campus_id) THEN
    RAISE EXCEPTION 'Ledger line references inactive or other-campus account'
      USING ERRCODE='23514';
  END IF;

  -- A cross-campus transfer touches BOTH campuses' financial periods.
  -- Check the line's own campus, not only the journal initiator campus.
  SELECT j.period_month,j.creation_txid INTO v_month,v_created_txid
    FROM public.ledger_journals j
    WHERE j.id=NEW.journal_id AND j.school_id=NEW.school_id;
  IF v_created_txid IS DISTINCT FROM pg_catalog.txid_current() THEN
    RAISE EXCEPTION 'Cannot append to a previously posted journal'
      USING ERRCODE='23514';
  END IF;
  SELECT p.status INTO v_period_status FROM public.accounting_periods p
    WHERE p.school_id=NEW.school_id AND p.campus_id=NEW.campus_id
      AND p.period_month=v_month FOR SHARE;
  IF v_period_status IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Ledger line campus period is not open'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER db06_line_scope
  BEFORE INSERT ON public.ledger_lines
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_check_ledger_line_scope();

-- A journal source must also arrive in the same posting transaction.
-- Future operations cannot attach a source later to a committed journal.
CREATE FUNCTION app_private.db06_check_source_creation_txid()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $
DECLARE v_created_txid bigint;
BEGIN
  SELECT j.creation_txid INTO v_created_txid
    FROM public.ledger_journals j
   WHERE j.id=NEW.journal_id AND j.school_id=NEW.school_id;
  IF v_created_txid IS DISTINCT FROM pg_catalog.txid_current() THEN
    RAISE EXCEPTION 'Journal source link must commit with its header'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$;
CREATE TRIGGER db06_source_same_transaction
  BEFORE INSERT ON public.ledger_source_links
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_check_source_creation_txid();

-- A posted journal must include balanced positive debit/credit entries.
-- Deferring validation to COMMIT permits header and lines inserted in the
-- SAME transaction while rejecting header-only and unbalanced attempts.
CREATE FUNCTION app_private.db06_assert_journal_balanced()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE
  v_journal uuid;
  v_rows bigint;
  v_debit numeric;
  v_credit numeric;
BEGIN
  IF TG_TABLE_NAME='ledger_journals' THEN
    v_journal := NEW.id;
  ELSE
    v_journal := NEW.journal_id;
  END IF;
  SELECT count(*),coalesce(sum(debit_minor),0),coalesce(sum(credit_minor),0)
    INTO v_rows,v_debit,v_credit
    FROM public.ledger_lines WHERE journal_id=v_journal;
  IF v_rows<2 OR v_debit<=0 OR v_debit<>v_credit THEN
    RAISE EXCEPTION 'Posted journal must have equal, positive debit/credit'
      USING ERRCODE='23514';
  END IF;
  -- Exactly one typed source link is required before COMMIT. The source
  -- link's own CHECK and same-school FKs prevent orphan/forged origins.
  IF NOT EXISTS (
    SELECT 1 FROM public.ledger_source_links
    WHERE journal_id=v_journal
  ) THEN
    RAISE EXCEPTION 'Posted journal missing trusted source link'
      USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER db06_journal_balanced_header
  AFTER INSERT ON public.ledger_journals
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_assert_journal_balanced();
CREATE CONSTRAINT TRIGGER db06_journal_balanced_lines
  AFTER INSERT ON public.ledger_lines
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_assert_journal_balanced();

-- Immutable posting evidence. Nothing silently rewrites/erases a journal.
CREATE FUNCTION app_private.db06_reject_posted_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
BEGIN
  RAISE EXCEPTION 'Posted accounting evidence immutable; create reversal'
    USING ERRCODE='23514';
END;
$$;

CREATE TRIGGER db06_journals_immutable BEFORE UPDATE OR DELETE
  ON public.ledger_journals FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_lines_immutable BEFORE UPDATE OR DELETE
  ON public.ledger_lines FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_links_immutable BEFORE UPDATE OR DELETE
  ON public.ledger_source_links FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_reversals_immutable BEFORE UPDATE OR DELETE
  ON public.ledger_reversals FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_expenses_immutable BEFORE UPDATE OR DELETE
  ON public.expenses FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_transfers_immutable BEFORE UPDATE OR DELETE
  ON public.account_transfers FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_capital_immutable BEFORE UPDATE OR DELETE
  ON public.capital_transactions FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_openings_immutable BEFORE UPDATE OR DELETE
  ON public.account_opening_entries FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_cash_adjustments_immutable BEFORE UPDATE OR DELETE
  ON public.cash_closing_adjustments FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_bank_statement_immutable BEFORE UPDATE OR DELETE
  ON public.bank_statement_lines FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_bank_matches_immutable BEFORE UPDATE OR DELETE
  ON public.bank_reconciliation_matches FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_operation_receipts_immutable BEFORE UPDATE OR DELETE
  ON public.financial_operation_receipts FOR EACH ROW
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();

-- TRUNCATE bypasses row-level constraints; deny on every posted evidence
-- table even if an operator accidentally uses a privileged bulk command.
CREATE TRIGGER db06_journals_no_truncate BEFORE TRUNCATE
  ON public.ledger_journals FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_lines_no_truncate BEFORE TRUNCATE
  ON public.ledger_lines FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_links_no_truncate BEFORE TRUNCATE
  ON public.ledger_source_links FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_reversals_no_truncate BEFORE TRUNCATE
  ON public.ledger_reversals FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_expenses_no_truncate BEFORE TRUNCATE
  ON public.expenses FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_transfers_no_truncate BEFORE TRUNCATE
  ON public.account_transfers FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_capital_no_truncate BEFORE TRUNCATE
  ON public.capital_transactions FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_openings_no_truncate BEFORE TRUNCATE
  ON public.account_opening_entries FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_cash_adjustments_no_truncate BEFORE TRUNCATE
  ON public.cash_closing_adjustments FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_bank_statement_no_truncate BEFORE TRUNCATE
  ON public.bank_statement_lines FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_bank_matches_no_truncate BEFORE TRUNCATE
  ON public.bank_reconciliation_matches FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_operation_receipts_no_truncate BEFORE TRUNCATE
  ON public.financial_operation_receipts FOR EACH STATEMENT
  EXECUTE FUNCTION app_private.db06_reject_posted_mutation();

-- Final cash closings are immutable; provisional revisions must increase.
-- The local sync pending counter can ONLY be trusted after an authorized
-- online check, not from client-submitted integer values.
CREATE FUNCTION app_private.db06_check_cash_closing_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
BEGIN
  IF OLD.status='final' OR
     OLD.school_id IS DISTINCT FROM NEW.school_id OR
     OLD.campus_id IS DISTINCT FROM NEW.campus_id OR
     OLD.financial_account_id IS DISTINCT FROM NEW.financial_account_id OR
     OLD.closing_date IS DISTINCT FROM NEW.closing_date OR
     NEW.revision<>OLD.revision+1 THEN
    RAISE EXCEPTION 'Final cash closing or its identity cannot be edited'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER db06_cash_close_guard
  BEFORE UPDATE ON public.cash_closings
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_check_cash_closing_transition();

-- Cash closing and its denomination evidence cannot be erased. A
-- finalized closing is locked; only a new approved adjustment may reconcile.
CREATE TRIGGER db06_cash_closings_no_delete
  BEFORE DELETE ON public.cash_closings
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_cash_closings_no_truncate
  BEFORE TRUNCATE ON public.cash_closings
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_cash_counts_immutable
  BEFORE UPDATE OR DELETE ON public.cash_closing_counts
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_cash_counts_no_truncate
  BEFORE TRUNCATE ON public.cash_closing_counts
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db06_reject_posted_mutation();

-- Closed accounting periods and finalized bank reconciliation cannot
-- silently reopen, change identity or be deleted after reporting.
CREATE FUNCTION app_private.db06_validate_period_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $
BEGIN
  IF OLD.status='closed'
    OR NEW.school_id IS DISTINCT FROM OLD.school_id
    OR NEW.campus_id IS DISTINCT FROM OLD.campus_id
    OR NEW.period_month IS DISTINCT FROM OLD.period_month
    OR NEW.status<>'closed' THEN
    RAISE EXCEPTION 'Accounting period may only be closed once'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$;
CREATE TRIGGER db06_period_close_guard
  BEFORE UPDATE ON public.accounting_periods
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_validate_period_transition();
CREATE TRIGGER db06_period_no_delete
  BEFORE DELETE ON public.accounting_periods
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_period_no_truncate
  BEFORE TRUNCATE ON public.accounting_periods
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db06_reject_posted_mutation();

CREATE FUNCTION app_private.db06_validate_bank_reconcile_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $
BEGIN
  IF OLD.status='final'
    OR NEW.school_id IS DISTINCT FROM OLD.school_id
    OR NEW.campus_id IS DISTINCT FROM OLD.campus_id
    OR NEW.bank_account_id IS DISTINCT FROM OLD.bank_account_id
    OR NEW.statement_end IS DISTINCT FROM OLD.statement_end
    OR NEW.status<>'final' THEN
    RAISE EXCEPTION 'Final bank reconciliation or identity cannot change'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$;
CREATE TRIGGER db06_bank_reconcile_final_guard
  BEFORE UPDATE ON public.bank_reconciliations
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_validate_bank_reconcile_transition();
CREATE TRIGGER db06_bank_reconcile_no_delete
  BEFORE DELETE ON public.bank_reconciliations
  FOR EACH ROW EXECUTE FUNCTION app_private.db06_reject_posted_mutation();
CREATE TRIGGER db06_bank_reconcile_no_truncate
  BEFORE TRUNCATE ON public.bank_reconciliations
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db06_reject_posted_mutation();

-- RLS deny-by-default on every exposed public DB06 table. All financial
-- commands need future school/campus+current-role checks in trusted server.
ALTER TABLE public.ledger_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.capital_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_opening_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounting_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_reversals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_source_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_closings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_closing_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_closing_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_statement_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_reconciliations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_reconciliation_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_operation_receipts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON
 public.ledger_accounts,public.financial_accounts,
 public.expense_categories,public.expense_requests,public.expenses,
 public.account_transfers,public.capital_transactions,
 public.account_opening_entries,public.accounting_periods,
 public.ledger_journals,public.ledger_lines,public.ledger_reversals,
 public.ledger_source_links,public.cash_closings,public.cash_closing_counts,
 public.cash_closing_adjustments,public.bank_statement_lines,
 public.bank_reconciliations,public.bank_reconciliation_matches,
 public.financial_operation_receipts
FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db06_require_open_journal_period()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db06_check_ledger_line_scope()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db06_assert_journal_balanced()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db06_check_source_creation_txid()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db06_reject_posted_mutation()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db06_check_cash_closing_transition()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db06_validate_period_transition()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db06_validate_bank_reconcile_transition()
  FROM PUBLIC,anon,authenticated;

-- NOT INCLUDED YET: authorizing server posting, DB08 approval/delegation,
-- authoritative source-link existence, exact reversal mirror/transaction
-- kind accounting rules, aggregate accounting constraints, external audit,
-- DB07 inventory cost/COGS journal rules, DB09 sync and real printing.
COMMIT;
