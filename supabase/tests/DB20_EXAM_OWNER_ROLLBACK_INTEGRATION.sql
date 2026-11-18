-- Supa Model School DB20/DB21 examination smoke test.
-- Run in Supabase SQL Editor with a privileged test operator.
-- BEGIN/ROLLBACK guarantees no test subject, marks or exam are retained.
-- Intentionally tests authenticated RPCs, NOT direct base-table access.
BEGIN;
DO $auth$
DECLARE v_owner uuid;v_school uuid;v_campus uuid;v_year uuid;v_class uuid;v_date date;
BEGIN
 SELECT e.school_id,e.campus_id,e.academic_year_id,e.class_id,
 GREATEST(e.admitted_on,y.starts_on)
 INTO v_school,v_campus,v_year,v_class,v_date
 FROM public.student_enrollments e
 JOIN public.students s ON s.id=e.student_id AND s.active_status='active'
 JOIN public.academic_years y ON y.id=e.academic_year_id
 WHERE e.ended_on IS NULL AND GREATEST(e.admitted_on,y.starts_on)<=y.ends_on
 ORDER BY e.created_at LIMIT 1;
 SELECT user_id INTO v_owner FROM public.user_roles
 WHERE role='owner' AND is_active LIMIT 1;
 IF v_owner IS NULL OR v_class IS NULL THEN
   RAISE EXCEPTION 'Need one Owner and an active enrolled student fixture';
 END IF;
 PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('sms.test.school',v_school::text,true);
 PERFORM set_config('sms.test.campus',v_campus::text,true);
 PERFORM set_config('sms.test.year',v_year::text,true);
 PERFORM set_config('sms.test.class',v_class::text,true);
 PERFORM set_config('sms.test.date',v_date::text,true);
END $auth$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE v_school uuid:=current_setting('sms.test.school')::uuid;
 v_campus uuid:=current_setting('sms.test.campus')::uuid;
 v_year uuid:=current_setting('sms.test.year')::uuid;
 v_class uuid:=current_setting('sms.test.class')::uuid;
 v_date date:=current_setting('sms.test.date')::date;
 v_subject uuid;v_exam uuid;v_mark jsonb;v_count int:=0;
BEGIN
 v_subject:=(public.sms_exam_create_subject(v_school,v_campus,v_year,
   v_class,'Temporary Exam Smoke Subject')->>'id')::uuid;
 v_exam:=(public.sms_exam_create(v_school,v_campus,v_year,v_class,NULL,
   v_subject,'test','Temporary Exam Smoke Test',v_date,100,40)->>'id')::uuid;
 FOR v_mark IN SELECT value FROM jsonb_array_elements(
   public.sms_exam_roster(v_exam)->'roster') LOOP
   PERFORM public.sms_exam_save_mark(v_exam,
     (v_mark->>'enrollment_id')::uuid,75,false);
   v_count:=v_count+1;
 END LOOP;
 IF v_count<1 THEN RAISE EXCEPTION 'No roster students'; END IF;
 IF public.sms_exam_publish(v_exam)->>'published'<>'true'
 THEN RAISE EXCEPTION 'Publish not confirmed'; END IF;
 IF public.sms_exam_roster(v_exam)->>'status'<>'published'
 THEN RAISE EXCEPTION 'Published roster not reflected'; END IF;
 BEGIN
   PERFORM public.sms_exam_save_mark(
     v_exam,(v_mark->>'enrollment_id')::uuid,88,false);
   RAISE EXCEPTION 'Published result was mutable';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
 END;
END $test$;
SELECT 'PASS - Owner create/roster/save/publish and immutable published marks' AS result;
ROLLBACK;
-- Also verify grants without touching any rows:
SELECT has_function_privilege('anon',
  'public.sms_exam_snapshot(uuid,uuid,uuid)','EXECUTE') AS anon_can_run_snapshot,
 has_table_privilege('authenticated','public.sms_exams','SELECT') AS direct_client_select,
 has_function_privilege('authenticated',
  'public.sms_exam_snapshot(uuid,uuid,uuid)','EXECUTE') AS signed_in_rpc_enabled;
-- Expected: false, false, true.
