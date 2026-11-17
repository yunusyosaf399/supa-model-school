-- DB04 Attendance schema, review draft ONLY (2026-11-16).
-- Stacked on DB03 draft PR #25. Requires DB01 + DB02 deployed and DB03
-- composite enrollment constraint before this file may be applied.
-- One school, multiple campuses; Windows assigned-campus offline drafts
-- and Android online-only. Do not deploy or generate Flutter code here.
-- DB01's current role check excludes 'teacher'; do not grant attendance
-- rights until reviewed role expansion and class/period authorization exist.
BEGIN;

-- 1. A campus/year-aware school day. A date may differ by campus.
CREATE TABLE public.school_calendar_days (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  calendar_date date NOT NULL,
  day_kind text NOT NULL CHECK (
    day_kind IN ('instructional','exam','holiday','weekend','closure')),
  title text,
  reason text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (academic_year_id,school_id)
    REFERENCES public.academic_years(id,school_id) ON DELETE RESTRICT,
  UNIQUE (campus_id,calendar_date),
  UNIQUE (id,school_id,campus_id,academic_year_id,calendar_date)
);

-- 2. School Owner-approved settings; one ACTIVE policy per campus/year.
CREATE TABLE public.attendance_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  version_no integer NOT NULL DEFAULT 1 CHECK (version_no > 0),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','active','retired')),
  first_period_required boolean NOT NULL DEFAULT true,
  after_break_enabled boolean NOT NULL DEFAULT false,
  late_after time WITHOUT TIME ZONE,
  first_period_submit_deadline time WITHOUT TIME ZONE,
  after_break_submit_deadline time WITHOUT TIME ZONE,
  allow_backdated_request boolean NOT NULL DEFAULT false,
  effective_from date NOT NULL,
  effective_to date,
  approved_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (academic_year_id,school_id)
    REFERENCES public.academic_years(id,school_id) ON DELETE RESTRICT,
  CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CHECK (NOT after_break_enabled OR after_break_submit_deadline IS NOT NULL),
  CHECK (status <> 'active' OR approved_by IS NOT NULL),
  UNIQUE (campus_id,academic_year_id,version_no)
);
CREATE UNIQUE INDEX one_active_attendance_policy_per_campus_year
  ON public.attendance_policies(campus_id,academic_year_id)
  WHERE status='active';

-- 3. Teacher duty for one class/section/date/session, scheduled by trusted
-- staff. ONE primary and at most ONE authorized substitute may be assigned.
-- DB01 currently has only 'attendance_staff' user roles; full 'teacher' role
-- authorization is a future reviewed DB01 expansion, not bypassed here.
CREATE TABLE public.attendance_duties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  section_id uuid,
  attendance_date date NOT NULL,
  session_kind text NOT NULL
    CHECK (session_kind IN ('first_period','after_break')),
  duty_kind text NOT NULL
    CHECK (duty_kind IN ('primary','substitute')),
  assigned_user_id uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  substitution_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (academic_year_id,school_id)
    REFERENCES public.academic_years(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (class_id,campus_id,academic_year_id)
    REFERENCES public.classes(id,campus_id,academic_year_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (section_id,class_id)
    REFERENCES public.sections(id,class_id) ON DELETE RESTRICT,
  CHECK (
    (duty_kind='primary' AND approved_by IS NULL
      AND substitution_reason IS NULL)
    OR
    (duty_kind='substitute' AND approved_by IS NOT NULL
      AND length(btrim(coalesce(substitution_reason,''))) >= 4)
  ),
  UNIQUE NULLS NOT DISTINCT
    (campus_id,academic_year_id,class_id,section_id,
      attendance_date,session_kind,duty_kind),
  UNIQUE (id,school_id,campus_id,academic_year_id,class_id,
    attendance_date,session_kind)
);

-- 4. Distinct register for first period and optional after-break. Section
-- scope checked by a trigger against immutable selected duty. School-local
-- time zone comes from schools.timezone_name in the future trusted endpoint.
CREATE TABLE public.attendance_registers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  section_id uuid,
  calendar_day_id uuid NOT NULL,
  attendance_date date NOT NULL,
  session_kind text NOT NULL
    CHECK (session_kind IN ('first_period','after_break')),
  duty_id uuid NOT NULL,
  taken_by uuid NOT NULL REFERENCES auth.users(id),
  source_kind text NOT NULL DEFAULT 'online'
    CHECK (source_kind IN ('online','verified_desktop_sync')),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','submitted','locked')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  submitted_at timestamptz,
  locked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (campus_id,school_id)
    REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
  FOREIGN KEY (class_id,campus_id,academic_year_id)
    REFERENCES public.classes(id,campus_id,academic_year_id)
    ON DELETE RESTRICT,
  FOREIGN KEY (section_id,class_id)
    REFERENCES public.sections(id,class_id) ON DELETE RESTRICT,
  FOREIGN KEY (calendar_day_id,school_id,campus_id,
               academic_year_id,attendance_date)
    REFERENCES public.school_calendar_days
      (id,school_id,campus_id,academic_year_id,calendar_date)
    ON DELETE RESTRICT,
  FOREIGN KEY (duty_id,school_id,campus_id,academic_year_id,
               class_id,attendance_date,session_kind)
    REFERENCES public.attendance_duties
      (id,school_id,campus_id,academic_year_id,
       class_id,attendance_date,session_kind)
    ON DELETE RESTRICT,
  CHECK (
    (status='draft' AND submitted_at IS NULL AND locked_at IS NULL)
    OR (status='submitted' AND submitted_at IS NOT NULL AND locked_at IS NULL)
    OR (status='locked' AND submitted_at IS NOT NULL AND locked_at IS NOT NULL)
  ),
  UNIQUE NULLS NOT DISTINCT
    (campus_id,academic_year_id,class_id,section_id,
     attendance_date,session_kind),
  UNIQUE (id,school_id,campus_id,academic_year_id,
          class_id,attendance_date,session_kind),
  UNIQUE (id,school_id,campus_id)
);
CREATE INDEX attendance_registers_day_idx
  ON public.attendance_registers(campus_id,attendance_date,session_kind);

-- 5. Immutable register transition audit (created/submitted/locked/reopened).
-- Actual status changes and this event must commit in ONE trusted transaction.
CREATE TABLE public.attendance_register_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  register_id uuid NOT NULL,
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  event_kind text NOT NULL
    CHECK (event_kind IN ('created','submitted','locked','reopened')),
  previous_status text,
  new_status text NOT NULL
    CHECK (new_status IN ('draft','submitted','locked')),
  reason text,
  actor_id uuid NOT NULL REFERENCES auth.users(id),
  event_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (register_id,school_id,campus_id)
    REFERENCES public.attendance_registers(id,school_id,campus_id)
    ON DELETE RESTRICT,
  CHECK (previous_status IS NULL
     OR previous_status IN ('draft','submitted','locked')),
  CHECK (previous_status IS DISTINCT FROM new_status),
  CHECK (event_kind<>'reopened' OR length(btrim(coalesce(reason,'')))>=4),
  UNIQUE (school_id,operation_id)
);
CREATE INDEX attendance_register_events_register_idx
  ON public.attendance_register_events(register_id,event_at);

-- 6. Initial student mark is append-only. A changed mark requires an
-- approved correction decision, not UPDATE to the original evidence.
-- DB03 created enrollment scope key used by this FK; no second ALTER needed.
CREATE TABLE public.student_attendance_marks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  attendance_date date NOT NULL,
  session_kind text NOT NULL
    CHECK (session_kind IN ('first_period','after_break')),
  register_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  student_id uuid NOT NULL,
  mark_status text NOT NULL
    CHECK (mark_status IN ('present','absent','late','excused','leave','sick')),
  reason text,
  marked_by uuid NOT NULL REFERENCES auth.users(id),
  marked_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (register_id,school_id,campus_id,academic_year_id,
               class_id,attendance_date,session_kind)
    REFERENCES public.attendance_registers(
      id,school_id,campus_id,academic_year_id,class_id,
      attendance_date,session_kind) ON DELETE RESTRICT,
  FOREIGN KEY (enrollment_id,student_id,school_id,campus_id,
               academic_year_id,class_id)
    REFERENCES public.student_enrollments(
      id,student_id,school_id,campus_id,academic_year_id,class_id)
    ON DELETE RESTRICT,
  CHECK (mark_status NOT IN ('excused','leave','sick')
      OR length(btrim(coalesce(reason,'')))>=4),
  UNIQUE (register_id,enrollment_id),
  UNIQUE (id,school_id,campus_id)
);
CREATE INDEX student_attendance_by_student_date_idx
  ON public.student_attendance_marks(school_id,student_id,attendance_date);

-- 7. Backdated or mistaken mark correction is a REQUEST, not a direct edit.
CREATE TABLE public.attendance_correction_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  mark_id uuid NOT NULL,
  proposed_status text NOT NULL
    CHECK (proposed_status IN
      ('present','absent','late','excused','leave','sick')),
  expected_effective_revision bigint NOT NULL
    CHECK (expected_effective_revision >= 1),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  operation_id uuid NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (mark_id,school_id,campus_id)
    REFERENCES public.student_attendance_marks(id,school_id,campus_id)
    ON DELETE RESTRICT,
  UNIQUE (school_id,operation_id),
  UNIQUE (id,mark_id,school_id,campus_id),
  UNIQUE (id,mark_id,school_id,campus_id,proposed_status)
);

-- 8. One immutable decision per request. Accepted new_status MUST equal
-- proposed_status through the composite FK; SQL posting checks optimistic
-- current effective revision and authorized decision-maker in a transaction.
CREATE TABLE public.attendance_correction_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  request_id uuid NOT NULL,
  mark_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('approved','rejected')),
  approved_status text,
  effective_revision_after bigint,
  decision_reason text,
  decided_by uuid NOT NULL REFERENCES auth.users(id),
  operation_id uuid NOT NULL,
  decided_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (request_id,mark_id,school_id,campus_id)
    REFERENCES public.attendance_correction_requests
      (id,mark_id,school_id,campus_id) ON DELETE RESTRICT,
  FOREIGN KEY (request_id,mark_id,school_id,campus_id,approved_status)
    REFERENCES public.attendance_correction_requests
      (id,mark_id,school_id,campus_id,proposed_status) ON DELETE RESTRICT,
  CHECK (
    (decision='approved' AND approved_status IS NOT NULL
       AND effective_revision_after >= 2)
    OR
    (decision='rejected' AND approved_status IS NULL
       AND effective_revision_after IS NULL
       AND length(btrim(coalesce(decision_reason,''))) >= 4)
  ),
  UNIQUE (request_id),
  UNIQUE (school_id,operation_id),
  UNIQUE (mark_id,effective_revision_after)
);

-- 9. Staff daily attendance is linked to a real school account now;
-- DB05 employees/assignments will add authoritative employment and payroll
-- mapping later. Staff can work on non-instructional calendar days.
CREATE TABLE public.staff_attendance_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  calendar_day_id uuid NOT NULL,
  attendance_date date NOT NULL,
  staff_user_id uuid NOT NULL REFERENCES public.user_profiles(user_id),
  status text NOT NULL CHECK (
    status IN ('present','absent','late','leave','sick','offsite','holiday')),
  first_check_in timestamptz,
  last_check_out timestamptz,
  reason text,
  recorded_by uuid NOT NULL REFERENCES auth.users(id),
  operation_id uuid NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (calendar_day_id,school_id,campus_id,
               academic_year_id,attendance_date)
    REFERENCES public.school_calendar_days
      (id,school_id,campus_id,academic_year_id,calendar_date)
    ON DELETE RESTRICT,
  CHECK (first_check_in IS NULL OR last_check_out IS NULL
     OR last_check_out >= first_check_in),
  CHECK (status NOT IN ('leave','sick','offsite')
     OR length(btrim(coalesce(reason,'')))>=4),
  UNIQUE (campus_id,staff_user_id,attendance_date),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,school_id,campus_id)
);
CREATE INDEX staff_attendance_date_idx
  ON public.staff_attendance_records(campus_id,attendance_date);

-- 10. Staff correction request, also append-only.
CREATE TABLE public.staff_attendance_correction_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  record_id uuid NOT NULL,
  proposed_status text NOT NULL CHECK (
    proposed_status IN
      ('present','absent','late','leave','sick','offsite','holiday')),
  proposed_check_in timestamptz,
  proposed_check_out timestamptz,
  expected_effective_revision bigint NOT NULL
    CHECK (expected_effective_revision>=1),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 1000),
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  operation_id uuid NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (record_id,school_id,campus_id)
    REFERENCES public.staff_attendance_records(id,school_id,campus_id)
    ON DELETE RESTRICT,
  CHECK (proposed_check_in IS NULL OR proposed_check_out IS NULL
    OR proposed_check_out >= proposed_check_in),
  UNIQUE (school_id,operation_id),
  UNIQUE (id,record_id,school_id,campus_id,proposed_status),
  UNIQUE (id,record_id,school_id,campus_id)
);

-- 11. Approved staff corrections are immutable, remain visible to DB05
-- payroll as separate facts, and cannot silently change prior pay periods.
CREATE TABLE public.staff_attendance_correction_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL,
  campus_id uuid NOT NULL,
  request_id uuid NOT NULL,
  record_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('approved','rejected')),
  approved_status text,
  effective_revision_after bigint,
  decided_by uuid NOT NULL REFERENCES auth.users(id),
  operation_id uuid NOT NULL,
  decision_reason text,
  decided_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (request_id,record_id,school_id,campus_id)
    REFERENCES public.staff_attendance_correction_requests
      (id,record_id,school_id,campus_id) ON DELETE RESTRICT,
  FOREIGN KEY (request_id,record_id,school_id,campus_id,approved_status)
    REFERENCES public.staff_attendance_correction_requests
      (id,record_id,school_id,campus_id,proposed_status) ON DELETE RESTRICT,
  CHECK (
    (decision='approved' AND approved_status IS NOT NULL
      AND effective_revision_after >= 2)
    OR
    (decision='rejected' AND approved_status IS NULL
      AND effective_revision_after IS NULL
      AND length(btrim(coalesce(decision_reason,''))) >= 4)
  ),
  UNIQUE (request_id),
  UNIQUE (school_id,operation_id),
  UNIQUE (record_id,effective_revision_after)
);

-- Calendar must be inside the actual academic year. This trigger does not
-- authorize users, it only checks server-side scope/date integrity.
CREATE FUNCTION app_private.db04_validate_calendar_day()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE v_start date; v_end date;
BEGIN
  SELECT ay.starts_on,ay.ends_on INTO v_start,v_end
    FROM public.academic_years ay
   WHERE ay.id=NEW.academic_year_id AND ay.school_id=NEW.school_id;
  IF v_start IS NULL OR NEW.calendar_date < v_start
     OR NEW.calendar_date > v_end THEN
    RAISE EXCEPTION 'Attendance day outside academic year'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER db04_calendar_day_bounds
  BEFORE INSERT OR UPDATE ON public.school_calendar_days
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_validate_calendar_day();

-- Server validates which teacher is taking the date/session and whether
-- after-break collection is enabled. Duty + calendar/section may not be
-- silently retargeted after the register has been created.
CREATE FUNCTION app_private.db04_validate_register()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE
  v_section uuid;
  v_teacher uuid;
  v_day_kind text;
  v_after_break boolean;
BEGIN
  IF TG_OP='UPDATE' THEN
    IF OLD.school_id IS DISTINCT FROM NEW.school_id
      OR OLD.campus_id IS DISTINCT FROM NEW.campus_id
      OR OLD.academic_year_id IS DISTINCT FROM NEW.academic_year_id
      OR OLD.class_id IS DISTINCT FROM NEW.class_id
      OR OLD.section_id IS DISTINCT FROM NEW.section_id
      OR OLD.attendance_date IS DISTINCT FROM NEW.attendance_date
      OR OLD.session_kind IS DISTINCT FROM NEW.session_kind
      OR OLD.calendar_day_id IS DISTINCT FROM NEW.calendar_day_id
      OR OLD.duty_id IS DISTINCT FROM NEW.duty_id
      OR OLD.taken_by IS DISTINCT FROM NEW.taken_by
      OR OLD.source_kind IS DISTINCT FROM NEW.source_kind THEN
      RAISE EXCEPTION 'Attendance register identity is immutable'
        USING ERRCODE='23514';
    END IF;
    IF OLD.status='locked' OR NEW.revision<>OLD.revision+1 THEN
      RAISE EXCEPTION 'Locked or unversioned attendance register edit'
        USING ERRCODE='23514';
    END IF;
    IF (OLD.status='draft' AND NEW.status NOT IN ('draft','submitted'))
      OR (OLD.status='submitted' AND NEW.status NOT IN ('submitted','locked'))
    THEN
      RAISE EXCEPTION 'Invalid attendance lifecycle transition'
        USING ERRCODE='23514';
    END IF;
  END IF;

  SELECT d.section_id,d.assigned_user_id INTO v_section,v_teacher
    FROM public.attendance_duties d
    WHERE d.id=NEW.duty_id;
  IF NOT FOUND OR v_section IS DISTINCT FROM NEW.section_id
     OR v_teacher IS DISTINCT FROM NEW.taken_by THEN
    RAISE EXCEPTION 'Attendance teacher duty/section mismatch'
      USING ERRCODE='23514';
  END IF;

  SELECT c.day_kind INTO v_day_kind FROM public.school_calendar_days c
    WHERE c.id=NEW.calendar_day_id;
  IF v_day_kind NOT IN ('instructional','exam') THEN
    RAISE EXCEPTION 'Cannot submit student register on non-school day'
      USING ERRCODE='23514';
  END IF;

  SELECT p.after_break_enabled INTO v_after_break
    FROM public.attendance_policies p
    WHERE p.school_id=NEW.school_id
      AND p.campus_id=NEW.campus_id
      AND p.academic_year_id=NEW.academic_year_id
      AND p.status='active'
      AND NEW.attendance_date >= p.effective_from
      AND (p.effective_to IS NULL OR NEW.attendance_date<=p.effective_to);
  IF NOT FOUND OR (NEW.session_kind='after_break'
                     AND NOT v_after_break) THEN
    RAISE EXCEPTION 'Campus attendance policy not active for session'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER db04_register_scope_guard
  BEFORE INSERT OR UPDATE ON public.attendance_registers
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_validate_register();

-- Prevent a mark for a different section or before admission/after leaving.
-- Attendance marks are submitted atomically by authorized future RPCs.
CREATE FUNCTION app_private.db04_validate_student_mark()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE
  v_register_section uuid;
  v_enrollment_section uuid;
  v_actor uuid;
  v_state text;
  v_admitted date;
  v_ended date;
BEGIN
  SELECT r.section_id,r.taken_by,r.status,e.section_id,e.admitted_on,e.ended_on
    INTO v_register_section,v_actor,v_state,v_enrollment_section,
      v_admitted,v_ended
    FROM public.attendance_registers r
    JOIN public.student_enrollments e ON e.id=NEW.enrollment_id
   WHERE r.id=NEW.register_id;
  IF NOT FOUND
     OR v_register_section IS DISTINCT FROM v_enrollment_section
     OR NEW.marked_by IS DISTINCT FROM v_actor
     OR v_state <> 'draft'
     OR NEW.attendance_date < v_admitted
     OR (v_ended IS NOT NULL AND NEW.attendance_date > v_ended) THEN
    RAISE EXCEPTION 'Mark not valid for this register, teacher or enrollment'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER db04_student_mark_scope_guard
  BEFORE INSERT ON public.student_attendance_marks
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_validate_student_mark();

-- Every original mark, correction request/decision and staff daily record
-- is append-only. Rejected or approved corrections are NEW facts.
CREATE FUNCTION app_private.db04_reject_evidence_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
BEGIN
  RAISE EXCEPTION 'Attendance evidence is append-only'
    USING ERRCODE='23514';
END;
$$;
CREATE TRIGGER db04_duties_no_mutate
  BEFORE UPDATE OR DELETE ON public.attendance_duties
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_register_events_no_mutate
  BEFORE UPDATE OR DELETE ON public.attendance_register_events
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_student_marks_no_mutate
  BEFORE UPDATE OR DELETE ON public.student_attendance_marks
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_student_correction_requests_no_mutate
  BEFORE UPDATE OR DELETE ON public.attendance_correction_requests
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_student_correction_decisions_no_mutate
  BEFORE UPDATE OR DELETE ON public.attendance_correction_decisions
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_staff_records_no_mutate
  BEFORE UPDATE OR DELETE ON public.staff_attendance_records
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_staff_correction_requests_no_mutate
  BEFORE UPDATE OR DELETE ON public.staff_attendance_correction_requests
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_staff_correction_decisions_no_mutate
  BEFORE UPDATE OR DELETE ON public.staff_attendance_correction_decisions
  FOR EACH ROW EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();

-- Bulk TRUNCATE bypasses row triggers: block for all evidence tables.
CREATE TRIGGER db04_duties_no_truncate
  BEFORE TRUNCATE ON public.attendance_duties
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_register_events_no_truncate
  BEFORE TRUNCATE ON public.attendance_register_events
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_student_marks_no_truncate
  BEFORE TRUNCATE ON public.student_attendance_marks
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_student_correction_requests_no_truncate
  BEFORE TRUNCATE ON public.attendance_correction_requests
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_student_correction_decisions_no_truncate
  BEFORE TRUNCATE ON public.attendance_correction_decisions
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_staff_records_no_truncate
  BEFORE TRUNCATE ON public.staff_attendance_records
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_staff_correction_requests_no_truncate
  BEFORE TRUNCATE ON public.staff_attendance_correction_requests
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();
CREATE TRIGGER db04_staff_correction_decisions_no_truncate
  BEFORE TRUNCATE ON public.staff_attendance_correction_decisions
  FOR EACH STATEMENT EXECUTE FUNCTION app_private.db04_reject_evidence_mutation();

-- RLS deny-by-default: public API cannot read/edit student or staff marks.
-- Future classroom/Owner reports must use explicitly scoped, reviewed
-- server operations and current user_roles, NEVER a Flutter campus filter.
ALTER TABLE public.school_calendar_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_duties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_registers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_register_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_attendance_marks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_correction_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_correction_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_attendance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_attendance_correction_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_attendance_correction_decisions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON
  public.school_calendar_days,
  public.attendance_policies,
  public.attendance_duties,
  public.attendance_registers,
  public.attendance_register_events,
  public.student_attendance_marks,
  public.attendance_correction_requests,
  public.attendance_correction_decisions,
  public.staff_attendance_records,
  public.staff_attendance_correction_requests,
  public.staff_attendance_correction_decisions
FROM PUBLIC,anon,authenticated;

REVOKE ALL ON FUNCTION app_private.db04_validate_calendar_day()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db04_validate_register()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db04_validate_student_mark()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db04_reject_evidence_mutation()
  FROM PUBLIC,anon,authenticated;

-- No trusted attendance submit/correct/lock RPC is authored or deployed.
-- No role expansion, device sync, DB05 employee/payroll link or
-- dashboard attendance read projection is exposed by this DDL.
COMMIT;
