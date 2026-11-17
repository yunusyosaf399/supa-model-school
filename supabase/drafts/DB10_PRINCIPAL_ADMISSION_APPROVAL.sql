-- DB10: authenticated admission submission and Principal-only decision bridge.
-- Never trust a client-supplied actor. The existing DB02 workflow is authoritative.
create or replace function app_private.owner_submit_admission(
  p_application_id uuid, p_expected_revision bigint, p_operation_id uuid,
  p_conditional_due date, p_conditional_reason text
) returns jsonb
language plpgsql security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_application public.admission_applications%rowtype;
begin
  if v_actor is null or p_application_id is null or p_operation_id is null
     or p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'Invalid admission submission' using errcode='22023';
  end if;
  select * into v_application from public.admission_applications
   where id=p_application_id;
  if not found then
    raise exception 'Application not found' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.user_roles r
      join public.user_profiles up on up.user_id=r.user_id
      join auth.users u on u.id=r.user_id
      join public.schools s on s.id=r.school_id
      join public.campuses c on c.id=v_application.campus_id
        and c.school_id=s.id
    where r.user_id=v_actor and r.school_id=v_application.school_id
      and r.role='owner' and r.campus_id is null and r.is_active
      and up.is_active and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
      and s.status='active' and c.is_active
  ) then
    raise exception 'Verified Owner required for submission'
      using errcode='42501';
  end if;
  return app_private.admission_submit(v_actor,p_application_id,
    p_expected_revision,p_operation_id,p_conditional_due,p_conditional_reason);
end;
$fn$;

create or replace function public.owner_submit_admission(
  p_application_id uuid, p_expected_revision bigint, p_operation_id uuid,
  p_conditional_due date, p_conditional_reason text
) returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.owner_submit_admission(p_application_id,
    p_expected_revision,p_operation_id,p_conditional_due,p_conditional_reason);
$fn$;

create or replace function app_private.principal_review_admission(
  p_application_id uuid, p_expected_revision bigint, p_operation_id uuid,
  p_decision text, p_reason text
) returns jsonb
language plpgsql security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_application public.admission_applications%rowtype;
begin
  if v_actor is null or p_application_id is null or p_operation_id is null
     or p_expected_revision is null or p_expected_revision < 1
     or p_decision not in ('approve','return','reject') then
    raise exception 'Invalid Principal decision' using errcode='22023';
  end if;
  select * into v_application from public.admission_applications
  where id=p_application_id;
  if not found then
    raise exception 'Application not found' using errcode='42501';
  end if;
  -- Separation of duties: submitter/creator never reviews their own intake.
  if v_application.created_by=v_actor
     or exists (select 1 from public.user_roles own
        where own.user_id=v_actor and own.school_id=v_application.school_id
          and own.role in ('owner','super_admin') and own.is_active)
     or not exists (
       select 1 from public.user_roles r
         join public.user_profiles up on up.user_id=r.user_id
         join auth.users u on u.id=r.user_id
         join public.schools s on s.id=r.school_id
         join public.campuses c on c.id=r.campus_id and c.school_id=s.id
       where r.user_id=v_actor and r.school_id=v_application.school_id
         and r.campus_id=v_application.campus_id
         and r.role='principal' and r.is_active
         and up.is_active and u.email_confirmed_at is not null
         and u.deleted_at is null and u.is_anonymous is not true
         and s.status='active' and c.is_active
     ) then
    raise exception 'Assigned verified Principal required'
      using errcode='42501';
  end if;
  return app_private.admission_review(v_actor,p_application_id,
     p_expected_revision,p_operation_id,p_decision,p_reason);
end;
$fn$;

create or replace function public.principal_review_admission(
  p_application_id uuid,p_expected_revision bigint,p_operation_id uuid,
  p_decision text,p_reason text
) returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.principal_review_admission(p_application_id,
   p_expected_revision,p_operation_id,p_decision,p_reason);
$fn$;

-- Principals can see ONLY submitted/pending records in their assigned campus.
-- No raw table SELECT and no guardian contact or private document download.
create or replace function app_private.principal_admission_queue(
  p_school_id uuid, p_campus_id uuid,
  p_limit integer default 50,p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_total bigint;
  v_items jsonb;
begin
  if v_actor is null or p_school_id is null or p_campus_id is null
    or p_limit is null or p_limit not between 1 and 100
    or p_offset is null or p_offset<0 then
    raise exception 'Invalid approval queue request' using errcode='22023';
  end if;
  if exists(select 1 from public.user_roles r
      where r.user_id=v_actor and r.school_id=p_school_id
        and r.role in ('owner','super_admin') and r.is_active)
    or not exists (
      select 1 from public.user_roles r
       join public.user_profiles up on up.user_id=r.user_id
       join auth.users u on u.id=r.user_id
       join public.schools s on s.id=r.school_id
       join public.campuses c on c.id=r.campus_id and c.school_id=s.id
      where r.user_id=v_actor and r.school_id=p_school_id
       and r.campus_id=p_campus_id and r.role='principal' and r.is_active
       and up.is_active and u.email_confirmed_at is not null
       and u.deleted_at is null and u.is_anonymous is not true
       and s.status='active' and c.is_active
    ) then
      raise exception 'Assigned verified Principal required' using errcode='42501';
  end if;
  select count(*) into v_total from public.admission_applications a
    where a.school_id=p_school_id and a.campus_id=p_campus_id
      and a.admission_status='submitted' and a.approval_state='pending'
      and a.created_by is distinct from v_actor;
  select coalesce(jsonb_agg(jsonb_build_object(
       'id',a.id,'revision',a.revision,'name',a.applicant_name,
       'year_id',a.academic_year_id,
       'documents_state',a.documents_state,
       'conditional_due',a.missing_documents_due_on,
       'conditional_reason',a.conditional_reason,
       'submitted_at',a.submitted_at,
       'pending_documents',(
         select count(*) from public.student_documents d
         where d.application_id=a.id and d.is_required and d.is_applicable
           and d.document_status <> 'verified'
       )
     ) order by a.submitted_at,a.id),'[]'::jsonb)
     into v_items
  from (
    select a.* from public.admission_applications a
    where a.school_id=p_school_id and a.campus_id=p_campus_id
      and a.admission_status='submitted' and a.approval_state='pending'
      and a.created_by is distinct from v_actor
    order by a.submitted_at,a.id
    limit p_limit offset p_offset
  ) a;
  return jsonb_build_object('total',v_total,'applications',v_items);
end;
$fn$;

create or replace function public.principal_admission_queue(
  p_school_id uuid,p_campus_id uuid,
  p_limit integer default 50,p_offset integer default 0
) returns jsonb language sql stable security invoker set search_path=''
as $fn$
 select app_private.principal_admission_queue(
   p_school_id,p_campus_id,p_limit,p_offset);
$fn$;

revoke all on function app_private.owner_submit_admission(uuid,bigint,uuid,date,text)
  from public,anon,authenticated;
revoke all on function public.owner_submit_admission(uuid,bigint,uuid,date,text)
  from public,anon,authenticated;
revoke all on function app_private.principal_review_admission(uuid,bigint,uuid,text,text)
  from public,anon,authenticated;
revoke all on function public.principal_review_admission(uuid,bigint,uuid,text,text)
  from public,anon,authenticated;
revoke all on function app_private.principal_admission_queue(uuid,uuid,integer,integer)
  from public,anon,authenticated;
revoke all on function public.principal_admission_queue(uuid,uuid,integer,integer)
  from public,anon,authenticated;
grant execute on function app_private.owner_submit_admission(uuid,bigint,uuid,date,text)
  to authenticated;
grant execute on function public.owner_submit_admission(uuid,bigint,uuid,date,text)
  to authenticated;
grant execute on function app_private.principal_review_admission(uuid,bigint,uuid,text,text)
  to authenticated;
grant execute on function public.principal_review_admission(uuid,bigint,uuid,text,text)
  to authenticated;
grant execute on function app_private.principal_admission_queue(uuid,uuid,integer,integer)
  to authenticated;
grant execute on function public.principal_admission_queue(uuid,uuid,integer,integer)
  to authenticated;
