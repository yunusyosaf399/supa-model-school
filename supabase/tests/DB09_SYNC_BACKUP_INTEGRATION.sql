-- DB09 fictional SQL acceptance. DISPOSABLE LOCAL PostgreSQL ONLY.
-- Requires DB01..DB09 schema source in order; NOT hosted production.
-- Requires local Auth user sms-adm-admin-a@example.invalid.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';
DO $fixture$
DECLARE
 actor uuid;
 s uuid:='11111111-1111-4111-8111-111111111111';
 ca uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 cb uuid:='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 dev uuid:='90000000-0000-4000-8000-000000000001';
 destination uuid:='90000000-0000-4000-8000-000000000002';
 manifest uuid:='90000000-0000-4000-8000-000000000003';
 restore uuid:='90000000-0000-4000-8000-000000000004';
 report uuid:='90000000-0000-4000-8000-000000000005';
 n integer; v_last_seq bigint;
BEGIN
 SELECT id INTO actor FROM auth.users
 WHERE email='sms-adm-admin-a@example.invalid';
 IF actor IS NULL THEN RAISE EXCEPTION 'Create fictional local Auth user'; END IF;
 INSERT INTO public.schools(id,name,currency_code,timezone_name)
 VALUES(s,'Fictional Sync School','PKR','Asia/Karachi');
 INSERT INTO public.campuses(id,school_id,code,name)
 VALUES(ca,s,'A','Campus A'),(cb,s,'B','Campus B');
 INSERT INTO public.user_profiles(user_id,display_name)
 VALUES(actor,'Fictional Desktop Operator');
 INSERT INTO public.registered_devices(
 id,school_id,assigned_campus_id,registered_user_id,display_name,is_offline_enabled)
 VALUES(dev,s,ca,actor,'Local Campus A Windows Test',true);
 INSERT INTO public.db09_device_authorizations(
 device_id,school_id,campus_id,offline_allowed,authorized_by)
 VALUES(dev,s,ca,true,actor);
 BEGIN
  INSERT INTO public.db09_device_cursors(
   device_id,school_id,campus_id,last_reported_applied_seq)
  VALUES(dev,s,cb,0);
  RAISE EXCEPTION 'CROSS CAMPUS device cursor accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 INSERT INTO public.db09_operation_receipts(
 school_id,operation_id,campus_id,device_id,actor_id,entity_kind,
 entity_id,expected_revision,request_sha256,result_kind,result_json)
 VALUES(s,'99999999-0000-4000-8000-000000000001',ca,dev,actor,
 'admission_draft','99999999-0000-4000-8000-000000000010',1,
 decode(repeat('ab',32),'hex'),'conflict','{"reason":"stale_revision"}');
 BEGIN
  INSERT INTO public.db09_operation_receipts(
   school_id,operation_id,campus_id,device_id,actor_id,entity_kind,
   request_sha256,result_kind,result_json)
  VALUES(s,'99999999-0000-4000-8000-000000000001',ca,dev,actor,
   'admission_draft',decode(repeat('cd',32),'hex'),'accepted','{}');
  RAISE EXCEPTION 'Duplicate operation UUID stored with changed payload';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 INSERT INTO public.db09_sync_conflicts(
 school_id,campus_id,device_id,operation_id,entity_kind,entity_id,
 local_revision,server_revision,conflict_kind)
 VALUES(s,ca,dev,'99999999-0000-4000-8000-000000000001',
 'admission_draft','99999999-0000-4000-8000-000000000010',
 1,2,'stale_revision');
 INSERT INTO public.db09_cloud_changes(
 school_id,audience,campus_id,entity_kind,entity_id,change_kind,revision)
 VALUES(s,'campus',ca,'student','99999999-0000-4000-8000-000000000010',
 'upsert',2);
 INSERT INTO public.db09_cloud_changes(
 school_id,audience,campus_id,entity_kind,entity_id,change_kind,revision)
 VALUES(s,'campus',ca,'student','99999999-0000-4000-8000-000000000011',
 'delete',3);
 SELECT c.last_seq INTO v_last_seq FROM public.db09_change_clocks c WHERE c.school_id=s;
 IF v_last_seq<>2 THEN RAISE EXCEPTION 'Commit ordered change feed failed: %',v_last_seq; END IF;
 INSERT INTO public.db09_tombstones(
 school_id,change_seq,entity_kind,entity_id,campus_id)
 VALUES(s,2,'student','99999999-0000-4000-8000-000000000011',ca);
 BEGIN
  DELETE FROM public.db09_cloud_changes WHERE school_id=s AND change_seq=1;
  RAISE EXCEPTION 'Cloud change history mutable';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 INSERT INTO public.db09_device_cursors(
 device_id,school_id,campus_id,last_reported_applied_seq,bootstrap_seq)
 VALUES(dev,s,ca,2,1);
 INSERT INTO public.db09_backup_destinations(
 id,school_id,campus_id,destination_kind,label,configured_by)
 VALUES(destination,s,ca,'external_drive','Encrypted External Disk',actor);
 INSERT INTO public.db09_backup_manifests(
 id,school_id,campus_id,device_id,destination_id,schema_version,
 last_applied_seq,outbox_pending,unresolved_conflicts,snapshot_sha256,
 size_bytes,created_by)
 VALUES(manifest,s,ca,dev,destination,9,2,1,1,
 decode(repeat('bc',32),'hex'),1048576,actor);
 INSERT INTO public.db09_backup_artifacts(
 school_id,campus_id,manifest_id,artifact_kind,storage_ref,
 checksum_sha256,size_bytes)
 VALUES(s,ca,manifest,'sqlite_encrypted','encrypted-asset-reference',
 decode(repeat('cd',32),'hex'),1048576);
 INSERT INTO public.db09_restore_sessions(
 id,school_id,campus_id,target_device_id,manifest_id,cloud_base_seq,
 status,started_by,approved_by,reason)
 VALUES(restore,s,ca,dev,manifest,2,'approved',actor,actor,
 'Fictional replacement desktop restore');
 INSERT INTO public.db09_restore_check_events(
 school_id,campus_id,restore_id,step_code,step_status,checked_by)
 VALUES(s,ca,restore,'cloud_latest_loaded','passed',actor),
 (s,ca,restore,'backup_checksum_verified','passed',actor),
 (s,ca,restore,'pending_outbox_replayed','passed',actor);
 INSERT INTO public.db09_report_definitions(
 id,school_id,campus_id,report_kind,source_domain,authorized_by)
 VALUES(report,s,ca,'campus_dashboard','school',actor);
 INSERT INTO public.db09_report_snapshots(
 school_id,report_id,campus_id,as_of,source_seq,aggregates_json)
 VALUES(s,report,ca,'2026-04-06',2,'{"pupils":0,"is_demo":false}');
 SELECT count(*) INTO n FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='public' AND c.relrowsecurity
 AND c.relname LIKE 'db09\_%' ESCAPE '\';
 IF n<>18 THEN RAISE EXCEPTION 'DB09 RLS missing: %/18',n; END IF;
 IF pg_catalog.has_table_privilege('authenticated',
 'public.db09_operation_receipts','INSERT')
 OR pg_catalog.has_table_privilege('anon','public.db09_cloud_changes','SELECT')
 THEN RAISE EXCEPTION 'Direct sync table privileges unsafe'; END IF;
END;
$fixture$;
\echo DB09 local fictional sync and backup assertions passed - ROLLBACK
ROLLBACK;
