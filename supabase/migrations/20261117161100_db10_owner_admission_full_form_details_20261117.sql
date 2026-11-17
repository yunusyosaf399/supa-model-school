-- DB10 admission draft v2: persist the remaining Admission Wizard fields
-- as typed, allowlisted nonfinancial metadata without exposing raw tables.
alter table public.admission_applications
 add column if not exists extra_details jsonb not null default '{}'::jsonb;
do $constraints$
begin
 if not exists(select 1 from pg_constraint
  where conrelid='public.admission_applications'::regclass
    and conname='admission_applications_extra_details_object_check') then
  alter table public.admission_applications add constraint
    admission_applications_extra_details_object_check
      check (jsonb_typeof(extra_details)='object' and
        octet_length(extra_details::text)<=12000);
 end if;
end $constraints$;

create or replace function app_private.owner_save_admission_draft_v2(
  p_school_id uuid,p_campus_id uuid,p_academic_year_id uuid,
  p_application_id uuid,p_expected_revision bigint,p_operation_id uuid,
  p_applicant_name text,p_date_of_birth date,p_previous_school text,
  p_class_id uuid,p_section_id uuid,p_guardians jsonb,p_details jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
 v_key text;
 v_value jsonb;
 v_result jsonb;
 v_id uuid;
 v_revision bigint;
begin
 if p_details is null or jsonb_typeof(p_details)<>'object'
   or octet_length(p_details::text)>12000 then
   raise exception 'Invalid admission details' using errcode='22023';
 end if;
 for v_key in select jsonb_object_keys(p_details) loop
   if v_key not in (
      'gender','nationality','religion','primary_language',
      'notes','birth_certificate_number','identity_number',
      'address','city','emergency_contact','admission_fee_status',
      'uses_transport','transport_notes','requests_discount','discount_notes'
   ) then
     raise exception 'Unsupported admission field' using errcode='22023';
   end if;
   v_value:=p_details->v_key;
   if v_key in ('uses_transport','requests_discount') then
     if jsonb_typeof(v_value)<>'boolean' then
       raise exception 'Invalid admission switch value'
         using errcode='22023';
     end if;
   elsif jsonb_typeof(v_value)<>'string'
      or length(trim(both '"' from v_value::text))>4000 then
       raise exception 'Invalid admission text field' using errcode='22023';
   end if;
 end loop;

 v_result:=app_private.owner_save_admission_draft(
   p_school_id,p_campus_id,p_academic_year_id,p_application_id,
   p_expected_revision,p_operation_id,p_applicant_name,p_date_of_birth,
   p_previous_school,p_class_id,p_section_id,p_guardians);
 v_id:=(v_result->>'application_id')::uuid;
 v_revision:=(v_result->>'revision')::bigint;

 update public.admission_applications a
  set extra_details=p_details
  where a.id=v_id and a.school_id=p_school_id
    and a.campus_id=p_campus_id and a.revision=v_revision
    and a.admission_status in ('draft','returned');
 if not found then
   raise exception 'Draft details revision conflict' using errcode='40001';
 end if;
 return v_result;
end;
$fn$;
create or replace function public.owner_save_admission_draft_v2(
  p_school_id uuid,p_campus_id uuid,p_academic_year_id uuid,
  p_application_id uuid,p_expected_revision bigint,p_operation_id uuid,
  p_applicant_name text,p_date_of_birth date,p_previous_school text,
  p_class_id uuid,p_section_id uuid,p_guardians jsonb,p_details jsonb
) returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.owner_save_admission_draft_v2(
  p_school_id,p_campus_id,p_academic_year_id,p_application_id,
  p_expected_revision,p_operation_id,p_applicant_name,p_date_of_birth,
  p_previous_school,p_class_id,p_section_id,p_guardians,p_details);
$fn$;

revoke all on function app_private.owner_save_admission_draft_v2(
 uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb,jsonb)
 from public,anon,authenticated;
revoke all on function public.owner_save_admission_draft_v2(
 uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb,jsonb)
 from public,anon,authenticated;
grant execute on function app_private.owner_save_admission_draft_v2(
 uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb,jsonb)
 to authenticated;
grant execute on function public.owner_save_admission_draft_v2(
 uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb,jsonb)
 to authenticated;

-- Reuse the Owner-only worklist grant and return the allowlisted details
-- for Resume, but never storage paths or private file objects.
-- DB10: Owner admission register: drafts, pending, returned, approved, rejected.
-- Sensitive applicant/guardian data is projected only after verified Owner check.
-- No document storage paths or downloads are exposed.
create or replace function app_private.owner_admission_worklist(
  p_school_id uuid, p_campus_id uuid,
  p_limit integer default 50, p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_total bigint;
  v_rows jsonb;
begin
  if v_actor is null or p_school_id is null or p_campus_id is null
     or p_limit is null or p_limit not between 1 and 100
     or p_offset is null or p_offset < 0 then
    raise exception 'Invalid admission worklist request' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.user_roles r
    join public.user_profiles up on up.user_id=r.user_id
    join auth.users u on u.id=r.user_id
    join public.schools sch on sch.id=r.school_id
    join public.campuses ca on ca.id=p_campus_id and ca.school_id=sch.id
    where r.user_id=v_actor and r.school_id=p_school_id
      and r.role='owner' and r.campus_id is null and r.is_active
      and up.is_active and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
      and sch.status='active' and ca.is_active
  ) then
    raise exception 'Verified Owner required' using errcode='42501';
  end if;

  select count(*) into v_total from public.admission_applications a
  where a.school_id=p_school_id and a.campus_id=p_campus_id
;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'revision',q.revision,'status',q.admission_status,
    'name',q.applicant_name,'date_of_birth',q.date_of_birth,
    'previous_school',q.previous_school,'academic_year_id',q.academic_year_id,
    'campus_id',q.campus_id,'class_id',q.requested_class_id,
    'section_id',q.requested_section_id,'updated_at',q.updated_at,
    'approval_state',q.approval_state,'documents_state',q.documents_state,
    'student_id',q.student_id,'conditional_due',q.missing_documents_due_on,
    'conditional_reason',q.conditional_reason,
    'returned_reason',q.returned_reason,'submitted_at',q.submitted_at,
    'guardians',q.guardians,'documents',q.documents,
    'extra_details',q.extra_details
  ) order by q.updated_at desc,q.id),'[]'::jsonb)
  into v_rows
  from (
    select a.id,a.revision,a.admission_status,a.applicant_name,
      a.date_of_birth,a.previous_school,a.academic_year_id,a.campus_id,
      a.requested_class_id,a.requested_section_id,a.updated_at,
      a.approval_state,a.documents_state,a.student_id,a.missing_documents_due_on,
      a.conditional_reason,a.returned_reason,a.submitted_at,a.extra_details,
      (select coalesce(jsonb_agg(jsonb_build_object(
        'full_name',g.full_name,'relationship',g.relationship,
        'phone',g.phone,'is_primary',g.is_primary,
        'is_legal_guardian',g.is_legal_guardian
      ) order by g.is_primary desc,g.id),'[]'::jsonb)
       from public.admission_application_guardians g
       where g.application_id=a.id and g.school_id=a.school_id
         and g.campus_id=a.campus_id) guardians,
      (select coalesce(jsonb_agg(jsonb_build_object(
        'kind',d.document_kind,'required',d.is_required,
        'applicable',d.is_applicable,'status',d.document_status,
        'due_on',d.submission_due_on
      ) order by d.document_kind),'[]'::jsonb)
       from public.student_documents d
       where d.application_id=a.id and d.school_id=a.school_id
         and d.campus_id=a.campus_id) documents
    from public.admission_applications a
    where a.school_id=p_school_id and a.campus_id=p_campus_id
  
    order by a.updated_at desc,a.id
    limit p_limit offset p_offset
  ) q;
  return jsonb_build_object('total',v_total,'applications',v_rows);
end;
$fn$;

create or replace function public.owner_admission_worklist(
  p_school_id uuid,p_campus_id uuid,
  p_limit integer default 50,p_offset integer default 0
) returns jsonb language sql stable security invoker set search_path=''
as $fn$
  select app_private.owner_admission_worklist(
    p_school_id,p_campus_id,p_limit,p_offset
  );
$fn$;

revoke all on function app_private.owner_admission_worklist(uuid,uuid,integer,integer)
 from public,anon,authenticated;
revoke all on function public.owner_admission_worklist(uuid,uuid,integer,integer)
 from public,anon,authenticated;
grant execute on function app_private.owner_admission_worklist(uuid,uuid,integer,integer)
 to authenticated;
grant execute on function public.owner_admission_worklist(uuid,uuid,integer,integer)
 to authenticated;

