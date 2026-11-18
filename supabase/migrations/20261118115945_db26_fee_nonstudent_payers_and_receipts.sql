-- DB26: receipts and charge ledger for non-student payers.
-- Separate from student fees to preserve the existing student foreign keys.
create table app_private.sms_fee_other_people (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 campus_id uuid not null references public.campuses(id),
 display_name text not null check (length(btrim(display_name)) between 2 and 120),
 contact text check (contact is null or length(contact) between 3 and 80),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(id,school_id,campus_id)
);
create table app_private.sms_fee_other_charges (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 campus_id uuid not null references public.campuses(id),
 academic_year_id uuid not null references public.academic_years(id),
 person_id uuid not null,
 category_id uuid not null references public.fee_categories(id),
 gross_minor bigint not null check(gross_minor>0 and gross_minor<=100000000000),
 due_on date not null,
 memo text not null check(length(btrim(memo)) between 3 and 500),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 operation_id uuid not null unique,
 foreign key(person_id,school_id,campus_id)
   references app_private.sms_fee_other_people(id,school_id,campus_id),
 unique(id,school_id,campus_id,academic_year_id,person_id)
);
create table app_private.sms_fee_other_receipts (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 campus_id uuid not null references public.campuses(id),
 academic_year_id uuid not null references public.academic_years(id),
 person_id uuid not null,
 receipt_no text not null,
 amount_minor bigint not null check(amount_minor>0),
 method text not null check(method in ('cash','bank')),
 bank_reference text,
 issued_by uuid not null references auth.users(id),
 issued_at timestamptz not null default now(),
 operation_id uuid not null unique,
 foreign key(person_id,school_id,campus_id)
   references app_private.sms_fee_other_people(id,school_id,campus_id),
 unique(id,school_id,campus_id,academic_year_id,person_id),
 unique(school_id,receipt_no),
 check(method<>'bank' or length(btrim(coalesce(bank_reference,'')))>=3)
);
create table app_private.sms_fee_other_allocations (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 campus_id uuid not null references public.campuses(id),
 academic_year_id uuid not null references public.academic_years(id),
 person_id uuid not null,
 charge_id uuid not null,
 receipt_id uuid not null,
 amount_minor bigint not null check(amount_minor>0),
 created_at timestamptz not null default now(),
 foreign key(charge_id,school_id,campus_id,academic_year_id,person_id)
   references app_private.sms_fee_other_charges(
      id,school_id,campus_id,academic_year_id,person_id),
 foreign key(receipt_id,school_id,campus_id,academic_year_id,person_id)
   references app_private.sms_fee_other_receipts(
      id,school_id,campus_id,academic_year_id,person_id),
 unique(receipt_id,charge_id)
);
create table app_private.sms_fee_other_operations (
 school_id uuid not null references public.schools(id),
 operation_id uuid not null,
 action text not null check(action in ('person','charge','receipt')),
 actor_id uuid not null references auth.users(id),
 request_hash bytea not null check(octet_length(request_hash)=32),
 result_json jsonb not null check(jsonb_typeof(result_json)='object'),
 created_at timestamptz not null default now(),
 primary key(school_id,operation_id)
);
create index sms_fee_other_payer_idx
 on app_private.sms_fee_other_charges(school_id,campus_id,academic_year_id,person_id);
create index sms_fee_other_alloc_charge_idx
 on app_private.sms_fee_other_allocations(charge_id);

alter table app_private.sms_fee_other_people enable row level security;
alter table app_private.sms_fee_other_charges enable row level security;
alter table app_private.sms_fee_other_receipts enable row level security;
alter table app_private.sms_fee_other_allocations enable row level security;
alter table app_private.sms_fee_other_operations enable row level security;
revoke all on app_private.sms_fee_other_people,
 app_private.sms_fee_other_charges,
 app_private.sms_fee_other_receipts,
 app_private.sms_fee_other_allocations,
 app_private.sms_fee_other_operations from public,anon,authenticated;

create trigger sms_fee_other_charge_immutable before update or delete
 on app_private.sms_fee_other_charges for each row
 execute function app_private.db03_reject_posted_mutation();
create trigger sms_fee_other_receipt_immutable before update or delete
 on app_private.sms_fee_other_receipts for each row
 execute function app_private.db03_reject_posted_mutation();
create trigger sms_fee_other_allocation_immutable before update or delete
 on app_private.sms_fee_other_allocations for each row
 execute function app_private.db03_reject_posted_mutation();

create or replace function app_private.sms_fee_other_people_snapshot(
 p_school uuid,p_campus uuid,p_year uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_people jsonb;v_categories jsonb;v_currency text;
begin
 if not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.read')
 then raise exception 'Fee read permission required' using errcode='42501';end if;
 if not exists(select 1 from public.academic_years y
 where y.id=p_year and y.school_id=p_school)
 then raise exception 'Invalid year' using errcode='22023';end if;
 select currency_code into v_currency from public.schools where id=p_school;
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',fc.id,'code',fc.code,'name',fc.name,
   'frequency',fc.charge_frequency) order by fc.name),'[]'::jsonb)
 into v_categories from public.fee_categories fc
 where fc.school_id=p_school and fc.is_active;

 select coalesce(jsonb_agg(jsonb_build_object(
   'id',p.id,'name',p.display_name,'contact',p.contact,
   'charges',coalesce((select jsonb_agg(jsonb_build_object(
       'id',ch.id,'category_id',ch.category_id,'category',fc.name,
       'frequency',fc.charge_frequency,'amount_minor',ch.gross_minor,
       'due_on',ch.due_on,'memo',ch.memo,
       'paid_minor',coalesce((select sum(a.amount_minor)
          from app_private.sms_fee_other_allocations a
          where a.charge_id=ch.id),0),
       'outstanding_minor',ch.gross_minor-coalesce(
          (select sum(a.amount_minor)
          from app_private.sms_fee_other_allocations a
          where a.charge_id=ch.id),0)
      ) order by ch.due_on,ch.created_at)
     from app_private.sms_fee_other_charges ch
     join public.fee_categories fc on fc.id=ch.category_id
     where ch.person_id=p.id and ch.school_id=p_school
       and ch.campus_id=p_campus and ch.academic_year_id=p_year),
       '[]'::jsonb),
   'receipts',coalesce((select jsonb_agg(jsonb_build_object(
       'id',r.id,'number',r.receipt_no,'amount_minor',r.amount_minor,
       'method',r.method,'issued_at',r.issued_at)
       order by r.issued_at desc)
       from app_private.sms_fee_other_receipts r
       where r.person_id=p.id and r.school_id=p_school
        and r.campus_id=p_campus and r.academic_year_id=p_year),
       '[]'::jsonb)
   ) order by p.display_name,p.id),'[]'::jsonb)
 into v_people from app_private.sms_fee_other_people p
 where p.school_id=p_school and p.campus_id=p_campus;
 return jsonb_build_object(
   'school_id',p_school,'campus_id',p_campus,'year_id',p_year,
   'currency',v_currency,'people',v_people,'categories',v_categories,
   'can_collect',app_private.sms_fee_role_authorized(
     p_school,p_campus,'fees.update'));
end;
$fn$;

create or replace function app_private.sms_fee_other_person_create(
 p_school uuid,p_campus uuid,p_name text,p_contact text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_hash bytea;v_request jsonb;
v_old record;v_id uuid;v_result jsonb;v_contact text:=nullif(btrim(coalesce(p_contact,'')),'');
begin
 if not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.update')
 then raise exception 'Fee write access required' using errcode='42501';end if;
 if p_operation is null or length(btrim(coalesce(p_name,''))) not between 2 and 120
    or (v_contact is not null and length(v_contact) not between 3 and 80)
 then raise exception 'Invalid person details' using errcode='22023';end if;
 perform 1 from public.campuses where id=p_campus and school_id=p_school for update;
 v_request:=jsonb_build_object('name',btrim(p_name),'contact',v_contact,'campus',p_campus);
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
 select * into v_old from app_private.sms_fee_other_operations
   where school_id=p_school and operation_id=p_operation;
 if found then
  if v_old.actor_id<>v_actor or v_old.action<>'person' or v_old.request_hash<>v_hash
   then raise exception 'Operation reused' using errcode='22023';end if;
  return v_old.result_json;
 end if;
 insert into app_private.sms_fee_other_people(
   school_id,campus_id,display_name,contact,created_by)
 values(p_school,p_campus,btrim(p_name),v_contact,v_actor) returning id into v_id;
 v_result:=jsonb_build_object('saved',true,'person_id',v_id);
 insert into app_private.sms_fee_other_operations(
   school_id,operation_id,action,actor_id,request_hash,result_json)
 values(p_school,p_operation,'person',v_actor,v_hash,v_result);
 return v_result;
end;
$fn$;

create or replace function app_private.sms_fee_other_post_charge(
 p_school uuid,p_campus uuid,p_year uuid,p_person uuid,p_category uuid,
 p_amount_minor bigint,p_due_on date,p_note text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_hash bytea;v_request jsonb;
v_old record;v_id uuid;v_result jsonb;v_yr record;
begin
 if not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.update')
 then raise exception 'Fee write access required' using errcode='42501';end if;
 select starts_on,ends_on into v_yr from public.academic_years
   where id=p_year and school_id=p_school;
 if v_yr.starts_on is null or p_due_on is null or
   p_due_on not between v_yr.starts_on and v_yr.ends_on
   or p_amount_minor is null or p_amount_minor<=0 or p_amount_minor>100000000000
   or length(btrim(coalesce(p_note,''))) not between 3 and 500
   or p_operation is null or not exists(
     select 1 from app_private.sms_fee_other_people p
     where p.id=p_person and p.school_id=p_school and p.campus_id=p_campus)
   or not exists(select 1 from public.fee_categories fc
     where fc.id=p_category and fc.school_id=p_school and fc.is_active)
 then raise exception 'Invalid person, category, amount or date'
   using errcode='22023';end if;
 perform 1 from public.campuses where id=p_campus and school_id=p_school for update;
 v_request:=jsonb_build_object('campus',p_campus,'year',p_year,
  'person',p_person,'category',p_category,'amount',p_amount_minor,
  'due',p_due_on,'note',btrim(p_note));
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
 select * into v_old from app_private.sms_fee_other_operations
   where school_id=p_school and operation_id=p_operation;
 if found then
  if v_old.actor_id<>v_actor or v_old.action<>'charge' or v_old.request_hash<>v_hash
   then raise exception 'Operation reused' using errcode='22023';end if;
  return v_old.result_json;
 end if;
 insert into app_private.sms_fee_other_charges(
   school_id,campus_id,academic_year_id,person_id,category_id,
   gross_minor,due_on,memo,created_by,operation_id)
 values(p_school,p_campus,p_year,p_person,p_category,p_amount_minor,
   p_due_on,btrim(p_note),v_actor,p_operation) returning id into v_id;
 v_result:=jsonb_build_object('saved',true,'charge_id',v_id,'amount_minor',p_amount_minor);
 insert into app_private.sms_fee_other_operations(
  school_id,operation_id,action,actor_id,request_hash,result_json)
 values(p_school,p_operation,'charge',v_actor,v_hash,v_result);
 return v_result;
end;
$fn$;

create or replace function app_private.sms_fee_other_collect(
 p_school uuid,p_campus uuid,p_year uuid,p_person uuid,p_amount_minor bigint,
 p_method text,p_bank_ref text,p_lines jsonb,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_bank text:=nullif(btrim(coalesce(p_bank_ref,'')),'');
v_hash bytea;v_request jsonb;v_old record;v_result jsonb;
v_line jsonb;v_charge uuid;v_minor bigint;v_owed bigint;v_total bigint:=0;
v_serial bigint;v_no text;v_receipt uuid;
begin
 if not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.update')
 then raise exception 'Fee collection permission required' using errcode='42501';end if;
 if p_operation is null or p_amount_minor is null or p_amount_minor<=0
  or p_amount_minor>100000000000 or p_method not in ('cash','bank')
  or (p_method='bank' and length(coalesce(v_bank,''))<3)
  or jsonb_typeof(p_lines)<>'array'
  or jsonb_array_length(p_lines) not between 1 and 150
  or not exists(select 1 from app_private.sms_fee_other_people p
    where p.id=p_person and p.school_id=p_school and p.campus_id=p_campus)
  or not exists(select 1 from public.academic_years y
    where y.id=p_year and y.school_id=p_school)
 then raise exception 'Invalid collection request' using errcode='22023';end if;
 if p_method='cash' then v_bank:=null;end if;
 perform 1 from public.campuses where id=p_campus and school_id=p_school for update;
 v_request:=jsonb_build_object('campus',p_campus,'year',p_year,'person',p_person,
  'amount',p_amount_minor,'method',p_method,'bank',v_bank,'lines',p_lines);
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
 select * into v_old from app_private.sms_fee_other_operations
 where school_id=p_school and operation_id=p_operation;
 if found then
   if v_old.actor_id<>v_actor or v_old.action<>'receipt' or v_old.request_hash<>v_hash
   then raise exception 'Operation reused with changed details'
    using errcode='22023';end if;
   return v_old.result_json;
 end if;
 if exists(select 1 from jsonb_array_elements(p_lines) x
   group by x->>'charge_id' having count(*)>1)
 then raise exception 'Duplicate charge allocation' using errcode='22023';end if;
 for v_line in select value from jsonb_array_elements(p_lines) x(value) loop
   begin
     v_charge:=(v_line->>'charge_id')::uuid;
     v_minor:=(v_line->>'amount_minor')::bigint;
   exception when invalid_text_representation or numeric_value_out_of_range
   then raise exception 'Invalid allocation line' using errcode='22023';end;
   if v_minor is null or v_minor<=0 then
     raise exception 'Allocation must be positive' using errcode='22023';end if;
   select ch.gross_minor-coalesce(
      (select sum(a.amount_minor) from app_private.sms_fee_other_allocations a
       where a.charge_id=ch.id),0) into v_owed
   from app_private.sms_fee_other_charges ch
   where ch.id=v_charge and ch.person_id=p_person and ch.school_id=p_school
     and ch.campus_id=p_campus and ch.academic_year_id=p_year
   for update;
   if v_owed is null or v_minor>v_owed then
     raise exception 'Allocation exceeds person charge balance'
       using errcode='22023';end if;
   v_total:=v_total+v_minor;
   if v_total>p_amount_minor then
     raise exception 'Allocation exceeds payment amount' using errcode='22023';end if;
 end loop;
 if v_total<>p_amount_minor then
   raise exception 'All received funds must be allocated' using errcode='22023';end if;
 insert into public.fee_receipt_counters(school_id,next_serial)
 values(p_school,2)
 on conflict(school_id) do update
 set next_serial=public.fee_receipt_counters.next_serial+1
 returning next_serial-1 into v_serial;
 v_no:='SMS-'||lpad(v_serial::text,9,'0');
 insert into app_private.sms_fee_other_receipts(
  school_id,campus_id,academic_year_id,person_id,receipt_no,
  amount_minor,method,bank_reference,issued_by,operation_id)
 values(p_school,p_campus,p_year,p_person,v_no,
  p_amount_minor,p_method,v_bank,v_actor,p_operation) returning id into v_receipt;
 for v_line in select value from jsonb_array_elements(p_lines) x(value) loop
  insert into app_private.sms_fee_other_allocations(
   school_id,campus_id,academic_year_id,person_id,charge_id,receipt_id,amount_minor)
  values(p_school,p_campus,p_year,p_person,(v_line->>'charge_id')::uuid,
   v_receipt,(v_line->>'amount_minor')::bigint);
 end loop;
 v_result:=jsonb_build_object('saved',true,'receipt_id',v_receipt,
   'receipt_no',v_no,'amount_minor',p_amount_minor);
 insert into app_private.sms_fee_other_operations(
   school_id,operation_id,action,actor_id,request_hash,result_json)
 values(p_school,p_operation,'receipt',v_actor,v_hash,v_result);
 return v_result;
end;
$fn$;

create or replace function public.fee_other_people_snapshot(
 p_school uuid,p_campus uuid,p_year uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.sms_fee_other_people_snapshot(p_school,p_campus,p_year);$fn$;
create or replace function public.fee_other_person_create(
 p_school uuid,p_campus uuid,p_name text,p_contact text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_fee_other_person_create(
  p_school,p_campus,p_name,p_contact,p_operation);$fn$;
create or replace function public.fee_other_post_charge(
 p_school uuid,p_campus uuid,p_year uuid,p_person uuid,p_category uuid,
 p_amount_minor bigint,p_due_on date,p_note text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_fee_other_post_charge(
  p_school,p_campus,p_year,p_person,p_category,p_amount_minor,
  p_due_on,p_note,p_operation);$fn$;
create or replace function public.fee_other_collect(
 p_school uuid,p_campus uuid,p_year uuid,p_person uuid,p_amount_minor bigint,
 p_method text,p_bank_ref text,p_lines jsonb,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_fee_other_collect(
  p_school,p_campus,p_year,p_person,p_amount_minor,p_method,
  p_bank_ref,p_lines,p_operation);$fn$;

revoke all on function
 app_private.sms_fee_other_people_snapshot(uuid,uuid,uuid),
 app_private.sms_fee_other_person_create(uuid,uuid,text,text,uuid),
 app_private.sms_fee_other_post_charge(uuid,uuid,uuid,uuid,uuid,bigint,date,text,uuid),
 app_private.sms_fee_other_collect(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,uuid),
 public.fee_other_people_snapshot(uuid,uuid,uuid),
 public.fee_other_person_create(uuid,uuid,text,text,uuid),
 public.fee_other_post_charge(uuid,uuid,uuid,uuid,uuid,bigint,date,text,uuid),
 public.fee_other_collect(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,uuid)
from public,anon,authenticated;
grant execute on function
 app_private.sms_fee_other_people_snapshot(uuid,uuid,uuid),
 app_private.sms_fee_other_person_create(uuid,uuid,text,text,uuid),
 app_private.sms_fee_other_post_charge(uuid,uuid,uuid,uuid,uuid,bigint,date,text,uuid),
 app_private.sms_fee_other_collect(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,uuid),
 public.fee_other_people_snapshot(uuid,uuid,uuid),
 public.fee_other_person_create(uuid,uuid,text,text,uuid),
 public.fee_other_post_charge(uuid,uuid,uuid,uuid,uuid,bigint,date,text,uuid),
 public.fee_other_collect(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,uuid)
to authenticated;
