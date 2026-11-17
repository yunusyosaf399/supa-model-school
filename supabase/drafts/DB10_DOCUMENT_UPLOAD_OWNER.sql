-- DB10 admissions: narrowly-scoped, immutable object INSERT and
-- authenticated document-upload registration. Files remain unverified.
-- Storage uses private sms-admission-documents bucket; no list/read/upsert/delete grants.
create or replace function app_private.can_insert_admission_object(
  p_bucket text,p_path text
) returns boolean language plpgsql stable security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_parts text[] := pg_catalog.string_to_array(p_path,'/');
  v_school uuid;
  v_campus uuid;
  v_application uuid;
  v_document uuid;
begin
  if p_bucket<>'sms-admission-documents'
    or v_actor is null or pg_catalog.array_length(v_parts,1)<>5 then
    return false;
  end if;
  if v_parts[1] !~* '^[a-f0-9-]{36}$'
    or v_parts[2] !~* '^[a-f0-9-]{36}$'
    or v_parts[3] !~* '^[a-f0-9-]{36}$'
    or v_parts[4] !~* '^[a-f0-9-]{36}$'
    or v_parts[5] !~* '^[a-f0-9-]{36}\.(pdf|jpg|png|webp)$' then
    return false;
  end if;
  begin
    v_school:=v_parts[1]::uuid;
    v_campus:=v_parts[2]::uuid;
    v_application:=v_parts[3]::uuid;
    v_document:=v_parts[4]::uuid;
  exception when invalid_text_representation then return false;
  end;
  return exists(
    select 1 from public.student_documents d
    join public.admission_applications a
      on a.id=d.application_id and a.school_id=d.school_id
      and a.campus_id=d.campus_id
    join public.user_roles r on r.school_id=d.school_id and r.user_id=v_actor
    join public.user_profiles p on p.user_id=v_actor
    join auth.users u on u.id=v_actor
    join public.schools s on s.id=d.school_id and s.status='active'
    join public.campuses c on c.id=d.campus_id and c.is_active
    where d.id=v_document and a.id=v_application
      and d.school_id=v_school and d.campus_id=v_campus
      and a.admission_status in ('draft','returned')
      and d.document_status in ('missing','uploaded','rejected')
      and d.is_applicable
      and r.role='owner' and r.campus_id is null and r.is_active
      and p.is_active and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
  );
end;
$fn$;

revoke all on function app_private.can_insert_admission_object(text,text)
 from public,anon,authenticated;
grant execute on function app_private.can_insert_admission_object(text,text)
 to authenticated;

create policy "db10_admission_object_insert_owner_only"
 on storage.objects for insert to authenticated
 with check (
   bucket_id='sms-admission-documents'
   and app_private.can_insert_admission_object(bucket_id,name)
 );

create or replace function app_private.owner_register_admission_upload(
  p_document_id uuid, p_object_path text,p_expected_revision bigint
) returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_doc public.student_documents%rowtype;
  v_obj storage.objects%rowtype;
  v_size bigint;
  v_type text;
  v_version integer;
begin
  if v_actor is null or p_document_id is null or p_object_path is null
    or p_expected_revision is null or p_expected_revision<1 then
    raise exception 'Invalid document registration request' using errcode='22023';
  end if;
  select * into v_doc from public.student_documents
   where id=p_document_id for update;
  if not found or v_doc.application_id is null or not v_doc.is_applicable then
    raise exception 'Document unavailable' using errcode='42501';
  end if;
  if not app_private.can_insert_admission_object(
      'sms-admission-documents',p_object_path) then
    raise exception 'Not authorized to register upload' using errcode='42501';
  end if;
  -- Idempotency: registration retries return the version already stored.
  select version_no into v_version from public.student_document_uploads
   where document_id=p_document_id and object_path=p_object_path;
  if found then
    return jsonb_build_object('document_id',p_document_id,
      'revision',v_doc.revision,'status',v_doc.document_status,
      'version',v_version);
  end if;
  if v_doc.revision<>p_expected_revision then
    raise exception 'Document revision conflict' using errcode='40001';
  end if;
  select * into v_obj from storage.objects o
    where o.bucket_id='sms-admission-documents'
      and o.name=p_object_path and o.owner_id=v_actor::text
      and o.archived_at is null and coalesce(o.is_delete_marker,false)=false;
  if not found then
    raise exception 'Uploaded file not found for current actor'
      using errcode='23503';
  end if;
  -- Bucket enforces size and MIME on upload; re-check stored metadata
  -- before moving document to "uploaded". This is not byte-level validation.
  if coalesce(v_obj.metadata->>'size','') !~ '^[0-9]{1,10}$' then
    raise exception 'Storage file size metadata unavailable' using errcode='22023';
  end if;
  v_size:=(v_obj.metadata->>'size')::bigint;
  v_type:=v_obj.metadata->>'mimetype';
  if v_size<1 or v_size>10485760
    or v_type not in ('application/pdf','image/jpeg','image/png','image/webp')
    or not (
      (pg_catalog.right(p_object_path,4)='.pdf' and v_type='application/pdf')
      or (pg_catalog.right(p_object_path,4)='.jpg' and v_type='image/jpeg')
      or (pg_catalog.right(p_object_path,4)='.png' and v_type='image/png')
      or (pg_catalog.right(p_object_path,5)='.webp' and v_type='image/webp')
    ) then
    raise exception 'Invalid file size, MIME, or extension' using errcode='22023';
  end if;
  if exists(select 1 from public.student_document_uploads
      where object_path=p_object_path) then
    raise exception 'Object already linked elsewhere' using errcode='23505';
  end if;
  select coalesce(max(version_no),0)+1 into v_version
   from public.student_document_uploads where document_id=p_document_id;
  insert into public.student_document_uploads(
    school_id,campus_id,document_id,version_no,storage_bucket,object_path,
    content_type,file_size_bytes,uploaded_by)
   values(v_doc.school_id,v_doc.campus_id,p_document_id,v_version,
     'sms-admission-documents',p_object_path,v_type,v_size,v_actor);
  update public.student_documents
   set storage_path=p_object_path,document_status='uploaded',
       rejection_reason=null,verified_at=null,verified_by=null,
       revision=revision+1,updated_at=pg_catalog.now()
   where id=p_document_id
   returning * into v_doc;
  return jsonb_build_object('document_id',p_document_id,
    'revision',v_doc.revision,'status','uploaded','version',v_version);
end;
$fn$;

create or replace function public.owner_register_admission_upload(
  p_document_id uuid,p_object_path text,p_expected_revision bigint
) returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.owner_register_admission_upload(
  p_document_id,p_object_path,p_expected_revision);
$fn$;
revoke all on function app_private.owner_register_admission_upload(uuid,text,bigint)
 from public,anon,authenticated;
revoke all on function public.owner_register_admission_upload(uuid,text,bigint)
 from public,anon,authenticated;
grant execute on function app_private.owner_register_admission_upload(uuid,text,bigint)
 to authenticated;
grant execute on function public.owner_register_admission_upload(uuid,text,bigint)
 to authenticated;
