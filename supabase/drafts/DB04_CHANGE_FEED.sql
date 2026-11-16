-- D04-T04. REVIEW-ONLY SQL; do NOT deploy to hosted Supabase.
-- Depends on DB01, DB02, D03 workflow, D04_OFFLINE_INGEST.sql, IN THAT ORDER.
-- Scope: admission application upserts/deletes for one assigned Windows campus.
-- Other entities (documents, students, guardians, finance) are NOT replicated.
-- All changes from any trusted server writer are recorded by the SAME trigger.
BEGIN;

-- Global ordering is intentionally serialized. A plain BIGSERIAL WITHOUT
-- serialization is unsafe: a later transaction can COMMIT first and make
-- a page cursor skip an earlier, uncommitted lower sequence number.
-- Every writer receives the transaction advisory lock BEFORE allocating a
-- sequence. It is released only at COMMIT/ROLLBACK. Gaps from rollback are
-- legitimate; the cursor is a last-seen ID, never a row count.
CREATE TABLE app_private.offline_admission_change_log (
  change_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  application_id uuid NOT NULL,
  event_type text NOT NULL
    CHECK (event_type IN ('admission.upsert','admission.delete')),
  revision bigint NOT NULL CHECK (revision > 0),
  payload jsonb NOT NULL
    CHECK (pg_catalog.jsonb_typeof(payload) = 'object'),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT
);

CREATE INDEX offline_admission_changes_campus_seq_idx
  ON app_private.offline_admission_change_log
  (school_id,campus_id,change_seq);

ALTER TABLE app_private.offline_admission_change_log
  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.offline_admission_change_log
  FROM PUBLIC,anon,authenticated;

-- Append-only; no unaudited pruning/rewrite. For each retained cursor,
-- historical rows must remain readable. Retention/checkpoints are future work.
CREATE FUNCTION app_private.offline_change_log_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Offline change log is append-only'
    USING ERRCODE='23514';
END;
$$;
CREATE TRIGGER offline_change_log_no_update_delete
BEFORE UPDATE OR DELETE ON app_private.offline_admission_change_log
FOR EACH ROW EXECUTE FUNCTION app_private.offline_change_log_immutable();

-- A private SECURITY DEFINER trigger is the only automatic writer. It
-- supports a tombstone on DELETE rather than silently leaving stale rows
-- in offline clients. No guardian/document contents are included.
CREATE FUNCTION app_private.offline_capture_admission_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_school uuid;
  v_campus uuid;
  v_id uuid;
  v_revision bigint;
  v_type text;
  v_payload jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_school := OLD.school_id;
    v_campus := OLD.campus_id;
    v_id := OLD.id;
    v_revision := OLD.revision;
    v_type := 'admission.delete';
    v_payload := pg_catalog.jsonb_build_object(
      'id',OLD.id,'deleted',true);
  ELSE
    IF TG_OP = 'UPDATE' THEN
      -- A campus transfer must follow a reviewed workflow, never a silent
      -- admission row retarget that could leak/drop data across campuses.
      IF OLD.school_id IS DISTINCT FROM NEW.school_id OR
         OLD.campus_id IS DISTINCT FROM NEW.campus_id OR
         OLD.id IS DISTINCT FROM NEW.id THEN
        RAISE EXCEPTION 'Admission scope and ID cannot be reassigned'
          USING ERRCODE='23514';
      END IF;
      IF NEW.revision <= OLD.revision THEN
        RAISE EXCEPTION 'Admission revision must increase on update'
          USING ERRCODE='23514';
      END IF;
    END IF;
    v_school := NEW.school_id;
    v_campus := NEW.campus_id;
    v_id := NEW.id;
    v_revision := NEW.revision;
    v_type := 'admission.upsert';
    -- Allowlisted admission fields only, no unbounded row_to_json or PII
    -- from uploaded documents/guardian contact and no arbitrary table names.
    v_payload := pg_catalog.jsonb_build_object(
      'id',NEW.id,
      'academic_year_id',NEW.academic_year_id,
      'requested_class_id',NEW.requested_class_id,
      'requested_section_id',NEW.requested_section_id,
      'student_id',NEW.student_id,
      'applicant_name',NEW.applicant_name,
      'date_of_birth',NEW.date_of_birth,
      'previous_school',NEW.previous_school,
      'admission_status',NEW.admission_status,
      'approval_state',NEW.approval_state,
      'documents_state',NEW.documents_state,
      'missing_documents_due_on',NEW.missing_documents_due_on,
      'conditional_reason',NEW.conditional_reason,
      'revision',NEW.revision,
      'updated_at',NEW.updated_at);
  END IF;

  -- IMPORTANT: this lock must be acquired before the IDENTITY value is
  -- allocated, and held to commit. ALL admission mutation pathways use the
  -- same trigger and therefore cannot insert an out-of-order change.
  PERFORM pg_catalog.pg_advisory_xact_lock(410704,4404);
  INSERT INTO app_private.offline_admission_change_log(
    school_id,campus_id,application_id,event_type,revision,payload)
  VALUES (v_school,v_campus,v_id,v_type,v_revision,v_payload);
  RETURN NULL; -- AFTER ROW trigger result is ignored
END;
$$;

CREATE TRIGGER admission_offline_change_capture
AFTER INSERT OR UPDATE OR DELETE ON public.admission_applications
FOR EACH ROW EXECUTE FUNCTION app_private.offline_capture_admission_change();

-- Backfill already-existing admissions into the feed, if any. The preceding
-- CREATE TRIGGER and this INSERT are in one migration transaction, so no
-- other writer can see a half-installed trigger. Serialize sequence IDs.
-- This is a latest-state bootstrap, NOT an audit of historical transitions.
DO $bootstrap$
DECLARE
  r public.admission_applications%ROWTYPE;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(410704,4404);
  FOR r IN
    SELECT * FROM public.admission_applications ORDER BY school_id,campus_id,id
  LOOP
    INSERT INTO app_private.offline_admission_change_log(
      school_id,campus_id,application_id,event_type,revision,payload)
    VALUES (
      r.school_id,r.campus_id,r.id,'admission.upsert',r.revision,
      pg_catalog.jsonb_build_object(
        'id',r.id,'academic_year_id',r.academic_year_id,
        'requested_class_id',r.requested_class_id,
        'requested_section_id',r.requested_section_id,
        'student_id',r.student_id,
        'applicant_name',r.applicant_name,
        'date_of_birth',r.date_of_birth,
        'previous_school',r.previous_school,
        'admission_status',r.admission_status,
        'approval_state',r.approval_state,
        'documents_state',r.documents_state,
        'missing_documents_due_on',r.missing_documents_due_on,
        'conditional_reason',r.conditional_reason,
        'revision',r.revision,'updated_at',r.updated_at));
  END LOOP;
END;
$bootstrap$;

-- One authenticated, registered desktop can read only its current campus,
-- regardless of a client-supplied cursor or forged campus ID. No direct
-- GRANT SELECT; the trusted Edge server passes p_actor after Auth getUser.
CREATE FUNCTION app_private.offline_pull_admission_changes(
  p_actor uuid,
  p_school uuid,
  p_campus uuid,
  p_device uuid,
  p_device_proof text,
  p_after bigint,
  p_page_size integer DEFAULT 100
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_max bigint;
  v_count integer;
  v_last bigint;
  v_events jsonb;
BEGIN
  IF p_actor IS NULL OR p_school IS NULL OR p_campus IS NULL
     OR p_device IS NULL OR p_after IS NULL OR p_after < 0
     OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 100
     OR p_device_proof IS NULL
     OR p_device_proof !~ '^[0-9a-fA-F]{64}$'
  THEN
    RAISE EXCEPTION 'Invalid campus change cursor request'
      USING ERRCODE='22023';
  END IF;

  -- Read permission here uses the same strict admission-draft actor access
  -- as the v1 offline writer. A campus owner on another registered PC does
  -- not gain this one device's feed.
  IF NOT app_private.admission_actor_allowed(
      p_actor,p_school,p_campus,'draft')
  THEN
    RAISE EXCEPTION 'No current permission for campus change feed'
      USING ERRCODE='42501';
  END IF;

  -- Row locks fence a simultaneous credential/device revocation until this
  -- pull transaction completes (revocation wins on the next request).
  PERFORM 1
    FROM public.registered_devices d
    JOIN app_private.offline_device_credentials dc ON dc.device_id=d.id
   WHERE d.id=p_device
     AND d.school_id=p_school
     AND d.assigned_campus_id=p_campus
     AND d.registered_user_id=p_actor
     AND d.is_offline_enabled AND d.revoked_at IS NULL
     AND dc.revoked_at IS NULL
     AND dc.expires_at > pg_catalog.now()
     AND dc.credential_sha256 = pg_catalog.sha256(
       pg_catalog.decode(p_device_proof,'hex'))
   FOR SHARE OF d,dc;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Desktop offline authorization revoked or invalid'
      USING ERRCODE='42501';
  END IF;

  -- An arbitrary future cursor can permanently skip changes; fail closed.
  SELECT coalesce(pg_catalog.max(change_seq),0)
    INTO v_max
    FROM app_private.offline_admission_change_log
   WHERE school_id=p_school AND campus_id=p_campus;
  IF p_after > v_max THEN
    RAISE EXCEPTION 'Cursor ahead of campus change log'
      USING ERRCODE='22023';
  END IF;

  -- Fetch one extra record to determine has_more. PostgreSQL bigint IDs
  -- can have gaps; never assume the next cursor is current+page_size.
  -- Events are ordered and scoped in SQL, not filtered after delivery.
  SELECT
    coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'change_seq',change_seq::text,
          'event_type',event_type,
          'application_id',application_id,
          'revision',revision::text,
          'payload',payload
        ) ORDER BY change_seq
      ) FILTER (WHERE rn <= p_page_size),
      '[]'::jsonb
    ),
    coalesce(pg_catalog.max(change_seq)
      FILTER (WHERE rn <= p_page_size),p_after),
    pg_catalog.count(*)::integer
  INTO v_events,v_last,v_count
  FROM (
    SELECT x.change_seq,x.event_type,x.application_id,x.revision,x.payload,
      pg_catalog.row_number() OVER (ORDER BY x.change_seq) AS rn
    FROM (
      SELECT change_seq,event_type,application_id,revision,payload
      FROM app_private.offline_admission_change_log
      WHERE school_id=p_school AND campus_id=p_campus
        AND change_seq > p_after
      ORDER BY change_seq
      LIMIT p_page_size + 1
    ) AS x
  ) AS page;

  RETURN pg_catalog.jsonb_build_object(
    'school_id',p_school,
    'campus_id',p_campus,
    'events',v_events,
    'next_cursor',v_last::text,
    'has_more',v_count > p_page_size);
END;
$$;

-- Function grants: no Flutter/anon/authenticated direct SQL access.
REVOKE ALL ON FUNCTION app_private.offline_change_log_immutable()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.offline_capture_admission_change()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.offline_pull_admission_changes(
  uuid,uuid,uuid,uuid,text,bigint,integer)
  FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA app_private TO service_role;
GRANT EXECUTE ON FUNCTION app_private.offline_pull_admission_changes(
  uuid,uuid,uuid,uuid,text,bigint,integer)
  TO service_role;
COMMIT;
