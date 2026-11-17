-- Live fixture verification only. Read-only except for transaction-local JWT
-- simulation; no new records are created or deleted by this script.
-- Target: Supa Model School project, 2026-11-17 synthetic fixture.
begin;

do $verify$
declare
  v_school uuid := 'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654';
  v_campus uuid := 'e2308d36-ff0d-438d-97b4-95ed6d4c13c6';
begin
  if (select count(*) from public.academic_years where school_id=v_school and is_active)<>1
  or (select count(*) from public.classes where school_id=v_school and campus_id=v_campus)<>4
  or (select count(*) from public.sections sec join public.classes cl on cl.id=sec.class_id
      where cl.school_id=v_school and cl.campus_id=v_campus)<>8
  or (select count(*) from public.students where school_id=v_school and registration_no like 'TEST-2026-%')<>32
  or (select count(*) from public.student_enrollments where school_id=v_school and campus_id=v_campus and ended_on is null)<>32
  or (select count(*) from public.student_guardians sg join public.students s on s.id=sg.student_id
      where s.school_id=v_school and s.registration_no like 'TEST-2026-%')<>32
  or (select count(*) from public.admission_applications where school_id=v_school and campus_id=v_campus and admission_status='draft' and applicant_name like 'TEST Admission Applicant %')<>5
  or (select count(*) from public.student_documents d join public.admission_applications a on a.id=d.application_id
      where a.school_id=v_school and a.applicant_name like 'TEST Admission Applicant %' and d.document_status='missing')<>10
  or (select count(*) from app_private.dashboard_demo_snapshots where school_id=v_school)<>0
  or (select setting_value->>'status' from public.school_settings where school_id=v_school and setting_key='initial_setup')<>'complete'
  then raise exception 'DB10 live fixture expectation mismatch'; end if;
end $verify$;

-- Simulates a SQL role/JWT context, NOT a genuine HTTP login test.
select set_config('request.jwt.claim.sub',(
  select r.user_id::text from public.user_roles r
  join public.user_profiles p on p.user_id=r.user_id
  join auth.users u on u.id=r.user_id
  where r.role='owner' and r.is_active and r.campus_id is null
    and p.is_active and u.email_confirmed_at is not null
    and u.deleted_at is null and u.is_anonymous is not true
  limit 1),true);
set local role authenticated;

do $owner$
declare v_snapshot jsonb;
begin
  v_snapshot := public.owner_dashboard_snapshot(
    'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
    'e2308d36-ff0d-438d-97b4-95ed6d4c13c6'
  );
  if (v_snapshot->>'is_demo') <> 'false'
  or v_snapshot->>'source' <> 'live_db02_summary'
  or (v_snapshot->>'active_students')::integer <> 32
  or v_snapshot->>'year_label'<>'2026-2027'
  or v_snapshot->>'currency_code'<>'PKR' then
    raise exception 'Verified Owner dashboard returned wrong live fixture';
  end if;
end $owner$;

reset role;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $forbidden$
begin
  begin
    perform public.owner_dashboard_snapshot(
      'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
      'e2308d36-ff0d-438d-97b4-95ed6d4c13c6'
    );
    raise exception 'UNAUTHORIZED dashboard unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $forbidden$;
reset role;
rollback;
