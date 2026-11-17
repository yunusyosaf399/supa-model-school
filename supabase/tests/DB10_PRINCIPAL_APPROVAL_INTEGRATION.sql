-- DB10 Principal approval integration. All fixture writes ROLLBACK.
begin;
create temporary table db10_case (
 application_id uuid, submitted_revision bigint, principal_id uuid,
 owner_id uuid, school_id uuid, campus_id uuid
) on commit drop;
grant select,insert,update on db10_case to authenticated;

do $baseline$
begin
 if (select count(*) from public.students) <> 32
    or (select count(*) from public.admission_applications) <> 5 then
    raise exception 'Unexpected live fixture counts; test not safe to run'; end if;
 if has_function_privilege('anon',
   'public.owner_submit_admission(uuid,bigint,uuid,date,text)','EXECUTE')
    or has_function_privilege('anon',
   'public.principal_review_admission(uuid,bigint,uuid,text,text)','EXECUTE')
    or has_function_privilege('anon',
   'public.principal_admission_queue(uuid,uuid,integer,integer)','EXECUTE')
 then raise exception 'Anonymous admission approval API exposed'; end if;
end $baseline$;

do $principal_fixture$
declare v_school uuid;v_campus uuid;v_owner uuid;v_principal uuid;
begin
 select r.school_id,c.id,r.user_id
 into strict v_school,v_campus,v_owner
 from public.user_roles r
 join public.campuses c on c.school_id=r.school_id and c.is_active
 where r.role='owner' and r.is_active and r.campus_id is null limit 1;
 v_principal:=gen_random_uuid();
 -- Throwaway auth identity for role-isolation testing; transaction is rolled back.
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,
  encrypted_password,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,is_anonymous)
 values(v_principal,'00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated',
  'test-db10-principal-'||v_principal::text||'@example.invalid',
  pg_catalog.now(),'!not-a-real-password!',
  '{}'::jsonb,'{}'::jsonb,pg_catalog.now(),pg_catalog.now(),false);
 insert into public.user_profiles(user_id,display_name,is_active)
 values(v_principal,'TEST Temporary Principal',true);
 insert into public.user_roles(user_id,school_id,campus_id,role,is_active)
 values(v_principal,v_school,v_campus,'principal',true);
 insert into db10_case(school_id,campus_id,principal_id,owner_id)
 values(v_school,v_campus,v_principal,v_owner);
end $principal_fixture$;

select set_config('request.jwt.claim.sub',
 (select owner_id::text from db10_case limit 1),true);
set local role authenticated;

do $owner$
declare
 v_case db10_case%rowtype;v_year uuid;v_class uuid;v_section uuid;
 v_save jsonb;v_submit jsonb;v_operation uuid:=gen_random_uuid();
 v_day date;
begin
 select * into strict v_case from db10_case;
 -- Public Owner draft API derives actor from auth.uid.
 select id into v_year from public.academic_years
 where school_id=v_case.school_id and is_active limit 1;
 select id into v_class from public.classes
 where school_id=v_case.school_id and campus_id=v_case.campus_id
   and academic_year_id=v_year and name='Grade 1' limit 1;
 select id into v_section from public.sections
 where class_id=v_class and name='A' limit 1;
 v_save:=public.owner_save_admission_draft(
   v_case.school_id,v_case.campus_id,v_year,
   null,null,gen_random_uuid(),
   'TEST DB10 Principal Review Applicant '||left(gen_random_uuid()::text,8),
   date '2018-01-15','TEST Previous School',v_class,v_section,
   '[{"full_name":"TEST Principal Guardian","relationship":"father","phone":"03001234567","is_primary":true,"is_legal_guardian":true}]'::jsonb
 );
 if v_save->>'status'<>'draft' then
   raise exception 'Owner draft was not saved'; end if;

 begin
   perform public.owner_submit_admission(
     (v_save->>'application_id')::uuid,(v_save->>'revision')::bigint,
     gen_random_uuid(),(current_date+interval '3 months')::date,'Awaiting documents');
   raise exception 'Excessive deadline accepted';
 exception when invalid_parameter_value then null; end;

 v_day:=(pg_catalog.now() at time zone 'Asia/Karachi')::date;
 v_submit:=public.owner_submit_admission(
   (v_save->>'application_id')::uuid,(v_save->>'revision')::bigint,
   v_operation,(v_day+interval '1 month')::date,
   'TEST family gathering missing certificates'
 );
 if v_submit->>'status'<>'submitted'
    or v_submit->>'document_state'<>'conditional'
    or v_submit->>'approval_required'<>'true'
    or v_submit->>'student_id' is not null then
   raise exception 'Submission did not queue conditional Principal review: %',v_submit;
 end if;
 update db10_case set application_id=(v_save->>'application_id')::uuid;
 -- No registration takes place until Principal approval.
 begin
   perform public.principal_review_admission(
      (v_save->>'application_id')::uuid,
      (v_save->>'revision')::bigint+1,
      gen_random_uuid(),'approve',null);
   raise exception 'Owner was permitted to approve own application';
 exception when insufficient_privilege then null; end;
end $owner$;

reset role;
do $capture$
begin
 update db10_case c set submitted_revision=a.revision
 from public.admission_applications a where a.id=c.application_id;
 if (select count(*) from public.students)<>32 then
 raise exception 'Student prematurely created'; end if;
 if (select count(*) from public.admission_document_deadline_events e
    join db10_case c on c.application_id=e.application_id)<2 then
 raise exception 'Conditional document deadline events missing'; end if;
end $capture$;

select set_config('request.jwt.claim.sub',
 (select principal_id::text from db10_case limit 1),true);
set local role authenticated;
do $principal$
declare v_case db10_case%rowtype;v_queue jsonb;v_result jsonb;
begin
 select * into strict v_case from db10_case;
 v_queue:=public.principal_admission_queue(
  v_case.school_id,v_case.campus_id,50,0);
 if (v_queue->>'total')::integer <> 1
   or jsonb_array_length(v_queue->'applications')<>1
 then raise exception 'Principal queue is not scoped: %',v_queue; end if;
 begin
   perform public.principal_review_admission(
     v_case.application_id,v_case.submitted_revision-1,
     gen_random_uuid(),'approve',null);
   raise exception 'Stale Principal approval was accepted';
 exception when SQLSTATE '40001' then null; end;
 v_result:=public.principal_review_admission(
    v_case.application_id,v_case.submitted_revision,
    gen_random_uuid(),'approve',null);
 if v_result->>'status'<>'approved'
    or v_result->>'student_id' is null then
   raise exception 'Principal review did not finalize student: %',v_result; end if;
 v_queue:=public.principal_admission_queue(
  v_case.school_id,v_case.campus_id,50,0);
 if (v_queue->>'total')::integer<>0 then
   raise exception 'Reviewed application stayed in Principal queue'; end if;
end $principal$;
reset role;

do $finished$
declare v_case db10_case%rowtype;
begin
 select * into strict v_case from db10_case;
 if (select count(*) from public.students) <> 33
    or (select count(*) from public.student_enrollments where ended_on is null)<>33
    or (select count(*) from public.admission_applications
        where id=v_case.application_id and admission_status='approved'
          and student_id is not null) <>1
    or (select count(*) from public.admission_action_events
      where application_id=v_case.application_id and action='approved')<>1
 then raise exception 'Student finalization/audit not atomic'; end if;
end $finished$;

select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $unknown$
declare v_case db10_case%rowtype;
begin
 select * into strict v_case from db10_case;
 begin
   perform public.principal_admission_queue(v_case.school_id,v_case.campus_id);
   raise exception 'Unknown actor accessed Principal queue';
 exception when insufficient_privilege then null; end;
end $unknown$;
reset role;
rollback;
