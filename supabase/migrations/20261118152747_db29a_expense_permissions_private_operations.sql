-- DB29A: permission catalog and private expense operation infrastructure.
alter table public.expense_categories
 add constraint db29_expense_category_school_key unique(id,school_id);

insert into app_private.sms_permission_catalog(code,section,title,action,is_implemented)
 values('expenses.pay','Expenses','Post Approved Expense Payments','update',true)
 on conflict(code) do update set is_implemented=true,title=excluded.title;
update app_private.sms_permission_catalog
 set is_implemented=true
 where code in ('expenses.read','expenses.create','expenses.review');

create table app_private.sms_expense_category_accounts (
 category_id uuid primary key,
 school_id uuid not null references public.schools(id),
 ledger_account_id uuid not null,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 foreign key(category_id,school_id) references public.expense_categories(id,school_id),
 foreign key(ledger_account_id,school_id) references public.ledger_accounts(id,school_id),
 unique(school_id,category_id)
);
create table app_private.sms_expense_operations (
 school_id uuid not null references public.schools(id),
 operation_id uuid not null,
 action text not null check(action in ('category','account','request','review','payment')),
 actor_id uuid not null references auth.users(id),
 request_hash bytea not null check(octet_length(request_hash)=32),
 result_json jsonb not null check(jsonb_typeof(result_json)='object'),
 posted_at timestamptz not null default now(),
 primary key(school_id,operation_id)
);
alter table app_private.sms_expense_category_accounts enable row level security;
alter table app_private.sms_expense_operations enable row level security;
revoke all on app_private.sms_expense_category_accounts,
 app_private.sms_expense_operations from public,anon,authenticated;

create or replace function app_private.sms_expense_authorized(
 p_school uuid,p_campus uuid,p_action text)
returns boolean language sql stable security definer set search_path=''
as $fn$
 select p_action in ('expenses.read','expenses.create','expenses.pay') and
 exists(select 1 from public.campuses c join public.schools s on s.id=c.school_id
  where c.id=p_campus and c.school_id=p_school
    and c.is_active and s.status='active')
 and (app_private.is_verified_school_owner((select auth.uid()),p_school)
 or (exists(select 1 from public.user_roles r
   where r.user_id=(select auth.uid()) and r.school_id=p_school
   and r.campus_id=p_campus and r.is_active
   and r.role in ('principal','admin','accountant','teacher'))
 and app_private.sms_permission_allowed(p_school,p_campus,p_action)));
$fn$;

create or replace function app_private.sms_expense_existing(
 p_school uuid,p_operation uuid,p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_row app_private.sms_expense_operations%rowtype;
begin
 select * into v_row from app_private.sms_expense_operations
 where school_id=p_school and operation_id=p_operation;
 if not found then return null;end if;
 if v_row.actor_id is distinct from (select auth.uid())
  or v_row.action<>p_action
  or v_row.request_hash<>pg_catalog.sha256(pg_catalog.convert_to(p_payload::text,'UTF8'))
 then raise exception 'Operation reused with changed details'
   using errcode='22023';end if;
 return v_row.result_json;
end;$fn$;

create or replace function app_private.sms_expense_record(
 p_school uuid,p_operation uuid,p_action text,p_payload jsonb,p_result jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
begin
 insert into app_private.sms_expense_operations(
  school_id,operation_id,action,actor_id,request_hash,result_json)
 values(p_school,p_operation,p_action,(select auth.uid()),
  pg_catalog.sha256(pg_catalog.convert_to(p_payload::text,'UTF8')),p_result);
 return p_result;
end;$fn$;

-- Internal helpers are only used by trusted private expense functions.
revoke all on function
 app_private.sms_expense_authorized(uuid,uuid,text),
 app_private.sms_expense_existing(uuid,uuid,text,jsonb),
 app_private.sms_expense_record(uuid,uuid,text,jsonb,jsonb)
 from public,anon,authenticated;
