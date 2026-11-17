begin;
do $preflight$
begin
 if has_function_privilege('anon',
   'public.owner_register_admission_upload(uuid,text,bigint)','EXECUTE')
   or not has_function_privilege('authenticated',
   'public.owner_register_admission_upload(uuid,text,bigint)','EXECUTE')
 then raise exception 'Unsafe registration grants'; end if;
 if exists(select 1 from pg_policies where schemaname='storage'
    and tablename='objects' and policyname='db10_admission_object_insert_owner_only'
    and cmd <> 'INSERT') then raise exception 'Upload policy is not INSERT-only'; end if;
end $preflight$;

-- PostgreSQL fixture simulation: an object is inserted by trusted SQL
-- WITHOUT uploading bytes. This tests database authorization and metadata
-- linkage only; not the real Storage HTTP upload or file signatures.
create temporary table db10_upload_case (
  document_id uuid, object_path text, revision bigint, owner_id uuid
) on commit drop;
grant select on db10_upload_case to authenticated;

select set_config('request.jwt.claim.sub',
 (select r.user_id::text from public.user_roles r
   join public.user_profiles p on p.user_id=r.user_id
   join auth.users u on u.id=r.user_id
   where r.role='owner' and r.is_active and r.campus_id is null
     and p.is_active and u.email_confirmed_at is not null
     and u.deleted_at is null and u.is_anonymous is not true limit 1),true);
set local role authenticated;
do $auth$
declare
 v_doc public.student_documents%rowtype;
 v_app public.admission_applications%rowtype;
 v_path text;
begin
 -- Privileged table read is unavailable to authenticated; do not read it.
 null;
end $auth$;
reset role;

do $prepare$
declare v_doc public.student_documents%rowtype;
 v_app public.admission_applications%rowtype;
 v_path text;
 v_owner uuid;
begin
 select d.* into strict v_doc from public.student_documents d
 join public.admission_applications a on a.id=d.application_id
 where a.applicant_name='TEST Admission Applicant 001'
   and d.document_kind='birth_certificate';
 select * into strict v_app from public.admission_applications where id=v_doc.application_id;
 select user_id into strict v_owner from public.user_roles
    where role='owner' and campus_id is null and is_active;
 v_path:=v_doc.school_id::text||'/'||v_doc.campus_id::text||'/'||
  v_app.id::text||'/'||v_doc.id::text||'/'||gen_random_uuid()::text||'.pdf';
 insert into db10_upload_case values(v_doc.id,v_path,v_doc.revision,v_owner);
end $prepare$;

select set_config('request.jwt.claim.sub',
 (select owner_id::text from db10_upload_case limit 1),true);
set local role authenticated;
do $owner$
declare v_path text;
begin
 select object_path into strict v_path from db10_upload_case;
 if not app_private.can_insert_admission_object('sms-admission-documents',v_path)
 then raise exception 'Valid Owner upload was denied'; end if;
 if app_private.can_insert_admission_object('another-bucket',v_path)
    or app_private.can_insert_admission_object('sms-admission-documents','invalid/path.pdf')
 then raise exception 'Invalid path accepted'; end if;
end $owner$;
reset role;

-- metadata fixture is inserted by postgres (not through Storage HTTP)
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'sms-admission-documents',object_path,owner_id::text,
  '{"size":1024,"mimetype":"application/pdf"}'::jsonb from db10_upload_case;

select set_config('request.jwt.claim.sub',
 (select owner_id::text from db10_upload_case limit 1),true);
set local role authenticated;
do $register$
declare v_case db10_upload_case%rowtype;v jsonb;v_again jsonb;
begin
 select * into strict v_case from db10_upload_case;
 v:=public.owner_register_admission_upload(
   v_case.document_id,v_case.object_path,v_case.revision);
 if v->>'status'<>'uploaded' or (v->>'version')::int<>1
    or (v->>'revision')::bigint<>v_case.revision+1 then
    raise exception 'Registration did not mark uploaded: %',v; end if;
 v_again:=public.owner_register_admission_upload(
   v_case.document_id,v_case.object_path,v_case.revision);
 if v_again->>'version'<>v->>'version' then
    raise exception 'Upload retry not idempotent'; end if;
end $register$;
reset role;

do $admin_verify$
declare v_case db10_upload_case%rowtype;
begin
 select * into strict v_case from db10_upload_case;
 if (select count(*) from public.student_document_uploads
     where document_id=v_case.document_id and object_path=v_case.object_path)<>1
   or (select document_status from public.student_documents
       where id=v_case.document_id)<>'uploaded' then
   raise exception 'Upload version history not persisted'; end if;
end $admin_verify$;
select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $denied$
declare v_case db10_upload_case%rowtype;
begin
 select * into strict v_case from db10_upload_case;
 if app_private.can_insert_admission_object(
   'sms-admission-documents',v_case.object_path) then
   raise exception 'Unknown actor can insert document object'; end if;
 begin
   perform public.owner_register_admission_upload(
      v_case.document_id,v_case.object_path,v_case.revision);
   raise exception 'Unknown actor can register document';
 exception when insufficient_privilege then null; end;
end $denied$;
reset role;
rollback;
