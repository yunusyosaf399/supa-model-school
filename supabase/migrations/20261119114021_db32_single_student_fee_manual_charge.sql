-- DB32: one explicit student charge per operation; repeated genuine uniform purchases allowed.
-- Uses existing immutable DB03 charges, authorization, and operation-replay receipts.
create or replace function app_private.sms_fee_add_individual_charge(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,p_category uuid,
 p_charge_on date,p_due_on date,p_price_mode text,p_amount_minor bigint,
 p_description text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
 v_actor uuid:=(select auth.uid());
 v_year public.academic_years%rowtype;
 v_cat public.fee_categories%rowtype;
 v_e record;
 v_cycle uuid;
 v_month date;
 v_school_today date;
 v_timezone text;
 v_amount bigint;
 v_discount bigint:=0;
 v_plan_amount bigint;
 v_request jsonb;
 v_hash bytea;
 v_previous record;
 v_id uuid;
 v_result jsonb;
begin
 if v_actor is null or not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.update')
 then raise exception 'Authorized fee manager required' using errcode='42501';end if;
 if p_operation is null or p_school is null or p_campus is null
   or p_year is null or p_student is null or p_category is null
   or p_charge_on is null or p_due_on is null
   or p_price_mode not in ('standard','custom') or p_price_mode is null
   or length(btrim(coalesce(p_description,''))) not between 4 and 400
   or (p_price_mode='custom' and (p_amount_minor is null or p_amount_minor<1
        or p_amount_minor>100000000000))
   or (p_price_mode='standard' and p_amount_minor is not null)
 then raise exception 'Invalid individual charge details' using errcode='22023';end if;
 select * into v_year from public.academic_years y
 where y.id=p_year and y.school_id=p_school;
 select * into v_cat from public.fee_categories c
 where c.id=p_category and c.school_id=p_school and c.is_active;
 select s.timezone_name into v_timezone from public.schools s
 where s.id=p_school and s.status='active';
 if v_year.id is null or v_cat.id is null or v_timezone is null
 then raise exception 'Academic year or active category unavailable'
 using errcode='22023';end if;
 v_school_today:=(now() at time zone v_timezone)::date;
 if p_charge_on<v_year.starts_on or p_charge_on>v_year.ends_on
   or p_charge_on>v_school_today or p_due_on<p_charge_on
   or p_due_on>p_charge_on+366
 then raise exception 'Invalid charge or due date' using errcode='22023';end if;
 v_month:=date_trunc('month',p_charge_on)::date;
 -- Serialize student charging with normal campus billing, then check replay.
 perform 1 from public.campuses c
 where c.id=p_campus and c.school_id=p_school and c.is_active
 for update;
 if not found then raise exception 'Campus unavailable' using errcode='42501';end if;
 v_request:=jsonb_build_object('school',p_school,'campus',p_campus,
   'year',p_year,'student',p_student,'category',p_category,
   'charge_on',p_charge_on,'due_on',p_due_on,'price_mode',p_price_mode,
   'amount_minor',p_amount_minor,'description',btrim(p_description));
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
 select op.action,op.actor_id,op.request_sha256,op.result_json
 into v_previous from public.fee_operation_receipts op
 where op.school_id=p_school and op.operation_id=p_operation;
 if found then
   if v_previous.action<>'individual_charge' or v_previous.actor_id<>v_actor
      or v_previous.request_sha256<>v_hash
   then raise exception 'Operation ID reused with different charge'
     using errcode='22023';end if;
   return v_previous.result_json;
 end if;
 select e.id enrollment_id,e.class_id,e.student_id into v_e
 from public.student_enrollments e
 join public.students st on st.id=e.student_id and st.school_id=e.school_id
 where e.school_id=p_school and e.campus_id=p_campus
   and e.academic_year_id=p_year and e.student_id=p_student
   and st.active_status='active'
   and e.admitted_on<=p_charge_on
   and (e.ended_on is null or e.ended_on>=p_charge_on)
 order by e.admitted_on desc limit 1;
 if v_e.enrollment_id is null
 then raise exception 'Student not enrolled in this campus/year/date'
 using errcode='42501';end if;
 if p_price_mode='standard' then
   select i.amount_minor into v_plan_amount
   from public.fee_plans p
   join public.fee_plan_items i on i.fee_plan_id=p.id
      and i.category_id=p_category
   where p.school_id=p_school and p.campus_id=p_campus
     and p.academic_year_id=p_year and p.class_id=v_e.class_id
     and p.effective_from<=p_charge_on
     and (p.effective_to is null or p.effective_to>=p_charge_on)
   order by p.version_no desc limit 1;
   if v_plan_amount is null or v_plan_amount<=0
   then raise exception 'No class price configured for this category'
     using errcode='22023';end if;
   v_amount:=v_plan_amount;
 else
   v_amount:=p_amount_minor;
 end if;
 if v_cat.is_discountable then
   select least(v_amount,greatest(0,
     case when d.discount_kind='percent'
       then round(v_amount::numeric*d.percent_bps/10000)::bigint
     when d.discount_kind='fixed' then d.fixed_minor
     else 0 end)) into v_discount
   from public.fee_discounts d
   where d.enrollment_id=v_e.enrollment_id and d.category_id=p_category
     and d.is_active and d.start_month<=v_month
     and (d.end_month is null or d.end_month>=v_month)
   order by d.created_at desc limit 1;
   v_discount:=coalesce(v_discount,0);
 end if;
 insert into public.fee_billing_cycles(
   school_id,campus_id,academic_year_id,billing_month,status)
 values(p_school,p_campus,p_year,v_month,'open')
 on conflict(campus_id,academic_year_id,billing_month) do nothing
 returning id into v_cycle;
 if v_cycle is null then
   select b.id into v_cycle from public.fee_billing_cycles b
   where b.school_id=p_school and b.campus_id=p_campus
     and b.academic_year_id=p_year and b.billing_month=v_month
     and b.status='open';
 end if;
 if v_cycle is null then raise exception 'Billing period is closed'
 using errcode='23514';end if;
 insert into public.fee_charges(
  school_id,campus_id,academic_year_id,student_id,enrollment_id,class_id,
  billing_cycle_id,billing_month,category_id,source_kind,
  manual_operation_id,gross_minor,discount_minor,due_on,description,posted_by)
 values(p_school,p_campus,p_year,p_student,v_e.enrollment_id,v_e.class_id,
  v_cycle,v_month,p_category,'manual',p_operation,v_amount,v_discount,
  p_due_on,btrim(p_description),v_actor)
 returning id into v_id;
 v_result:=jsonb_build_object('saved',true,'charge_id',v_id,'student_id',p_student,
   'category',v_cat.name,'gross_minor',v_amount,'discount_minor',v_discount,
   'net_minor',v_amount-v_discount,'due_on',p_due_on,'source','manual');
 insert into public.fee_operation_receipts(
  school_id,operation_id,action,actor_id,request_sha256,result_json)
 values(p_school,p_operation,'individual_charge',v_actor,v_hash,v_result);
 return v_result;
end;$fn$;

create or replace function public.fee_add_individual_charge(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,p_category uuid,
 p_charge_on date,p_due_on date,p_price_mode text,p_amount_minor bigint,
 p_description text,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_fee_add_individual_charge(
 p_school,p_campus,p_year,p_student,p_category,p_charge_on,p_due_on,
 p_price_mode,p_amount_minor,p_description,p_operation);$fn$;
revoke all on function app_private.sms_fee_add_individual_charge(
 uuid,uuid,uuid,uuid,uuid,date,date,text,bigint,text,uuid),
 public.fee_add_individual_charge(
 uuid,uuid,uuid,uuid,uuid,date,date,text,bigint,text,uuid)
 from public,anon,authenticated;
grant execute on function app_private.sms_fee_add_individual_charge(
 uuid,uuid,uuid,uuid,uuid,date,date,text,bigint,text,uuid),
 public.fee_add_individual_charge(
 uuid,uuid,uuid,uuid,uuid,date,date,text,bigint,text,uuid)
 to authenticated;
