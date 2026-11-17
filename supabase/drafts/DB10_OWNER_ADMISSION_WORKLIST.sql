-- DB10: Owner admission worklist for resuming existing drafts.
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
    and a.admission_status in ('draft','returned');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'revision',q.revision,'status',q.admission_status,
    'name',q.applicant_name,'date_of_birth',q.date_of_birth,
    'previous_school',q.previous_school,'academic_year_id',q.academic_year_id,
    'campus_id',q.campus_id,'class_id',q.requested_class_id,
    'section_id',q.requested_section_id,'updated_at',q.updated_at,
    'guardians',q.guardians,'documents',q.documents
  ) order by q.updated_at desc,q.id),'[]'::jsonb)
  into v_rows
  from (
    select a.id,a.revision,a.admission_status,a.applicant_name,
      a.date_of_birth,a.previous_school,a.academic_year_id,a.campus_id,
      a.requested_class_id,a.requested_section_id,a.updated_at,
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
      and a.admission_status in ('draft','returned')
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
