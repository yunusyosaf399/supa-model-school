-- Mirror of applied live Supabase migration 20261118100705.
-- DB23: Deny teachers broad exam roster access until class/subject-scoped permission exists.
CREATE OR REPLACE FUNCTION app_private.sms_exam_require(p_school uuid, p_campus uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF (SELECT auth.uid()) IS NULL OR p_school IS NULL OR p_campus IS NULL
 OR p_action NOT IN ('exams.read','exams.create','exams.update')
 OR NOT EXISTS(SELECT 1 FROM public.campuses c JOIN public.schools s
 ON s.id=c.school_id AND s.status='active'
 WHERE c.id=p_campus AND c.school_id=p_school AND c.is_active)
 OR EXISTS (
   SELECT 1 FROM public.user_roles teacher_role
   WHERE teacher_role.user_id=(SELECT auth.uid())
     AND teacher_role.school_id=p_school
     AND teacher_role.campus_id=p_campus
     AND teacher_role.role='teacher' AND teacher_role.is_active
 ) -- Teacher access requires separate class-and-subject-scoped RPCs.
 OR NOT (app_private.is_verified_school_owner((SELECT auth.uid()),p_school)
    OR app_private.sms_permission_allowed(p_school,p_campus,p_action))
 THEN RAISE EXCEPTION 'Exam permission denied for campus' USING ERRCODE='42501'; END IF;
END;
$function$
;
