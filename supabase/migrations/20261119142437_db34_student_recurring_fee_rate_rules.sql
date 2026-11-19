-- DB34 installed on existing Supa Model School DB03 / DB25 foundations.

-- DB34: persistent per-student category rates. Defaults are preserved.
-- A latest 'standard' decision resets to class rates; historical decisions
-- remain as inactive rows and are considered by billing by effective month.
alter table public.student_fee_rules
  drop constraint student_fee_rules_rule_kind_check;
alter table public.student_fee_rules
  add constraint student_fee_rules_rule_kind_check
  check (rule_kind in ('override','exempt','standard'));
alter table public.student_fee_rules
  drop constraint student_fee_rules_check1;
alter table public.student_fee_rules
  add constraint student_fee_rules_check1
  check ((rule_kind='override' and amount_minor between 1 and 100000000000)
    or (rule_kind in ('exempt','standard') and amount_minor is null));

create index if not exists student_fee_rule_asof_idx
 on public.student_fee_rules(enrollment_id,category_id,
                            start_month desc,created_at desc);

create or replace function app_private.owner_student_fee_rates_snapshot(
 p_school uuid,p_campus uuid,p_year uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_year public.academic_years%rowtype;v_currency text;
 v_students jsonb;v_categories jsonb;v_rules jsonb;
begin
 if not app_private.is_verified_school_owner((select auth.uid()),p_school)
 then raise exception 'Verified Owner required' using errcode='42501';end if;
 if not exists(select 1 from public.campuses c where c.id=p_campus
   and c.school_id=p_school and c.is_active)
 then raise exception 'Invalid campus' using errcode='42501';end if;
 select * into v_year from public.academic_years y
 where y.id=p_year and y.school_id=p_school;
 if v_year.id is null then raise exception 'Academic year unavailable'
 using errcode='42501';end if;
 select s.currency_code into v_currency from public.schools s where s.id=p_school;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',e.student_id,'name',st.full_name_en,
  'registration',st.registration_no,'class_id',cl.id,'class_name',cl.name,
  'section_name',sec.name) order by cl.sort_order,st.full_name_en),
  '[]'::jsonb) into v_students
 from public.student_enrollments e
 join public.students st on st.id=e.student_id and st.school_id=e.school_id
 join public.classes cl on cl.id=e.class_id
 left join public.sections sec on sec.id=e.section_id
 where e.school_id=p_school and e.campus_id=p_campus
 and e.academic_year_id=p_year and st.active_status='active';
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',c.id,'name',c.name,'code',c.code,
   'frequency',c.charge_frequency) order by c.name),'[]'::jsonb)
 into v_categories from public.fee_categories c
 where c.school_id=p_school and c.is_active
 and c.charge_frequency in ('monthly','yearly');
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',r.id,'student_id',r.student_id,'category_id',r.category_id,
   'kind',r.rule_kind,'amount_minor',r.amount_minor,
   'start_month',r.start_month,'end_month',r.end_month,
   'reason',r.reason,'active',r.is_active,'created_at',r.created_at)
   order by r.created_at desc),'[]'::jsonb) into v_rules
 from public.student_fee_rules r
 where r.school_id=p_school and r.campus_id=p_campus
 and r.academic_year_id=p_year;
 return jsonb_build_object('school_id',p_school,'campus_id',p_campus,
  'year_id',p_year,'currency',v_currency,'students',v_students,
  'categories',v_categories,'rules',v_rules);
end;
$fn$;

create or replace function public.owner_student_fee_rates_snapshot(
 p_school uuid,p_campus uuid,p_year uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.owner_student_fee_rates_snapshot(
 p_school,p_campus,p_year);$fn$;

create or replace function app_private.owner_set_student_fee_rate(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,p_category uuid,
 p_kind text,p_amount_minor bigint,p_start_month date,p_end_month date,
 p_reason text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
 v_year public.academic_years%rowtype;v_enrollment uuid;
 v_timezone text;v_today date;v_hash bytea;v_request jsonb;
 v_old record;v_existing record;v_id uuid;v_result jsonb;
begin
 if v_actor is null or not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Only verified Owner may configure student rates'
 using errcode='42501';end if;
 if p_school is null or p_campus is null or p_year is null or p_student is null
   or p_category is null or p_operation is null or
   p_kind is null or p_kind not in ('override','exempt','standard')
   or (p_kind='override' and
      (p_amount_minor is null or p_amount_minor not between 1 and 100000000000))
   or (p_kind<>'override' and p_amount_minor is not null)
   or p_start_month is null
   or p_start_month<>date_trunc('month',p_start_month)::date
   or (p_end_month is not null and
       (p_end_month<>date_trunc('month',p_end_month)::date
       or p_end_month<p_start_month))
   or (p_kind='standard' and p_end_month is not null)
   or length(btrim(coalesce(p_reason,''))) not between 4 and 500
 then raise exception 'Invalid fee rate terms' using errcode='22023';end if;
 select * into v_year from public.academic_years y
 where y.id=p_year and y.school_id=p_school and y.is_active;
 select s.timezone_name into v_timezone from public.schools s
 where s.id=p_school;
 if v_year.id is null or v_timezone is null then
 raise exception 'School/year invalid' using errcode='42501';end if;
 v_today:=(now() at time zone v_timezone)::date;
 if p_start_month<date_trunc('month',v_today)::date
   or p_start_month<date_trunc('month',v_year.starts_on)::date
   or p_start_month>date_trunc('month',v_year.ends_on)::date
   or (p_end_month is not null
       and p_end_month>date_trunc('month',v_year.ends_on)::date)
 then raise exception 'Rate effective month outside current/future academic year'
 using errcode='22023';end if;
 if not exists(select 1 from public.fee_categories c
 where c.id=p_category and c.school_id=p_school and c.is_active
  and c.charge_frequency in ('monthly','yearly'))
 then raise exception 'Rate category must be active monthly or yearly'
 using errcode='22023';end if;
 perform 1 from public.campuses c
 where c.id=p_campus and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Campus unavailable' using errcode='42501';end if;
 v_request:=jsonb_build_object('school',p_school,'campus',p_campus,
  'year',p_year,'student',p_student,'category',p_category,
  'kind',p_kind,'amount',p_amount_minor,'from',p_start_month,
  'until',p_end_month,'reason',btrim(p_reason));
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
 select op.action,op.actor_id,op.request_sha256,op.result_json into v_old
 from public.fee_operation_receipts op
 where op.school_id=p_school and op.operation_id=p_operation;
 if found then
  if v_old.action<>'student_rate' or v_old.actor_id<>v_actor
    or v_old.request_sha256<>v_hash
  then raise exception 'Rate operation reused with changed terms'
   using errcode='22023';end if;
  return v_old.result_json;
 end if;
 select e.id into v_enrollment from public.student_enrollments e
 join public.students st on st.id=e.student_id and st.school_id=e.school_id
 where e.student_id=p_student and e.school_id=p_school
   and e.campus_id=p_campus and e.academic_year_id=p_year
   and st.active_status='active'
   and e.admitted_on<(p_start_month+interval '1 month')::date
   and (e.ended_on is null or e.ended_on>=p_start_month)
 order by e.admitted_on desc limit 1;
 if v_enrollment is null then raise exception 'Student not enrolled for rate month'
 using errcode='42501';end if;
 if exists(select 1 from public.fee_charges c
   where c.enrollment_id=v_enrollment and c.category_id=p_category
     and c.billing_month>=p_start_month
     and (p_end_month is null or c.billing_month<=p_end_month))
 then raise exception 'Posted charges cannot be repriced retroactively'
 using errcode='23514';end if;
 select r.id,r.start_month into v_existing
 from public.student_fee_rules r
 where r.enrollment_id=v_enrollment and r.category_id=p_category
   and r.is_active limit 1;
 if v_existing.id is not null and v_existing.start_month>p_start_month
 then raise exception 'An existing rate starts later; revise that period first'
 using errcode='23514';end if;
 update public.student_fee_rules
 set is_active=false
 where enrollment_id=v_enrollment and category_id=p_category and is_active;
 insert into public.student_fee_rules(
   school_id,campus_id,academic_year_id,student_id,enrollment_id,
   category_id,rule_kind,amount_minor,start_month,end_month,
   is_active,reason,approved_by)
 values(p_school,p_campus,p_year,p_student,v_enrollment,p_category,
   p_kind,p_amount_minor,p_start_month,p_end_month,true,btrim(p_reason),v_actor)
 returning id into v_id;
 v_result:=jsonb_build_object('saved',true,'rate_id',v_id,
  'student_id',p_student,'category_id',p_category,
  'kind',p_kind,'amount_minor',p_amount_minor,
  'start_month',p_start_month,'end_month',p_end_month);
 insert into public.fee_operation_receipts(
   school_id,operation_id,action,actor_id,request_sha256,result_json)
 values(p_school,p_operation,'student_rate',v_actor,v_hash,v_result);
 return v_result;
end;$fn$;

create or replace function public.owner_set_student_fee_rate(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,p_category uuid,
 p_kind text,p_amount_minor bigint,p_start_month date,p_end_month date,
 p_reason text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_set_student_fee_rate(
 p_school,p_campus,p_year,p_student,p_category,p_kind,p_amount_minor,
 p_start_month,p_end_month,p_reason,p_operation);$fn$;

revoke all on function
 app_private.owner_student_fee_rates_snapshot(uuid,uuid,uuid),
 public.owner_student_fee_rates_snapshot(uuid,uuid,uuid),
 app_private.owner_set_student_fee_rate(uuid,uuid,uuid,uuid,uuid,text,bigint,date,date,text,uuid),
 public.owner_set_student_fee_rate(uuid,uuid,uuid,uuid,uuid,text,bigint,date,date,text,uuid)
 from public,anon,authenticated;
grant execute on function
 app_private.owner_student_fee_rates_snapshot(uuid,uuid,uuid),
 public.owner_student_fee_rates_snapshot(uuid,uuid,uuid),
 app_private.owner_set_student_fee_rate(uuid,uuid,uuid,uuid,uuid,text,bigint,date,date,text,uuid),
 public.owner_set_student_fee_rate(uuid,uuid,uuid,uuid,uuid,text,bigint,date,date,text,uuid)
 to authenticated;


-- Apply as-of fee rate precedence to all category, class, section, selected
-- student and multi-category generators via this shared internal RPC.
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
 v_previous record;v_row record;v_plan record;v_item record;v_rule record;
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
   -- Use the latest decision as of this billing month, including archived
   -- history. A later expiring rule must not revive an earlier override.
   select null::uuid as id,null::text as rule_kind,
          null::bigint as amount_minor,null::date as end_month into v_rule;
   select r.id,r.rule_kind,r.amount_minor,r.end_month into v_rule
   from public.student_fee_rules r
   where r.school_id=p_school and r.campus_id=p_campus
     and r.academic_year_id=p_year and r.enrollment_id=v_row.enrollment_id
     and r.category_id=p_category and r.start_month<=p_month
   order by r.start_month desc,r.created_at desc,r.id desc limit 1;
   if v_plan.id is not null then
     select i.id,i.amount_minor,i.is_optional into v_item
     from public.fee_plan_items i
     where i.fee_plan_id=v_plan.id and i.category_id=p_category;
   end if;
   v_amt:=null;
   if p_override_minor is not null then
     v_amt:=p_override_minor;
   elsif v_rule.id is not null
     and (v_rule.end_month is null or v_rule.end_month>=p_month)
     and v_rule.rule_kind='exempt' then
     continue;
   elsif v_rule.id is not null
     and (v_rule.end_month is null or v_rule.end_month>=p_month)
     and v_rule.rule_kind='override' then
     v_amt:=v_rule.amount_minor;
   elsif v_item.id is not null
     and (not v_item.is_optional or coalesce(p_include_optional,false))
     and v_item.amount_minor>0 then
     v_amt:=v_item.amount_minor;
   end if;
   if v_amt is null or v_amt<=0 then continue;end if;
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
     case when p_override_minor is null and v_item.id is not null
       then v_plan.id else null end,
     case when p_override_minor is null and v_item.id is not null
       then v_item.id else null end,
     case when p_override_minor is null and v_item.id is not null
       then 'scheduled' else 'manual' end,
     case when p_override_minor is not null then p_operation
       when v_item.id is null
         then pg_catalog.md5('db34-rate:'||p_school::text||':'||
           p_year::text||':'||v_row.student_id::text||':'||
           p_category::text||':'||p_month::text)::uuid
       else null end,
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


-- Monthly Owner entrypoint delegates to the same rate-aware category engine
-- as Quick Pay category and section billing. Its original request hash and
-- result are preserved for operation-ID replay of already-posted requests.
create or replace function app_private.owner_generate_monthly_bills(
 p_school uuid,p_campus uuid,p_year uuid,p_month date,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
 v_year public.academic_years%rowtype;v_old record;
 v_hash bytea;v_request jsonb;v_cat record;v_line jsonb;
 v_added integer:=0;v_eligible integer:=0;v_cycle uuid;
 v_result jsonb;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Only verified Owner may generate monthly bills'
 using errcode='42501';end if;
 if p_operation is null or p_month is null
   or p_month<>date_trunc('month',p_month)::date
   or p_month>date_trunc('month',current_date)::date
 then raise exception 'Invalid billing month/operation' using errcode='22023';end if;
 select * into v_year from public.academic_years y
 where y.id=p_year and y.school_id=p_school and y.is_active;
 if v_year.id is null or p_month<date_trunc('month',v_year.starts_on)::date
 or p_month>date_trunc('month',v_year.ends_on)::date
 then raise exception 'Billing month not in active school year'
 using errcode='22023';end if;
 perform 1 from public.campuses c where c.id=p_campus
 and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Invalid campus' using errcode='42501';end if;
 v_request:=jsonb_build_object('school',p_school,'campus',p_campus,
   'year',p_year,'month',p_month);
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
 select op.request_sha256,op.result_json,op.action into v_old
 from public.fee_operation_receipts op
 where op.school_id=p_school and op.operation_id=p_operation;
 if found then
  if v_old.action<>'generate_charges' or v_old.request_sha256<>v_hash
  then raise exception 'Operation reused with changed terms'
  using errcode='22023';end if;
  return v_old.result_json;
 end if;
 for v_cat in select fc.id from public.fee_categories fc
   where fc.school_id=p_school and fc.is_active
      and fc.charge_frequency='monthly'
   order by fc.id loop
   v_line:=app_private.sms_fee_generate_category(
     p_school,p_campus,p_year,p_month,v_cat.id,'campus',null,null,false,
     pg_catalog.md5('db34-owner-monthly:'||p_operation::text||
       ':'||v_cat.id::text)::uuid);
   v_added:=v_added+(v_line->>'added_charges')::integer;
   v_eligible:=v_eligible+(v_line->>'eligible_students')::integer;
 end loop;
 if v_eligible=0 then
   raise exception 'No eligible monthly fee plans or student-specific rates'
   using errcode='22023';end if;
 select c.id into v_cycle from public.fee_billing_cycles c
 where c.school_id=p_school and c.campus_id=p_campus
   and c.academic_year_id=p_year and c.billing_month=p_month
   and c.status='open';
 v_result:=jsonb_build_object('saved',true,'added_charges',v_added,
   'month',p_month,'cycle_id',v_cycle);
 insert into public.fee_operation_receipts(
   school_id,operation_id,action,actor_id,request_sha256,result_json)
 values(p_school,p_operation,'generate_charges',v_actor,v_hash,v_result);
 return v_result;
end;$fn$;

