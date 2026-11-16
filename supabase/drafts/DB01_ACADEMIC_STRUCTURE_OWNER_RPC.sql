-- DB01 academic structure v1: school Owner creates classes and sections.
-- Requires DB01 foundation and completed Owner initial setup (version 20261116061531).
-- Privileged DML is isolated in app_private with an explicit active Owner check.
-- No client grants to INSERT/UPDATE classes, sections or audit tables.

-- Case-folded uniqueness protects against variants like Grade 1 / grade 1.
create unique index if not exists classes_campus_year_ci_uq
  on public.classes (campus_id, academic_year_id, lower(btrim(name)));
create unique index if not exists sections_class_ci_uq
  on public.sections (class_id, lower(btrim(name)));

create table public.academic_structure_audit_events (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  campus_id uuid not null,
  academic_year_id uuid not null,
  class_id uuid not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null default 'class_created'
    check (action = 'class_created'),
  details jsonb not null,
  created_at timestamptz not null default now(),
  foreign key (campus_id, school_id)
    references public.campuses(id,school_id) on delete restrict,
  foreign key (academic_year_id, school_id)
    references public.academic_years(id,school_id) on delete restrict,
  foreign key (class_id, campus_id, academic_year_id)
    references public.classes(id,campus_id,academic_year_id) on delete restrict
);
create index academic_structure_audit_scope_idx
 on public.academic_structure_audit_events(school_id,campus_id,created_at desc);
alter table public.academic_structure_audit_events enable row level security;
revoke all on public.academic_structure_audit_events from public,anon,authenticated;
grant select on public.academic_structure_audit_events to authenticated;
create policy owner_read_academic_structure_audit
 on public.academic_structure_audit_events
 for select to authenticated using (
   exists (
     select 1 from public.user_roles r
     join public.user_profiles p on p.user_id=r.user_id
     where r.school_id=academic_structure_audit_events.school_id
       and r.user_id=(select auth.uid())
       and r.role='owner' and r.campus_id is null
       and r.is_active and p.is_active
   )
 );

create function app_private.owner_create_class_with_sections(
  p_school_id uuid,
  p_campus_id uuid,
  p_academic_year_id uuid,
  p_class_name text,
  p_sort_order integer,
  p_sections text[]
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_actor uuid := auth.uid();
  v_class_id uuid;
  v_year public.academic_years%rowtype;
  v_campus public.campuses%rowtype;
  v_school public.schools%rowtype;
  v_setup jsonb;
  v_section_count integer;
  v_unique_count integer;
  v_sections jsonb;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles r
    join public.user_profiles p on p.user_id=r.user_id
    join auth.users u on u.id=r.user_id
    where r.user_id=v_actor and r.school_id=p_school_id
      and r.role='owner' and r.campus_id is null
      and r.is_active and p.is_active
      and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
  ) then
    raise exception 'Active verified school Owner required'
      using errcode='42501';
  end if;

  if p_school_id is null or p_campus_id is null or p_academic_year_id is null
     or p_class_name is null or length(btrim(p_class_name)) not between 1 and 100
     or p_sort_order is null or p_sort_order not between 0 and 1000
     or p_sections is null or cardinality(p_sections) not between 1 and 12
  then
    raise exception 'Invalid class/section details'
      using errcode='22023';
  end if;

  -- No blank/duplicate section labels, even if spelling/case differs.
  select count(*), count(distinct lower(btrim(parts.section_name)))
    into v_section_count,v_unique_count
  from unnest(p_sections) as parts(section_name);

  if v_section_count <> cardinality(p_sections)
    or v_unique_count <> v_section_count
    or exists (
      select 1 from unnest(p_sections) as parts(section_name)
      where parts.section_name is null or length(btrim(parts.section_name)) not between 1 and 50
    )
  then
    raise exception 'Section labels must be 1-50 chars and unique'
      using errcode='22023';
  end if;

  select * into v_school from public.schools
    where id=p_school_id and status='active' for share;
  if not found then
    raise exception 'Active school required' using errcode='42501';
  end if;

  select * into v_campus from public.campuses
    where id=p_campus_id and school_id=p_school_id and is_active for share;
  if not found then
    raise exception 'Authorized active campus required' using errcode='42501';
  end if;

  -- Lock one academic-year row to serialize concurrent class creation.
  select * into v_year from public.academic_years
    where id=p_academic_year_id and school_id=p_school_id and is_active
    for update;
  if not found then
    raise exception 'Active academic year required' using errcode='23514';
  end if;

  select setting_value into v_setup
    from public.school_settings
    where school_id=p_school_id and setting_key='initial_setup';
  if coalesce(v_setup->>'status','') <> 'complete' then
    raise exception 'Complete Owner school setup first' using errcode='23514';
  end if;

  if exists (
    select 1 from public.classes
    where campus_id=p_campus_id and academic_year_id=p_academic_year_id
      and lower(btrim(name))=lower(btrim(p_class_name))
  ) then
    raise exception 'This class already exists in the chosen campus and year'
      using errcode='23505';
  end if;

  insert into public.classes(school_id,campus_id,academic_year_id,name,sort_order)
    values(p_school_id,p_campus_id,p_academic_year_id,
      btrim(p_class_name),p_sort_order)
    returning id into v_class_id;

  insert into public.sections(class_id,name)
    select v_class_id,btrim(parts.section_name)
    from unnest(p_sections) as parts(section_name);

  select coalesce(
    jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name),
    '[]'::jsonb
  ) into v_sections from public.sections s where s.class_id=v_class_id;

  insert into public.academic_structure_audit_events(
    school_id,campus_id,academic_year_id,class_id,actor_user_id,details
  ) values (
    p_school_id,p_campus_id,p_academic_year_id,v_class_id,v_actor,
    jsonb_build_object('class_name',btrim(p_class_name),
      'sort_order',p_sort_order,'sections',v_sections)
  );

  return jsonb_build_object(
    'class_id',v_class_id,'class_name',btrim(p_class_name),
    'campus_id',p_campus_id,'academic_year_id',p_academic_year_id,
    'sections',v_sections
  );
end;
$function$;

-- PostgREST only exposes this SECURITY INVOKER wrapper.
create function public.owner_create_class_with_sections(
  p_school_id uuid,
  p_campus_id uuid,
  p_academic_year_id uuid,
  p_class_name text,
  p_sort_order integer,
  p_sections text[]
) returns jsonb
language sql security invoker set search_path=''
as $function$
  select app_private.owner_create_class_with_sections(
    p_school_id,p_campus_id,p_academic_year_id,
    p_class_name,p_sort_order,p_sections
  );
$function$;

revoke all on function app_private.owner_create_class_with_sections(
  uuid,uuid,uuid,text,integer,text[]
) from public,anon,authenticated;
revoke all on function public.owner_create_class_with_sections(
  uuid,uuid,uuid,text,integer,text[]
) from public,anon,authenticated;
grant execute on function app_private.owner_create_class_with_sections(
  uuid,uuid,uuid,text,integer,text[]
) to authenticated;
grant execute on function public.owner_create_class_with_sections(
  uuid,uuid,uuid,text,integer,text[]
) to authenticated;
