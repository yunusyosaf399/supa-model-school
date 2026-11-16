-- DB02 private admissions documents bucket. Metadata only: NO client
-- upload/read/delete policy is granted, no signed URL endpoint deployed.
-- Subsequent operations must validate file bytes, user campus authorization,
-- application/document UUIDs and immutable version metadata server-side.
-- Maximum 10 MiB per object and strict MIME allow list.

DO $bootstrap$
BEGIN
  IF EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id = 'sms-admission-documents'
  ) THEN
    RAISE EXCEPTION 'Private admissions document bucket already exists';
  END IF;
  INSERT INTO storage.buckets (
    id,name,public,file_size_limit,allowed_mime_types
  ) VALUES (
    'sms-admission-documents','sms-admission-documents',false,
    10485760,
    ARRAY['application/pdf','image/jpeg','image/png','image/webp']::text[]
  );
END $bootstrap$;

-- Explicitly do NOT create storage.objects authenticated policies here.
-- A policy for this bucket must be coupled to a reviewed, authenticated
-- upload-download service with document-level authorization tests.
