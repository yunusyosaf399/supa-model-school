-- DB18: Campus/year scoped monthly billing, category-specific scholarship,
-- exact cash/bank receipt allocation, and live finance summary.
-- Owner-only. Privileged functions stay in unexposed app_private schema.
-- Immutable posted charges/receipts/allocations remain immutable.
create table if not exists app_private.sms_fee_discount_audit(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 campus_id uuid not null references public.campuses(id),
 student_id uuid not null references public.students(id),
 actor_id uuid not null references auth.users(id),
 discount_id uuid not null references public.fee_discounts(id),
 action text not null,
 happened_at timestamptz not null default now()
);
alter table app_private.sms_fee_discount_audit enable row level security;
revoke all on app_private.sms_fee_discount_audit from public,anon,authenticated;

create or replace function app_private.owner_fee_monthly_ledger(
 p_school uuid,p_campus uuid,p_year uuid,p_month date)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_year public.academic_years%rowtype;
v_students jsonb;v_receipts jsonb;v_categories jsonb;
v_charged bigint;v_paid bigint;v_outstanding bigint;v_received bigint;
begin
 if not app_private.is_verified_school_owner((select auth.uid()),p_school)
 or not exists(select 1 from public.campuses c where c.id=p_campus
   and c.school_id=p_school and c.is_active) then
   raise exception 'Verified school Owner and campus required' using errcode='42501';
 end if;
 select * into v_year from public.academic_years y
   where y.id=p_year and y.school_id=p_school;
 if v_year.id is null or p_month is null
   or p_month<>date_trunc('month',p_month)::date
   or p_month<date_trunc('month',v_year.starts_on)::date
   or p_month>date_trunc('month',v_year.ends_on)::date
 then raise exception 'Invalid billing month or academic year'
   using errcode='22023';end if;

 select coalesce(sum(c.net_minor),0)::bigint into v_charged
 from public.fee_charges c where c.school_id=p_school
 and c.campus_id=p_campus and c.academic_year_id=p_year
 and c.billing_month=p_month;

 select coalesce(sum(a.amount_minor),0)::bigint into v_paid
 from public.fee_allocations a join public.fee_charges c
   on c.id=a.charge_id and c.school_id=a.school_id and c.student_id=a.student_id
 where c.school_id=p_school and c.campus_id=p_campus
 and c.academic_year_id=p_year and c.billing_month=p_month;

 select coalesce(sum(c.net_minor -
  coalesce((select sum(a.amount_minor) from public.fee_allocations a
            where a.charge_id=c.id),0)),0)::bigint into v_outstanding
 from public.fee_charges c where c.school_id=p_school
 and c.campus_id=p_campus and c.academic_year_id=p_year;

 select coalesce(sum(r.amount_minor),0)::bigint into v_received
 from public.fee_receipts r
 where r.school_id=p_school and r.collection_campus_id=p_campus
   and r.issued_at>=p_month::timestamptz
   and r.issued_at<(p_month+interval '1 month')::timestamptz;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',e.student_id,'enrollment_id',e.id,
  'registration',st.registration_no,'name',st.full_name_en,
  'class_name',cl.name,'active',st.active_status='active',
  'charged_minor',coalesce((select sum(c.net_minor) from public.fee_charges c
   where c.enrollment_id=e.id and c.billing_month=p_month),0),
  'paid_minor',coalesce((select sum(a.amount_minor)
   from public.fee_allocations a join public.fee_charges c on c.id=a.charge_id
   where c.enrollment_id=e.id and c.billing_month=p_month),0),
  'outstanding_minor',coalesce((select sum(c.net_minor-
     coalesce((select sum(a.amount_minor) from public.fee_allocations a
      where a.charge_id=c.id),0))
    from public.fee_charges c where c.enrollment_id=e.id
      and c.academic_year_id=p_year),0)
 ) order by cl.sort_order,st.full_name_en,e.id),'[]'::jsonb)
 into v_students
 from public.student_enrollments e
 join public.students st on st.id=e.student_id and st.school_id=e.school_id
 join public.classes cl on cl.id=e.class_id and cl.campus_id=e.campus_id
 where e.school_id=p_school and e.campus_id=p_campus
   and e.academic_year_id=p_year and
   e.admitted_on<(p_month+interval '1 month')::date
   and (e.ended_on is null or e.ended_on>=p_month);

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',fc.id,'code',fc.code,'name',fc.name,
  'frequency',fc.charge_frequency,'discountable',fc.is_discountable)
  order by fc.name),'[]'::jsonb) into v_categories
 from public.fee_categories fc where fc.school_id=p_school and fc.is_active;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.id,'number',q.receipt_no,'student_id',q.student_id,
  'name',q.student_name,'amount_minor',q.amount_minor,
  'method',q.payment_method,'issued_at',q.issued_at)
  order by q.issued_at desc,q.id desc),'[]'::jsonb)
 into v_receipts
 from (select r.*,st.full_name_en as student_name
 from public.fee_receipts r
 join public.students st on st.id=r.student_id and st.school_id=r.school_id
 where r.school_id=p_school and r.collection_campus_id=p_campus
 order by r.issued_at desc,r.id desc limit 15) q;

 return jsonb_build_object('school_id',p_school,'campus_id',p_campus,
 'year_id',p_year,'year_label',v_year.label,'month',p_month,
 'currency',(select s.currency_code from public.schools s where s.id=p_school),
 'charged_minor',v_charged,'paid_minor',v_paid,'outstanding_minor',v_outstanding,
 'received_minor',v_received,'students',v_students,
 'categories',v_categories,'recent_receipts',v_receipts);
end;
$fn$;

create or replace function app_private.owner_fee_student_statement(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_charges jsonb;v_receipts jsonb;v_discounts jsonb;
begin
 if not app_private.is_verified_school_owner((select auth.uid()),p_school)
 or not exists(select 1 from public.student_enrollments e
   where e.student_id=p_student and e.school_id=p_school
   and e.campus_id=p_campus and e.academic_year_id=p_year)
 then raise exception 'Student fee account outside Owner campus/year'
   using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'month',c.billing_month,'category',fc.name,
  'gross_minor',c.gross_minor,'discount_minor',c.discount_minor,
  'net_minor',c.net_minor,
  'paid_minor',coalesce((select sum(a.amount_minor)
    from public.fee_allocations a where a.charge_id=c.id),0),
  'due_on',c.due_on)
  order by c.billing_month,c.due_on,c.id),'[]'::jsonb)
 into v_charges
 from public.fee_charges c join public.fee_categories fc on fc.id=c.category_id
 where c.school_id=p_school and c.campus_id=p_campus
 and c.academic_year_id=p_year and c.student_id=p_student;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.id,'number',q.receipt_no,'amount_minor',q.amount_minor,
  'method',q.payment_method,'bank_reference',q.bank_reference,
  'issued_at',q.issued_at)
  order by q.issued_at desc,q.id desc),'[]'::jsonb)
 into v_receipts
 from (select r.* from public.fee_receipts r
   where r.school_id=p_school and r.collection_campus_id=p_campus
   and r.student_id=p_student
   order by r.issued_at desc,r.id desc limit 50) q;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',d.id,'category_id',d.category_id,'category',fc.name,
  'kind',d.discount_kind,'percent_bps',d.percent_bps,
  'fixed_minor',d.fixed_minor,'start_month',d.start_month,
  'end_month',d.end_month,'reason',d.reason)
  order by d.created_at desc),'[]'::jsonb) into v_discounts
 from public.fee_discounts d join public.fee_categories fc on fc.id=d.category_id
 where d.school_id=p_school and d.campus_id=p_campus
 and d.academic_year_id=p_year and d.student_id=p_student and d.is_active;

 return jsonb_build_object('student_id',p_student,'charges',v_charges,
 'receipts',v_receipts,'discounts',v_discounts);
end;
$fn$;

create or replace function app_private.owner_set_student_fee_discount(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,p_category uuid,
 p_kind text,p_percent_bps integer,p_fixed_minor bigint,
 p_start_month date,p_reason text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_enrollment uuid;v_id uuid;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Only Owner may grant fee discount'
   using errcode='42501';end if;
 if p_kind not in ('percent','fixed')
 or (p_kind='percent' and (p_percent_bps is null
      or p_percent_bps<0 or p_percent_bps>10000 or p_fixed_minor is not null))
 or (p_kind='fixed' and (p_fixed_minor is null
      or p_fixed_minor<0 or p_fixed_minor>100000000000 or p_percent_bps is not null))
 or p_start_month is null
 or p_start_month<>date_trunc('month',p_start_month)::date
 or p_start_month<date_trunc('month',current_date)::date
 or length(btrim(coalesce(p_reason,''))) not between 4 and 500
 then raise exception 'Invalid scholarship terms' using errcode='22023';end if;
 if not exists(select 1 from public.academic_years y
  where y.id=p_year and y.school_id=p_school and y.is_active
  and p_start_month between
   date_trunc('month',y.starts_on)::date and date_trunc('month',y.ends_on)::date)
 then raise exception 'Discount month not in active academic year'
 using errcode='22023';end if;
 if not exists(select 1 from public.fee_categories fc
    where fc.id=p_category and fc.school_id=p_school
      and fc.is_active and fc.is_discountable)
 then raise exception 'Category cannot be discounted' using errcode='42501';end if;
 -- Serialize discount replacement with invoice posting for this campus.
 perform 1 from public.campuses c where c.id=p_campus
 and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Invalid campus' using errcode='42501';end if;
 select e.id into v_enrollment from public.student_enrollments e
 where e.student_id=p_student and e.school_id=p_school
 and e.campus_id=p_campus and e.academic_year_id=p_year
 and e.ended_on is null limit 1;
 if v_enrollment is null then raise exception 'No active enrollment'
 using errcode='42501';end if;
 if exists(select 1 from public.fee_charges c where c.enrollment_id=v_enrollment
    and c.category_id=p_category and c.billing_month>=p_start_month)
 then raise exception 'Existing posted charges cannot be retroactively discounted'
 using errcode='23514';end if;
 update public.fee_discounts set is_active=false
 where enrollment_id=v_enrollment and category_id=p_category and is_active;
 insert into public.fee_discounts(
 school_id,campus_id,academic_year_id,student_id,enrollment_id,
 category_id,discount_kind,percent_bps,fixed_minor,start_month,
 is_active,reason,approved_by)
 values(p_school,p_campus,p_year,p_student,v_enrollment,
 p_category,p_kind,p_percent_bps,p_fixed_minor,p_start_month,
 true,btrim(p_reason),v_actor) returning id into v_id;
 insert into app_private.sms_fee_discount_audit(
 school_id,campus_id,student_id,actor_id,discount_id,action)
 values(p_school,p_campus,p_student,v_actor,v_id,'discount_granted');
 return jsonb_build_object('id',v_id,'saved',true);
end;
$fn$;

create or replace function app_private.owner_generate_monthly_bills(
 p_school uuid,p_campus uuid,p_year uuid,p_month date,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
v_cycle uuid;v_year public.academic_years%rowtype;
v_hash bytea;v_payload jsonb;v_old record;
v_added integer;v_result jsonb;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Only verified Owner can generate monthly bills'
   using errcode='42501';end if;
 if p_operation is null or p_month is null
  or p_month<>date_trunc('month',p_month)::date
  or p_month>date_trunc('month',current_date)::date
 then raise exception 'Invalid month or operation ID' using errcode='22023';end if;
 select * into v_year from public.academic_years y
 where y.id=p_year and y.school_id=p_school and y.is_active;
 if v_year.id is null or p_month<date_trunc('month',v_year.starts_on)::date
    or p_month>date_trunc('month',v_year.ends_on)::date
 then raise exception 'Billing month not in active academic year'
 using errcode='22023';end if;
 -- A single campus lock serializes billing, discounts and receipt allocation.
 perform 1 from public.campuses c where c.id=p_campus
 and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Invalid campus' using errcode='42501';end if;
 v_payload:=jsonb_build_object('school',p_school,'campus',p_campus,
  'year',p_year,'month',p_month);
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_payload::text,'UTF8'));
 select op.request_sha256,op.result_json,op.action into v_old
 from public.fee_operation_receipts op where op.school_id=p_school
 and op.operation_id=p_operation;
 if found then
  if v_old.action<>'generate_charges' or v_old.request_sha256<>v_hash
  then raise exception 'Operation ID previously used for another request'
    using errcode='22023';end if;
  return v_old.result_json;
 end if;
 insert into public.fee_billing_cycles(
 school_id,campus_id,academic_year_id,billing_month,status)
 values(p_school,p_campus,p_year,p_month,'open')
 on conflict(campus_id,academic_year_id,billing_month) do nothing
 returning id into v_cycle;
 if v_cycle is null then
   select id into v_cycle from public.fee_billing_cycles
   where campus_id=p_campus and academic_year_id=p_year
   and billing_month=p_month and school_id=p_school and status='open';
 end if;
 if v_cycle is null then raise exception 'Billing cycle is closed'
 using errcode='23514';end if;
 if not exists(
  select 1 from public.student_enrollments e
  join public.students st on st.id=e.student_id and st.school_id=e.school_id
  join lateral (select p.id from public.fee_plans p
   where p.school_id=e.school_id and p.campus_id=e.campus_id
     and p.academic_year_id=e.academic_year_id and p.class_id=e.class_id
     and p.effective_from<(p_month+interval '1 month')::date
     and (p.effective_to is null or p.effective_to>=p_month)
   order by p.version_no desc limit 1) p on true
  join public.fee_plan_items i on i.fee_plan_id=p.id
  join public.fee_categories fc on fc.id=i.category_id
    and fc.school_id=e.school_id and fc.charge_frequency='monthly'
    and fc.is_active
  where e.school_id=p_school and e.campus_id=p_campus
    and e.academic_year_id=p_year
    and e.admitted_on<(p_month+interval '1 month')::date
    and (e.ended_on is null or e.ended_on>=p_month)
    and st.active_status='active'
    and not i.is_optional and i.amount_minor>0
 ) then raise exception 'No active monthly fee plans for enrolled students. Configure class fees first.'
 using errcode='22023';end if;

 insert into public.fee_charges(
  school_id,campus_id,academic_year_id,student_id,enrollment_id,class_id,
  billing_cycle_id,billing_month,category_id,fee_plan_id,plan_item_id,
  source_kind,gross_minor,discount_minor,due_on,description,posted_by)
 select e.school_id,e.campus_id,e.academic_year_id,e.student_id,e.id,e.class_id,
  v_cycle,p_month,fc.id,p.id,i.id,
  'scheduled',i.amount_minor,
  least(i.amount_minor, greatest(0,coalesce(
   case when d.discount_kind='percent'
     then round(i.amount_minor::numeric*d.percent_bps/10000)::bigint
   when d.discount_kind='fixed' then d.fixed_minor end,0))),
  (p_month+interval '1 month'-interval '1 day')::date,
  fc.name||' • '||to_char(p_month,'YYYY-MM'),v_actor
 from public.student_enrollments e
 join public.students st on st.id=e.student_id and st.school_id=e.school_id
 join lateral (select p.* from public.fee_plans p
   where p.school_id=e.school_id and p.campus_id=e.campus_id
     and p.academic_year_id=e.academic_year_id and p.class_id=e.class_id
     and p.effective_from<(p_month+interval '1 month')::date
     and (p.effective_to is null or p.effective_to>=p_month)
   order by p.version_no desc limit 1) p on true
 join public.fee_plan_items i on i.fee_plan_id=p.id
 join public.fee_categories fc on fc.id=i.category_id
   and fc.school_id=e.school_id and fc.charge_frequency='monthly'
   and fc.is_active
 left join lateral (select d.* from public.fee_discounts d
   where d.enrollment_id=e.id and d.category_id=fc.id and d.is_active
   and d.start_month<=p_month
   and (d.end_month is null or d.end_month>=p_month)
   order by d.created_at desc limit 1) d on true
 where e.school_id=p_school and e.campus_id=p_campus
   and e.academic_year_id=p_year
   and e.admitted_on<(p_month+interval '1 month')::date
   and (e.ended_on is null or e.ended_on>=p_month)
   and st.active_status='active'
   and not i.is_optional and i.amount_minor>0
   and not exists(select 1 from public.fee_charges old
    where old.enrollment_id=e.id and old.billing_month=p_month
      and old.category_id=fc.id and old.source_kind='scheduled')
 on conflict do nothing;
 get diagnostics v_added=row_count;
 v_result:=jsonb_build_object('saved',true,'added_charges',v_added,
  'month',p_month,'cycle_id',v_cycle);
 insert into public.fee_operation_receipts(
 school_id,operation_id,action,actor_id,request_sha256,result_json)
 values(p_school,p_operation,'generate_charges',v_actor,v_hash,v_result);
 return v_result;
end;
$fn$;

create or replace function app_private.owner_collect_student_payment(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,
 p_amount_minor bigint,p_method text,p_bank_reference text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_payload jsonb;v_hash bytea;
v_old record;v_balance bigint;v_remaining bigint;v_take bigint;
v_serial bigint;v_no text;v_receipt uuid;v_row record;
v_result jsonb;v_bank text:=nullif(btrim(coalesce(p_bank_reference,'')),'');
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Only verified Owner may collect fees' using errcode='42501';end if;
 if p_student is null or p_operation is null
 or p_amount_minor is null or p_amount_minor<=0
 or p_amount_minor>100000000000
 or p_method not in ('cash','bank')
 or (p_method='bank' and length(coalesce(v_bank,''))<3)
 then raise exception 'Invalid payment request' using errcode='22023';end if;
 if p_method='cash' then v_bank:=null;end if;
 -- A previous academic year can still receive payment if it has charges.
 if not exists(select 1 from public.student_enrollments e
 where e.school_id=p_school and e.campus_id=p_campus
 and e.academic_year_id=p_year and e.student_id=p_student)
 then raise exception 'Student outside selected campus and academic year'
   using errcode='42501';end if;
 perform 1 from public.campuses c where c.id=p_campus
 and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Campus inactive' using errcode='42501';end if;
 v_payload:=jsonb_build_object('school',p_school,'campus',p_campus,
  'year',p_year,'student',p_student,'amount',p_amount_minor,
  'method',p_method,'reference',v_bank);
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_payload::text,'UTF8'));
 select op.request_sha256,op.result_json,op.action into v_old
 from public.fee_operation_receipts op where op.school_id=p_school
 and op.operation_id=p_operation;
 if found then
  if v_old.action<>'post_receipt' or v_old.request_sha256<>v_hash
  then raise exception 'Operation ID reused with different payment details'
    using errcode='22023';end if;
  return v_old.result_json;
 end if;
 select coalesce(sum(c.net_minor-
   coalesce((select sum(a.amount_minor) from public.fee_allocations a
    where a.charge_id=c.id),0)),0)::bigint into v_balance
 from public.fee_charges c where c.school_id=p_school
   and c.campus_id=p_campus and c.academic_year_id=p_year
   and c.student_id=p_student;
 if v_balance<p_amount_minor then
  raise exception 'Payment exceeds outstanding fees for selected year (% minor units)',v_balance
  using errcode='22023';end if;
 insert into public.fee_receipt_counters(school_id,next_serial)
 values(p_school,2)
 on conflict(school_id) do update
 set next_serial=public.fee_receipt_counters.next_serial+1
 returning next_serial-1 into v_serial;
 v_no:='SMS-'||lpad(v_serial::text,9,'0');
 insert into public.fee_receipts(
 school_id,collection_campus_id,student_id,receipt_no,
 operation_id,amount_minor,payment_method,bank_reference,issued_by)
 values(p_school,p_campus,p_student,v_no,p_operation,
 p_amount_minor,p_method,v_bank,v_actor) returning id into v_receipt;

 v_remaining:=p_amount_minor;
 for v_row in
  select c.id,
   (c.net_minor-coalesce((select sum(a.amount_minor)
      from public.fee_allocations a where a.charge_id=c.id),0))::bigint as owed
  from public.fee_charges c
  where c.school_id=p_school and c.campus_id=p_campus
   and c.academic_year_id=p_year and c.student_id=p_student
  order by c.due_on,c.billing_month,c.id
  for update of c
 loop
  if v_remaining<=0 then exit;end if;
  v_take:=least(greatest(v_row.owed,0),v_remaining);
  if v_take>0 then
   insert into public.fee_allocations(
    school_id,student_id,receipt_id,charge_id,amount_minor)
   values(p_school,p_student,v_receipt,v_row.id,v_take);
   v_remaining:=v_remaining-v_take;
  end if;
 end loop;
 if v_remaining<>0 then
  raise exception 'Payment allocation incomplete, rolled back'
   using errcode='23514';end if;
 v_result:=jsonb_build_object('saved',true,'receipt_id',v_receipt,
  'receipt_no',v_no,'amount_minor',p_amount_minor);
 insert into public.fee_operation_receipts(
 school_id,operation_id,action,actor_id,request_sha256,result_json)
 values(p_school,p_operation,'post_receipt',v_actor,v_hash,v_result);
 return v_result;
end;
$fn$;

-- Dashboard finance overlay: only actual posted data, never predicted revenue.
-- Do not change the Principal dashboard or expose finance without its own grant.
create or replace function app_private.owner_finance_dashboard_overlay(
 p_school uuid,p_campus uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_year uuid;v_collected bigint;v_owed bigint;v_trend jsonb;
begin
 if not app_private.is_verified_school_owner((select auth.uid()),p_school)
 or not exists(select 1 from public.campuses c
 where c.id=p_campus and c.school_id=p_school and c.is_active)
 then raise exception 'Owner finance summary denied' using errcode='42501';end if;
 select y.id into v_year from public.academic_years y
 where y.school_id=p_school and y.is_active
 order by y.starts_on desc limit 1;
 if v_year is null or not exists(select 1 from public.fee_charges c
   where c.school_id=p_school and c.campus_id=p_campus
   and c.academic_year_id=v_year)
 then return '{}'::jsonb;end if;
 select coalesce(sum(a.amount_minor),0)::bigint into v_collected
 from public.fee_allocations a join public.fee_charges c on c.id=a.charge_id
 where c.school_id=p_school and c.campus_id=p_campus
 and c.academic_year_id=v_year;
 select coalesce(sum(c.net_minor-
  coalesce((select sum(a.amount_minor) from public.fee_allocations a
   where a.charge_id=c.id),0)),0)::bigint into v_owed
 from public.fee_charges c where c.school_id=p_school
 and c.campus_id=p_campus and c.academic_year_id=v_year;
 select coalesce(jsonb_agg(jsonb_build_object(
  'label',to_char(m.month_date,'Mon'),
  'amount',round(coalesce(d.paid_minor,0)::numeric/100,2))
  order by m.month_date),'[]'::jsonb) into v_trend
 from (select (date_trunc('month',current_date)::date -
             (g.n||' months')::interval)::date as month_date
       from generate_series(5,0,-1) as g(n)) m
 left join lateral (
  select sum(a.amount_minor) paid_minor
  from public.fee_allocations a
  join public.fee_receipts r on r.id=a.receipt_id
  join public.fee_charges c on c.id=a.charge_id
  where c.school_id=p_school and c.campus_id=p_campus
   and c.academic_year_id=v_year
   and r.issued_at>=m.month_date::timestamptz
   and r.issued_at<(m.month_date+interval '1 month')::timestamptz
 ) d on true;
 return jsonb_build_object('fee_collected',
  round(v_collected::numeric/100,2),
  'fees_outstanding',round(v_owed::numeric/100,2),
  'fee_trend',v_trend);
end;
$fn$;

create or replace function public.owner_dashboard_snapshot(
 p_school_id uuid,p_campus_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.owner_dashboard_snapshot(p_school_id,p_campus_id) ||
 app_private.owner_finance_dashboard_overlay(p_school_id,p_campus_id); $fn$;

create or replace function public.owner_fee_monthly_ledger(
 p_school uuid,p_campus uuid,p_year uuid,p_month date)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.owner_fee_monthly_ledger(p_school,p_campus,p_year,p_month); $fn$;
create or replace function public.owner_fee_student_statement(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.owner_fee_student_statement(p_school,p_campus,p_year,p_student); $fn$;
create or replace function public.owner_set_student_fee_discount(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,p_category uuid,
 p_kind text,p_percent_bps integer,p_fixed_minor bigint,
 p_start_month date,p_reason text)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_set_student_fee_discount(p_school,p_campus,p_year,
 p_student,p_category,p_kind,p_percent_bps,p_fixed_minor,p_start_month,p_reason); $fn$;
create or replace function public.owner_generate_monthly_bills(
 p_school uuid,p_campus uuid,p_year uuid,p_month date,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_generate_monthly_bills(
 p_school,p_campus,p_year,p_month,p_operation); $fn$;
create or replace function public.owner_collect_student_payment(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,
 p_amount_minor bigint,p_method text,p_bank_reference text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_collect_student_payment(
 p_school,p_campus,p_year,p_student,p_amount_minor,p_method,p_bank_reference,p_operation); $fn$;

revoke all on function app_private.owner_fee_monthly_ledger(uuid,uuid,uuid,date),
 app_private.owner_fee_student_statement(uuid,uuid,uuid,uuid),
 app_private.owner_set_student_fee_discount(uuid,uuid,uuid,uuid,uuid,text,integer,bigint,date,text),
 app_private.owner_generate_monthly_bills(uuid,uuid,uuid,date,uuid),
 app_private.owner_collect_student_payment(uuid,uuid,uuid,uuid,bigint,text,text,uuid),
 app_private.owner_finance_dashboard_overlay(uuid,uuid),
 public.owner_fee_monthly_ledger(uuid,uuid,uuid,date),
 public.owner_fee_student_statement(uuid,uuid,uuid,uuid),
 public.owner_set_student_fee_discount(uuid,uuid,uuid,uuid,uuid,text,integer,bigint,date,text),
 public.owner_generate_monthly_bills(uuid,uuid,uuid,date,uuid),
 public.owner_collect_student_payment(uuid,uuid,uuid,uuid,bigint,text,text,uuid)
from public,anon,authenticated;
grant execute on function app_private.owner_fee_monthly_ledger(uuid,uuid,uuid,date),
 app_private.owner_fee_student_statement(uuid,uuid,uuid,uuid),
 app_private.owner_set_student_fee_discount(uuid,uuid,uuid,uuid,uuid,text,integer,bigint,date,text),
 app_private.owner_generate_monthly_bills(uuid,uuid,uuid,date,uuid),
 app_private.owner_collect_student_payment(uuid,uuid,uuid,uuid,bigint,text,text,uuid),
 app_private.owner_finance_dashboard_overlay(uuid,uuid),
 public.owner_fee_monthly_ledger(uuid,uuid,uuid,date),
 public.owner_fee_student_statement(uuid,uuid,uuid,uuid),
 public.owner_set_student_fee_discount(uuid,uuid,uuid,uuid,uuid,text,integer,bigint,date,text),
 public.owner_generate_monthly_bills(uuid,uuid,uuid,date,uuid),
 public.owner_collect_student_payment(uuid,uuid,uuid,uuid,bigint,text,text,uuid)
to authenticated;
