-- DB13 trusted file metadata validation for optional student photos.
CREATE OR REPLACE FUNCTION app_private.owner_register_admission_upload(p_document_id uuid, p_object_path text, p_expected_revision bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- Student photos are optional images, never PDFs or oversized documents.
  -- Revalidate on the trusted server as the Flutter picker can be bypassed.
  if v_doc.document_kind='photo' and (
    v_size>2097152 or v_type not in ('image/jpeg','image/png','image/webp')
    or pg_catalog.right(p_object_path,4)='.pdf'
  ) then
    raise exception 'Student photo must be JPG/PNG/WebP up to 2 MiB'
      using errcode='22023';
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
$function$;
