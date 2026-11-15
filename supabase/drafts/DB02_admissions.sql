-- REVIEW DRAFT ONLY. NOT EXECUTED OR DEPLOYED.
-- DB02 admissions, students, guardians, document deadlines and enrollments.
-- Depends on DB01; RLS is enabled but fully deny-by-default pending policies.
begin;

create table public.students (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  -- Assigned only by a trusted admission finalization operation; never by
  -- untrusted direct client writes.
  registration_no text not null
    check (registration_no = btrim(registration_no)
           and length(registration_no) between 1 and 40),
  full_name_en text not null
    check (length(btrim(full_name_en)) between 2 and 200),
  full_name_ur text,
  date_of_birth date,
  gender text check (gender in ('male','female','other')),
  photo_storage_path text,
  -- Keep sensitive medical files outside this general-purpose identity row.
  active_status text not null default 'active'
    check (active_status in ('active','inactive','withdrawn','graduated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  revision bigint not null default 1 check (revision > 0),
  unique (school_id,registration_no),
  unique (id,school_id)
);
-- Prevent case-only variants of the same human registration number.
create unique index students_school_registration_ci_uq
  on public.students (school_id, lower(registration_no));
create index students_school_name_lookup_idx
  on public.students (school_id, lower(full_name_en));
create index students_school_status_idx
  on public.students (school_id, active_status);

create table public.guardians (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  full_name text not null
    check (length(btrim(full_name)) between 2 and 200),
  full_name_ur text,
  phone text,
  alternate_phone text,
  government_id text,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id,school_id)
);
-- A guardian may be linked to several siblings within the SAME school.
create index guardians_school_name_lookup_idx
  on public.guardians (school_id, lower(full_name));
create index guardians_school_phone_idx
  on public.guardians (school_id, phone)
  where phone is not null;

create table public.student_guardians (
  student_id uuid not null,
  guardian_id uuid not null,
  school_id uuid not null,
  relationship text not null
    check (relationship in ('father','mother','guardian','other')),
  is_primary boolean not null default false,
  emergency_contact boolean not null default false,
  is_legal_guardian boolean not null default false,
  added_at timestamptz not null default now(),
  foreign key (student_id,school_id)
    references public.students(id,school_id) on delete restrict,
  foreign key (guardian_id,school_id)
    references public.guardians(id,school_id) on delete restrict,
  primary key (student_id,guardian_id)
);
create unique index one_primary_guardian_per_student
  on public.student_guardians(student_id) where is_primary;
-- Separate father/mother relationships can be shared with siblings; this
-- index prevents duplicate father/mother links for the SAME student.
create unique index one_parent_relationship_per_student
  on public.student_guardians(student_id,relationship)
  where relationship in ('father','mother');
create index student_guardians_school_guardian_idx
  on public.student_guardians (school_id,guardian_id);
-- "At least one primary contact" is validated during admission approval,
-- not by allowing direct inserts into an RLS-protected link table.

create table public.admission_applications (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  campus_id uuid not null,
  academic_year_id uuid not null,
  student_id uuid,
  applicant_name text not null,
  date_of_birth date,
  previous_school text,
  -- Student may be enrolled conditionally before all documents are verified.
  -- Admission approval and documentation completeness are separate states.
  admission_status text not null default 'draft'
    check (admission_status in ('draft','submitted','approved','returned','rejected')),
  approval_state text not null default 'not_required'
    check (approval_state in ('not_required','pending','approved','returned','rejected')),
  documents_state text not null default 'incomplete'
    check (documents_state in ('complete','conditional','incomplete')),
  missing_documents_due_on date,
  conditional_reason text,
  submitted_at timestamptz,
  approved_at timestamptz,
  approved_by uuid references auth.users(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  foreign key (campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict,
  foreign key (academic_year_id,school_id)
    references public.academic_years(id,school_id) on delete restrict,
  foreign key (student_id,school_id)
    references public.students(id,school_id) on delete restrict,
  check (documents_state <> 'conditional' or missing_documents_due_on is not null),
  check (
    admission_status <> 'approved'
    or (documents_state in ('complete','conditional')
        and approval_state in ('not_required','approved'))
  ),
  unique (id,school_id),
  unique (id,campus_id),
  unique (id,school_id,campus_id),
  unique (id,student_id)
);
create index admissions_campus_status_idx
  on public.admission_applications(campus_id,admission_status);

-- A student_documents row represents ONE document requirement per application.
-- Optional/nonapplicable transfer certificates must not become overdue.
-- The latest object pointer is retained for quick reads; immutable versions
-- and review events live in the two tables below.
create table public.student_documents (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  campus_id uuid not null,
  application_id uuid not null,
  student_id uuid,
  document_kind text not null
    check (document_kind in ('birth_certificate','transfer_certificate','photo','other')),
  document_label text,
  is_required boolean not null default false,
  is_applicable boolean not null default true,
  document_status text not null default 'missing'
    check (document_status in ('missing','uploaded','verified','rejected')),
  submission_due_on date,
  storage_path text,
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  revision bigint not null default 1 check (revision > 0),
  foreign key (application_id,school_id,campus_id)
    references public.admission_applications(id,school_id,campus_id) on delete restrict,
  foreign key (student_id,school_id)
    references public.students(id,school_id) on delete restrict,
  foreign key (application_id,student_id)
    references public.admission_applications(id,student_id) on delete restrict,
  check (is_applicable or not is_required),
  check (document_kind <> 'other' or length(btrim(coalesce(document_label,''))) > 0),
  check (document_status <> 'missing' or storage_path is null),
  check (document_status not in ('uploaded','verified','rejected') or storage_path is not null),
  check (document_status <> 'verified' or
          (verified_at is not null and verified_by is not null)),
  check (document_status <> 'rejected' or
          length(btrim(coalesce(rejection_reason,''))) > 0),
  unique (id,school_id,campus_id),
  unique (id,application_id)
);
create unique index one_standard_requirement_per_application
  on public.student_documents(application_id,document_kind)
  where document_kind <> 'other';
create unique index one_other_requirement_label_per_application
  on public.student_documents(application_id,lower(document_label))
  where document_kind = 'other';
create index documents_pending_idx
  on public.student_documents(campus_id,submission_due_on)
  where is_required and is_applicable and document_status <> 'verified';
create index documents_application_lookup_idx
  on public.student_documents(application_id,document_status);

-- Every upload is kept as an immutable metadata/version record. The Storage
-- object itself resides in a private bucket protected by separate policies.
create table public.student_document_uploads (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  campus_id uuid not null,
  document_id uuid not null,
  version_no integer not null check (version_no > 0),
  storage_bucket text not null check (length(btrim(storage_bucket)) > 0),
  object_path text not null check (length(btrim(object_path)) > 0),
  content_type text not null
    check (content_type in ('application/pdf','image/jpeg','image/png','image/webp')),
  file_size_bytes bigint not null check (file_size_bytes > 0),
  sha256_hex text check (sha256_hex ~ '^[a-fA-F0-9]{64}$'),
  uploaded_by uuid not null references auth.users(id),
  uploaded_at timestamptz not null default now(),
  foreign key (document_id,school_id,campus_id)
    references public.student_documents(id,school_id,campus_id) on delete restrict,
  unique (document_id,version_no),
  unique (id,document_id)
);
create index student_document_uploads_doc_idx
  on public.student_document_uploads(document_id,version_no desc);

-- A verification/rejection decision refers to a PARTICULAR upload version.
-- These rows should be append-only under a trusted, audited server operation.
create table public.student_document_reviews (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  campus_id uuid not null,
  document_id uuid not null,
  upload_id uuid not null,
  decision text not null check (decision in ('verified','rejected')),
  reason text,
  reviewed_by uuid not null references auth.users(id),
  reviewed_at timestamptz not null default now(),
  foreign key (document_id,school_id,campus_id)
    references public.student_documents(id,school_id,campus_id) on delete restrict,
  foreign key (upload_id,document_id)
    references public.student_document_uploads(id,document_id) on delete restrict,
  check (decision <> 'rejected' or length(btrim(coalesce(reason,''))) > 0),
  unique (upload_id,decision,reviewed_by,reviewed_at)
);
create index student_document_reviews_doc_idx
  on public.student_document_reviews(document_id,reviewed_at desc);

-- Extension of conditional deadlines must be justified and recorded.
-- Applications may have a common deadline; individual documents can also
-- have their own due dates. Past deadlines are never silently discarded.
create table public.admission_document_deadline_events (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  campus_id uuid not null,
  application_id uuid not null,
  document_id uuid,
  old_due_on date,
  new_due_on date not null,
  reason text not null check (length(btrim(reason)) > 0),
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  foreign key (application_id,school_id,campus_id)
    references public.admission_applications(id,school_id,campus_id) on delete restrict,
  foreign key (document_id,application_id)
    references public.student_documents(id,application_id) on delete restrict,
  check (old_due_on is distinct from new_due_on)
);
create index admission_document_deadline_events_idx
  on public.admission_document_deadline_events(application_id,changed_at desc);

create table public.student_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null,
  school_id uuid not null,
  campus_id uuid not null,
  academic_year_id uuid not null,
  class_id uuid not null,
  section_id uuid,
  class_roll_no text,
  admitted_on date not null,
  ended_on date,
  end_reason text,
  created_at timestamptz not null default now(),
  foreign key (student_id,school_id)
    references public.students(id,school_id) on delete restrict,
  foreign key (campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict,
  foreign key (academic_year_id,school_id)
    references public.academic_years(id,school_id) on delete restrict,
  foreign key (class_id,campus_id,academic_year_id)
    references public.classes(id,campus_id,academic_year_id) on delete restrict,
  foreign key (section_id,class_id)
    references public.sections(id,class_id) on delete restrict,
  check (ended_on is null or ended_on >= admitted_on),
  unique (id,student_id)
);
create unique index one_active_enrollment_per_student
  on public.student_enrollments(student_id) where ended_on is null;
create unique index unique_active_class_roll
  on public.student_enrollments(section_id,class_roll_no)
  where ended_on is null and section_id is not null and class_roll_no is not null;
create index enrollments_campus_year_idx
  on public.student_enrollments(campus_id,academic_year_id);

create table public.campus_transfer_requests (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  student_id uuid not null,
  from_campus_id uuid not null,
  to_campus_id uuid not null,
  requested_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  decision_at timestamptz,
  reason text not null,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','cancelled')),
  created_at timestamptz not null default now(),
  foreign key (student_id,school_id)
    references public.students(id,school_id) on delete restrict,
  foreign key (from_campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict,
  foreign key (to_campus_id,school_id)
    references public.campuses(id,school_id) on delete restrict,
  check (from_campus_id <> to_campus_id)
);

-- Debt-collection transfers must be introduced AFTER fee_charges in DB03
-- and must reference the original charge without creating new revenue.
-- Overdue is derived from due date + verified status, not a mutable state.

alter table public.students enable row level security;
alter table public.guardians enable row level security;
alter table public.student_guardians enable row level security;
alter table public.admission_applications enable row level security;
alter table public.student_documents enable row level security;
alter table public.student_document_uploads enable row level security;
alter table public.student_document_reviews enable row level security;
alter table public.admission_document_deadline_events enable row level security;
alter table public.student_enrollments enable row level security;
alter table public.campus_transfer_requests enable row level security;

-- NO client grants/policies yet. Explicitly deny until field-level permission
-- matrix, authorization helpers, campus-transfer visibility are tested.
revoke all on public.students,public.guardians,public.student_guardians,
  public.admission_applications,public.student_documents,
  public.student_document_uploads,public.student_document_reviews,
  public.admission_document_deadline_events,public.student_enrollments,
  public.campus_transfer_requests from public,anon,authenticated;

commit;
-- Review notes:
-- 1. Need secure, serialized permanent registration/roll number allocation.
-- 2. Need one-active-application-per-child business key and duplicate check.
-- 3. Need authorization policies for campus-bound staff and owner.
-- 4. Need conditional doc approval policy and delayed upload workflow.
-- 5. Need storage bucket access, audit and trusted server mutations.
-- 6. No actual migration/test/deployment performed.
-- 7. D03-T01 authoring review: school-scoped FK to students/guardians,
--    normalized registration uniqueness, one primary guardian, sibling reuse.
-- 8. Student and guardian data remain completely inaccessible through
--    authenticated/anon Data API until explicit reviewed RLS policies exist.
-- 9. These data tables have NO INSERT/UPDATE/DELETE clients or policies.
-- 10. A trusted server operation must issue permanent registration numbers.
-- 11. Conditional enrollment remains permitted with a recorded document deadline.
--     Required-document presence and approval transition logic must be checked
--     atomically by a trusted server operation; a row CHECK cannot count siblings.
-- 12. Missing-document OVERDUE is derived from due date in school-local timezone.
--     Expiration does NOT automatically remove an enrolled student.
-- 13. Upload version/review/deadline history is append-only by business rule.
-- 14. Storage access policies and document verification RPC are not implemented.
-- 15. DB02 DDL has NOT been executed against local or hosted PostgreSQL.
