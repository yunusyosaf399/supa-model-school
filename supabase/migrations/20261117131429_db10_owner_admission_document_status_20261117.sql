-- DB10 private document status API for existing Owner draft only.
-- Deliberately excludes storage_path; no file reads or signed URLs.
create or replace function app_private.owner_admission_documents(
  p_application_id uuid
) returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_actor uuid := (select auth.uid()); v_rows jsonb;
begin
  if p_application_id is null or v_actor is null then
    raise exception 'Owner sign-in and application required' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.admission_applications a
    join public.user_roles r on r.school_id=a.school_id and r.user_id=v_actor
    join public.user_profiles up on up.user_id=v_actor
    join auth.users u on u.id=v_actor
    join public.schools sch on sch.id=a.school_id and sch.status='active'
    join public.campuses c on c.id=a.campus_id and c.is_active
    where a.id=p_application_id and a.admission_status in ('draft','returned')
      and r.role='owner' and r.is_active and r.campus_id is null
      and up.is_active and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
  ) then
    raise exception 'Not authorized for these admission documents'
      using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'revision',d.revision,'kind',d.document_kind,
    'required',d.is_required,'applicable',d.is_applicable,
    'status',d.document_status,
    'version',(select max(u.version_no) from public.student_document_uploads u
      where u.document_id=d.id)
  ) order by d.document_kind),'[]'::jsonb) into v_rows
  from public.student_documents d
  where d.application_id=p_application_id;
  return v_rows;
end;
$fn$;
create or replace function public.owner_admission_documents(p_application_id uuid)
 returns jsonb language sql stable security invoker set search_path=''
 as $fn$
 select app_private.owner_admission_documents(p_application_id);
 $fn$;
revoke all on function app_private.owner_admission_documents(uuid)
 from public,anon,authenticated;
revoke all on function public.owner_admission_documents(uuid)
 from public,anon,authenticated;
grant execute on function app_private.owner_admission_documents(uuid) to authenticated;
grant execute on function public.owner_admission_documents(uuid) to authenticated;
