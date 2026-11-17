-- DB10 Owner admission draft: executes in rollback-only transaction.
-- No persistent students/admissions/guardians/audit records created by this test.
begin;
do $permissions$
begin
 if has_function_privilege('anon',
    'public.owner_save_admission_draft(uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb)',
    'EXECUTE') then raise exception 'Anonymous draft write permitted'; end if;
 if not has_function_privilege('authenticated',
    'public.owner_save_admission_draft(uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb)',
    'EXECUTE') then raise exception 'Authenticated draft execute grant missing'; end if;
 if (select prosecdef from pg_proc where oid='public.owner_save_admission_draft(uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb)'::regprocedure)
 then raise exception 'Public wrapper must be security invoker'; end if;
end $permissions$;

select set_config('request.jwt.claim.sub',
 (select r.user_id::text from public.user_roles r
 join public.user_profiles p on p.user_id=r.user_id
 join auth.users u on u.id=r.user_id
 where r.role='owner' and r.campus_id is null and r.is_active and p.is_active
   and u.email_confirmed_at is not null and u.deleted_at is null
   and u.is_anonymous is not true limit 1),true);
set local role authenticated;

do $owner$
declare
 v_school uuid := 'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654';
 v_campus uuid := 'e2308d36-ff0d-438d-97b4-95ed6d4c13c6';
 v_year uuid := '3157978d-2d08-451b-80d7-13dc83aeddbe';
 v_class uuid;
 v_section uuid;
 v_result jsonb;
 v_second jsonb;
 v_id uuid;
 v_operation uuid := gen_random_uuid();
 v_update uuid := gen_random_uuid();
begin
 select c.id,s.id into strict v_class,v_section
 from public.classes c join public.sections s on s.class_id=c.id
 where c.school_id=v_school and c.campus_id=v_campus
   and c.academic_year_id=v_year and c.name='Grade 1' and s.name='A';

 v_result := public.owner_save_admission_draft(
   v_school,v_campus,v_year,null,null,v_operation,
   'TEST DB10 ROLLBACK Applicant',date '2018-05-20',
   'TEST Previous School',v_class,v_section,
   '[{"full_name":"TEST DB10 Guardian","relationship":"father","phone":"03000000000","is_primary":true,"is_legal_guardian":true}]'::jsonb);
 v_id := (v_result->>'application_id')::uuid;
 if v_result->>'status'<>'draft' or (v_result->>'revision')::int<>1
 then raise exception 'Admission draft creation failed: %',v_result; end if;

 v_second := public.owner_save_admission_draft(
   v_school,v_campus,v_year,null,null,v_operation,
   'TEST DB10 ROLLBACK Applicant',date '2018-05-20',
   'TEST Previous School',v_class,v_section,
   '[]'::jsonb);
 if v_second->>'application_id'<>v_result->>'application_id'
 then raise exception 'Idempotent retry created duplicate'; end if;

 v_second := public.owner_save_admission_draft(
   v_school,v_campus,v_year,v_id,1,v_update,
   'TEST DB10 ROLLBACK Applicant Updated',date '2018-05-20',
   'TEST Previous School',v_class,v_section,'[]'::jsonb);
 if (v_second->>'revision')::int<>2 then
   raise exception 'Draft update did not advance revision'; end if;

 begin
   perform public.owner_save_admission_draft(
     v_school,v_campus,v_year,v_id,1,gen_random_uuid(),
     'TEST DB10 ROLLBACK Applicant Updated',date '2018-05-20',
     '',v_class,v_section,'[]'::jsonb);
   raise exception 'Stale revision accepted';
 exception when SQLSTATE '40001' then null; end;

end $owner$;

reset role;
-- Administrator-only fixture checks; the application role must NOT read these tables.
do $admin_verify$
declare v_id uuid;
begin
 select id into strict v_id from public.admission_applications
 where applicant_name='TEST DB10 ROLLBACK Applicant Updated';
 if (select count(*) from public.student_documents where application_id=v_id)<>2
  or (select count(*) from public.admission_action_events where application_id=v_id)<>2
  or (select count(*) from public.students)<>32
 then raise exception 'Draft documents/audit/student safety checks failed'; end if;
end $admin_verify$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $denied$
begin
 begin
  perform public.owner_save_admission_draft(
   'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
   'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',
   '3157978d-2d08-451b-80d7-13dc83aeddbe',
   null,null,gen_random_uuid(),'TEST unauthorized',date '2018-01-01',
   '',null,null,'[]'::jsonb);
  raise exception 'Unknown actor wrote draft';
 exception when insufficient_privilege then null; end;
end $denied$;
reset role;
rollback;
