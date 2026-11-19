-- DB36 disposable LOCAL ONLY student fee ledger integration.
-- Fake Owner/campus/students; verify partial allocations, month/category sums
-- and read permission boundaries. All sample data rolls back.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='30s';
do $fixture$
declare
 v_owner uuid:='c0c0c0c0-0000-4000-8000-000000000001';
 v_school uuid:=gen_random_uuid();
 v_campus uuid:=gen_random_uuid();
 v_other uuid:=gen_random_uuid();
 v_year uuid:=gen_random_uuid();
 v_class uuid:=gen_random_uuid();
 v_student uuid:=gen_random_uuid();
 v_enrollment uuid:=gen_random_uuid();
 v_tuition uuid:=gen_random_uuid();
 v_transport uuid:=gen_random_uuid();
 v_cycle1 uuid:=gen_random_uuid();
 v_cycle2 uuid:=gen_random_uuid();
 v_charge1 uuid:=gen_random_uuid();
 v_charge2 uuid:=gen_random_uuid();
 v_r1 uuid:=gen_random_uuid();
 v_r2 uuid:=gen_random_uuid();
 v_prior date:=(date_trunc('month',current_date)-interval '1 month')::date;
 v_now date:=date_trunc('month',current_date)::date;
 v_result jsonb;
 v_before int;
begin
 if not exists(select 1 from auth.users where id=v_owner)
 then raise exception 'Fixture Owner account missing';end if;
 insert into public.schools(id,name,currency_code,timezone_name)
 values(v_school,'Fictional DB36 School','PKR','Etc/UTC');
 insert into public.campuses(id,school_id,code,name) values
 (v_campus,v_school,'M','Main Campus'),(v_other,v_school,'X','Other Campus');
 insert into public.academic_years(
 id,school_id,label,starts_on,ends_on,is_active)
 values(v_year,v_school,'DB36-Test',
 (v_prior-interval '5 months')::date,
 (v_now+interval '7 months')::date,true);
 insert into public.user_profiles(user_id,display_name)
 values(v_owner,'Fictional DB36 Owner')
 on conflict(user_id) do nothing;
 insert into public.user_roles(user_id,school_id,role,is_active)
 values(v_owner,v_school,'owner',true);
 insert into public.classes(id,school_id,campus_id,academic_year_id,name)
 values(v_class,v_school,v_campus,v_year,'Grade 2');
 insert into public.students(
 id,school_id,registration_no,full_name_en,date_of_birth)
 values(v_student,v_school,'DB36-DEMO-1','Fictional Fee Student',
 current_date-interval '8 years');
 insert into public.student_enrollments(
 id,student_id,school_id,campus_id,academic_year_id,class_id,admitted_on)
 values(v_enrollment,v_student,v_school,v_campus,v_year,v_class,
 (v_prior-interval '2 months')::date);
 insert into public.fee_categories(
 id,school_id,code,name,charge_frequency)
 values(v_tuition,v_school,'TUITION','Tuition','monthly'),
 (v_transport,v_school,'TRANSPORT','Transport','monthly');
 insert into public.fee_billing_cycles(
 id,school_id,campus_id,academic_year_id,billing_month)
 values(v_cycle1,v_school,v_campus,v_year,v_prior),
 (v_cycle2,v_school,v_campus,v_year,v_now);
 insert into public.fee_charges(
 id,school_id,campus_id,academic_year_id,student_id,enrollment_id,
 class_id,billing_cycle_id,billing_month,category_id,source_kind,
 manual_operation_id,gross_minor,discount_minor,due_on,
 description,posted_by)
 values
 (v_charge1,v_school,v_campus,v_year,v_student,v_enrollment,
 v_class,v_cycle1,v_prior,v_tuition,'manual',gen_random_uuid(),
 10000,1000,(v_prior+interval '20 days')::date,
 'Individual tuition charge',v_owner),
 (v_charge2,v_school,v_campus,v_year,v_student,v_enrollment,
 v_class,v_cycle2,v_now,v_transport,'manual',gen_random_uuid(),
 6000,0,(v_now+interval '20 days')::date,
 'Personal transport amount',v_owner);
 insert into public.fee_receipts(
 id,school_id,collection_campus_id,student_id,receipt_no,
 operation_id,amount_minor,payment_method,issued_by,bank_reference)
 values
 (v_r1,v_school,v_campus,v_student,'DB36-REC-1',
 gen_random_uuid(),8500,'cash',v_owner,null),
 (v_r2,v_school,v_campus,v_student,'DB36-REC-2',
 gen_random_uuid(),1500,'bank',v_owner,'TEST-BANK-001');
 insert into public.fee_allocations(
 school_id,student_id,receipt_id,charge_id,amount_minor)
 values
 (v_school,v_student,v_r1,v_charge1,5500),
 (v_school,v_student,v_r1,v_charge2,3000),
 (v_school,v_student,v_r2,v_charge1,1500);
 perform set_config('request.jwt.claim.sub',v_owner::text,true);
 perform set_config('request.jwt.claim.role','authenticated',true);
 select count(*) into v_before from public.fee_charges
 where school_id=v_school;
 v_result:=public.fee_student_detailed_ledger(
  v_school,v_campus,v_year,v_student);
 if (v_result->'totals'->>'charge_count')::integer<>2
   or (v_result->'totals'->>'gross_minor')::bigint<>16000
   or (v_result->'totals'->>'discount_minor')::bigint<>1000
   or (v_result->'totals'->>'net_minor')::bigint<>15000
   or (v_result->'totals'->>'paid_minor')::bigint<>10000
   or (v_result->'totals'->>'outstanding_minor')::bigint<>5000
 then raise exception 'Incorrect DB36 ledger totals: %',v_result->'totals';end if;
 if jsonb_array_length(v_result->'charges')<>2
 or jsonb_array_length(v_result->'months')<>2
 or jsonb_array_length(v_result->'categories')<>2
 or jsonb_array_length(v_result->'receipts')<>2
 or jsonb_array_length(v_result->'allocations')<>3
 then raise exception 'DB36 missing category/month/receipt detail';end if;
 if not exists(
 select 1 from jsonb_array_elements(v_result->'charges') x
 where x->>'category'='Tuition' and (x->>'paid_minor')::bigint=7000
 and (x->>'outstanding_minor')::bigint=2000
 and x->>'source_kind'='manual'
 ) then raise exception 'Tuition partial payments not reconciled';end if;
 if not exists(select 1 from jsonb_array_elements(v_result->'receipts') x
 where x->>'number'='DB36-REC-1'
 and (x->>'allocated_to_year_minor')::bigint=8500)
 then raise exception 'Receipt 1 allocation incorrect';end if;
 if (select count(*) from public.fee_charges where school_id=v_school)<>v_before
 then raise exception 'DB36 read unexpectedly modified posted charges';end if;
 begin
   perform public.fee_student_detailed_ledger(
     v_school,v_other,v_year,v_student);
   raise exception 'Foreign campus student ledger unexpectedly exposed';
 exception when sqlstate '42501' then null;
 end;
 perform set_config('request.jwt.claim.sub','',true);
 begin
   perform public.fee_student_detailed_ledger(
     v_school,v_campus,v_year,v_student);
   raise exception 'Anonymous student ledger unexpectedly exposed';
 exception when sqlstate '42501' then null;
 end;
end;
$fixture$;
rollback;
