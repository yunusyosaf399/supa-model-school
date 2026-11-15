-- D03-T03 ADMISSION WORKFLOW EXTENSIONS — REVIEW DRAFT, NOT DEPLOYED.
-- Dependency: DB01_foundation.sql then DB02_admissions.sql.
-- These tables are denied to anon/authenticated; only reviewed trusted
-- backend functions can create/update workflow records.

begin;

alter table public.admission_applications
  add column requested_class_id uuid,
  add column requested_section_id uuid,
  add column client_operation_id uuid,
  add column returned_reason text,
  add column reviewed_by uuid references auth.users(id),
  add column reviewed_at timestamptz,
  add constraint admission_requested_class_fk
    foreign key (requested_class_id,campus_id,academic_year_id)
    references public.classes(id,campus_id,academic_year_id) on delete restrict,
  add constraint admission_requested_section_fk
    foreign key (requested_section_id,requested_class_id)
    references public.sections(id,class_id) on delete restrict,
  add constraint admission_section_requires_class
    check (requested_section_id is null or requested_class_id is not null),
  add constraint admission_approval_requires_student
    check (admission_status <> 'approved' or student_id is not null),
  add constraint admission_rejection_requires_reason
    check (admission_status not in ('returned','rejected')
           or length(btrim(coalesce(returned_reason,''))) > 0),
  add constraint admission_client_op_unique
    unique (school_id,client_operation_id);

-- A draft child has no permanent school registration ID. The normalized
-- name+DOB duplicate search is a REVIEW GUARD, not a lifelong identifier.
-- A trusted Owner exception workflow for genuine same-name same-DOB children
-- is left for subsequent design and must be audited.
create index admission_active_child_candidate_idx
  on public.admission_applications
  (school_id,lower(btrim(applicant_name)),date_of_birth)
  where admission_status in ('draft','submitted','returned');

create table public.admission_application_guardians (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  campus_id uuid not null,
  application_id uuid not null,
  existing_guardian_id uuid,
  full_name text not null check (length(btrim(full_name)) between 2 and 200),
  relationship text not null check (relationship in ('father','mother','guardian','other')),
  phone text,
  is_primary boolean not null default false,
  is_legal_guardian boolean not null default false,
  created_at timestamptz not null default now(),
  foreign key (application_id,school_id,campus_id)
    references public.admission_applications(id,school_id,campus_id) on delete restrict,
  foreign key (existing_guardian_id,school_id)
    references public.guardians(id,school_id) on delete restrict,
  unique (id,application_id)
);
create unique index one_primary_application_guardian
  on public.admission_application_guardians(application_id)
  where is_primary;
create unique index one_parent_role_per_application
  on public.admission_application_guardians(application_id,relationship)
  where relationship in ('father','mother');
create index application_guardians_app_idx
  on public.admission_application_guardians(application_id);

-- Sequence is school-wide rather than campus-wide. Increment happens under
-- a PostgreSQL row lock inside the same transaction as enrollment.
create table public.school_registration_counters (
  school_id uuid primary key references public.schools(id) on delete restrict,
  next_serial bigint not null default 1 check (next_serial between 1 and 999999999)
);

create table public.admission_action_events (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  campus_id uuid not null,
  application_id uuid not null,
  operation_id uuid not null,
  actor_id uuid not null references auth.users(id),
  action text not null check (action in ('draft_created','draft_updated',
     'submitted','approved','returned','rejected')),
  previous_status text,
  result_status text not null,
  message text,
  occurred_at timestamptz not null default now(),
  foreign key (application_id,school_id,campus_id)
    references public.admission_applications(id,school_id,campus_id) on delete restrict,
  unique (school_id,operation_id)
);
create index admission_action_events_application_idx
  on public.admission_action_events(application_id,occurred_at desc);

alter table public.admission_application_guardians enable row level security;
alter table public.school_registration_counters enable row level security;
alter table public.admission_action_events enable row level security;

revoke all on public.admission_application_guardians,
  public.school_registration_counters,public.admission_action_events
  from public,anon,authenticated;

-- The trusted backend runs as database administrator / narrowly scoped server.
-- No RLS policies permit client writes to these tables. A private operation
-- function must validate a verified authenticated actor and current role.
commit;
