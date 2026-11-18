-- Mirror of applied live Supabase migration 20261118095758.
-- DB22: Preserve historical exam enrollment eligibility regardless of current student status.
CREATE OR REPLACE FUNCTION app_private.sms_exam_roster(p_exam uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 AND (en.ended_on IS NULL OR en.ended_on>=v_exam.scheduled_on);
 RETURN jsonb_build_object('exam_id',p_exam,'status',v_exam.status,
 'max_marks',v_exam.max_marks,'pass_marks',v_exam.pass_marks,'roster',v_roster);
END;
$function$
;

CREATE OR REPLACE FUNCTION app_private.sms_exam_save_mark(p_exam uuid, p_enrollment uuid, p_score numeric, p_absent boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 AND en.class_id=v_exam.class_id
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
$function$
;


