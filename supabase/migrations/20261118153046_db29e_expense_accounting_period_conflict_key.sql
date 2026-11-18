CREATE OR REPLACE FUNCTION app_private.sms_expense_payment(p_school uuid, p_campus uuid, p_request uuid, p_account uuid, p_amount_minor bigint, p_paid_on date, p_vendor text, p_reference text, p_operation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor uuid:=(select auth.uid());
 v_req record;v_acct record;v_debit uuid;v_period uuid;
 v_period_status text;v_month date;v_tz text;
 v_paid bigint;v_vendor text:=nullif(btrim(coalesce(p_vendor,'')),'');
 v_ref text:=nullif(btrim(coalesce(p_reference,'')),'');
 v_payload jsonb;v_previous jsonb;v_id uuid;v_journal uuid;v_result jsonb;
begin
 if not app_private.sms_expense_authorized(p_school,p_campus,'expenses.pay')
 then raise exception 'Expense payment permission required' using errcode='42501';end if;
 if p_operation is null or p_amount_minor is null or
  p_amount_minor<=0 or p_amount_minor>100000000000 or p_paid_on is null or
  (v_vendor is not null and length(v_vendor)>160) or
  (v_ref is not null and length(v_ref)>160)
 then raise exception 'Invalid expense payment details' using errcode='22023';end if;
 select timezone_name into v_tz from public.schools
 where id=p_school and status='active' for update;
 if v_tz is null or p_paid_on>(now() at time zone v_tz)::date
 then raise exception 'Payment date must be today or earlier'
 using errcode='22023';end if;
 v_payload:=jsonb_build_object('campus',p_campus,'request',p_request,
  'account',p_account,'amount',p_amount_minor,'date',p_paid_on,
  'vendor',v_vendor,'reference',v_ref);
 v_previous:=app_private.sms_expense_existing(p_school,p_operation,'payment',v_payload);
 if v_previous is not null then return v_previous;end if;
 select req.id,req.category_id,req.expense_kind,req.requested_amount_minor,
 req.expense_date,req.status
 into v_req from public.expense_requests req
 where req.id=p_request and req.school_id=p_school
   and req.campus_id=p_campus for update;
 if v_req.status is distinct from 'approved' then
 raise exception 'Expense must be approved by Owner before payment'
 using errcode='22023';end if;
 select a.id,a.account_kind,a.ledger_account_id,a.status into v_acct
 from public.financial_accounts a
 where a.id=p_account and a.school_id=p_school and a.campus_id=p_campus;
 if v_acct.status is distinct from 'active' or
   (v_acct.account_kind='bank' and length(coalesce(v_ref,''))<3)
 then raise exception 'Active account and bank reference required'
 using errcode='22023';end if;
 select coalesce(sum(amount_minor),0) into v_paid from public.expenses
 where request_id=p_request and school_id=p_school;
 if v_paid+p_amount_minor>v_req.requested_amount_minor
 then raise exception 'Payment exceeds approved remaining amount'
 using errcode='22023';end if;
 select ledger_account_id into v_debit
 from app_private.sms_expense_category_accounts
 where category_id=v_req.category_id and school_id=p_school;
 if v_debit is null then raise exception 'Missing expense ledger mapping'
 using errcode='22023';end if;
 v_month:=date_trunc('month',p_paid_on::timestamp)::date;
 if not exists(select 1 from public.academic_years y
 where y.school_id=p_school
 and p_paid_on between y.starts_on and y.ends_on)
 then raise exception 'Payment outside academic year' using errcode='22023';end if;
 insert into public.accounting_periods(school_id,campus_id,period_month,status)
 values(p_school,p_campus,v_month,'open')
 on conflict(campus_id,period_month) do nothing;
 select id,status into v_period,v_period_status from public.accounting_periods
 where school_id=p_school and campus_id=p_campus and period_month=v_month
 for update;
 if v_period_status is distinct from 'open'
 then raise exception 'Accounting period is closed' using errcode='22023';end if;

 insert into public.expenses(
  school_id,campus_id,category_id,expense_kind,request_id,
  financial_account_id,amount_minor,paid_on,vendor_name,
  external_reference,operation_id,posted_by)
 values(p_school,p_campus,v_req.category_id,v_req.expense_kind,p_request,
  p_account,p_amount_minor,p_paid_on,v_vendor,v_ref,p_operation,v_actor)
 returning id into v_id;
 insert into public.ledger_journals(
  school_id,initiating_campus_id,accounting_period_id,period_month,
  journal_date,journal_kind,operation_id,explanation,posted_by)
 values(p_school,p_campus,v_period,v_month,p_paid_on,
  'expense_payment',p_operation,'Expense request '||p_request::text,v_actor)
 returning id into v_journal;
 insert into public.ledger_lines(
  school_id,campus_id,journal_id,ledger_account_id,
  debit_minor,credit_minor,line_memo)
 values
 (p_school,p_campus,v_journal,v_debit,p_amount_minor,0,'Approved expense paid'),
 (p_school,p_campus,v_journal,v_acct.ledger_account_id,0,p_amount_minor,
 'Cash or bank paid');
 insert into public.ledger_source_links(
  journal_id,school_id,journal_kind,expense_id)
 values(v_journal,p_school,'expense_payment',v_id);
 v_result:=jsonb_build_object(
   'saved',true,'payment_id',v_id,'journal_id',v_journal,
   'request_id',p_request,'amount_minor',p_amount_minor,
   'remaining_minor',v_req.requested_amount_minor-v_paid-p_amount_minor);
 return app_private.sms_expense_record(
  p_school,p_operation,'payment',v_payload,v_result);
end;$function$
;
