-- Remote schema migration 20261116061531, applied to Supa Model School.
-- Note: real school values are supplied by the authorized Owner in Flutter;
-- the migration itself contains no school-specific data or credentials.
-- D02 Owner initial setup, depends on deployed DB01.
-- Only a verified, active, school-wide Owner may complete initial setup.
-- Public RPC is SECURITY INVOKER. Privileged writes happen exclusively in
-- unexposed app_private schema with an explicit authenticated Owner check.
-- No client table UPDATE/INSERT grants are introduced.

create table public.owner_setup_audit_events (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  campus_id uuid not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null default 'initial_setup_completed'
    check (action = 'initial_setup_completed'),
  previous_values jsonb not null,
  new_values jsonb not null,
  created_at timestamptz not null default now(),
  foreign key (campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict
);
create index owner_setup_audit_school_created_idx
  on public.owner_setup_audit_events (school_id,created_at desc);
alter table public.owner_setup_audit_events enable row level security;
revoke all on public.owner_setup_audit_events
  from public, anon, authenticated;
grant select on public.owner_setup_audit_events to authenticated;

create policy owner_setup_audit_select on public.owner_setup_audit_events
  for select to authenticated using (
    exists (
      select 1
      from public.user_roles r
      join public.user_profiles p on p.user_id = r.user_id
      where r.school_id = owner_setup_audit_events.school_id
        and r.user_id = (select auth.uid())
        and r.campus_id is null
        and r.role = 'owner'
        and r.is_active and p.is_active
    )
  );

create function app_private.complete_owner_initial_setup(
  p_school_id uuid,
  p_campus_id uuid,
  p_school_name text,
  p_campus_name text,
  p_currency_code text,
  p_timezone_name text,
  p_year_label text,
  p_year_starts_on date,
  p_year_ends_on date,
  p_expected_school_revision bigint,
  p_expected_campus_revision bigint
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_school public.schools%rowtype;
  v_campus public.campuses%rowtype;
  v_initial jsonb;
  v_year_id uuid;
  v_before jsonb;
  v_after jsonb;
begin
  if v_actor is null or not exists (
    select 1
    from public.user_roles r
    join public.user_profiles p on p.user_id=r.user_id
    join auth.users u on u.id=r.user_id
    where r.user_id=v_actor and r.school_id=p_school_id
      and r.role='owner' and r.campus_id is null and r.is_active
      and p.is_active and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
  ) then
    raise exception 'Active verified school Owner required'
      using errcode='42501';
  end if;

  -- Reject stale clients rather than silently overwriting current settings.
  if p_expected_school_revision is null or p_expected_campus_revision is null
    or p_expected_school_revision < 1 or p_expected_campus_revision < 1 then
    raise exception 'Expected entity revisions are required'
      using errcode='22023';
  end if;

  if p_school_name is null or length(btrim(p_school_name)) not between 2 and 200
     or p_campus_name is null or length(btrim(p_campus_name)) not between 2 and 200
     or p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$'
     or p_currency_code = 'XXX'
     or p_timezone_name is null or length(btrim(p_timezone_name)) < 2
     or p_year_label is null or length(btrim(p_year_label)) not between 4 and 30
     or p_year_starts_on is null or p_year_ends_on is null
     or p_year_ends_on <= p_year_starts_on
     or p_year_ends_on > p_year_starts_on + 550
  then
    raise exception 'Invalid school, campus, currency or academic year fields'
      using errcode='22023';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_timezone_names
    where name = p_timezone_name
  ) then
    raise exception 'Unknown IANA timezone' using errcode='22023';
  end if;

  select * into v_school from public.schools
    where id=p_school_id and status='active' for update;
  if not found then
    raise exception 'School is not active or does not exist'
      using errcode='42501';
  end if;

  select * into v_campus from public.campuses
    where id=p_campus_id and school_id=p_school_id and is_active
    for update;
  if not found then
    raise exception 'Campus is not active or not in school'
      using errcode='42501';
  end if;

  if v_school.revision <> p_expected_school_revision
     or v_campus.revision <> p_expected_campus_revision then
    raise exception 'Stale setup form. Reload before saving'
      using errcode='40001';
  end if;

  select setting_value into v_initial
    from public.school_settings
    where school_id=p_school_id and setting_key='initial_setup'
    for update;
  if not found or coalesce(v_initial->>'status','') <> 'pending' then
    raise exception 'Initial school setup already completed or unavailable'
      using errcode='23514';
  end if;

  if exists (select 1 from public.academic_years where school_id=p_school_id) then
    raise exception 'Academic years exist; use a future year-management operation'
      using errcode='23514';
  end if;

  v_before := pg_catalog.jsonb_build_object(
    'school_name',v_school.name,
    'campus_name',v_campus.name,
    'currency_code',v_school.currency_code,
    'timezone_name',v_school.timezone_name,
    'academic_year',null,
    'school_revision',v_school.revision,
    'campus_revision',v_campus.revision
  );

  update public.schools set name=btrim(p_school_name),
    currency_code=p_currency_code,
    timezone_name=p_timezone_name,
    updated_at=pg_catalog.clock_timestamp(),
    revision=revision+1
  where id=p_school_id;

  update public.campuses set name=btrim(p_campus_name),
    updated_at=pg_catalog.clock_timestamp(),
    revision=revision+1
  where id=p_campus_id and school_id=p_school_id;

  insert into public.academic_years (
    school_id,label,starts_on,ends_on,is_active
  ) values (
    p_school_id,btrim(p_year_label),p_year_starts_on,p_year_ends_on,true
  ) returning id into v_year_id;

  update public.school_settings set
    setting_value=pg_catalog.jsonb_build_object(
      'status','complete',
      'currency_configured',true,
      'timezone_configured',true,
      'campus_configured',true,
      'academic_year_configured',true,
      'academic_year_id',v_year_id,
      'completed_at',pg_catalog.clock_timestamp(),
      'completed_by',v_actor
    ),
    revision=revision+1,
    updated_at=pg_catalog.clock_timestamp()
  where school_id=p_school_id and setting_key='initial_setup';

  v_after := pg_catalog.jsonb_build_object(
    'school_name',btrim(p_school_name),
    'campus_name',btrim(p_campus_name),
    'currency_code',p_currency_code,
    'timezone_name',p_timezone_name,
    'academic_year_id',v_year_id,
    'academic_year_label',btrim(p_year_label),
    'academic_year_starts_on',p_year_starts_on,
    'academic_year_ends_on',p_year_ends_on,
    'school_revision',v_school.revision+1,
    'campus_revision',v_campus.revision+1
  );

  insert into public.owner_setup_audit_events (
    school_id,campus_id,actor_user_id,previous_values,new_values
  ) values (p_school_id,p_campus_id,v_actor,v_before,v_after);

  return pg_catalog.jsonb_build_object(
    'school_id',p_school_id,
    'campus_id',p_campus_id,
    'academic_year_id',v_year_id,
    'school_revision',v_school.revision+1,
    'campus_revision',v_campus.revision+1,
    'setup_status','complete'
  );
end;
$function$;

-- The single public PostgREST entrypoint uses the caller's privileges.
create function public.owner_complete_initial_setup(
  p_school_id uuid,
  p_campus_id uuid,
  p_school_name text,
  p_campus_name text,
  p_currency_code text,
  p_timezone_name text,
  p_year_label text,
  p_year_starts_on date,
  p_year_ends_on date,
  p_expected_school_revision bigint,
  p_expected_campus_revision bigint
) returns jsonb
language sql
security invoker
set search_path = ''
as $function$
 select app_private.complete_owner_initial_setup(
   p_school_id,p_campus_id,p_school_name,p_campus_name,
   p_currency_code,p_timezone_name,p_year_label,
   p_year_starts_on,p_year_ends_on,
   p_expected_school_revision,p_expected_campus_revision
 );
$function$;

revoke all on function app_private.complete_owner_initial_setup(
 uuid,uuid,text,text,text,text,text,date,date,bigint,bigint
) from public, anon, authenticated;
revoke all on function public.owner_complete_initial_setup(
 uuid,uuid,text,text,text,text,text,date,date,bigint,bigint
) from public, anon, authenticated;
grant execute on function app_private.complete_owner_initial_setup(
 uuid,uuid,text,text,text,text,text,date,date,bigint,bigint
) to authenticated;
grant execute on function public.owner_complete_initial_setup(
 uuid,uuid,text,text,text,text,text,date,date,bigint,bigint
) to authenticated;

-- No direct client update on schools/campuses/settings/years/audit.
