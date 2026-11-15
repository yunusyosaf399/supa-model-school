-- D04-T03: offline draft operation ingestion. REVIEW-ONLY SQL; DO NOT
-- deploy before DB01/DB02 + workflow + PostgreSQL/RLS integration passes.
-- Dependencies in order:
--  DB01_foundation.sql, DB02_admissions.sql, DB02_WORKFLOW_SCHEMA.sql,
--  DB02_ADMISSION_OPERATIONS.sql, then this file.
-- No client roles can access app_private, these tables or this operation.
-- Trusted Edge handler derives p_actor from verified Supabase Auth getUser().
BEGIN;

-- Reuse DB01 public.registered_devices as the authoritative single-PC/campus
-- assignment; keep the device proof separately in unexposed private storage.
-- Provision/rotate a high-entropy, 32-byte random credential using a trusted
-- administrator. Store only SHA256(raw credential bytes), NOT its hex text.
CREATE TABLE app_private.offline_device_credentials (
  device_id uuid PRIMARY KEY
    REFERENCES public.registered_devices(id) ON DELETE RESTRICT,
  credential_sha256 bytea NOT NULL
    CHECK (pg_catalog.octet_length(credential_sha256) = 32),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

-- A provisional local UUID is NOT a cloud admission UUID. The mapping and
-- accepted revision are authoritative for future ordered operations.
CREATE TABLE app_private.offline_admission_mappings (
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  device_id uuid NOT NULL
    REFERENCES public.registered_devices(id) ON DELETE RESTRICT,
  local_application_id uuid NOT NULL,
  cloud_application_id uuid NOT NULL,
  last_local_revision bigint NOT NULL CHECK (last_local_revision > 0),
  last_cloud_revision bigint NOT NULL CHECK (last_cloud_revision > 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY (school_id,device_id,local_application_id),
  UNIQUE (school_id,cloud_application_id),
  FOREIGN KEY (cloud_application_id,school_id,campus_id)
    REFERENCES public.admission_applications(id,school_id,campus_id)
    ON DELETE RESTRICT
);

-- Exact-response receipts survive lost network ACKs. Only a SHA256 of the
-- canonical request is stored here, not a second copy of pupil PII.
CREATE TABLE app_private.offline_ingest_receipts (
  school_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  device_id uuid NOT NULL,
  local_application_id uuid NOT NULL,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  request_sha256 bytea NOT NULL
    CHECK (pg_catalog.octet_length(request_sha256) = 32),
  cloud_application_id uuid NOT NULL,
  cloud_revision bigint NOT NULL CHECK (cloud_revision > 0),
  local_revision bigint NOT NULL CHECK (local_revision > 0),
  response_json jsonb NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY (school_id,operation_id),
  FOREIGN KEY (school_id,device_id,local_application_id)
    REFERENCES app_private.offline_admission_mappings
      (school_id,device_id,local_application_id) ON DELETE RESTRICT
);
CREATE INDEX offline_receipts_device_time_idx
  ON app_private.offline_ingest_receipts(device_id,processed_at DESC);

-- Rows are append-only; even privileged sync code must not accidentally
-- erase the proof of acceptance during retry or cleanup.
CREATE FUNCTION app_private.offline_receipt_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'An offline ingest receipt is immutable'
    USING ERRCODE = '23514';
END;
$$;
CREATE TRIGGER offline_receipt_no_update_delete
BEFORE UPDATE OR DELETE ON app_private.offline_ingest_receipts
FOR EACH ROW EXECUTE FUNCTION app_private.offline_receipt_immutable();

-- Private tables are defence-in-depth RLS deny-by-default. Only the trusted
-- function owner can access them; do not expose app_private in Data API.
ALTER TABLE app_private.offline_device_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.offline_admission_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.offline_ingest_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.offline_device_credentials,
  app_private.offline_admission_mappings,
  app_private.offline_ingest_receipts FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.offline_receipt_immutable()
  FROM PUBLIC,anon,authenticated;

-- Deliberately serializes offline operations at school level in this small
-- pilot. The lock plus receipt PK prevents concurrent duplicate execution.
-- For higher throughput, review a deterministic per-aggregate lock strategy.
CREATE FUNCTION app_private.offline_ingest_admission_draft(
  p_actor uuid,
  p_school uuid,
  p_campus uuid,
  p_device uuid,
  p_device_proof text,
  p_operation uuid,
  p_local_application uuid,
  p_local_revision bigint,
  p_expected_cloud_revision bigint,
  p_payload jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_device uuid;
  v_hash bytea;
  v_receipt app_private.offline_ingest_receipts%ROWTYPE;
  v_map app_private.offline_admission_mappings%ROWTYPE;
  v_cloud_id uuid;
  v_cloud_revision bigint;
  v_result jsonb;
BEGIN
  IF p_actor IS NULL OR p_school IS NULL OR p_campus IS NULL
     OR p_device IS NULL OR p_operation IS NULL
     OR p_local_application IS NULL OR p_local_revision IS NULL
     OR p_local_revision < 1
     OR coalesce(pg_catalog.jsonb_typeof(p_payload),'null') <> 'object'
     OR p_device_proof IS NULL
     OR p_device_proof !~ '^[0-9a-fA-F]{64}$'
  THEN
    RAISE EXCEPTION 'Invalid offline ingest envelope' USING ERRCODE='22023';
  END IF;
  -- V1 only supports campus-local drafts that were initially created offline.
  -- Imported existing-cloud admissions and finance are intentionally denied.
  IF p_expected_cloud_revision IS NOT NULL THEN
    RAISE EXCEPTION 'Existing-cloud draft edit not supported in offline v1'
      USING ERRCODE='22023';
  END IF;
  IF p_payload - ARRAY[
      'operation_id','local_application_id','academic_year_id',
      'applicant_name','date_of_birth','previous_school',
      'requested_class_id','requested_section_id'
    ] <> '{}'::jsonb
    OR p_payload->>'operation_id' IS DISTINCT FROM p_operation::text
    OR p_payload->>'local_application_id'
      IS DISTINCT FROM p_local_application::text
    OR pg_catalog.length(pg_catalog.btrim(
      coalesce(p_payload->>'applicant_name',''))) NOT BETWEEN 2 AND 200
    OR p_payload->>'academic_year_id' IS NULL
  THEN
    RAISE EXCEPTION 'Operation payload mismatch' USING ERRCODE='22023';
  END IF;
  -- The offline client emits ISO date text, never locale-dependent dates.
  -- Reject strings PostgreSQL might otherwise interpret permissively.
  IF p_payload->>'date_of_birth' IS NOT NULL
     AND p_payload->>'date_of_birth' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}
  IF NOT app_private.admission_actor_allowed(
      p_actor,p_school,p_campus,'draft') THEN
    RAISE EXCEPTION 'Actor not permitted for campus draft ingestion'
      USING ERRCODE='42501';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'sms:offline-ingest:'||p_school::text,0));

  -- Registered device + exact assigned user + current authorization + proof.
  -- FOR SHARE holds these rows against revocation during this transaction.
  SELECT d.id INTO v_device
  FROM public.registered_devices d
  JOIN app_private.offline_device_credentials dc ON dc.device_id=d.id
  WHERE d.id=p_device AND d.school_id=p_school
    AND d.assigned_campus_id=p_campus AND d.registered_user_id=p_actor
    AND d.is_offline_enabled AND d.revoked_at IS NULL
    AND dc.revoked_at IS NULL AND dc.expires_at > pg_catalog.now()
    AND dc.credential_sha256 = pg_catalog.sha256(
      pg_catalog.decode(p_device_proof,'hex'))
  FOR SHARE OF d,dc;
  IF v_device IS NULL THEN
    RAISE EXCEPTION 'Device assignment or proof not valid'
      USING ERRCODE='42501';
  END IF;

  v_hash := pg_catalog.sha256(pg_catalog.convert_to(
    pg_catalog.jsonb_build_object(
      'actor',p_actor,'school',p_school,'campus',p_campus,
      'device',p_device,'operation',p_operation,
      'local_application',p_local_application,
      'local_revision',p_local_revision,
      'expected_cloud_revision',p_expected_cloud_revision,
      'payload',p_payload
    )::text,'UTF8'));

  SELECT * INTO v_receipt FROM app_private.offline_ingest_receipts
    WHERE school_id=p_school AND operation_id=p_operation;
  IF FOUND THEN
    IF v_receipt.request_sha256 IS DISTINCT FROM v_hash
       OR v_receipt.campus_id<>p_campus
       OR v_receipt.device_id<>p_device
       OR v_receipt.local_application_id<>p_local_application
       OR v_receipt.actor_id<>p_actor THEN
      RAISE EXCEPTION 'Operation UUID already used for other request'
        USING ERRCODE='23505';
    END IF;
    RETURN v_receipt.response_json;
  END IF;

  -- The older admission API also uses operation UUIDs: disallow a collision
  -- with a separately accepted online draft/submit/review action.
  IF EXISTS(
    SELECT 1 FROM public.admission_action_events
    WHERE school_id=p_school AND operation_id=p_operation
  ) THEN
    RAISE EXCEPTION 'Operation UUID already used by admission action'
      USING ERRCODE='23505';
  END IF;

  SELECT * INTO v_map FROM app_private.offline_admission_mappings
    WHERE school_id=p_school AND device_id=p_device
      AND local_application_id=p_local_application
    FOR UPDATE;
  IF NOT FOUND THEN
    IF p_local_revision<>1 THEN
      RAISE EXCEPTION 'Missing initial offline application revision'
        USING ERRCODE='40001';
    END IF;
    v_cloud_id := app_private.admission_save_draft(
      p_actor,p_school,p_campus,(p_payload->>'academic_year_id')::uuid,
      NULL,NULL,p_operation,
      p_payload->>'applicant_name',
      NULLIF(p_payload->>'date_of_birth','')::date,
      p_payload->>'previous_school',
      NULLIF(p_payload->>'requested_class_id','')::uuid,
      NULLIF(p_payload->>'requested_section_id','')::uuid,
      '[]'::jsonb);
    SELECT revision INTO v_cloud_revision
      FROM public.admission_applications
      WHERE id=v_cloud_id AND school_id=p_school AND campus_id=p_campus;
    INSERT INTO app_private.offline_admission_mappings(
      school_id,campus_id,device_id,local_application_id,
      cloud_application_id,last_local_revision,last_cloud_revision
    ) VALUES (
      p_school,p_campus,p_device,p_local_application,
      v_cloud_id,p_local_revision,v_cloud_revision);
  ELSE
    IF v_map.campus_id<>p_campus OR
       p_local_revision <> v_map.last_local_revision + 1 THEN
      RAISE EXCEPTION 'Offline revision out of order'
        USING ERRCODE='40001';
    END IF;
    v_cloud_id := app_private.admission_save_draft(
      p_actor,p_school,p_campus,(p_payload->>'academic_year_id')::uuid,
      v_map.cloud_application_id,v_map.last_cloud_revision,p_operation,
      p_payload->>'applicant_name',
      NULLIF(p_payload->>'date_of_birth','')::date,
      p_payload->>'previous_school',
      NULLIF(p_payload->>'requested_class_id','')::uuid,
      NULLIF(p_payload->>'requested_section_id','')::uuid,
      '[]'::jsonb);
    SELECT revision INTO v_cloud_revision
      FROM public.admission_applications
      WHERE id=v_cloud_id AND school_id=p_school AND campus_id=p_campus;
    UPDATE app_private.offline_admission_mappings
      SET last_local_revision=p_local_revision,
          last_cloud_revision=v_cloud_revision,
          updated_at=pg_catalog.now()
      WHERE school_id=p_school AND device_id=p_device
        AND local_application_id=p_local_application;
  END IF;
  IF v_cloud_id IS NULL OR v_cloud_revision IS NULL THEN
    RAISE EXCEPTION 'Admission result missing'
      USING ERRCODE='P0001';
  END IF;
  v_result := pg_catalog.jsonb_build_object(
    'status','accepted','operation_id',p_operation,
    'local_application_id',p_local_application,
    'cloud_application_id',v_cloud_id,
    'cloud_revision',v_cloud_revision,
    'local_revision',p_local_revision);
  INSERT INTO app_private.offline_ingest_receipts(
    school_id,operation_id,campus_id,device_id,local_application_id,
    actor_id,request_sha256,cloud_application_id,cloud_revision,
    local_revision,response_json
  ) VALUES (
    p_school,p_operation,p_campus,p_device,p_local_application,
    p_actor,v_hash,v_cloud_id,v_cloud_revision,p_local_revision,v_result);
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION app_private.offline_ingest_admission_draft(
  uuid,uuid,uuid,uuid,text,uuid,uuid,bigint,bigint,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA app_private TO service_role;
GRANT EXECUTE ON FUNCTION app_private.offline_ingest_admission_draft(
  uuid,uuid,uuid,uuid,text,uuid,uuid,bigint,bigint,jsonb)
  TO service_role;
COMMIT;

  THEN
    RAISE EXCEPTION 'Birth date format invalid' USING ERRCODE='22023';
  END IF;
  -- Validate the CURRENT account and campus; never trust user metadata or
  -- a client-provided role. Only the trusted Edge handler supplies p_actor.
  IF NOT app_private.admission_actor_allowed(
      p_actor,p_school,p_campus,'draft') THEN
    RAISE EXCEPTION 'Actor not permitted for campus draft ingestion'
      USING ERRCODE='42501';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'sms:offline-ingest:'||p_school::text,0));

  -- Registered device + exact assigned user + current authorization + proof.
  -- FOR SHARE holds these rows against revocation during this transaction.
  SELECT d.id INTO v_device
  FROM public.registered_devices d
  JOIN app_private.offline_device_credentials dc ON dc.device_id=d.id
  WHERE d.id=p_device AND d.school_id=p_school
    AND d.assigned_campus_id=p_campus AND d.registered_user_id=p_actor
    AND d.is_offline_enabled AND d.revoked_at IS NULL
    AND dc.revoked_at IS NULL AND dc.expires_at > pg_catalog.now()
    AND dc.credential_sha256 = pg_catalog.sha256(
      pg_catalog.decode(p_device_proof,'hex'))
  FOR SHARE OF d,dc;
  IF v_device IS NULL THEN
    RAISE EXCEPTION 'Device assignment or proof not valid'
      USING ERRCODE='42501';
  END IF;

  v_hash := pg_catalog.sha256(pg_catalog.convert_to(
    pg_catalog.jsonb_build_object(
      'actor',p_actor,'school',p_school,'campus',p_campus,
      'device',p_device,'operation',p_operation,
      'local_application',p_local_application,
      'local_revision',p_local_revision,
      'expected_cloud_revision',p_expected_cloud_revision,
      'payload',p_payload
    )::text,'UTF8'));

  SELECT * INTO v_receipt FROM app_private.offline_ingest_receipts
    WHERE school_id=p_school AND operation_id=p_operation;
  IF FOUND THEN
    IF v_receipt.request_sha256 IS DISTINCT FROM v_hash
       OR v_receipt.campus_id<>p_campus
       OR v_receipt.device_id<>p_device
       OR v_receipt.local_application_id<>p_local_application
       OR v_receipt.actor_id<>p_actor THEN
      RAISE EXCEPTION 'Operation UUID already used for other request'
        USING ERRCODE='23505';
    END IF;
    RETURN v_receipt.response_json;
  END IF;

  -- The older admission API also uses operation UUIDs: disallow a collision
  -- with a separately accepted online draft/submit/review action.
  IF EXISTS(
    SELECT 1 FROM public.admission_action_events
    WHERE school_id=p_school AND operation_id=p_operation
  ) THEN
    RAISE EXCEPTION 'Operation UUID already used by admission action'
      USING ERRCODE='23505';
  END IF;

  SELECT * INTO v_map FROM app_private.offline_admission_mappings
    WHERE school_id=p_school AND device_id=p_device
      AND local_application_id=p_local_application
    FOR UPDATE;
  IF NOT FOUND THEN
    IF p_local_revision<>1 THEN
      RAISE EXCEPTION 'Missing initial offline application revision'
        USING ERRCODE='40001';
    END IF;
    v_cloud_id := app_private.admission_save_draft(
      p_actor,p_school,p_campus,(p_payload->>'academic_year_id')::uuid,
      NULL,NULL,p_operation,
      p_payload->>'applicant_name',
      NULLIF(p_payload->>'date_of_birth','')::date,
      p_payload->>'previous_school',
      NULLIF(p_payload->>'requested_class_id','')::uuid,
      NULLIF(p_payload->>'requested_section_id','')::uuid,
      '[]'::jsonb);
    SELECT revision INTO v_cloud_revision
      FROM public.admission_applications
      WHERE id=v_cloud_id AND school_id=p_school AND campus_id=p_campus;
    INSERT INTO app_private.offline_admission_mappings(
      school_id,campus_id,device_id,local_application_id,
      cloud_application_id,last_local_revision,last_cloud_revision
    ) VALUES (
      p_school,p_campus,p_device,p_local_application,
      v_cloud_id,p_local_revision,v_cloud_revision);
  ELSE
    IF v_map.campus_id<>p_campus OR
       p_local_revision <> v_map.last_local_revision + 1 THEN
      RAISE EXCEPTION 'Offline revision out of order'
        USING ERRCODE='40001';
    END IF;
    v_cloud_id := app_private.admission_save_draft(
      p_actor,p_school,p_campus,(p_payload->>'academic_year_id')::uuid,
      v_map.cloud_application_id,v_map.last_cloud_revision,p_operation,
      p_payload->>'applicant_name',
      NULLIF(p_payload->>'date_of_birth','')::date,
      p_payload->>'previous_school',
      NULLIF(p_payload->>'requested_class_id','')::uuid,
      NULLIF(p_payload->>'requested_section_id','')::uuid,
      '[]'::jsonb);
    SELECT revision INTO v_cloud_revision
      FROM public.admission_applications
      WHERE id=v_cloud_id AND school_id=p_school AND campus_id=p_campus;
    UPDATE app_private.offline_admission_mappings
      SET last_local_revision=p_local_revision,
          last_cloud_revision=v_cloud_revision,
          updated_at=pg_catalog.now()
      WHERE school_id=p_school AND device_id=p_device
        AND local_application_id=p_local_application;
  END IF;
  IF v_cloud_id IS NULL OR v_cloud_revision IS NULL THEN
    RAISE EXCEPTION 'Admission result missing'
      USING ERRCODE='P0001';
  END IF;
  v_result := pg_catalog.jsonb_build_object(
    'status','accepted','operation_id',p_operation,
    'local_application_id',p_local_application,
    'cloud_application_id',v_cloud_id,
    'cloud_revision',v_cloud_revision,
    'local_revision',p_local_revision);
  INSERT INTO app_private.offline_ingest_receipts(
    school_id,operation_id,campus_id,device_id,local_application_id,
    actor_id,request_sha256,cloud_application_id,cloud_revision,
    local_revision,response_json
  ) VALUES (
    p_school,p_operation,p_campus,p_device,p_local_application,
    p_actor,v_hash,v_cloud_id,v_cloud_revision,p_local_revision,v_result);
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION app_private.offline_ingest_admission_draft(
  uuid,uuid,uuid,uuid,text,uuid,uuid,bigint,bigint,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA app_private TO service_role;
GRANT EXECUTE ON FUNCTION app_private.offline_ingest_admission_draft(
  uuid,uuid,uuid,uuid,text,uuid,uuid,bigint,bigint,jsonb)
  TO service_role;
COMMIT;
