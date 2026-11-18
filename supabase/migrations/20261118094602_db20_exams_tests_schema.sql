-- Live Supabase migration mirror 20261118094602 (db20_exams_tests_schema).
-- Do not reapply to a database where migration exists.

-- DB20 Exams & tests: schema, fail-closed RLS, composite student/campus/year containment.
CREATE TABLE public.sms_exam_subjects(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,campus_id uuid NOT NULL,academic_year_id uuid NOT NULL,
 class_id uuid NOT NULL,name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 100),
 created_by uuid NOT NULL REFERENCES auth.users(id),created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(class_id,campus_id,academic_year_id) REFERENCES public.classes(id,campus_id,academic_year_id),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 FOREIGN KEY(academic_year_id,school_id) REFERENCES public.academic_years(id,school_id),
 UNIQUE(id,school_id,campus_id,academic_year_id,class_id));
CREATE UNIQUE INDEX sms_exam_subject_name ON public.sms_exam_subjects(
 school_id,campus_id,academic_year_id,class_id,lower(name));
CREATE TABLE public.sms_exams(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,
 campus_id uuid NOT NULL,academic_year_id uuid NOT NULL,class_id uuid NOT NULL,
 section_id uuid,subject_id uuid NOT NULL,title text NOT NULL CHECK(length(btrim(title)) BETWEEN 2 AND 120),
 kind text NOT NULL CHECK(kind IN('exam','test','quiz')),scheduled_on date NOT NULL,
 max_marks numeric(7,2) NOT NULL CHECK(max_marks>0 AND max_marks<=10000),
 pass_marks numeric(7,2) NOT NULL CHECK(pass_marks>=0 AND pass_marks<=max_marks),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN('draft','published')),
 created_by uuid NOT NULL REFERENCES auth.users(id),created_at timestamptz NOT NULL DEFAULT now(),
 published_by uuid REFERENCES auth.users(id),published_at timestamptz,
 FOREIGN KEY(class_id,campus_id,academic_year_id) REFERENCES public.classes(id,campus_id,academic_year_id),
 FOREIGN KEY(section_id,class_id) REFERENCES public.sections(id,class_id),
 FOREIGN KEY(subject_id,school_id,campus_id,academic_year_id,class_id)
 REFERENCES public.sms_exam_subjects(id,school_id,campus_id,academic_year_id,class_id),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 FOREIGN KEY(academic_year_id,school_id) REFERENCES public.academic_years(id,school_id),
 CHECK((status='draft' AND published_by IS NULL AND published_at IS NULL) OR
 (status='published' AND published_by IS NOT NULL AND published_at IS NOT NULL)),
 UNIQUE(id,school_id,campus_id,academic_year_id,class_id));
CREATE INDEX sms_exams_calendar ON public.sms_exams(school_id,campus_id,academic_year_id,scheduled_on);
CREATE TABLE public.sms_exam_marks(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 exam_id uuid NOT NULL,enrollment_id uuid NOT NULL,student_id uuid NOT NULL,
 school_id uuid NOT NULL,campus_id uuid NOT NULL,academic_year_id uuid NOT NULL,class_id uuid NOT NULL,
 score numeric(7,2),absent boolean NOT NULL DEFAULT false,
 updated_by uuid NOT NULL REFERENCES auth.users(id),updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((absent AND score IS NULL) OR (NOT absent AND score IS NOT NULL AND score>=0)),
 FOREIGN KEY(exam_id,school_id,campus_id,academic_year_id,class_id)
 REFERENCES public.sms_exams(id,school_id,campus_id,academic_year_id,class_id),
 FOREIGN KEY(enrollment_id,student_id,school_id,campus_id,academic_year_id,class_id)
 REFERENCES public.student_enrollments(id,student_id,school_id,campus_id,academic_year_id,class_id),
 UNIQUE(exam_id,enrollment_id));
CREATE INDEX sms_exam_marks_enrollment ON public.sms_exam_marks(enrollment_id);
CREATE TABLE app_private.sms_exam_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid NOT NULL REFERENCES public.campuses(id),exam_id uuid,
 actor_id uuid NOT NULL REFERENCES auth.users(id),action text NOT NULL,
 event_at timestamptz NOT NULL DEFAULT now(),details jsonb NOT NULL DEFAULT '{}'::jsonb);
ALTER TABLE public.sms_exam_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_exam_marks ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.sms_exam_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sms_exam_subjects,public.sms_exams,public.sms_exam_marks FROM PUBLIC,anon,authenticated;
REVOKE ALL ON app_private.sms_exam_events FROM PUBLIC,anon,authenticated;

