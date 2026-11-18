-- DB25: targeted, category-specific billed charges from configured plans or
-- one student's explicit charge. Uses the existing immutable invoice ledger.
create or replace function app_private.sms_fee_generate_category(
 p_school uuid,p_campus uuid,p_year uuid,p_month date,p_category uuid,
 p_scope text,p_target uuid,p_override_minor bigint,
 p_include_optional boolean,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
 v_actor uuid:=(select auth.uid());v_year public.academic_years%rowtype;
 v_cat public.fee_categories%rowtype;v_cycle uuid;
 v_school_today date;v_timezone text;v_request jsonb;v_hash bytea;
 v_previous record;v_row record;v_plan record;v_item record;
 v_amt bigint;v_discount bigint;v_added int:=0;v_skipped int:=0;
 v_result jsonb;v_eligible int:=0;v_existing boolean;
begin
 if not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.update')
 then raise exception 'Authorized Fee Manager required' using errcode='42501';
 end if;
 if p_month is null or p_month<>date_trunc('month',p_month)::date
   or p_category is null or p_operation is null or
   p_scope not in ('campus','class','student') or p_scope is null
   or (p_scope='campus' and p_target is not null)
   or (p_scope<>'campus' and p_target is null)
   or (p_override_minor is not null and (p_scope<>'student'
        or p_override_minor<1 or p_override_minor>100000000000))
 then raise exception 'Invalid category generation request'
   using errcode='22023';end if;
 select * into v_year from public.academic_years y
 where y.id=p_year and y.school_id=p_school;
 select * into v_cat from public.fee_categories c
 where c.id=p_category and c.school_id=p_school and c.is_active;
 select timezone_name into v_timezone from public.schools s where s.id=p_school;
 if v_year.id is null or v_cat.id is null or v_timezone is null
 then raise exception 'School year or fee category unavailable'
   using errcode='22023';end if;
 v_school_today:=(now() at time zone v_timezone)::date;
 if p_month<date_trunc('month',v_year.starts_on)::date
   or p_month>date_trunc('month',v_year.ends_on)::date
   or p_month>date_trunc('month',v_school_today)::date
 then raise exception 'Billing month outside academic year or in future'
   using errcode='22023';end if;
 if p_scope='class' and not exists(
   select 1 from public.classes cl where cl.id=p_target
     and cl.school_id=p_school and cl.campus_id=p_campus
     and cl.academic_year_id=p_year)
 then raise exception 'Class is outside selected campus/year'
   using errcode='42501';end if;
 if p_scope='student' and not exists(
   select 1 from public.student_enrollments e
   where e.student_id=p_target and e.school_id=p_school
     and e.campus_id=p_campus and e.academic_year_id=p_year)
 then raise exception 'Student is outside selected campus/year'
   using errcode='42501';end if;
 -- School-wide category generation is based on a class plan only.
 -- Optional fees require explicit opt-in; personal overrides can bill
 -- a non-plan item (e.g. individual transport or examination).
 perform 1 from public.campuses c where c.id=p_campus
   and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Campus inactive' using errcode='42501';end if;
 v_request:=jsonb_build_object('school',p_school,'campus',p_campus,
    'year',p_year,'month',p_month,'category',p_category,
    'scope',p_scope,'target',p_target,'override',p_override_minor,
    'optional',coalesce(p_include_optional,false));
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
 select op.request_sha256,op.result_json,op.action,op.actor_id into v_previous
 from public.fee_operation_receipts op
 where op.school_id=p_school and op.operation_id=p_operation;
 if found then
  if v_previous.action<>'generate_charges'
     or v_previous.request_sha256<>v_hash
     or v_previous.actor_id<>v_actor
   then raise exception 'Billing operation reused with changed details'
     using errcode='22023';end if;
  return v_previous.result_json;
 end if;

 insert into public.fee_billing_cycles(
   school_id,campus_id,academic_year_id,billing_month,status)
 values(p_school,p_campus,p_year,p_month,'open')
 on conflict(campus_id,academic_year_id,billing_month) do nothing
 returning id into v_cycle;
 if v_cycle is null then
  select c.id into v_cycle from public.fee_billing_cycles c
  where c.school_id=p_school and c.campus_id=p_campus
    and c.academic_year_id=p_year and c.billing_month=p_month
    and c.status='open';
 end if;
 if v_cycle is null then raise exception 'Billing cycle closed'
   using errcode='23514';end if;

 for v_row in
   select e.id as enrollment_id,e.student_id,e.class_id,e.admitted_on,
     e.ended_on
   from public.student_enrollments e
   join public.students st on st.id=e.student_id and st.school_id=e.school_id
   where e.school_id=p_school and e.campus_id=p_campus
     and e.academic_year_id=p_year
     and st.active_status='active'
     and e.admitted_on<(p_month+interval '1 month')::date
     and (e.ended_on is null or e.ended_on>=p_month)
     and (p_scope<>'student' or e.student_id=p_target)
     and (p_scope<>'class' or e.class_id=p_target)
   order by e.class_id,e.student_id,e.id
 loop
   select null::uuid as id,null::integer as version_no into v_plan;
   select null::uuid as id,0::bigint as amount_minor,false as is_optional into v_item;
   select p.id,p.version_no into v_plan
   from public.fee_plans p
   where p.school_id=p_school and p.campus_id=p_campus
     and p.academic_year_id=p_year and p.class_id=v_row.class_id
     and p.effective_from<(p_month+interval '1 month')::date
     and (p.effective_to is null or p.effective_to>=p_month)
   order by p.version_no desc limit 1;
   v_amt:=null;
   if p_override_minor is not null then
     v_amt:=p_override_minor;
   elsif v_plan.id is not null then
     select i.id,i.amount_minor,i.is_optional into v_item
     from public.fee_plan_items i
     where i.fee_plan_id=v_plan.id and i.category_id=p_category;
     if v_item.id is not null
       and (not v_item.is_optional or coalesce(p_include_optional,false))
       and v_item.amount_minor>0
     then v_amt:=v_item.amount_minor;end if;
   end if;
   if v_amt is null then continue;end if;
   v_eligible:=v_eligible+1;
   -- Monthly category: once for a month, regardless of source_kind.
   -- Yearly category: once per academic year.
   -- One-time category: once per student at this school, across years.
   -- Manual category: separate explicit operations can incur repeat charges.
   select exists(select 1 from public.fee_charges c
     where c.school_id=p_school and c.student_id=v_row.student_id
       and c.category_id=p_category
       and (v_cat.charge_frequency='one_time'
         or (v_cat.charge_frequency='yearly' and c.academic_year_id=p_year)
         or (v_cat.charge_frequency='monthly'
             and c.academic_year_id=p_year and c.billing_month=p_month)
         or (v_cat.charge_frequency='manual' and p_override_minor is null
             and c.academic_year_id=p_year and c.billing_month=p_month
             and c.source_kind='scheduled'))
   ) into v_existing;
   if v_existing then v_skipped:=v_skipped+1;continue;end if;
   select least(v_amt,greatest(0,coalesce(
     case when d.discount_kind='percent'
        then round(v_amt::numeric*d.percent_bps/10000)::bigint
     when d.discount_kind='fixed' then d.fixed_minor end,0))) into v_discount
   from (select 1) t left join lateral (
      select d.* from public.fee_discounts d
      where d.enrollment_id=v_row.enrollment_id
        and d.category_id=p_category and d.is_active
        and d.start_month<=p_month
        and (d.end_month is null or d.end_month>=p_month)
      order by d.created_at desc limit 1
   ) d on true;
   insert into public.fee_charges(
     school_id,campus_id,academic_year_id,student_id,enrollment_id,class_id,
     billing_cycle_id,billing_month,category_id,fee_plan_id,plan_item_id,
     source_kind,manual_operation_id,gross_minor,discount_minor,
     due_on,description,posted_by)
   values(p_school,p_campus,p_year,v_row.student_id,v_row.enrollment_id,
     v_row.class_id,v_cycle,p_month,p_category,
     case when p_override_minor is null then v_plan.id else null end,
     case when p_override_minor is null then v_item.id else null end,
     case when p_override_minor is null then 'scheduled' else 'manual' end,
     case when p_override_minor is not null then p_operation else null end,
     v_amt,coalesce(v_discount,0),
     (p_month+interval '1 month'-interval '1 day')::date,
     v_cat.name||' • '||to_char(p_month,'YYYY-MM')||
       case when p_override_minor is not null
          then ' • individual charge' else '' end,
     v_actor);
   v_added:=v_added+1;
 end loop;
 v_result:=jsonb_build_object('saved',true,'added_charges',v_added,
   'skipped_existing',v_skipped,'eligible_students',v_eligible,
   'category',v_cat.name,'frequency',v_cat.charge_frequency,
   'month',p_month);
 insert into public.fee_operation_receipts(
  school_id,operation_id,action,actor_id,request_sha256,result_json)
 values(p_school,p_operation,'generate_charges',v_actor,v_hash,v_result);
 return v_result;
end;
$fn$;

create or replace function public.fee_generate_category(
 p_school uuid,p_campus uuid,p_year uuid,p_month date,p_category uuid,
 p_scope text,p_target uuid,p_override_minor bigint,
 p_include_optional boolean,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.sms_fee_generate_category(
  p_school,p_campus,p_year,p_month,p_category,p_scope,p_target,
  p_override_minor,p_include_optional,p_operation);
$fn$;

revoke all on function app_private.sms_fee_generate_category(
 uuid,uuid,uuid,date,uuid,text,uuid,bigint,boolean,uuid),
 public.fee_generate_category(
 uuid,uuid,uuid,date,uuid,text,uuid,bigint,boolean,uuid)
 from public,anon,authenticated;
grant execute on function app_private.sms_fee_generate_category(
 uuid,uuid,uuid,date,uuid,text,uuid,bigint,boolean,uuid),
 public.fee_generate_category(
 uuid,uuid,uuid,date,uuid,text,uuid,bigint,boolean,uuid)
 to authenticated;
