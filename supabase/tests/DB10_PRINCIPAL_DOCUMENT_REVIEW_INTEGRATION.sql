-- DB10 document inspection and Principal verification; ALL writes roll back.
begin;
create temporary table db10_review_fixture(
 app_id uuid,doc_id uuid,owner_id uuid,principal_id uuid,
 school_id uuid,campus_id uuid,path text,
 initial_revision bigint,upload_id uuid
) on commit drop;
grant select on db10_review_fixture to authenticated;

do $prepare$
declare
 v_app public.admission_applications%rowtype;
 v_doc public.student_documents%rowtype;
 v_school uuid;v_campus uuid;v_principal uuid;v_owner uuid;
 v_path text;v_upload uuid;
begin
 select * into strict v_app from public.admission_applications
  where applicant_name='TEST Admission Applicant 001';
 select * into strict v_doc from public.student_documents
  where application_id=v_app.id and document_kind='birth_certificate';
 select user_id into strict v_owner from public.user_roles
   where role='owner' and school_id=v_app.school_id and is_active;
 v_school:=v_app.school_id;v_campus:=v_app.campus_id;
 v_principal:=gen_random_uuid();
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,
   encrypted_password,raw_app_meta_data,raw_user_meta_data,
   created_at,updated_at,is_anonymous)
 values (v_principal,'00000000-0000-0000-0000-000000000000',
    'authenticated','authenticated',
    'db10-document-principal-'||v_principal::text||'@example.invalid',
    now(),'!not-a-password!','{}'::jsonb,'{}'::jsonb,
    now(),now(),false);
 insert into public.user_profiles(user_id,display_name,is_active)
 values(v_principal,'TEST Document Principal',true);
 insert into public.user_roles(user_id,school_id,campus_id,role,is_active)
 values(v_principal,v_school,v_campus,'principal',true);

 -- This is a synthetic metadata fixture. No actual certificate is uploaded.
 v_path:=v_school::text||'/'||v_campus::text||'/'||
   v_app.id::text||'/'||v_doc.id::text||'/'||gen_random_uuid()::text||'.pdf';
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('sms-admission-documents',v_path,v_owner::text,
   '{"size":1024,"mimetype":"application/pdf"}'::jsonb);
 insert into public.student_document_uploads(
   school_id,campus_id,document_id,version_no,storage_bucket,
   object_path,content_type,file_size_bytes,uploaded_by)
 values(v_school,v_campus,v_doc.id,1,'sms-admission-documents',
  v_path,'application/pdf',1024,v_owner)
 returning id into v_upload;
 update public.student_documents
  set storage_path=v_path,document_status='uploaded',
    revision=revision+1,updated_at=now()
 where id=v_doc.id returning revision into v_doc.revision;
 update public.admission_applications
  set admission_status='submitted',approval_state='pending',
      documents_state='conditional',
      missing_documents_due_on=(current_date+interval '1 month')::date,
      conditional_reason='TEST pending certificates',
      submitted_at=now(),updated_at=now(),revision=revision+1
 where id=v_app.id;
 insert into db10_review_fixture values(
  v_app.id,v_doc.id,v_owner,v_principal,v_school,v_campus,
  v_path,v_doc.revision,v_upload);
end $prepare$;

select set_config('request.jwt.claim.sub',
 (select owner_id::text from db10_review_fixture limit 1),true);
set local role authenticated;
do $owner_denied$
declare f db10_review_fixture%rowtype;
begin
 select * into strict f from db10_review_fixture;
 if app_private.principal_can_read_uploaded_object(
   'sms-admission-documents',f.path)
 then raise exception 'Owner can read Principal document'; end if;
 begin
   perform public.principal_document_review_list(f.app_id);
   raise exception 'Owner can inspect Principal review metadata';
 exception when insufficient_privilege then null; end;
 begin
   perform public.principal_review_admission_document(
    f.doc_id,f.initial_revision,gen_random_uuid(),'verify',null);
   raise exception 'Owner can verify a document';
 exception when insufficient_privilege then null; end;
end $owner_denied$;
reset role;

select set_config('request.jwt.claim.sub',
 (select principal_id::text from db10_review_fixture limit 1),true);
set local role authenticated;
do $principal$
declare
 f db10_review_fixture%rowtype;
 v_docs jsonb;v_approved jsonb;v_again jsonb;v_op uuid:=gen_random_uuid();
begin
 select * into strict f from db10_review_fixture;
 if not app_private.principal_can_read_uploaded_object(
  'sms-admission-documents',f.path)
 then raise exception 'Principal cannot inspect assigned file'; end if;
 v_docs:=public.principal_document_review_list(f.app_id);
 if jsonb_array_length(v_docs)<>2 or
    not exists(select 1 from jsonb_array_elements(v_docs) d
       where d->>'id'=f.doc_id::text
         and d->>'object_path'=f.path
         and d->>'upload_id'=f.upload_id::text
         and d->>'status'='uploaded') then
   raise exception 'Principal document list missing registered version: %',v_docs;
 end if;
 begin
   perform public.principal_review_admission_document(
    f.doc_id,f.initial_revision-1,gen_random_uuid(),'verify',null);
   raise exception 'Stale document review accepted';
 exception when SQLSTATE '40001' then null; end;
 v_approved:=public.principal_review_admission_document(
   f.doc_id,f.initial_revision,v_op,'verify',null);
 if v_approved->>'status'<>'verified'
   or (v_approved->>'revision')::bigint<>f.initial_revision+1 then
   raise exception 'Document status did not advance: %',v_approved; end if;
 v_again:=public.principal_review_admission_document(
   f.doc_id,f.initial_revision,v_op,'verify',null);
 if v_again->>'status'<>'verified' then
   raise exception 'Idempotent review retry failed'; end if;
end $principal$;
reset role;
do $verify_audit$
declare f db10_review_fixture%rowtype;
begin
 select * into strict f from db10_review_fixture;
 if (select count(*) from public.student_document_reviews
   where document_id=f.doc_id and decision='verified'
     and reviewed_by=f.principal_id)<>1
  or (select document_status from public.student_documents
   where id=f.doc_id)<>'verified'
  or (select count(*) from public.students)<>32 then
  raise exception 'Document audit or student isolation mismatch'; end if;
end $verify_audit$;
rollback;
