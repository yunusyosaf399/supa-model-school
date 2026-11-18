-- DB29B: secure expense categories, campus cash/bank accounts,
-- request intake, Owner approval, and permission-scoped workspace.

create or replace function app_private.sms_expense_workspace(
 p_school uuid,p_campus uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_owner boolean;v_read boolean;v_create boolean;v_pay boolean;
v_currency text;v_tz text;
begin
 v_owner:=app_private.is_verified_school_owner((select auth.uid()),p_school);
 v_read:=app_private.sms_expense_authorized(p_school,p_campus,'expenses.read');
 v_create:=app_private.sms_expense_authorized(p_school,p_campus,'expenses.create');
 v_pay:=app_private.sms_expense_authorized(p_school,p_campus,'expenses.pay');
 if not (v_read or v_create or v_pay) then
  raise exception 'Expense module permission required' using errcode='42501';end if;
 select currency_code,timezone_name into v_currency,v_tz from public.schools
 where id=p_school and status='active';
 return jsonb_build_object(
 'school_id',p_school,'campus_id',p_campus,'currency',v_currency,'timezone',v_tz,
 'is_owner',v_owner,'can_create',v_create,'can_read',v_read,'can_pay',v_pay,
 'categories',coalesce((select jsonb_agg(jsonb_build_object(
   'id',cat.id,'code',cat.code,'name',cat.name,'kind',cat.expense_kind,
   'active',cat.is_active) order by cat.name)
 from public.expense_categories cat where cat.school_id=p_school),'[]'::jsonb),
 'accounts',coalesce((select jsonb_agg(jsonb_build_object(
    'id',a.id,'name',a.display_name,'method',a.account_kind,
    'status',a.status,'masked_reference',a.masked_reference)
    order by a.account_kind,a.display_name)
 from public.financial_accounts a
 where a.school_id=p_school and a.campus_id=p_campus),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(jsonb_build_object(
   'id',req.id,'category_id',req.category_id,'category',cat.name,
   'kind',req.expense_kind,'amount_minor',req.requested_amount_minor,
   'expense_date',req.expense_date,'purpose',req.purpose,'status',req.status,
   'requester_id',req.requester_id,'requested_at',req.requested_at,
   'reviewed_by',req.reviewed_by,'reviewed_at',req.reviewed_at,
   'rejection_reason',req.rejection_reason,
   'paid_minor',coalesce((select sum(e.amount_minor)
      from public.expenses e where e.request_id=req.id),0),
   'payments',coalesce((select jsonb_agg(jsonb_build_object(
     'id',e.id,'amount_minor',e.amount_minor,'paid_on',e.paid_on,
     'vendor',e.vendor_name,'reference',e.external_reference,
     'account_id',e.financial_account_id,'posted_at',e.posted_at)
     order by e.posted_at desc)
     from public.expenses e where e.request_id=req.id),'[]'::jsonb)
   ) order by req.requested_at desc,req.id desc)
 from (select * from public.expense_requests r
  where r.school_id=p_school and r.campus_id=p_campus
   and (v_read or v_pay or v_owner or r.requester_id=(select auth.uid()))
  order by r.requested_at desc,r.id desc limit 300) req
 join public.expense_categories cat on cat.id=req.category_id),'[]'::jsonb));
end;
$fn$;

create or replace function app_private.sms_expense_create_category(
 p_school uuid,p_code text,p_name text,p_kind text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
 v_code text:=upper(btrim(coalesce(p_code,'')));
 v_name text:=btrim(coalesce(p_name,''));v_payload jsonb;
 v_previous jsonb;v_category uuid;v_account uuid;v_result jsonb;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Owner-only category setup' using errcode='42501';end if;
 if p_operation is null or v_code !~ '^[A-Z][A-Z0-9_]{1,29}$'
  or length(v_name) not between 2 and 120
  or coalesce(p_kind,'') not in ('operating','inventory_procurement','capital_asset')
 then raise exception 'Invalid expense category details' using errcode='22023';end if;
 perform 1 from public.schools where id=p_school and status='active' for update;
 v_payload:=jsonb_build_object('code',v_code,'name',v_name,'kind',p_kind);
 v_previous:=app_private.sms_expense_existing(p_school,p_operation,'category',v_payload);
 if v_previous is not null then return v_previous;end if;
 insert into public.expense_categories(school_id,code,name,expense_kind)
 values(p_school,v_code,v_name,p_kind) returning id into v_category;
 insert into public.ledger_accounts(school_id,campus_id,code,name,account_type,account_scope)
 values(p_school,null,'SMSE_'||v_code,v_name,
  case when p_kind='operating' then 'expense' else 'asset' end,'school')
 returning id into v_account;
 insert into app_private.sms_expense_category_accounts(
 category_id,school_id,ledger_account_id,created_by)
 values(v_category,p_school,v_account,v_actor);
 v_result:=jsonb_build_object('saved',true,'category_id',v_category,
 'ledger_account_id',v_account);
 return app_private.sms_expense_record(p_school,p_operation,'category',v_payload,v_result);
end;$fn$;

create or replace function app_private.sms_expense_create_account(
 p_school uuid,p_campus uuid,p_name text,p_kind text,
 p_masked text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
 v_name text:=btrim(coalesce(p_name,''));
 v_masked text:=nullif(btrim(coalesce(p_masked,'')),'');
 v_tz text;v_payload jsonb;v_previous jsonb;v_ledger uuid;
 v_account uuid;v_result jsonb;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Owner-only account setup' using errcode='42501';end if;
 if p_operation is null or length(v_name) not between 2 and 160
  or coalesce(p_kind,'') not in ('cash','bank')
  or (v_masked is not null and length(v_masked) not between 4 and 20)
 then raise exception 'Invalid payment account details' using errcode='22023';end if;
 select timezone_name into v_tz from public.schools
 where id=p_school and status='active' for update;
 if v_tz is null or not exists(select 1 from public.campuses
 where id=p_campus and school_id=p_school and is_active)
 then raise exception 'Invalid campus' using errcode='42501';end if;
 v_payload:=jsonb_build_object('campus',p_campus,'name',v_name,
  'kind',p_kind,'masked',v_masked);
 v_previous:=app_private.sms_expense_existing(p_school,p_operation,'account',v_payload);
 if v_previous is not null then return v_previous;end if;
 insert into public.ledger_accounts(
 school_id,campus_id,code,name,account_type,account_scope)
 values(p_school,p_campus,'SMFA_'||upper(p_kind)||'_'||
  substr(replace(p_operation::text,'-',''),1,12),v_name,'asset','campus')
 returning id into v_ledger;
 insert into public.financial_accounts(
 school_id,campus_id,ledger_account_id,ledger_account_type,account_kind,
 display_name,masked_reference,opened_on,status,created_by)
 values(p_school,p_campus,v_ledger,'asset',p_kind,v_name,
 v_masked,(now() at time zone v_tz)::date,'active',v_actor)
 returning id into v_account;
 v_result:=jsonb_build_object('saved',true,'account_id',v_account);
 return app_private.sms_expense_record(p_school,p_operation,'account',v_payload,v_result);
end;$fn$;

create or replace function app_private.sms_expense_request(
 p_school uuid,p_campus uuid,p_category uuid,p_amount_minor bigint,
 p_expense_date date,p_purpose text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_kind text;v_tz text;
 v_payload jsonb;v_previous jsonb;v_id uuid;v_result jsonb;
 v_purpose text:=btrim(coalesce(p_purpose,''));
begin
 if not app_private.sms_expense_authorized(p_school,p_campus,'expenses.create')
 then raise exception 'Expense create permission required' using errcode='42501';end if;
 if p_operation is null or p_amount_minor is null or
  p_amount_minor<=0 or p_amount_minor>100000000000 or
  p_expense_date is null or length(v_purpose) not between 4 and 1000
 then raise exception 'Invalid expense request details' using errcode='22023';end if;
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
 v_purpose,'pending',v_actor,p_operation) returning id into v_id;
 v_result:=jsonb_build_object('saved',true,'request_id',v_id,'status','pending');
 return app_private.sms_expense_record(p_school,p_operation,'request',v_payload,v_result);
end;$fn$;

create or replace function app_private.sms_expense_review(
 p_school uuid,p_campus uuid,p_request uuid,p_decision text,
 p_reason text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
 v_payload jsonb;v_previous jsonb;v_status text;v_result jsonb;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Owner approval required' using errcode='42501';end if;
 if p_operation is null or coalesce(p_decision,'') not in ('approved','rejected')
  or (p_decision='rejected' and length(coalesce(v_reason,''))<4)
 then raise exception 'Invalid expense review' using errcode='22023';end if;
 if p_decision='approved' then v_reason:=null;end if;
 perform 1 from public.schools where id=p_school and status='active' for update;
 v_payload:=jsonb_build_object('campus',p_campus,'request',p_request,
 'decision',p_decision,'reason',v_reason);
 v_previous:=app_private.sms_expense_existing(p_school,p_operation,'review',v_payload);
 if v_previous is not null then return v_previous;end if;
 select status into v_status from public.expense_requests
 where id=p_request and school_id=p_school and campus_id=p_campus for update;
 if v_status is distinct from 'pending' then
 raise exception 'Only pending expense requests may be reviewed'
 using errcode='22023';end if;
 update public.expense_requests set
 status=p_decision,reviewed_by=v_actor,reviewed_at=now(),rejection_reason=v_reason
 where id=p_request;
 v_result:=jsonb_build_object('saved',true,'request_id',p_request,'status',p_decision);
 return app_private.sms_expense_record(p_school,p_operation,'review',v_payload,v_result);
end;$fn$;

create or replace function public.expense_workspace(p_school uuid,p_campus uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.sms_expense_workspace(p_school,p_campus);$fn$;
create or replace function public.expense_create_category(
 p_school uuid,p_code text,p_name text,p_kind text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_expense_create_category(
 p_school,p_code,p_name,p_kind,p_operation);$fn$;
create or replace function public.expense_create_account(
 p_school uuid,p_campus uuid,p_name text,p_kind text,p_masked text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_expense_create_account(
 p_school,p_campus,p_name,p_kind,p_masked,p_operation);$fn$;
create or replace function public.expense_request(
 p_school uuid,p_campus uuid,p_category uuid,p_amount_minor bigint,
 p_expense_date date,p_purpose text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_expense_request(
 p_school,p_campus,p_category,p_amount_minor,p_expense_date,p_purpose,p_operation);$fn$;
create or replace function public.expense_review(
 p_school uuid,p_campus uuid,p_request uuid,p_decision text,
 p_reason text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_expense_review(
 p_school,p_campus,p_request,p_decision,p_reason,p_operation);$fn$;

revoke all on function
 app_private.sms_expense_workspace(uuid,uuid),
 app_private.sms_expense_create_category(uuid,text,text,text,uuid),
 app_private.sms_expense_create_account(uuid,uuid,text,text,text,uuid),
 app_private.sms_expense_request(uuid,uuid,uuid,bigint,date,text,uuid),
 app_private.sms_expense_review(uuid,uuid,uuid,text,text,uuid),
 public.expense_workspace(uuid,uuid),
 public.expense_create_category(uuid,text,text,text,uuid),
 public.expense_create_account(uuid,uuid,text,text,text,uuid),
 public.expense_request(uuid,uuid,uuid,bigint,date,text,uuid),
 public.expense_review(uuid,uuid,uuid,text,text,uuid)
 from public,anon,authenticated;
grant execute on function
 app_private.sms_expense_workspace(uuid,uuid),
 app_private.sms_expense_create_category(uuid,text,text,text,uuid),
 app_private.sms_expense_create_account(uuid,uuid,text,text,text,uuid),
 app_private.sms_expense_request(uuid,uuid,uuid,bigint,date,text,uuid),
 app_private.sms_expense_review(uuid,uuid,uuid,text,text,uuid),
 public.expense_workspace(uuid,uuid),
 public.expense_create_category(uuid,text,text,text,uuid),
 public.expense_create_account(uuid,uuid,text,text,text,uuid),
 public.expense_request(uuid,uuid,uuid,bigint,date,text,uuid),
 public.expense_review(uuid,uuid,uuid,text,text,uuid)
 to authenticated;
