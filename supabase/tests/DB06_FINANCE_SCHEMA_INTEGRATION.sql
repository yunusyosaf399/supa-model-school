-- DB06 finance double-entry schema: rollback-only synthetic PostgreSQL fixture.
-- DISPOSABLE LOCAL DATABASE ONLY with DB01+DB02+DB03+DB04+DB05 applied.
-- Needs fictional local Auth account sms-adm-admin-a@example.invalid.
-- Not an accounting posting API test; code does not deploy or move real cash.
-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB06_FINANCE_SCHEMA_INTEGRATION.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';
DO $fixture$
DECLARE
  actor_id uuid;
  s uuid := '11111111-1111-4111-8111-111111111111';
  ca uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  cb uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  cash_account uuid := '10000000-0000-4000-8000-000000000001';
  bank_account uuid := '10000000-0000-4000-8000-000000000002';
  equity_account uuid := '10000000-0000-4000-8000-000000000003';
  expense_account uuid := '10000000-0000-4000-8000-000000000004';
  income_account uuid := '10000000-0000-4000-8000-000000000005';
  cash_wallet uuid := '20000000-0000-4000-8000-000000000001';
  bank_wallet uuid := '20000000-0000-4000-8000-000000000002';
  pa uuid := '30000000-0000-4000-8000-000000000001';
  pb uuid := '30000000-0000-4000-8000-000000000002';
  capital_id uuid := '40000000-0000-4000-8000-000000000001';
  transfer_id uuid := '40000000-0000-4000-8000-000000000002';
  category_id uuid := '40000000-0000-4000-8000-000000000003';
  req_id uuid := '40000000-0000-4000-8000-000000000004';
  expense_id uuid := '40000000-0000-4000-8000-000000000005';
  jc uuid := '50000000-0000-4000-8000-000000000001';
  jt uuid := '50000000-0000-4000-8000-000000000002';
  je uuid := '50000000-0000-4000-8000-000000000003';
  bank_debit_line uuid := '60000000-0000-4000-8000-000000000001';
  close_id uuid := '70000000-0000-4000-8000-000000000001';
  bank_line_id uuid := '80000000-0000-4000-8000-000000000001';
  recon_id uuid := '80000000-0000-4000-8000-000000000002';
  cash_balance bigint;
  bank_balance bigint;
  income_total bigint;
  n integer;
BEGIN
 SELECT id INTO actor_id FROM auth.users
  WHERE email='sms-adm-admin-a@example.invalid';
 IF actor_id IS NULL THEN
  RAISE EXCEPTION 'Create fictional LOCAL Auth user first';
 END IF;
 INSERT INTO public.schools(id,name,currency_code,timezone_name)
 VALUES(s,'Fictional Cashbook School','PKR','Asia/Karachi');
 INSERT INTO public.campuses(id,school_id,code,name) VALUES
  (ca,s,'A','Campus A'),(cb,s,'B','Campus B');
 INSERT INTO public.ledger_accounts
  (id,school_id,campus_id,code,name,account_type,account_scope)
 VALUES
  (cash_account,s,ca,'CASH_A','Campus A cash','asset','campus'),
  (bank_account,s,cb,'BANK_B','Campus B bank','asset','campus'),
  (equity_account,s,NULL,'CAPITAL','Owner Equity','equity','school'),
  (expense_account,s,NULL,'EXPENSE','Operating expense','expense','school'),
  (income_account,s,NULL,'INCOME','Tuition income','income','school');
 INSERT INTO public.financial_accounts(
  id,school_id,campus_id,ledger_account_id,account_kind,display_name,
  opened_on,created_by)
 VALUES
  (cash_wallet,s,ca,cash_account,'cash','Campus A Cash','2026-04-01',actor_id),
  (bank_wallet,s,cb,bank_account,'bank','Campus B Bank','2026-04-01',actor_id);

 INSERT INTO public.accounting_periods(
  id,school_id,campus_id,period_month)
 VALUES (pa,s,ca,'2026-04-01'),(pb,s,cb,'2026-04-01');

 -- OWNER CAPITAL INJECTION: asset debit 50,000, equity credit 50,000.
 -- It must never be counted as operating INCOME.
 INSERT INTO public.capital_transactions(
  id,school_id,campus_id,financial_account_id,capital_kind,
  amount_minor,occurred_on,reason,operation_id,approved_by)
 VALUES(capital_id,s,ca,cash_wallet,'owner_injection',
  50000,'2026-04-04','Fictional start-up capital',
  'a0000000-0000-4000-8000-000000000001',actor_id);
 INSERT INTO public.ledger_journals(
  id,school_id,initiating_campus_id,accounting_period_id,period_month,
  journal_date,journal_kind,operation_id,explanation,posted_by)
 VALUES(jc,s,ca,pa,'2026-04-01','2026-04-04','capital_in',
  'a0000000-0000-4000-8000-000000000001',
  'Capital injection into Campus A cash',actor_id);
 INSERT INTO public.ledger_lines(
  school_id,campus_id,journal_id,ledger_account_id,debit_minor,credit_minor)
 VALUES
  (s,ca,jc,cash_account,50000,0),
  (s,ca,jc,equity_account,0,50000);
 INSERT INTO public.ledger_source_links(
  journal_id,school_id,journal_kind,capital_id)
 VALUES(jc,s,'capital_in',capital_id);

 -- CROSS-CAMPUS transfer: debit BANK B, credit CASH A; no revenue/expense.
 INSERT INTO public.account_transfers(
  id,school_id,from_account_id,to_account_id,amount_minor,
  transferred_on,reason,operation_id,approved_by,posted_by)
 VALUES(transfer_id,s,cash_wallet,bank_wallet,10000,
  '2026-04-05','Internal cross-campus cash transfer',
  'a0000000-0000-4000-8000-000000000002',actor_id,actor_id);
 INSERT INTO public.ledger_journals(
  id,school_id,initiating_campus_id,accounting_period_id,period_month,
  journal_date,journal_kind,operation_id,explanation,posted_by)
 VALUES(jt,s,ca,pa,'2026-04-01','2026-04-05','transfer',
  'a0000000-0000-4000-8000-000000000002',
  'Move money from Campus A cash to Campus B bank',actor_id);
 INSERT INTO public.ledger_lines(
  id,school_id,campus_id,journal_id,ledger_account_id,
  debit_minor,credit_minor)
 VALUES
  (bank_debit_line,s,cb,jt,bank_account,10000,0),
  (DEFAULT,s,ca,jt,cash_account,0,10000);
 INSERT INTO public.ledger_source_links(
  journal_id,school_id,journal_kind,transfer_id)
 VALUES(jt,s,'transfer',transfer_id);

 -- EXPENSE REQUEST is PENDING, NOT CASH. Once approved separately,
 -- create a distinct paid expense and its trusted balanced journal.
 INSERT INTO public.expense_categories(
  id,school_id,code,name,expense_kind)
 VALUES(category_id,s,'UTILITIES','Utilities','operating');
 INSERT INTO public.expense_requests(
  id,school_id,campus_id,category_id,expense_kind,
  requested_amount_minor,expense_date,purpose,requester_id,
  request_operation_id)
 VALUES(req_id,s,ca,category_id,'operating',
  6000,'2026-04-06','Electricity bill for fictional school',actor_id,
  'a0000000-0000-4000-8000-000000000003');
 IF (SELECT count(*) FROM public.expenses WHERE school_id=s)<>0 THEN
  RAISE EXCEPTION 'PENDING expense request incorrectly became a payment';
 END IF;
 UPDATE public.expense_requests SET
  status='approved',reviewed_by=actor_id,reviewed_at=now()
 WHERE id=req_id;
 INSERT INTO public.expenses(
  id,school_id,campus_id,category_id,expense_kind,request_id,
  financial_account_id,amount_minor,paid_on,operation_id,posted_by)
 VALUES(expense_id,s,ca,category_id,'operating',req_id,
  cash_wallet,6000,'2026-04-06',
  'a0000000-0000-4000-8000-000000000004',actor_id);
 INSERT INTO public.ledger_journals(
  id,school_id,initiating_campus_id,accounting_period_id,period_month,
  journal_date,journal_kind,operation_id,explanation,posted_by)
 VALUES(je,s,ca,pa,'2026-04-01','2026-04-06','expense_payment',
  'a0000000-0000-4000-8000-000000000004',
  'Fictional paid campus utilities',actor_id);
 INSERT INTO public.ledger_lines(
  school_id,campus_id,journal_id,ledger_account_id,debit_minor,credit_minor)
 VALUES
  (s,ca,je,expense_account,6000,0),
  (s,ca,je,cash_account,0,6000);
 INSERT INTO public.ledger_source_links(
  journal_id,school_id,journal_kind,expense_id)
 VALUES(je,s,'expense_payment',expense_id);

 -- Validate DEFERRED journal-balance and source-link constraint triggers.
 SET CONSTRAINTS ALL IMMEDIATE;

 SELECT sum(l.debit_minor-l.credit_minor) INTO cash_balance
 FROM public.ledger_lines l
 WHERE l.ledger_account_id=cash_account;
 SELECT sum(l.debit_minor-l.credit_minor) INTO bank_balance
 FROM public.ledger_lines l
 WHERE l.ledger_account_id=bank_account;
 SELECT coalesce(sum(l.credit_minor-l.debit_minor),0) INTO income_total
 FROM public.ledger_lines l
 WHERE l.ledger_account_id=income_account;
 IF cash_balance<>34000 OR bank_balance<>10000 OR income_total<>0 THEN
  RAISE EXCEPTION
    'Cashbook totals wrong: cash %, bank %, income %',
    cash_balance,bank_balance,income_total;
 END IF;

 -- Account scope must be checked by PostgreSQL, never filtered in Flutter.
 BEGIN
  INSERT INTO public.ledger_lines(
    school_id,campus_id,journal_id,ledger_account_id,debit_minor)
   VALUES(s,cb,jc,cash_account,1);
  RAISE EXCEPTION 'CROSS CAMPUS forged asset posting was accepted';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;

 -- A second journal cannot claim a source already paid by first journal.
 BEGIN
  INSERT INTO public.ledger_journals(
   school_id,initiating_campus_id,accounting_period_id,period_month,
   journal_date,journal_kind,operation_id,explanation,posted_by)
  VALUES(s,ca,pa,'2026-04-01','2026-04-07','transfer',
   'a0000000-0000-4000-8000-000000000005',
   'Duplicate source attack should fail',actor_id);
  INSERT INTO public.ledger_source_links(
   journal_id,school_id,journal_kind,transfer_id)
  SELECT id,s,'transfer',transfer_id
  FROM public.ledger_journals
  WHERE operation_id='a0000000-0000-4000-8000-000000000005';
  RAISE EXCEPTION 'Duplicate transfer source posted twice';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;

 -- Money cannot be altered/deleted after posting.
 BEGIN
  UPDATE public.ledger_lines SET debit_minor=80000
   WHERE id=bank_debit_line;
  RAISE EXCEPTION 'Posted ledger line was mutable';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 BEGIN
  DELETE FROM public.ledger_journals WHERE id=jc;
  RAISE EXCEPTION 'Posted journal deleted';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 BEGIN
  TRUNCATE public.financial_operation_receipts;
  RAISE EXCEPTION 'Financial operation receipts were truncated';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;

 -- CASH closing cannot finalize with unresolved offline sync.
 INSERT INTO public.cash_closings(
  id,school_id,campus_id,financial_account_id,closing_date,
  book_balance_minor,counted_minor,unresolved_sync_count,counted_by)
 VALUES(close_id,s,ca,cash_wallet,'2026-04-06',34000,34000,2,actor_id);
 INSERT INTO public.cash_closing_counts(
  school_id,campus_id,cash_closing_id,denomination_minor,piece_count)
 VALUES(s,ca,close_id,1000,34);
 BEGIN
  UPDATE public.cash_closings SET
   status='final',verified_by=actor_id,closed_at=now(),revision=2
   WHERE id=close_id;
  RAISE EXCEPTION 'Cash closing finalized despite PENDING SYNC';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
 UPDATE public.cash_closings SET
  status='final',verified_by=actor_id,closed_at=now(),
  unresolved_sync_count=0,revision=revision+1 WHERE id=close_id;
 IF (SELECT sum(subtotal_minor) FROM public.cash_closing_counts
      WHERE cash_closing_id=close_id)<>34000 THEN
  RAISE EXCEPTION 'Denomination count incorrect';
 END IF;
 BEGIN
  UPDATE public.cash_closings SET status='provisional',revision=revision+1
    WHERE id=close_id;
  RAISE EXCEPTION 'Final closing reopened';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;

 -- BANK reconciliation matches statement to ledger account movement.
 INSERT INTO public.bank_statement_lines(
  id,school_id,campus_id,bank_account_id,external_line_key,
  booked_on,inflow_minor,imported_by)
 VALUES(bank_line_id,s,cb,bank_wallet,'BANK-STMT-LINE-001',
  '2026-04-05',10000,actor_id);
 INSERT INTO public.bank_reconciliations(
  id,school_id,campus_id,bank_account_id,statement_end,
  book_balance_minor,statement_balance_minor,reconciled_by)
 VALUES(recon_id,s,cb,bank_wallet,'2026-04-30',10000,10000,actor_id);
 INSERT INTO public.bank_reconciliation_matches(
  school_id,bank_account_id,reconciliation_id,bank_statement_line_id,
  ledger_line_id,matched_by)
 VALUES(s,bank_wallet,recon_id,bank_line_id,bank_debit_line,actor_id);
 UPDATE public.bank_reconciliations
  SET status='final',approved_by=actor_id,approved_at=now()
  WHERE id=recon_id;
 BEGIN
  UPDATE public.bank_reconciliations
   SET status='draft',approved_by=NULL,approved_at=NULL WHERE id=recon_id;
  RAISE EXCEPTION 'Final bank reconciliation reopened';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;

 -- A closed period cannot accept new journal postings.
 UPDATE public.accounting_periods
  SET status='closed',approved_by=actor_id,closed_at=now()
  WHERE id=pb;
 BEGIN
  INSERT INTO public.ledger_journals(
   school_id,initiating_campus_id,accounting_period_id,period_month,
   journal_date,journal_kind,operation_id,explanation,posted_by)
  VALUES(s,cb,pb,'2026-04-01','2026-04-30','transfer',
   'a0000000-0000-4000-8000-000000000006',
   'Closed period should reject journal',actor_id);
  RAISE EXCEPTION 'New journal accepted in CLOSED period';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;

 -- Confirm 20 tables have RLS and ordinary clients cannot SELECT or post.
 SELECT count(*) INTO n FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='public' AND c.relname IN (
  'ledger_accounts','financial_accounts','expense_categories',
  'expense_requests','expenses','account_transfers','capital_transactions',
  'account_opening_entries','accounting_periods','ledger_journals',
  'ledger_lines','ledger_reversals','ledger_source_links','cash_closings',
  'cash_closing_counts','cash_closing_adjustments','bank_statement_lines',
  'bank_reconciliations','bank_reconciliation_matches',
  'financial_operation_receipts'
 ) AND c.relrowsecurity;
 IF n<>20 THEN
  RAISE EXCEPTION 'DB06 incomplete RLS: % of 20 enabled',n;
 END IF;
 IF pg_catalog.has_table_privilege('authenticated',
      'public.ledger_lines','INSERT')
  OR pg_catalog.has_table_privilege('authenticated',
      'public.financial_accounts','SELECT')
  OR pg_catalog.has_table_privilege('anon',
      'public.expenses','SELECT') THEN
  RAISE EXCEPTION 'Unsafe direct finance client grants';
 END IF;
END;
$fixture$;

\echo DB06 FICTIONAL ACCOUNTING SCHEMA/CONSTRAINTS PASSED — ROLLBACK
ROLLBACK;
