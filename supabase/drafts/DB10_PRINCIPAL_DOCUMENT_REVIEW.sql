-- DB10: Principal may inspect registered certificates for submitted
-- applications in their own campus, then verify/reject specific file versions.
-- No public bucket, owner download, broad SELECT, UPDATE or DELETE policy.
alter table public.student_document_reviews
  add column if not exists operation_id uuid;
create unique index if not exists student_document_reviews_school_operation_uidx
  on public.student_document_reviews(school_id,operation_id)
  where operation_id is not null;

create or replace function app_private.principal_can_review_application(
  p_application uuid
) returns boolean language sql stable security definer set search_path=''
as $fn$
 select auth.uid() is not null and exists (
  select 1 from public.admission_applications a
    join public.user_roles r on r.school_id=a.school_id
      and r.campus_id=a.campus_id
    join public.user_profiles up on up.user_id=r.user_id
    join auth.users u on u.id=r.user_id
    join public.schools s on s.id=a.school_id
    join public.campuses c on c.id=a.campus_id and c.school_id=s.id
  where a.id=p_application
    and a.admission_status='submitted' and a.approval_state='pending'
    and a.created_by is distinct from auth.uid()
    and r.user_id=auth.uid() and r.role='principal' and r.is_active
    and up.is_active and u.email_confirmed_at is not null
    and u.deleted_at is null and u.is_anonymous is not true
    and s.status='active' and c.is_active
    and not exists (
     select 1 from public.user_roles owner_role
     where owner_role.user_id=auth.uid()
       and owner_role.school_id=a.school_id
       and owner_role.role in ('owner','super_admin')
       and owner_role.is_active)
 );
$fn$;
revoke all on function app_private.principal_can_review_application(uuid)
 from public,anon,authenticated;
grant execute on function app_private.principal_can_review_application(uuid)
 to authenticated;

create or replace function app_private.principal_can_read_uploaded_object(
 p_bucket text,p_object_path text
) returns boolean language sql stable security definer set search_path=''
as $fn$
  select p_bucket='sms-admission-documents'
    and exists(
      select 1 from public.student_document_uploads u
       join public.student_documents d on d.id=u.document_id
         and d.school_id=u.school_id and d.campus_id=u.campus_id
       where u.storage_bucket=p_bucket and u.object_path=p_object_path
         and d.storage_path=p_object_path
         and d.document_status in ('uploaded','verified','rejected')
         and d.application_id is not null
         and app_private.principal_can_review_application(d.application_id)
    );
$fn$;
revoke all on function app_private.principal_can_read_uploaded_object(text,text)
 from public,anon,authenticated;
grant execute on function app_private.principal_can_read_uploaded_object(text,text)
 to authenticated;

create policy "db10_principal_admission_current_file_read"
 on storage.objects for select to authenticated
 using(bucket_id='sms-admission-documents'
  and app_private.principal_can_read_uploaded_object(bucket_id,name));

create or replace function app_private.principal_document_review_list(
 p_application_id uuid
) returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_documents jsonb;
begin
 if not app_private.principal_can_review_application(p_application_id) then
  raise exception 'Assigned Principal review required' using errcode='42501';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',d.id,'kind',d.document_kind,'required',d.is_required,
  'applicable',d.is_applicable,'status',d.document_status,
  'revision',d.revision,
  'upload_id',u.id,'version',u.version_no,
  'bucket',case when u.id is null then null else u.storage_bucket end,
  'object_path',case when u.id is null then null else u.object_path end,
  'content_type',u.content_type,'size_bytes',u.file_size_bytes
 ) order by d.document_kind),'[]'::jsonb) into v_documents
 from public.student_documents d
 left join lateral (
  select u.* from public.student_document_uploads u
   where u.document_id=d.id and u.object_path=d.storage_path
   order by u.version_no desc limit 1
 ) u on true
 where d.application_id=p_application_id;
 return v_documents;
end;
$fn$;

create or replace function public.principal_document_review_list(p_application_id uuid)
 returns jsonb language sql stable security invoker set search_path=''
as $fn$
 select app_private.principal_document_review_list(p_application_id);
$fn$;
revoke all on function app_private.principal_document_review_list(uuid)
 from public,anon,authenticated;
revoke all on function public.principal_document_review_list(uuid)
 from public,anon,authenticated;
grant execute on function app_private.principal_document_review_list(uuid)
 to authenticated;
grant execute on function public.principal_document_review_list(uuid)
 to authenticated;

create or replace function app_private.principal_review_admission_document(
 p_document_id uuid,p_expected_revision bigint,
 p_operation_id uuid,p_decision text,p_reason text
) returns jsonb
language plpgsql security definer set search_path=''
as $fn$
declare
 v_actor uuid := (select auth.uid());
 v_doc public.student_documents%rowtype;
 v_upload public.student_document_uploads%rowtype;
 v_existing public.student_document_reviews%rowtype;
 v_next text;
begin
 if v_actor is null or p_document_id is null or p_operation_id is null
   or p_expected_revision is null or p_expected_revision<1
   or p_decision not in ('verify','reject') then
   raise exception 'Invalid document review request' using errcode='22023';
 end if;
 select * into v_doc from public.student_documents
  where id=p_document_id for update;
 if not found or v_doc.application_id is null
   or not app_private.principal_can_review_application(v_doc.application_id) then
   raise exception 'Assigned Principal review required' using errcode='42501';
 end if;
 select * into v_existing from public.student_document_reviews
  where school_id=v_doc.school_id and operation_id=p_operation_id;
 if found then
   if v_existing.document_id<>p_document_id
      or v_existing.reviewed_by<>v_actor
      or v_existing.decision <>
           case p_decision when 'verify' then 'verified' else 'rejected' end
   then
     raise exception 'Review operation ID already used' using errcode='23505';
   end if;
   return jsonb_build_object('document_id',v_doc.id,
      'status',v_existing.decision,'revision',v_doc.revision,
      'upload_id',v_existing.upload_id);
 end if;
 if v_doc.revision<>p_expected_revision then
   raise exception 'Document revision conflict' using errcode='40001';
 end if;
 if v_doc.document_status<>'uploaded' then
   raise exception 'Only uploaded documents may be reviewed' using errcode='23514';
 end if;
 if p_decision='reject'
   and length(btrim(coalesce(p_reason,'')))<4 then
   raise exception 'Document rejection needs a reason'
     using errcode='22023';
 end if;
 select * into v_upload from public.student_document_uploads
  where document_id=v_doc.id and object_path=v_doc.storage_path
  order by version_no desc limit 1;
 if not found or not exists (
  select 1 from storage.objects o
  where o.bucket_id=v_upload.storage_bucket and o.name=v_upload.object_path
   and o.archived_at is null and coalesce(o.is_delete_marker,false)=false
 ) then
  raise exception 'Verified stored file version required'
    using errcode='23503';
 end if;
 v_next:=case p_decision when 'verify' then 'verified' else 'rejected' end;
 insert into public.student_document_reviews(
   school_id,campus_id,document_id,upload_id,decision,reason,
   reviewed_by,operation_id
 ) values(v_doc.school_id,v_doc.campus_id,v_doc.id,v_upload.id,
   v_next,case when v_next='rejected' then btrim(p_reason) else null end,
   v_actor,p_operation_id);
 update public.student_documents
 set document_status=v_next,
   verified_by=case when v_next='verified' then v_actor else null end,
   verified_at=case when v_next='verified' then now() else null end,
   rejection_reason=case when v_next='rejected' then btrim(p_reason) else null end,
   revision=revision+1,updated_at=now()
 where id=v_doc.id returning * into v_doc;
 return jsonb_build_object('document_id',v_doc.id,
   'status',v_doc.document_status,'revision',v_doc.revision,
   'upload_id',v_upload.id);
end;
$fn$;

create or replace function public.principal_review_admission_document(
 p_document_id uuid,p_expected_revision bigint,p_operation_id uuid,
 p_decision text,p_reason text
) returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.principal_review_admission_document(
  p_document_id,p_expected_revision,p_operation_id,p_decision,p_reason);
$fn$;
revoke all on function app_private.principal_review_admission_document(uuid,bigint,uuid,text,text)
 from public,anon,authenticated;
revoke all on function public.principal_review_admission_document(uuid,bigint,uuid,text,text)
 from public,anon,authenticated;
grant execute on function app_private.principal_review_admission_document(uuid,bigint,uuid,text,text)
 to authenticated;
grant execute on function public.principal_review_admission_document(uuid,bigint,uuid,text,text)
 to authenticated;
