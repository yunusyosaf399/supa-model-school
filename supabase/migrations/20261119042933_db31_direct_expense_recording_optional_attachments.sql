-- DB31: Expense records are saved immediately without Owner/Principal review.
-- Attachments remain optional. Payment is a separate permissioned, balanced journal.
-- Existing approved/rejected expenses and their audit history are preserved.
alter table public.expense_requests drop constraint expense_requests_status_check;
alter table public.expense_requests add constraint expense_requests_status_check
 check (status in ('pending','recorded','approved','rejected','cancelled'));
alter table public.expense_requests drop constraint expense_requests_check;
alter table public.expense_requests add constraint expense_requests_check check (
 (status in ('pending','cancelled') and reviewed_by is null and reviewed_at is null)
 or (status='recorded' and reviewed_by is null and reviewed_at is null
     and rejection_reason is null)
 or (status='approved' and reviewed_by is not null and reviewed_at is not null)
 or (status='rejected' and reviewed_by is not null and reviewed_at is not null
     and length(btrim(coalesce(rejection_reason,'')))>=4)
);

-- sms_expense_request
CREATE OR REPLACE FUNCTION app_private.sms_expense_request(p_school uuid, p_campus uuid, p_category uuid, p_amount_minor bigint, p_expense_date date, p_purpose text, p_operation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=(select auth.uid());v_kind text;v_tz text;
 v_payload jsonb;v_previous jsonb;v_id uuid;v_result jsonb;
 v_purpose text:=btrim(coalesce(p_purpose,''));
begin
 if not app_private.sms_expense_authorized(p_school,p_campus,'expenses.create')
 then raise exception 'Expense create permission required' using errcode='42501';end if;
 if p_operation is null or p_amount_minor is null or
  p_amount_minor<=0 or p_amount_minor>100000000000 or
  p_expense_date is null or length(v_purpose) not between 4 and 1000
 then raise exception 'Invalid expense details' using errcode='22023';end if;
 select timezone_name into v_tz from public.schools
 where id=p_school and status='active' for update;
 if v_tz is null or p_expense_date>(now() at time zone v_tz)::date
  or not exists(select 1 from public.academic_years y
    where y.school_id=p_school and p_expense_date between y.starts_on and y.ends_on)
 then raise exception 'Expense date outside school year or in the future'
  using errcode='22023';end if;
 select expense_kind into v_kind from public.expense_categories
 where id=p_category and school_id=p_school and is_active;
 if v_kind is null then raise exception 'Inactive or invalid category'
  using errcode='22023';end if;
 v_payload:=jsonb_build_object('campus',p_campus,'category',p_category,
 'amount',p_amount_minor,'date',p_expense_date,'purpose',v_purpose);
 v_previous:=app_private.sms_expense_existing(p_school,p_operation,'request',v_payload);
 if v_previous is not null then return v_previous;end if;
 insert into public.expense_requests(
 school_id,campus_id,category_id,expense_kind,requested_amount_minor,
 expense_date,purpose,status,requester_id,request_operation_id)
 values(p_school,p_campus,p_category,v_kind,p_amount_minor,p_expense_date,
 v_purpose,'recorded',v_actor,p_operation) returning id into v_id;
 v_result:=jsonb_build_object('saved',true,'request_id',v_id,'status','recorded');
 return app_private.sms_expense_record(p_school,p_operation,'request',v_payload,v_result);
end;$function$
;

-- sms_expense_payment
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
 if coalesce(v_req.status,'') not in ('recorded','approved') then
 raise exception 'Expense must be recorded before payment'
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
 then raise exception 'Payment exceeds remaining expense amount'
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
 (p_school,p_campus,v_journal,v_debit,p_amount_minor,0,'Recorded expense paid'),
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

-- sms_expense_evidence_can_upload
CREATE OR REPLACE FUNCTION app_private.sms_expense_evidence_can_upload(p_bucket text, p_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_parts text[]:=string_to_array(p_path,'/');
 v_school uuid;v_campus uuid;v_request uuid;v_payment uuid;
 v_actor uuid:=(select auth.uid());v_owner boolean;v_status text;
 v_requester uuid;
begin
 if p_bucket<>'sms-expense-evidence' or v_actor is null
 or array_length(v_parts,1)<>5
 or v_parts[1] !~* '^[a-f0-9-]{36}$'
 or v_parts[2] !~* '^[a-f0-9-]{36}$'
 or v_parts[3] !~* '^[a-f0-9-]{36}$'
 or v_parts[5] !~* '^[a-f0-9-]{36}\.(pdf|jpg|png|webp)$'
 then return false;end if;
 begin
  v_school:=v_parts[1]::uuid;v_campus:=v_parts[2]::uuid;
  v_request:=v_parts[3]::uuid;
  if v_parts[4]<>'request' then v_payment:=v_parts[4]::uuid;end if;
 exception when invalid_text_representation then return false;end;
 if not app_private.sms_expense_evidence_can_view(v_school,v_campus,v_request)
 then return false;end if;
 select status,requester_id into v_status,v_requester
 from public.expense_requests
 where id=v_request and school_id=v_school and campus_id=v_campus;
 if v_status not in ('pending','recorded','approved') then return false;end if;
 v_owner:=app_private.is_verified_school_owner(v_actor,v_school);
 if v_payment is null then
  return v_owner or app_private.sms_expense_authorized(
   v_school,v_campus,'expenses.pay') or (v_requester=v_actor
    and app_private.sms_expense_authorized(v_school,v_campus,'expenses.create'));
 end if;
 if v_status not in ('recorded','approved') or not exists(
  select 1 from public.expenses e where e.id=v_payment
   and e.school_id=v_school and e.campus_id=v_campus
   and e.request_id=v_request) then return false;end if;
 return v_owner or app_private.sms_expense_authorized(
  v_school,v_campus,'expenses.pay');
end;$function$
;

-- sms_expense_evidence_list
CREATE OR REPLACE FUNCTION app_private.sms_expense_evidence_list(p_school uuid, p_campus uuid, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_owner boolean;v_status text;
begin
 if not app_private.sms_expense_evidence_can_view(p_school,p_campus,p_request)
 then raise exception 'Expense documents not accessible' using errcode='42501';end if;
 select status into v_status from public.expense_requests
 where id=p_request and school_id=p_school and campus_id=p_campus;
 v_owner:=app_private.is_verified_school_owner((select auth.uid()),p_school);
 return jsonb_build_object(
 'is_owner',v_owner,'request_status',v_status,
 'can_upload_invoice',v_status in ('pending','recorded','approved') and
  (v_owner or app_private.sms_expense_authorized(p_school,p_campus,'expenses.pay')
   or exists(select 1 from public.expense_requests r where r.id=p_request
    and r.requester_id=(select auth.uid()) and
      app_private.sms_expense_authorized(p_school,p_campus,'expenses.create'))),
 'can_upload_receipt',v_status in ('recorded','approved') and
  (v_owner or app_private.sms_expense_authorized(p_school,p_campus,'expenses.pay')),
 'attachments',coalesce((select jsonb_agg(jsonb_build_object(
   'id',a.id,'kind',a.evidence_kind,'payment_id',a.payment_id,
   'file_name',a.file_name,'mime_type',a.mime_type,
   'bytes',a.file_size_bytes,'path',a.object_path,
   'status',a.review_status,'uploaded_at',a.uploaded_at,
   'reviewed_at',a.reviewed_at,'rejection_reason',a.rejection_reason,
   'uploaded_by',a.uploaded_by) order by a.uploaded_at desc,a.id desc)
   from public.expense_attachments a where a.school_id=p_school
    and a.campus_id=p_campus and a.request_id=p_request),'[]'::jsonb));
end;$function$
;

-- Retire legacy approval endpoints for ordinary authenticated users.
-- Review history remains intact; already recorded expenses cannot be reviewed.
revoke execute on function
 app_private.sms_expense_review(uuid,uuid,uuid,text,text,uuid),
 public.expense_review(uuid,uuid,uuid,text,text,uuid),
 app_private.sms_expense_evidence_review(uuid,uuid,uuid,text,text),
 public.expense_evidence_review(uuid,uuid,uuid,text,text)
from authenticated;


-- Staff permission labels must reflect direct expense recording.
update app_private.sms_permission_catalog
 set title='Post Expense Payments'
 where code='expenses.pay';
