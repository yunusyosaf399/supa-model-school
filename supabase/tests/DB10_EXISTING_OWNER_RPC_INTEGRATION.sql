-- DB10 end-to-end integration of EXISTING deployed DB01/DB02 Owner RPCs.
-- Test against disposable local database preferably. Hosted run is rollback-only.
-- PRECONDITION: one school/campus, setup pending, no academic years/classes.
-- Includes temporary, transaction-scoped Owner setup + class audit writes.
begin;

do $preflight$
declare v_count integer;
begin
  if (select count(*) from public.schools) <> 1
    or (select count(*) from public.campuses) <> 1
    or (select count(*) from public.academic_years) <> 0
    or (select count(*) from public.classes) <> 0
    or (select count(*) from public.user_roles where role='owner' and is_active and campus_id is null) <> 1
    or (select count(*) from public.school_settings
         where setting_key='initial_setup'
           and setting_value->>'status'='pending') <> 1 then
    raise exception 'Unsafe fixture: setup must be pending with one school/campus/Owner and no years/classes';
  end if;
  select count(*) into v_count from pg_proc p
    where p.pronamespace='public'::regnamespace
      and p.proname in (
        'owner_complete_initial_setup',
        'owner_create_class_with_sections',
        'owner_dashboard_snapshot'
      );
  if v_count<>3 then raise exception 'Missing existing Owner RPCs'; end if;

  if exists (
    select 1 from pg_proc p
    where p.pronamespace='public'::regnamespace
      and p.proname in (
        'owner_complete_initial_setup',
        'owner_create_class_with_sections',
        'owner_dashboard_snapshot')
      and (p.prosecdef
        or has_function_privilege('anon',p.oid,'EXECUTE')
        or not has_function_privilege('authenticated',p.oid,'EXECUTE'))
  ) then raise exception 'Insecure Owner wrapper privileges'; end if;
end $preflight$;

-- The signed-in Owner identity is taken from the existing bootstrap role.
-- No new auth users are inserted, and the test never prints an identity.
select set_config('request.jwt.claim.sub',
  (select r.user_id::text from public.user_roles r
   join public.user_profiles p on p.user_id=r.user_id
   join auth.users u on u.id=r.user_id
   where r.role='owner' and r.is_active and r.campus_id is null
     and p.is_active and u.email_confirmed_at is not null
     and u.deleted_at is null and u.is_anonymous is not true
   limit 1),true);
set local role authenticated;

do $owner$
declare
  v_school public.schools%rowtype;
  v_campus public.campuses%rowtype;
  v_result jsonb;
  v_class jsonb;
  v_year uuid;
  v_demo jsonb;
  v_live jsonb;
begin
  select * into strict v_school from public.schools;
  select * into strict v_campus from public.campuses;

  select public.owner_dashboard_snapshot(v_school.id,v_campus.id) into v_demo;
  if v_demo->>'is_demo' <> 'true' then
    raise exception 'Pre-setup dashboard must be identified as demo';
  end if;

  v_result := public.owner_complete_initial_setup(
    v_school.id,v_campus.id,v_school.name,v_campus.name,
    'PKR','Asia/Karachi',
    'TEST-2026-2027',date '2026-04-01',date '2027-03-31',
    v_school.revision,v_campus.revision
  );
  v_year := (v_result->>'academic_year_id')::uuid;
  if v_result->>'setup_status'<>'complete'
     or (select count(*) from public.academic_years
         where id=v_year and school_id=v_school.id and is_active)<>1
     or (select count(*) from public.owner_setup_audit_events
         where school_id=v_school.id)<>1 then
    raise exception 'Owner setup not atomic or not audited';
  end if;

  begin
    perform public.owner_complete_initial_setup(
      v_school.id,v_campus.id,v_school.name,v_campus.name,
      'PKR','Asia/Karachi',
      'TEST-2026-2027',date '2026-04-01',date '2027-03-31',
      v_school.revision,v_campus.revision
    );
    raise exception 'Stale setup unexpectedly accepted';
  exception when SQLSTATE '40001' then null;
  end;

  v_class := public.owner_create_class_with_sections(
    v_school.id,v_campus.id,v_year,'DB10 Fixture Grade 1',1,
    array['A','B']::text[]
  );
  if jsonb_array_length(v_class->'sections')<>2
     or (select count(*) from public.academic_structure_audit_events
         where school_id=v_school.id)<>1 then
    raise exception 'Class and section creation or auditing failed';
  end if;

  begin
    perform public.owner_create_class_with_sections(
      v_school.id,v_campus.id,v_year,'db10 fixture grade 1',1,
      array['A','B']::text[]
    );
    raise exception 'Duplicate class was accepted';
  exception when unique_violation then null;
  end;

  select public.owner_dashboard_snapshot(v_school.id,v_campus.id) into v_live;
  if v_live->>'is_demo'<>'false' then
    raise exception 'Dashboard failed to switch from demo to live';
  end if;
end $owner$;

reset role;
select set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001',true);
set local role authenticated;

do $denied$
declare v_school uuid;v_campus uuid;v_year uuid;
begin
  -- No RLS SELECT on school rows for unknown actor; tests use dummy IDs.
  v_school := '00000000-0000-4000-8000-000000000002'::uuid;
  v_campus := '00000000-0000-4000-8000-000000000003'::uuid;
  v_year := '00000000-0000-4000-8000-000000000004'::uuid;
  begin
    perform public.owner_dashboard_snapshot(v_school,v_campus);
    raise exception 'Unknown actor accessed dashboard';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.owner_create_class_with_sections(
      v_school,v_campus,v_year,'Unauthorized',1,array['A']::text[]);
    raise exception 'Unknown actor created class';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.owner_complete_initial_setup(
      v_school,v_campus,'Unauthorized School','Unauthorized Campus',
      'PKR','Asia/Karachi','TEST-2026-2027',date '2026-04-01',
      date '2027-03-31',1,1
    );
    raise exception 'Unknown actor completed setup';
  exception when insufficient_privilege then null;
  end;
end $denied$;
reset role;
rollback;
