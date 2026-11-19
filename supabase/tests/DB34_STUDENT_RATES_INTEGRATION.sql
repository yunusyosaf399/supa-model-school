-- DB34: fictional-only integration of saved rates with real billing RPCs.
-- Runs on isolated local Supabase; entire fixture ROLLS BACK.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';

DO $test$
DECLARE
  v_owner uuid:='c0c0c0c0-0000-4000-8000-000000000001';
  v_school uuid:=gen_random_uuid();
  v_campus uuid:=gen_random_uuid();
  v_year uuid:=gen_random_uuid();
  v_class uuid:=gen_random_uuid();
  v_student uuid:=gen_random_uuid();
  v_enroll uuid:=gen_random_uuid();
  v_plan uuid:=gen_random_uuid();
  v_tuition uuid:=gen_random_uuid();
  v_transport uuid:=gen_random_uuid();
  v_exam uuid:=gen_random_uuid();
  v_month date:=date_trunc('month',current_date)::date;
  v_next date:=(date_trunc('month',current_date)+interval '1 month')::date;
  v_result jsonb;
  v_repeat jsonb;
  v_op uuid:=gen_random_uuid();
  v_count integer;
  v_amount bigint;
  v_source text;
BEGIN
  IF NOT exists(select 1 from auth.users u where u.id=v_owner
     and u.email_confirmed_at is not null) THEN
     raise exception 'Fictional local owner auth fixture missing';
  END IF;

  INSERT INTO public.schools(id,name,currency_code,timezone_name)
    values(v_school,'Fictional DB34 School','PKR','Etc/UTC');
  INSERT INTO public.campuses(id,school_id,code,name)
    values(v_campus,v_school,'M','Main Test Campus');
  INSERT INTO public.academic_years(id,school_id,label,starts_on,ends_on,is_active)
    values(v_year,v_school,'DB34-year',
      (v_month-interval '3 months')::date,
      (v_month+interval '15 months'-interval '1 day')::date,true);
  INSERT INTO public.user_profiles(user_id,display_name)
    values(v_owner,'Fictional DB34 Owner')
    on conflict(user_id) do nothing;
  INSERT INTO public.user_roles(user_id,school_id,role,is_active)
    values(v_owner,v_school,'owner',true);
  INSERT INTO public.classes(id,school_id,campus_id,academic_year_id,name)
    values(v_class,v_school,v_campus,v_year,'Fictional Grade 1');
  INSERT INTO public.students(id,school_id,registration_no,full_name_en,date_of_birth)
    values(v_student,v_school,'FICTIONAL-DB34-001','Fictional Student',current_date-interval '8 years');
  INSERT INTO public.student_enrollments(
    id,student_id,school_id,campus_id,academic_year_id,class_id,admitted_on)
    values(v_enroll,v_student,v_school,v_campus,v_year,v_class,
      (v_month-interval '2 months')::date);
  INSERT INTO public.fee_categories(
    id,school_id,code,name,charge_frequency,is_discountable)
    values(v_tuition,v_school,'TUITION','Tuition','monthly',true),
      (v_transport,v_school,'TRANSPORT','Transport','monthly',true),
      (v_exam,v_school,'LAB','Lab','monthly',true);
  INSERT INTO public.fee_plans(
    id,school_id,campus_id,academic_year_id,class_id,name,version_no,
    effective_from,status)
    values(v_plan,v_school,v_campus,v_year,v_class,
      'Fictional Standard',1,(v_month-interval '2 months')::date,'active');
  INSERT INTO public.fee_plan_items(
    school_id,campus_id,fee_plan_id,category_id,amount_minor)
    values(v_school,v_campus,v_plan,v_tuition,100000),
      (v_school,v_campus,v_plan,v_exam,20000);

  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  if not app_private.is_verified_school_owner(v_owner,v_school)
  then raise exception 'Fictional Owner setup failed';end if;

  v_result:=public.owner_set_student_fee_rate(
    v_school,v_campus,v_year,v_student,v_tuition,
    'override',85000,v_month,null,'Individual monthly tuition',gen_random_uuid());
  if v_result->>'kind'<>'override' then
    raise exception 'Tuition rate not saved';end if;
  v_result:=public.owner_set_student_fee_rate(
    v_school,v_campus,v_year,v_student,v_transport,
    'override',25000,v_month,null,'Individual monthly transport',gen_random_uuid());
  v_result:=public.owner_set_student_fee_rate(
    v_school,v_campus,v_year,v_student,v_exam,
    'exempt',null,v_month,null,'Lab fee waived by Owner',gen_random_uuid());

  INSERT INTO public.fee_discounts(
    school_id,campus_id,academic_year_id,student_id,enrollment_id,
    category_id,discount_kind,percent_bps,start_month,reason,approved_by)
    values(v_school,v_campus,v_year,v_student,v_enroll,
      v_tuition,'percent',1000,v_month,'Fictional 10 percent discount',v_owner);

  v_result:=public.owner_generate_monthly_bills(
    v_school,v_campus,v_year,v_month,v_op);
  if (v_result->>'added_charges')::int<>2
  then raise exception 'Expected tuition and rule-only transport; got %',v_result;end if;
  select count(*) into v_count from public.fee_charges
    where school_id=v_school and student_id=v_student;
  if v_count<>2 then raise exception 'Exemption or duplicate billing failed';end if;

  select gross_minor,source_kind into v_amount,v_source
    from public.fee_charges
    where school_id=v_school and student_id=v_student and category_id=v_tuition;
  if v_amount<>85000 or v_source<>'scheduled'
  then raise exception 'Tuition override not applied to class-plan charge';end if;
  select net_minor into v_amount from public.fee_charges
    where school_id=v_school and student_id=v_student and category_id=v_tuition;
  if v_amount<>76500 then raise exception 'Discount not applied to override';end if;
  select gross_minor,source_kind into v_amount,v_source
    from public.fee_charges
    where school_id=v_school and student_id=v_student and category_id=v_transport;
  if v_amount<>25000 or v_source<>'manual'
  then raise exception 'Rule-only transport charge not generated';end if;

  v_repeat:=public.owner_generate_monthly_bills(
    v_school,v_campus,v_year,v_month,v_op);
  if v_repeat<>v_result then
    raise exception 'Monthly billing replay changed result';end if;

  begin
    perform public.owner_set_student_fee_rate(
      v_school,v_campus,v_year,v_student,v_tuition,
      'override',90000,v_month,null,'Forbidden retroactive repricing',
      gen_random_uuid());
    raise exception 'Retroactive rate change wrongly allowed';
  exception when sqlstate '23514' then null;
  end;

  v_result:=public.owner_set_student_fee_rate(
    v_school,v_campus,v_year,v_student,v_tuition,
    'standard',null,v_next,null,'Restore class amount next month',
    gen_random_uuid());
  if v_result->>'kind'<>'standard' then
    raise exception 'Standard rate reset failed';end if;
  select count(*) into v_count from public.student_fee_rules
    where school_id=v_school and student_id=v_student
      and category_id=v_tuition;
  if v_count<>2 then
    raise exception 'Fee rate history was overwritten';end if;
  v_result:=public.owner_student_fee_rates_snapshot(
    v_school,v_campus,v_year);
  if jsonb_array_length(v_result->'rules')<>4 then
    raise exception 'Student rate snapshot missing history';end if;
END;
$test$;
ROLLBACK;
