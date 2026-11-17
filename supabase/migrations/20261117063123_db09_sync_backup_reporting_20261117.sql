-- DB09 OFFLINE DEVICE SYNC, BACKUP, RESTORE AND REPORTING — DESIGN ONLY
-- One school, multi-campus. Windows assigned-campus offline, Android ONLINE.
-- DB01/DB02 deployed; DB03–DB08 reviewed SQL sources required first.
-- Prior D04-T03/T04 offline-ingest/change-feed draft branches MUST be
-- reconciled before deployment: do not create two competing cloud feeds.

ALTER TABLE public.registered_devices
 ADD CONSTRAINT db09_device_school_campus_unique UNIQUE (id,school_id,assigned_campus_id);

-- 01 Device authorization is one assigned campus; revocation is
-- server-side and invalidates subsequent ingest/pull regardless of old JWT.
CREATE TABLE public.db09_device_authorizations (
 device_id uuid PRIMARY KEY,
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 offline_allowed boolean NOT NULL DEFAULT false,
 permission_revision bigint NOT NULL DEFAULT 1 CHECK (permission_revision>0),
 enabled_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz,
 revoked_at timestamptz,
 authorized_by uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY(device_id,school_id,campus_id)
 REFERENCES public.registered_devices(id,school_id,assigned_campus_id),
 UNIQUE(device_id,school_id,campus_id),
 CHECK(expires_at IS NULL OR expires_at>enabled_at)
);
CREATE TABLE public.db09_device_access_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 device_id uuid NOT NULL,
 event_kind text NOT NULL CHECK (event_kind IN
 ('authorized','renewed','revoked','expired','campus_change_denied')),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 operation_id uuid NOT NULL,
 event_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(device_id,school_id,campus_id)
 REFERENCES public.db09_device_authorizations(device_id,school_id,campus_id),
 UNIQUE(school_id,operation_id)
);

-- 02 durable UNIQUE operation receipt for idempotent Windows offline
-- upload. Same UUID and different SHA256 MUST be rejected by trusted RPC.
CREATE TABLE public.db09_operation_receipts (
 school_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 device_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 entity_kind text NOT NULL CHECK(entity_kind IN
 ('admission_draft','student_update','attendance_draft','expense_request',
  'inventory_request','notification_read','other')),
 entity_id uuid,
 expected_revision bigint CHECK(expected_revision IS NULL OR expected_revision>=0),
 request_sha256 bytea NOT NULL CHECK(octet_length(request_sha256)=32),
 result_kind text NOT NULL CHECK(result_kind IN
 ('accepted','rejected','conflict','pending_approval')),
 result_json jsonb NOT NULL CHECK(jsonb_typeof(result_json)='object'),
 processed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(school_id,operation_id),
 FOREIGN KEY(device_id,school_id,campus_id)
 REFERENCES public.db09_device_authorizations(device_id,school_id,campus_id),
 UNIQUE(school_id,operation_id,device_id,campus_id)
);

-- 03-04 Server change feed commit order is assigned by a ROW LOCK.
-- No use of a bare sequence alone (transactions might commit out of order).
CREATE TABLE public.db09_change_clocks (
 school_id uuid PRIMARY KEY REFERENCES public.schools(id),
 last_seq bigint NOT NULL DEFAULT 0 CHECK(last_seq>=0)
);
CREATE TABLE public.db09_cloud_changes (
 school_id uuid NOT NULL REFERENCES public.schools(id),
 change_seq bigint NOT NULL CHECK(change_seq>0),
 audience text NOT NULL CHECK(audience IN ('school','campus')),
 campus_id uuid,
 entity_kind text NOT NULL CHECK(entity_kind ~ '^[a-z][a-z0-9_]{2,60}$'),
 entity_id uuid NOT NULL,
 change_kind text NOT NULL CHECK(change_kind IN ('upsert','delete','revoke')),
 revision bigint NOT NULL CHECK(revision>=1),
 payload_digest bytea CHECK(payload_digest IS NULL OR octet_length(payload_digest)=32),
 changed_at timestamptz NOT NULL DEFAULT now(),
 operation_id uuid,
 PRIMARY KEY(school_id,change_seq),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 CHECK((audience='school' AND campus_id IS NULL) OR
       (audience='campus' AND campus_id IS NOT NULL))
);
CREATE INDEX db09_changes_campus_cursor
 ON public.db09_cloud_changes(school_id,campus_id,change_seq);
CREATE FUNCTION app_private.db09_assign_change_seq()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $db09$
BEGIN
 INSERT INTO public.db09_change_clocks(school_id,last_seq)
 VALUES(NEW.school_id,1)
 ON CONFLICT(school_id)
 DO UPDATE SET last_seq=public.db09_change_clocks.last_seq+1
 RETURNING last_seq INTO NEW.change_seq;
 RETURN NEW;
END;
$db09$;
CREATE TRIGGER db09_change_commit_order BEFORE INSERT
 ON public.db09_cloud_changes FOR EACH ROW
 EXECUTE FUNCTION app_private.db09_assign_change_seq();

-- 05 Authoritative deletion/revocation must reach the desktop as tombstone.
CREATE TABLE public.db09_tombstones (
 school_id uuid NOT NULL,
 change_seq bigint NOT NULL,
 entity_kind text NOT NULL,
 entity_id uuid NOT NULL,
 campus_id uuid,
 erased_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(school_id,change_seq),
 FOREIGN KEY(school_id,change_seq)
 REFERENCES public.db09_cloud_changes(school_id,change_seq),
 FOREIGN KEY(campus_id,school_id)
 REFERENCES public.campuses(id,school_id)
);

-- 06 Desktop cursor ACK is a device claim. Actual atomic SQLite apply
-- must be tested client-side; server never assumes bytes are durably saved.
CREATE TABLE public.db09_device_cursors (
 device_id uuid PRIMARY KEY,
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 last_reported_applied_seq bigint NOT NULL DEFAULT 0 CHECK(last_reported_applied_seq>=0),
 bootstrap_seq bigint NOT NULL DEFAULT 0 CHECK(bootstrap_seq>=0),
 report_revision bigint NOT NULL DEFAULT 1 CHECK(report_revision>0),
 reported_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(device_id,school_id,campus_id)
 REFERENCES public.db09_device_authorizations(device_id,school_id,campus_id),
 CHECK(last_reported_applied_seq>=bootstrap_seq)
);
-- 07 Failed concurrent edits must be kept, NOT last-write-wins.
CREATE TABLE public.db09_sync_conflicts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 device_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 entity_kind text NOT NULL,
 entity_id uuid,
 local_revision bigint CHECK(local_revision IS NULL OR local_revision>=0),
 server_revision bigint CHECK(server_revision IS NULL OR server_revision>=0),
 conflict_kind text NOT NULL CHECK(conflict_kind IN
 ('stale_revision','authorization','duplicate_payload','missing_entity',
  'invalid_business_rule','offline_approval')),
 status text NOT NULL DEFAULT 'unresolved'
  CHECK(status IN ('unresolved','resolved','abandoned')),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(school_id,operation_id,device_id,campus_id)
 REFERENCES public.db09_operation_receipts(school_id,operation_id,device_id,campus_id),
 UNIQUE(school_id,operation_id),
 UNIQUE(id,school_id,campus_id)
);
-- 08 Resolution is immutable evidence requiring authorized online actor.
CREATE TABLE public.db09_conflict_resolutions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 conflict_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN
 ('keep_server','retry_as_new','manual_merge','abandon')),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 approved_at timestamptz NOT NULL DEFAULT now(),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 4 AND 1000),
 operation_id uuid NOT NULL,
 FOREIGN KEY(conflict_id,school_id,campus_id)
 REFERENCES public.db09_sync_conflicts(id,school_id,campus_id),
 UNIQUE(conflict_id),
 UNIQUE(school_id,operation_id)
);

-- 09 Sync run is an audit checkpoint and not proof of final acceptance.
CREATE TABLE public.db09_sync_runs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 device_id uuid NOT NULL,
 started_at timestamptz NOT NULL DEFAULT now(),
 ended_at timestamptz,
 status text NOT NULL DEFAULT 'started'
 CHECK(status IN ('started','completed','failed','revoked')),
 pushed_count integer NOT NULL DEFAULT 0 CHECK(pushed_count>=0),
 pulled_count integer NOT NULL DEFAULT 0 CHECK(pulled_count>=0),
 failed_count integer NOT NULL DEFAULT 0 CHECK(failed_count>=0),
 FOREIGN KEY(device_id,school_id,campus_id)
 REFERENCES public.db09_device_authorizations(device_id,school_id,campus_id),
 CHECK(ended_at IS NULL OR ended_at>=started_at)
);

-- 10-13 Backup destinations belong to Owner settings. Never store
-- encryption secrets, full local paths, raw backup database bytes here.
CREATE TABLE public.db09_backup_destinations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 destination_kind text NOT NULL CHECK(destination_kind IN
 ('local_encrypted','external_drive','cloud_encrypted')),
 label text NOT NULL CHECK(length(btrim(label)) BETWEEN 3 AND 150),
 encrypted_locator_ref text,
 enabled boolean NOT NULL DEFAULT true,
 configured_by uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 UNIQUE(id,school_id),
 UNIQUE(id,school_id,campus_id)
);
CREATE TABLE public.db09_backup_manifests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 device_id uuid NOT NULL,
 destination_id uuid NOT NULL,
 schema_version integer NOT NULL CHECK(schema_version>0),
 last_applied_seq bigint NOT NULL CHECK(last_applied_seq>=0),
 outbox_pending integer NOT NULL CHECK(outbox_pending>=0),
 unresolved_conflicts integer NOT NULL CHECK(unresolved_conflicts>=0),
 snapshot_sha256 bytea NOT NULL CHECK(octet_length(snapshot_sha256)=32),
 size_bytes bigint NOT NULL CHECK(size_bytes>0),
 encrypted boolean NOT NULL DEFAULT true CHECK(encrypted),
 snapshot_at timestamptz NOT NULL DEFAULT now(),
 created_by uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY(device_id,school_id,campus_id)
 REFERENCES public.db09_device_authorizations(device_id,school_id,campus_id),
 FOREIGN KEY(destination_id,school_id)
 REFERENCES public.db09_backup_destinations(id,school_id),
 UNIQUE(id,school_id,campus_id),
 UNIQUE(school_id,device_id,destination_id,snapshot_sha256)
);
CREATE TABLE public.db09_backup_artifacts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 manifest_id uuid NOT NULL,
 artifact_kind text NOT NULL CHECK(artifact_kind IN
 ('sqlite_encrypted','documents_encrypted','outbox_encrypted','cloud_snapshot')),
 storage_ref text NOT NULL CHECK(length(btrim(storage_ref)) BETWEEN 4 AND 500),
 checksum_sha256 bytea NOT NULL CHECK(octet_length(checksum_sha256)=32),
 size_bytes bigint NOT NULL CHECK(size_bytes>0),
 FOREIGN KEY(manifest_id,school_id,campus_id)
 REFERENCES public.db09_backup_manifests(id,school_id,campus_id),
 UNIQUE(manifest_id,artifact_kind)
);
CREATE TABLE public.db09_restore_sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 target_device_id uuid NOT NULL,
 manifest_id uuid,
 cloud_base_seq bigint NOT NULL CHECK(cloud_base_seq>=0),
 status text NOT NULL DEFAULT 'planned' CHECK(status IN
 ('planned','validated','approved','restored','failed')),
 started_by uuid NOT NULL REFERENCES auth.users(id),
 approved_by uuid REFERENCES auth.users(id),
 started_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 4 AND 1000),
 FOREIGN KEY(target_device_id,school_id,campus_id)
 REFERENCES public.db09_device_authorizations(device_id,school_id,campus_id),
 FOREIGN KEY(manifest_id,school_id,campus_id)
 REFERENCES public.db09_backup_manifests(id,school_id,campus_id),
 CHECK(status NOT IN ('approved','restored') OR approved_by IS NOT NULL),
 UNIQUE(id,school_id,campus_id)
);
-- 14 Immutable restore steps, including verified cloud base then pending
-- backup outbox reconciliation; cannot overwrite newer Supabase records.
CREATE TABLE public.db09_restore_check_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 restore_id uuid NOT NULL,
 step_code text NOT NULL CHECK(step_code IN
 ('cloud_latest_loaded','backup_checksum_verified','storage_files_checked',
  'pending_outbox_replayed','conflicts_reviewed','final_verification')),
 step_status text NOT NULL CHECK(step_status IN ('passed','failed','skipped')),
 detail_json jsonb NOT NULL DEFAULT '{}'::jsonb
  CHECK(jsonb_typeof(detail_json)='object'),
 checked_by uuid NOT NULL REFERENCES auth.users(id),
 checked_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(restore_id,school_id,campus_id)
 REFERENCES public.db09_restore_sessions(id,school_id,campus_id),
 UNIQUE(restore_id,step_code,checked_at)
);

-- 15-16 Reporting projections are scoped, never untrusted SQL.
CREATE TABLE public.db09_report_definitions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 report_kind text NOT NULL CHECK(report_kind IN
 ('owner_dashboard','campus_dashboard','fee_summary','attendance_summary',
  'salary_summary','cashbook','inventory_summary','transport_summary')),
 source_domain text NOT NULL CHECK(source_domain IN
 ('school','fees','attendance','payroll','finance','inventory','transport')),
 parameters_json jsonb NOT NULL DEFAULT '{}'::jsonb
  CHECK(jsonb_typeof(parameters_json)='object'),
 authorized_by uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 UNIQUE NULLS NOT DISTINCT(school_id,campus_id,report_kind),
 UNIQUE(id,school_id)
);
CREATE TABLE public.db09_report_snapshots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 report_id uuid NOT NULL,
 campus_id uuid,
 as_of date NOT NULL,
 source_seq bigint NOT NULL CHECK(source_seq>=0),
 is_demo boolean NOT NULL DEFAULT false,
 aggregates_json jsonb NOT NULL CHECK(jsonb_typeof(aggregates_json)='object'),
 generated_at timestamptz NOT NULL DEFAULT now(),
 generated_by uuid REFERENCES auth.users(id),
 FOREIGN KEY(report_id,school_id)
 REFERENCES public.db09_report_definitions(id,school_id),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 UNIQUE(report_id,as_of,source_seq),
 UNIQUE(id,school_id)
);

-- 17 Device reassignment: NEVER allow offline campus change.
CREATE TABLE public.db09_device_reassign_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 device_id uuid NOT NULL REFERENCES public.registered_devices(id),
 from_campus_id uuid NOT NULL,
 to_campus_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN
 ('requested','rejected','approved_with_wipe')),
 authorized_by uuid NOT NULL REFERENCES auth.users(id),
 operation_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(from_campus_id,school_id) REFERENCES public.campuses(id,school_id),
 FOREIGN KEY(to_campus_id,school_id) REFERENCES public.campuses(id,school_id),
 CHECK(from_campus_id<>to_campus_id),
 UNIQUE(school_id,operation_id)
);

CREATE FUNCTION app_private.db09_guard_device_cursor()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $db09$
DECLARE v_auth public.db09_device_authorizations%ROWTYPE;
BEGIN
 SELECT * INTO v_auth FROM public.db09_device_authorizations
 WHERE device_id=NEW.device_id AND school_id=NEW.school_id
 AND campus_id=NEW.campus_id FOR SHARE;
 IF NOT FOUND OR v_auth.revoked_at IS NOT NULL OR NOT v_auth.offline_allowed
 OR (v_auth.expires_at IS NOT NULL AND v_auth.expires_at<=now()) THEN
  RAISE EXCEPTION 'Device not authorized for campus cursor' USING ERRCODE='23514';
 END IF;
 IF TG_OP='UPDATE' AND (
  NEW.device_id<>OLD.device_id OR NEW.school_id<>OLD.school_id
  OR NEW.campus_id<>OLD.campus_id OR NEW.report_revision<>OLD.report_revision+1
  OR NEW.last_reported_applied_seq<OLD.last_reported_applied_seq
 ) THEN
  RAISE EXCEPTION 'Cursor rollback or scope change forbidden' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$db09$;
CREATE TRIGGER db09_cursor_guard BEFORE INSERT OR UPDATE
 ON public.db09_device_cursors FOR EACH ROW
 EXECUTE FUNCTION app_private.db09_guard_device_cursor();

CREATE FUNCTION app_private.db09_reject_evidence_edit()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $db09$
BEGIN
 RAISE EXCEPTION 'Immutable sync/backup evidence' USING ERRCODE='23514';
END;
$db09$;
CREATE TRIGGER db09_device_access_events_no_edit BEFORE UPDATE OR DELETE ON public.db09_device_access_events FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_device_access_events_no_truncate BEFORE TRUNCATE ON public.db09_device_access_events FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_operation_receipts_no_edit BEFORE UPDATE OR DELETE ON public.db09_operation_receipts FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_operation_receipts_no_truncate BEFORE TRUNCATE ON public.db09_operation_receipts FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_cloud_changes_no_edit BEFORE UPDATE OR DELETE ON public.db09_cloud_changes FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_cloud_changes_no_truncate BEFORE TRUNCATE ON public.db09_cloud_changes FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_tombstones_no_edit BEFORE UPDATE OR DELETE ON public.db09_tombstones FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_tombstones_no_truncate BEFORE TRUNCATE ON public.db09_tombstones FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_conflict_resolutions_no_edit BEFORE UPDATE OR DELETE ON public.db09_conflict_resolutions FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_conflict_resolutions_no_truncate BEFORE TRUNCATE ON public.db09_conflict_resolutions FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_backup_manifests_no_edit BEFORE UPDATE OR DELETE ON public.db09_backup_manifests FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_backup_manifests_no_truncate BEFORE TRUNCATE ON public.db09_backup_manifests FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_backup_artifacts_no_edit BEFORE UPDATE OR DELETE ON public.db09_backup_artifacts FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_backup_artifacts_no_truncate BEFORE TRUNCATE ON public.db09_backup_artifacts FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_restore_check_events_no_edit BEFORE UPDATE OR DELETE ON public.db09_restore_check_events FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_restore_check_events_no_truncate BEFORE TRUNCATE ON public.db09_restore_check_events FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_device_reassign_events_no_edit BEFORE UPDATE OR DELETE ON public.db09_device_reassign_events FOR EACH ROW EXECUTE FUNCTION app_private.db09_reject_evidence_edit();
CREATE TRIGGER db09_device_reassign_events_no_truncate BEFORE TRUNCATE ON public.db09_device_reassign_events FOR EACH STATEMENT EXECUTE FUNCTION app_private.db09_reject_evidence_edit();

ALTER TABLE public.db09_device_authorizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_device_access_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_operation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_change_clocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_cloud_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_tombstones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_device_cursors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_sync_conflicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_conflict_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_sync_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_backup_destinations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_backup_manifests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_backup_artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_restore_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_restore_check_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_report_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_report_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db09_device_reassign_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.db09_device_authorizations,
 public.db09_device_access_events,
 public.db09_operation_receipts,
 public.db09_change_clocks,
 public.db09_cloud_changes,
 public.db09_tombstones,
 public.db09_device_cursors,
 public.db09_sync_conflicts,
 public.db09_conflict_resolutions,
 public.db09_sync_runs,
 public.db09_backup_destinations,
 public.db09_backup_manifests,
 public.db09_backup_artifacts,
 public.db09_restore_sessions,
 public.db09_restore_check_events,
 public.db09_report_definitions,
 public.db09_report_snapshots,
 public.db09_device_reassign_events FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db09_guard_device_cursor() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db09_assign_change_seq() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db09_reject_evidence_edit() FROM PUBLIC,anon,authenticated;

