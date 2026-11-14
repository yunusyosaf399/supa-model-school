-- REVIEW DRAFT ONLY. NOT EXECUTED OR DEPLOYED.
-- DB01 Foundation / authorization. Requires Supabase PostgreSQL and auth schema.
-- Apply only after CLI-generated migration, local migration and RLS tests.
begin;

create schema if not exists app_private;
revoke all on schema app_private from public;

create table public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 2 and 200),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  timezone_name text not null check (length(timezone_name) > 2),
  contact_phone text,
  logo_storage_path text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0)
);

create table public.campuses (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  code text not null check (length(btrim(code)) between 1 and 30),
  name text not null check (length(btrim(name)) between 2 and 200),
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (school_id,code),
  unique (id,school_id)
);
create index campuses_school_idx on public.campuses(school_id);

create table public.academic_years (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  label text not null,
  starts_on date not null,
  ends_on date not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  check (ends_on > starts_on),
  unique (school_id,label),
  unique (id,school_id)
);
create unique index one_active_year_per_school on public.academic_years(school_id) where is_active;

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  campus_id uuid not null,
  academic_year_id uuid not null,
  name text not null,
  sort_order integer not null default 0,
  foreign key (campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict,
  foreign key (academic_year_id,school_id)
    references public.academic_years(id,school_id) on delete restrict,
  unique (campus_id,academic_year_id,name),
  unique (id,campus_id,academic_year_id)
);
create index classes_campus_year_idx on public.classes(campus_id,academic_year_id);

create table public.sections (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete restrict,
  name text not null,
  unique (class_id,name),
  unique (id,class_id)
);

-- The auth identity is NOT created by inserting rows here.
create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Membership table MUST NOT be client writable. Owner bootstrap must be
-- performed by a trusted administrator after creating the auth identity.
create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles(user_id) on delete restrict,
  school_id uuid not null references public.schools(id) on delete restrict,
  campus_id uuid,
  role text not null check (role in (
    'owner','super_admin','principal','admin','accountant','attendance_staff'
  )),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  foreign key (campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict,
  check (
    (role in ('owner','super_admin') and campus_id is null) or
    (role not in ('owner','super_admin') and campus_id is not null)
  ),
  unique nulls not distinct (user_id,school_id,campus_id,role)
);
create index user_roles_user_school_idx
  on public.user_roles(user_id,school_id) where is_active;
create index user_roles_campus_idx on public.user_roles(campus_id) where is_active;

create table public.principal_report_permissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles(user_id) on delete restrict,
  school_id uuid not null references public.schools(id) on delete restrict,
  detail_campus_id uuid not null,
  permitted boolean not null default false,
  granted_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  foreign key (detail_campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict,
  unique (user_id,detail_campus_id)
);

create table public.school_settings (
  school_id uuid not null references public.schools(id) on delete restrict,
  setting_key text not null,
  setting_value jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  primary key (school_id,setting_key)
);

create table public.campus_settings (
  school_id uuid not null,
  campus_id uuid not null,
  setting_key text not null,
  setting_value jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  foreign key (campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict,
  primary key (campus_id,setting_key)
);

create table public.registered_devices (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  assigned_campus_id uuid not null,
  registered_user_id uuid not null references public.user_profiles(user_id),
  display_name text not null,
  is_offline_enabled boolean not null default false,
  revoked_at timestamptz,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (assigned_campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict
);

-- Controlled read-only RLS helpers. SECURITY DEFINER is restricted to this
-- unexposed schema to avoid recursive policies on user_roles.
create or replace function app_private.is_school_owner(p_school_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.user_roles r
    join public.user_profiles p on p.user_id = r.user_id
    where r.school_id = p_school_id
      and r.user_id = (select auth.uid())
      and r.role in ('owner','super_admin')
      and r.is_active and p.is_active
  )
$$;

create or replace function app_private.has_school_access(p_school_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.user_roles r
    join public.user_profiles p on p.user_id = r.user_id
    where r.school_id = p_school_id
      and r.user_id = (select auth.uid())
      and r.is_active and p.is_active
  )
$$;

create or replace function app_private.can_read_campus(p_campus_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.campuses c
    join public.user_roles r on r.school_id = c.school_id
    join public.user_profiles p on p.user_id = r.user_id
    where c.id = p_campus_id
      and r.user_id = (select auth.uid())
      and r.is_active and p.is_active
      and (r.role in ('owner','super_admin') or r.campus_id = c.id)
  )
$$;

revoke all on function app_private.is_school_owner(uuid) from public;
revoke all on function app_private.has_school_access(uuid) from public;
revoke all on function app_private.can_read_campus(uuid) from public;
grant usage on schema app_private to authenticated;
grant execute on function app_private.is_school_owner(uuid) to authenticated;
grant execute on function app_private.has_school_access(uuid) to authenticated;
grant execute on function app_private.can_read_campus(uuid) to authenticated;

-- SQL-created public tables do not get automatic RLS.
alter table public.schools enable row level security;
alter table public.campuses enable row level security;
alter table public.academic_years enable row level security;
alter table public.classes enable row level security;
alter table public.sections enable row level security;
alter table public.user_profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.principal_report_permissions enable row level security;
alter table public.school_settings enable row level security;
alter table public.campus_settings enable row level security;
alter table public.registered_devices enable row level security;

-- Baseline is SELECT only: no INSERT/UPDATE/DELETE client grants or policies.
revoke all on public.schools,public.campuses,public.academic_years,
  public.classes,public.sections,public.user_profiles,public.user_roles,
  public.principal_report_permissions,public.school_settings,
  public.campus_settings,public.registered_devices from anon,authenticated;
grant select on public.schools,public.campuses,public.academic_years,
  public.classes,public.sections,public.user_profiles,public.user_roles,
  public.principal_report_permissions,public.school_settings,
  public.campus_settings,public.registered_devices to authenticated;

create policy school_read on public.schools for select to authenticated
  using (app_private.has_school_access(id));
create policy campus_read on public.campuses for select to authenticated
  using (app_private.can_read_campus(id));
create policy year_read on public.academic_years for select to authenticated
  using (app_private.has_school_access(school_id));
create policy class_read on public.classes for select to authenticated
  using (app_private.can_read_campus(campus_id));
create policy section_read on public.sections for select to authenticated
  using (exists (select 1 from public.classes c where c.id = class_id));
create policy own_profile_read on public.user_profiles for select to authenticated
  using (user_id = (select auth.uid()));
create policy own_role_read on public.user_roles for select to authenticated
  using (user_id = (select auth.uid()) or app_private.is_school_owner(school_id));
create policy principal_grant_read on public.principal_report_permissions
  for select to authenticated
  using (user_id = (select auth.uid()) or app_private.is_school_owner(school_id));
create policy school_setting_read on public.school_settings for select to authenticated
  using (app_private.has_school_access(school_id));
create policy campus_setting_read on public.campus_settings for select to authenticated
  using (app_private.can_read_campus(campus_id));
create policy device_read on public.registered_devices for select to authenticated
  using (registered_user_id = (select auth.uid()) or app_private.is_school_owner(school_id));

commit;
-- Review notes:
-- 1. RLS checks must be run with authenticated test users and separate campuses.
-- 2. No owner bootstrap / user management / privilege-changing operations yet.
-- 3. No CRUD policies until authenticated server operations are designed.
-- 4. Validate PostgREST Data API exposure grants in target project.
-- 5. SQL has NOT been executed; migration ordering to be created by CLI.
