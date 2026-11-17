-- DB10 Admission Draft bridge (Owner-only, authenticated, no document uploads).
-- Existing app_private.admission_save_draft remains the single source of truth.
-- NEVER pass a client-provided actor; this function binds actor to auth.uid().
create or replace function app_private.owner_save_admission_draft(
  p_school_id uuid, p_campus_id uuid, p_academic_year_id uuid,
  p_application_id uuid, p_expected_revision bigint,
  p_operation_id uuid, p_applicant_name text, p_date_of_birth date,
  p_previous_school text, p_class_id uuid, p_section_id uuid,
  p_guardians jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_id uuid;
  v_revision bigint;
begin
  if v_actor is null or p_operation_id is null
     or p_school_id is null or p_campus_id is null
     or p_academic_year_id is null
     or length(btrim(coalesce(p_applicant_name,''))) not between 2 and 200
     or (p_date_of_birth is not null and p_date_of_birth > current_date)
     or (p_application_id is not null and (p_expected_revision is null or p_expected_revision < 1))
     or coalesce(jsonb_typeof(p_guardians),'null') <> 'array'
     or jsonb_array_length(p_guardians)>8 then
    raise exception 'Invalid admission draft request' using errcode='22023';
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
  ) then raise exception 'Verified Owner required' using errcode='42501'; end if;
  if not exists (
    select 1 from public.academic_years y
    where y.id=p_academic_year_id and y.school_id=p_school_id and y.is_active
  ) then raise exception 'Invalid academic year' using errcode='23503'; end if;
  if p_section_id is not null and p_class_id is null then
    raise exception 'Section needs class' using errcode='22023'; end if;
  if p_class_id is not null and not exists (
    select 1 from public.classes cl
    where cl.id=p_class_id and cl.school_id=p_school_id
      and cl.campus_id=p_campus_id and cl.academic_year_id=p_academic_year_id
  ) then raise exception 'Class not in selected campus/year' using errcode='23503'; end if;
  if p_section_id is not null and not exists (
    select 1 from public.sections sec
    where sec.id=p_section_id and sec.class_id=p_class_id
  ) then raise exception 'Section not in selected class' using errcode='23503'; end if;

  v_id := app_private.admission_save_draft(
    v_actor,p_school_id,p_campus_id,p_academic_year_id,
    p_application_id,p_expected_revision,p_operation_id,
    p_applicant_name,p_date_of_birth,p_previous_school,
    p_class_id,p_section_id,p_guardians
  );
  select a.revision into v_revision from public.admission_applications a
  where a.id=v_id and a.school_id=p_school_id and a.campus_id=p_campus_id;
  if v_revision is null then
    raise exception 'Draft save could not be confirmed' using errcode='P0001';
  end if;
  return jsonb_build_object('application_id',v_id,'revision',v_revision,'status','draft');
end;
$fn$;

create or replace function public.owner_save_admission_draft(
  p_school_id uuid, p_campus_id uuid, p_academic_year_id uuid,
  p_application_id uuid, p_expected_revision bigint,
  p_operation_id uuid, p_applicant_name text, p_date_of_birth date,
  p_previous_school text, p_class_id uuid, p_section_id uuid,
  p_guardians jsonb
) returns jsonb language sql security invoker set search_path=''
as $fn$
  select app_private.owner_save_admission_draft(
    p_school_id,p_campus_id,p_academic_year_id,p_application_id,
    p_expected_revision,p_operation_id,p_applicant_name,p_date_of_birth,
    p_previous_school,p_class_id,p_section_id,p_guardians
  );
$fn$;

revoke all on function app_private.owner_save_admission_draft(
 uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb)
 from public,anon,authenticated;
revoke all on function public.owner_save_admission_draft(
 uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb)
 from public,anon,authenticated;
grant execute on function app_private.owner_save_admission_draft(
 uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb) to authenticated;
grant execute on function public.owner_save_admission_draft(
 uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb) to authenticated;
