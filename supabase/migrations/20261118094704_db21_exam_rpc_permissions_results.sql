-- Live Supabase migration mirror 20261118094704 (db21_exam_rpc_permissions_results).
-- Do not reapply to a database where migration exists.

-- DB21: Authenticated exam/test workflows. Private definer functions
-- verify effective Owner or campus grant on every call, public RPC wrappers
-- execute as invoker. All base tables remain RLS-denied to clients.
CREATE FUNCTION app_private.sms_exam_require(p_school uuid,p_campus uuid,p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
BEGIN
 IF (SELECT auth.uid()) IS NULL OR p_school IS NULL OR p_campus IS NULL
 OR p_action NOT IN ('exams.read','exams.create','exams.update')
 OR NOT EXISTS(SELECT 1 FROM public.campuses c JOIN public.schools s
 ON s.id=c.school_id AND s.status='active'
 WHERE c.id=p_campus AND c.school_id=p_school AND c.is_active)
 OR NOT (app_private.is_verified_school_owner((SELECT auth.uid()),p_school)
    OR app_private.sms_permission_allowed(p_school,p_campus,p_action))
 THEN RAISE EXCEPTION 'Exam permission denied for campus' USING ERRCODE='42501'; END IF;
END;
$f$;
CREATE FUNCTION app_private.sms_exam_snapshot(p_school uuid,p_campus uuid,p_year uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_year uuid;v_label text;v_result jsonb;
BEGIN
 PERFORM app_private.sms_exam_require(p_school,p_campus,'exams.read');
 SELECT y.id,y.label INTO v_year,v_label FROM public.academic_years y
 WHERE y.school_id=p_school AND (y.id=p_year OR (p_year IS NULL AND y.is_active))
 ORDER BY y.is_active DESC LIMIT 1;
 IF v_year IS NULL THEN RAISE EXCEPTION 'No academic year found' USING ERRCODE='22023'; END IF;
 SELECT jsonb_build_object('year_id',v_year,'year_label',v_label,
  'classes',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',c.id,'name',c.name,'sections',COALESCE((
   SELECT jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) ORDER BY s.name)
   FROM public.sections s WHERE s.class_id=c.id),'[]'::jsonb)
  ) ORDER BY c.sort_order,c.name)
   FROM public.classes c WHERE c.school_id=p_school AND c.campus_id=p_campus
   AND c.academic_year_id=v_year),'[]'::jsonb),
  'subjects',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',s.id,'class_id',s.class_id,'name',s.name) ORDER BY s.name)
   FROM public.sms_exam_subjects s WHERE s.school_id=p_school
   AND s.campus_id=p_campus AND s.academic_year_id=v_year),'[]'::jsonb),
  'exams',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',e.id,'title',e.title,'kind',e.kind,'class_id',e.class_id,
   'section_id',e.section_id,'subject_id',e.subject_id,'date',e.scheduled_on,
   'max_marks',e.max_marks,'pass_marks',e.pass_marks,'status',e.status,
   'entered',(SELECT count(*) FROM public.sms_exam_marks m WHERE m.exam_id=e.id)
  ) ORDER BY e.scheduled_on DESC,e.created_at DESC)
   FROM public.sms_exams e WHERE e.school_id=p_school AND e.campus_id=p_campus
   AND e.academic_year_id=v_year),'[]'::jsonb)
 ) INTO v_result;
 RETURN v_result;
END;
$f$;
CREATE FUNCTION app_private.sms_exam_create_subject(
 p_school uuid,p_campus uuid,p_year uuid,p_class uuid,p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_id uuid;
BEGIN
 PERFORM app_private.sms_exam_require(p_school,p_campus,'exams.create');
 IF length(btrim(coalesce(p_name,''))) NOT BETWEEN 2 AND 100
 OR NOT EXISTS(SELECT 1 FROM public.classes c WHERE c.id=p_class
 AND c.school_id=p_school AND c.campus_id=p_campus AND c.academic_year_id=p_year)
 THEN RAISE EXCEPTION 'Invalid subject or class' USING ERRCODE='22023'; END IF;
 INSERT INTO public.sms_exam_subjects(school_id,campus_id,academic_year_id,class_id,name,created_by)
 VALUES(p_school,p_campus,p_year,p_class,btrim(p_name),(SELECT auth.uid()))
 RETURNING id INTO v_id;
 INSERT INTO app_private.sms_exam_events(school_id,campus_id,actor_id,action,details)
 VALUES(p_school,p_campus,(SELECT auth.uid()),'subject_created',jsonb_build_object('subject_id',v_id));
 RETURN jsonb_build_object('id',v_id);
END;
$f$;
CREATE FUNCTION app_private.sms_exam_create(
 p_school uuid,p_campus uuid,p_year uuid,p_class uuid,p_section uuid,
 p_subject uuid,p_kind text,p_title text,p_date date,p_max numeric,p_pass numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_id uuid;v_year public.academic_years%rowtype;
BEGIN
 PERFORM app_private.sms_exam_require(p_school,p_campus,'exams.create');
 SELECT * INTO v_year FROM public.academic_years WHERE id=p_year AND school_id=p_school;
 IF v_year.id IS NULL OR p_kind NOT IN ('exam','test','quiz')
 OR length(btrim(coalesce(p_title,''))) NOT BETWEEN 2 AND 120
 OR p_date IS NULL OR p_date<v_year.starts_on OR p_date>v_year.ends_on
 OR p_max IS NULL OR p_max<=0 OR p_max>10000 OR p_pass IS NULL
 OR p_pass<0 OR p_pass>p_max
 OR NOT EXISTS(SELECT 1 FROM public.sms_exam_subjects s
 WHERE s.id=p_subject AND s.school_id=p_school AND s.campus_id=p_campus
 AND s.academic_year_id=p_year AND s.class_id=p_class)
 OR (p_section IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.sections
 WHERE id=p_section AND class_id=p_class))
 THEN RAISE EXCEPTION 'Invalid exam, subject, schedule or marks' USING ERRCODE='22023'; END IF;
 INSERT INTO public.sms_exams(school_id,campus_id,academic_year_id,class_id,section_id,
 subject_id,kind,title,scheduled_on,max_marks,pass_marks,created_by)
 VALUES(p_school,p_campus,p_year,p_class,p_section,p_subject,p_kind,btrim(p_title),
 p_date,p_max,p_pass,(SELECT auth.uid())) RETURNING id INTO v_id;
 INSERT INTO app_private.sms_exam_events(school_id,campus_id,exam_id,actor_id,action)
 VALUES(p_school,p_campus,v_id,(SELECT auth.uid()),'created');
 RETURN jsonb_build_object('id',v_id,'status','draft');
END;
$f$;
CREATE FUNCTION app_private.sms_exam_roster(p_exam uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_exam public.sms_exams%rowtype;v_roster jsonb;
BEGIN
 SELECT * INTO v_exam FROM public.sms_exams WHERE id=p_exam;
 IF v_exam.id IS NULL THEN RAISE EXCEPTION 'Exam not found' USING ERRCODE='22023'; END IF;
 PERFORM app_private.sms_exam_require(v_exam.school_id,v_exam.campus_id,'exams.read');
 SELECT COALESCE(jsonb_agg(jsonb_build_object('enrollment_id',en.id,
 'student_name',st.full_name_en,'registration_no',st.registration_no,
 'roll_no',en.class_roll_no,'score',m.score,
 'absent',COALESCE(m.absent,false),'entered',m.id IS NOT NULL)
 ORDER BY st.full_name_en,en.id),'[]'::jsonb) INTO v_roster
 FROM public.student_enrollments en
 JOIN public.students st ON st.id=en.student_id AND st.school_id=en.school_id
 LEFT JOIN public.sms_exam_marks m ON m.exam_id=p_exam AND m.enrollment_id=en.id
 WHERE en.school_id=v_exam.school_id AND en.campus_id=v_exam.campus_id
 AND en.academic_year_id=v_exam.academic_year_id AND en.class_id=v_exam.class_id
 AND (v_exam.section_id IS NULL OR en.section_id=v_exam.section_id)
 AND en.admitted_on<=v_exam.scheduled_on
 AND (en.ended_on IS NULL OR en.ended_on>=v_exam.scheduled_on)
 AND st.active_status='active';
 RETURN jsonb_build_object('exam_id',p_exam,'status',v_exam.status,
 'max_marks',v_exam.max_marks,'pass_marks',v_exam.pass_marks,'roster',v_roster);
END;
$f$;
CREATE FUNCTION app_private.sms_exam_save_mark(
 p_exam uuid,p_enrollment uuid,p_score numeric,p_absent boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_exam public.sms_exams%rowtype;v_student uuid;
BEGIN
 SELECT * INTO v_exam FROM public.sms_exams WHERE id=p_exam FOR UPDATE;
 IF v_exam.id IS NULL THEN RAISE EXCEPTION 'Exam not found' USING ERRCODE='22023'; END IF;
 PERFORM app_private.sms_exam_require(v_exam.school_id,v_exam.campus_id,'exams.update');
 IF v_exam.status<>'draft' OR p_absent IS NULL
 OR (p_absent AND p_score IS NOT NULL)
 OR (NOT p_absent AND (p_score IS NULL OR p_score<0 OR p_score>v_exam.max_marks))
 THEN RAISE EXCEPTION 'Marks invalid or exam already published' USING ERRCODE='22023'; END IF;
 SELECT en.student_id INTO v_student FROM public.student_enrollments en
 JOIN public.students st ON st.id=en.student_id AND st.school_id=en.school_id
 WHERE en.id=p_enrollment AND en.school_id=v_exam.school_id
 AND en.campus_id=v_exam.campus_id AND en.academic_year_id=v_exam.academic_year_id
 AND en.class_id=v_exam.class_id AND st.active_status='active'
 AND (v_exam.section_id IS NULL OR en.section_id=v_exam.section_id)
 AND en.admitted_on<=v_exam.scheduled_on
 AND (en.ended_on IS NULL OR en.ended_on>=v_exam.scheduled_on);
 IF v_student IS NULL THEN RAISE EXCEPTION 'Student not eligible for this exam'
 USING ERRCODE='42501'; END IF;
 INSERT INTO public.sms_exam_marks(exam_id,enrollment_id,student_id,school_id,campus_id,
 academic_year_id,class_id,score,absent,updated_by)
 VALUES(p_exam,p_enrollment,v_student,v_exam.school_id,v_exam.campus_id,
 v_exam.academic_year_id,v_exam.class_id,p_score,p_absent,(SELECT auth.uid()))
 ON CONFLICT(exam_id,enrollment_id) DO UPDATE SET score=excluded.score,
 absent=excluded.absent,updated_by=excluded.updated_by,updated_at=now();
 INSERT INTO app_private.sms_exam_events(school_id,campus_id,exam_id,actor_id,action,details)
 VALUES(v_exam.school_id,v_exam.campus_id,p_exam,(SELECT auth.uid()),'mark_saved',
 jsonb_build_object('enrollment_id',p_enrollment,'score',p_score,'absent',p_absent));
 RETURN jsonb_build_object('saved',true);
END;
$f$;
CREATE FUNCTION app_private.sms_exam_publish(p_exam uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_exam public.sms_exams%rowtype;v_roster jsonb;v_total int;v_entered int;
BEGIN
 SELECT * INTO v_exam FROM public.sms_exams WHERE id=p_exam FOR UPDATE;
 IF v_exam.id IS NULL THEN RAISE EXCEPTION 'Exam not found' USING ERRCODE='22023'; END IF;
 PERFORM app_private.sms_exam_require(v_exam.school_id,v_exam.campus_id,'exams.update');
 IF v_exam.status<>'draft' THEN RAISE EXCEPTION 'Exam already published' USING ERRCODE='22023'; END IF;
 v_roster:=app_private.sms_exam_roster(p_exam)->'roster';
 v_total:=jsonb_array_length(v_roster);
 SELECT count(*) INTO v_entered FROM jsonb_array_elements(v_roster) r
 WHERE (r.value->>'entered')='true';
 IF v_total=0 OR v_entered<>v_total THEN
 RAISE EXCEPTION 'All student marks or absences are required before publication'
 USING ERRCODE='22023'; END IF;
 UPDATE public.sms_exams SET status='published',published_by=(SELECT auth.uid()),published_at=now()
 WHERE id=p_exam;
 INSERT INTO app_private.sms_exam_events(school_id,campus_id,exam_id,actor_id,action,details)
 VALUES(v_exam.school_id,v_exam.campus_id,p_exam,(SELECT auth.uid()),'published',
 jsonb_build_object('students',v_total));
 RETURN jsonb_build_object('published',true,'students',v_total);
END;
$f$;
CREATE FUNCTION public.sms_exam_snapshot(p_school uuid,p_campus uuid,p_year uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $f$ SELECT app_private.sms_exam_snapshot(p_school,p_campus,p_year); $f$;
CREATE FUNCTION public.sms_exam_create_subject(p_school uuid,p_campus uuid,p_year uuid,p_class uuid,p_name text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $f$ SELECT app_private.sms_exam_create_subject(p_school,p_campus,p_year,p_class,p_name); $f$;
CREATE FUNCTION public.sms_exam_create(p_school uuid,p_campus uuid,p_year uuid,p_class uuid,
 p_section uuid,p_subject uuid,p_kind text,p_title text,p_date date,p_max numeric,p_pass numeric)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $f$ SELECT app_private.sms_exam_create(p_school,p_campus,p_year,p_class,
 p_section,p_subject,p_kind,p_title,p_date,p_max,p_pass); $f$;
CREATE FUNCTION public.sms_exam_roster(p_exam uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $f$ SELECT app_private.sms_exam_roster(p_exam); $f$;
CREATE FUNCTION public.sms_exam_save_mark(p_exam uuid,p_enrollment uuid,p_score numeric,p_absent boolean)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $f$ SELECT app_private.sms_exam_save_mark(p_exam,p_enrollment,p_score,p_absent); $f$;
CREATE FUNCTION public.sms_exam_publish(p_exam uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $f$ SELECT app_private.sms_exam_publish(p_exam); $f$;
REVOKE ALL ON FUNCTION app_private.sms_exam_require(uuid,uuid,text),
 app_private.sms_exam_snapshot(uuid,uuid,uuid),
 app_private.sms_exam_create_subject(uuid,uuid,uuid,uuid,text),
 app_private.sms_exam_create(uuid,uuid,uuid,uuid,uuid,uuid,text,text,date,numeric,numeric),
 app_private.sms_exam_roster(uuid),app_private.sms_exam_save_mark(uuid,uuid,numeric,boolean),
 app_private.sms_exam_publish(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.sms_exam_snapshot(uuid,uuid,uuid),
 public.sms_exam_create_subject(uuid,uuid,uuid,uuid,text),
 public.sms_exam_create(uuid,uuid,uuid,uuid,uuid,uuid,text,text,date,numeric,numeric),
 public.sms_exam_roster(uuid),public.sms_exam_save_mark(uuid,uuid,numeric,boolean),
 public.sms_exam_publish(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app_private.sms_exam_snapshot(uuid,uuid,uuid),
 app_private.sms_exam_create_subject(uuid,uuid,uuid,uuid,text),
 app_private.sms_exam_create(uuid,uuid,uuid,uuid,uuid,uuid,text,text,date,numeric,numeric),
 app_private.sms_exam_roster(uuid),app_private.sms_exam_save_mark(uuid,uuid,numeric,boolean),
 app_private.sms_exam_publish(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sms_exam_snapshot(uuid,uuid,uuid),
 public.sms_exam_create_subject(uuid,uuid,uuid,uuid,text),
 public.sms_exam_create(uuid,uuid,uuid,uuid,uuid,uuid,text,text,date,numeric,numeric),
 public.sms_exam_roster(uuid),public.sms_exam_save_mark(uuid,uuid,numeric,boolean),
 public.sms_exam_publish(uuid) TO authenticated;
UPDATE app_private.sms_permission_catalog SET is_implemented=true
WHERE code IN('exams.read','exams.create','exams.update');

