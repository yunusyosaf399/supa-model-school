-- DB08 APPROVALS, PERMISSIONS, AUDIT AND NOTIFICATIONS — DESIGN ONLY
-- Depends on DB01–DB07 sources. NOT DEPLOYED. No Flutter code.

ALTER TABLE public.user_roles DROP CONSTRAINT user_roles_role_check;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_role_check
 CHECK (role IN ('owner','super_admin','principal','vice_principal','admin','accountant','hr','teacher','coordinator','librarian','transport_manager','driver','nurse','store_keeper','security_guard','parent','attendance_staff'));

-- Same-school/campus source keys for approval workflow FKs.
ALTER TABLE public.expense_requests ADD CONSTRAINT db08_expense_req_key
 UNIQUE (id,school_id,campus_id);
ALTER TABLE public.employee_leave_requests ADD CONSTRAINT db08_leave_req_key
 UNIQUE (id,school_id,campus_id);
ALTER TABLE public.attendance_correction_requests ADD CONSTRAINT db08_attendance_req_key
 UNIQUE (id,school_id,campus_id);
ALTER TABLE public.inventory_transfers ADD CONSTRAINT db08_transfer_req_key
 UNIQUE (id,school_id,from_campus_id);
ALTER TABLE public.inventory_counts ADD CONSTRAINT db08_count_req_key
 UNIQUE (id,school_id,campus_id);

CREATE TABLE public.db08_roles (
 role_code text PRIMARY KEY CHECK (role_code IN ('owner','super_admin','principal','vice_principal','admin','accountant','hr','teacher','coordinator','librarian','transport_manager','driver','nurse','store_keeper','security_guard','parent','attendance_staff')),
 label text NOT NULL CHECK (length(btrim(label)) BETWEEN 2 AND 100),
 scope text NOT NULL CHECK (scope IN ('school','campus'))
);
CREATE TABLE public.db08_permissions (
 code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_.]{3,99}$'),
 domain text NOT NULL CHECK (domain IN
 ('school','admissions','fees','attendance','hr','payroll','finance',
  'inventory','canteen','uniform','transport','approval','backup','sync','reporting')),
 description text NOT NULL CHECK (length(btrim(description)) BETWEEN 4 AND 250)
);
CREATE TABLE public.db08_role_grants (
 school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
 role_code text NOT NULL REFERENCES public.db08_roles(role_code),
 permission_code text NOT NULL REFERENCES public.db08_permissions(code),
 allowed boolean NOT NULL,
 granted_by uuid NOT NULL REFERENCES auth.users(id),
 revision bigint NOT NULL DEFAULT 1 CHECK (revision>0),
 PRIMARY KEY (school_id,role_code,permission_code)
);
CREATE TABLE public.db08_user_overrides (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
 campus_id uuid,
 user_id uuid NOT NULL REFERENCES public.user_profiles(user_id),
 permission_code text NOT NULL REFERENCES public.db08_permissions(code),
 effect text NOT NULL CHECK (effect IN ('allow','deny')),
 valid_from timestamptz NOT NULL,
 valid_until timestamptz NOT NULL,
 approved_by uuid NOT NULL REFERENCES auth.users(id),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
 FOREIGN KEY (campus_id,school_id) REFERENCES public.campuses(id,school_id),
 CHECK (valid_until>valid_from),
 UNIQUE NULLS NOT DISTINCT(school_id,campus_id,user_id,permission_code,valid_from)
);
CREATE TABLE public.db08_role_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 subject_user_id uuid NOT NULL REFERENCES public.user_profiles(user_id),
 role_code text NOT NULL REFERENCES public.db08_roles(role_code),
 change_kind text NOT NULL CHECK(change_kind IN ('assign','revoke','suspend','reactivate')),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 operation_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 4 AND 500),
 happened_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (campus_id,school_id) REFERENCES public.campuses(id,school_id),
 UNIQUE (school_id,operation_id)
);
CREATE TABLE public.db08_approval_policies (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 action_code text NOT NULL CHECK(action_code IN
  ('admission','campus_transfer','expense','payroll','salary_advance',
   'leave','attendance_correction','fee_correction','stock_transfer',
   'stock_adjustment','cash_close','retail_refund','other')),
 version_no integer NOT NULL CHECK(version_no>0),
 min_amount_minor bigint CHECK(min_amount_minor IS NULL OR min_amount_minor>=0),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','active','retired')),
 approved_by uuid REFERENCES auth.users(id),
 activated_at timestamptz,
 FOREIGN KEY (campus_id,school_id) REFERENCES public.campuses(id,school_id),
 CHECK(status<>'active' OR (approved_by IS NOT NULL AND activated_at IS NOT NULL)),
 UNIQUE NULLS NOT DISTINCT(school_id,campus_id,action_code,version_no),
 UNIQUE(id,school_id)
);
CREATE UNIQUE INDEX db08_one_active_policy ON public.db08_approval_policies(
 school_id,COALESCE(campus_id,'00000000-0000-0000-0000-000000000000'::uuid),action_code)
 WHERE status='active';
CREATE TABLE public.db08_approval_steps (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 policy_id uuid NOT NULL,
 step_no integer NOT NULL CHECK(step_no>0),
 approver_role text NOT NULL REFERENCES public.db08_roles(role_code),
 no_self_approval boolean NOT NULL DEFAULT true,
 deadline_hours integer CHECK(deadline_hours BETWEEN 1 AND 720),
 FOREIGN KEY(policy_id,school_id)
 REFERENCES public.db08_approval_policies(id,school_id) ON DELETE RESTRICT,
 UNIQUE(policy_id,step_no),
 UNIQUE(policy_id,school_id,step_no)
);
-- Generic subject registry is NOT proof of underlying source validation:
-- trusted domain posting must verify entity school/campus and status.
CREATE TABLE public.db08_workflow_subjects (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 source_kind text NOT NULL CHECK(source_kind IN
 ('admission','campus_transfer','payroll','fee','cash_close','retail_refund','other')),
 source_id uuid NOT NULL,
 registered_by uuid NOT NULL REFERENCES auth.users(id),
 operation_id uuid NOT NULL,
 FOREIGN KEY (campus_id,school_id) REFERENCES public.campuses(id,school_id),
 UNIQUE(school_id,source_kind,source_id),
 UNIQUE(school_id,operation_id),
 UNIQUE(id,school_id)
);
CREATE TABLE public.db08_approval_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 policy_id uuid NOT NULL,
 source_kind text NOT NULL CHECK(source_kind IN
 ('expense','leave','attendance','stock_transfer','stock_count','workflow')),
 requester_id uuid NOT NULL REFERENCES auth.users(id),
 amount_minor bigint CHECK(amount_minor IS NULL OR amount_minor>=0),
 status text NOT NULL DEFAULT 'pending'
 CHECK(status IN ('pending','approved','rejected','returned','cancelled')),
 operation_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 4 AND 1000),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 FOREIGN KEY(policy_id,school_id) REFERENCES public.db08_approval_policies(id,school_id),
 UNIQUE(school_id,operation_id),
 UNIQUE(id,school_id,source_kind),
 UNIQUE(id,school_id,policy_id),
 UNIQUE(id,school_id)
);
CREATE TABLE public.db08_approval_sources (
 request_id uuid PRIMARY KEY,
 school_id uuid NOT NULL,
 campus_id uuid,
 source_kind text NOT NULL,
 expense_request_id uuid UNIQUE,
 leave_request_id uuid UNIQUE,
 attendance_request_id uuid UNIQUE,
 transfer_request_id uuid UNIQUE,
 stock_count_id uuid UNIQUE,
 workflow_subject_id uuid UNIQUE,
 FOREIGN KEY(request_id,school_id,source_kind)
 REFERENCES public.db08_approval_requests(id,school_id,source_kind),
 FOREIGN KEY(expense_request_id,school_id,campus_id)
 REFERENCES public.expense_requests(id,school_id,campus_id),
 FOREIGN KEY(leave_request_id,school_id,campus_id)
 REFERENCES public.employee_leave_requests(id,school_id,campus_id),
 FOREIGN KEY(attendance_request_id,school_id,campus_id)
 REFERENCES public.attendance_correction_requests(id,school_id,campus_id),
 FOREIGN KEY(transfer_request_id,school_id,campus_id)
 REFERENCES public.inventory_transfers(id,school_id,from_campus_id),
 FOREIGN KEY(stock_count_id,school_id,campus_id)
 REFERENCES public.inventory_counts(id,school_id,campus_id),
 FOREIGN KEY(workflow_subject_id,school_id)
 REFERENCES public.db08_workflow_subjects(id,school_id),
 CHECK(num_nonnulls(expense_request_id,leave_request_id,attendance_request_id,
 transfer_request_id,stock_count_id,workflow_subject_id)=1),
 CHECK(source_kind='workflow' OR campus_id IS NOT NULL),
 CHECK((source_kind='expense' AND expense_request_id IS NOT NULL) OR
  (source_kind='leave' AND leave_request_id IS NOT NULL) OR
  (source_kind='attendance' AND attendance_request_id IS NOT NULL) OR
  (source_kind='stock_transfer' AND transfer_request_id IS NOT NULL) OR
  (source_kind='stock_count' AND stock_count_id IS NOT NULL) OR
  (source_kind='workflow' AND workflow_subject_id IS NOT NULL))
);
CREATE TABLE public.db08_approval_delegations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 delegator_user_id uuid NOT NULL REFERENCES auth.users(id),
 delegate_user_id uuid NOT NULL REFERENCES auth.users(id),
 permission_code text NOT NULL REFERENCES public.db08_permissions(code),
 starts_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL,
 revoked_at timestamptz,
 approved_by uuid NOT NULL REFERENCES auth.users(id),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 4 AND 500),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 CHECK(delegator_user_id<>delegate_user_id AND expires_at>starts_at),
 UNIQUE(id,school_id)
);
CREATE TABLE public.db08_approval_decisions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 request_id uuid NOT NULL,
 policy_id uuid NOT NULL,
 step_no integer NOT NULL,
 decision text NOT NULL CHECK(decision IN ('approved','rejected','returned')),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 delegation_id uuid,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 4 AND 1000),
 operation_id uuid NOT NULL,
 decided_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(request_id,school_id,policy_id)
 REFERENCES public.db08_approval_requests(id,school_id,policy_id),
 FOREIGN KEY(policy_id,school_id,step_no)
 REFERENCES public.db08_approval_steps(policy_id,school_id,step_no),
 FOREIGN KEY(delegation_id,school_id)
 REFERENCES public.db08_approval_delegations(id,school_id),
 UNIQUE(request_id,step_no),
 UNIQUE(school_id,operation_id)
);
CREATE TABLE public.db08_audit_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 actor_id uuid REFERENCES auth.users(id),
 operation_id uuid,
 event_code text NOT NULL CHECK(event_code ~ '^[a-z][a-z0-9_.]{3,99}$'),
 target_entity text NOT NULL CHECK(length(btrim(target_entity)) BETWEEN 3 AND 100),
 target_id uuid,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(metadata)='object'),
 happened_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id)
);
CREATE INDEX db08_audit_by_school_time ON public.db08_audit_events(school_id,happened_at DESC);
CREATE TABLE public.db08_document_templates (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 kind text NOT NULL CHECK(kind IN ('fee_slip','receipt','payslip',
 'admission_letter','notice','student_card','transport_pass','other')),
 locale text NOT NULL DEFAULT 'en' CHECK(locale IN ('en','ur')),
 version_no integer NOT NULL CHECK(version_no>0),
 template_json jsonb NOT NULL CHECK(jsonb_typeof(template_json)='object'),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','active','retired')),
 approved_by uuid REFERENCES auth.users(id),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 CHECK(status<>'active' OR approved_by IS NOT NULL),
 UNIQUE NULLS NOT DISTINCT(school_id,campus_id,kind,locale,version_no)
);
CREATE TABLE public.db08_notification_messages (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 recipient_id uuid NOT NULL REFERENCES public.user_profiles(user_id),
 event_code text NOT NULL,
 subject text NOT NULL CHECK(length(btrim(subject)) BETWEEN 2 AND 180),
 body_text text NOT NULL CHECK(length(btrim(body_text)) BETWEEN 2 AND 4000),
 operation_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 UNIQUE(school_id,operation_id),
 UNIQUE(id,school_id,recipient_id)
);
CREATE TABLE public.db08_notification_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 recipient_id uuid NOT NULL,
 message_id uuid NOT NULL,
 event_kind text NOT NULL CHECK(event_kind IN
 ('queued','sent','failed','read','dismissed')),
 channel text NOT NULL CHECK(channel IN ('in_app','email','sms','push')),
 occurred_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(message_id,school_id,recipient_id)
 REFERENCES public.db08_notification_messages(id,school_id,recipient_id)
);
CREATE TABLE public.db08_user_shortcuts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 campus_id uuid,
 user_id uuid NOT NULL REFERENCES public.user_profiles(user_id),
 shortcut_code text NOT NULL CHECK(length(btrim(shortcut_code)) BETWEEN 3 AND 100),
 display_order integer NOT NULL CHECK(display_order BETWEEN 0 AND 200),
 FOREIGN KEY(campus_id,school_id) REFERENCES public.campuses(id,school_id),
 UNIQUE NULLS NOT DISTINCT(school_id,campus_id,user_id,shortcut_code)
);
CREATE TABLE public.db08_operation_receipts (
 school_id uuid NOT NULL REFERENCES public.schools(id),
 operation_id uuid NOT NULL,
 action_code text NOT NULL,
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 request_sha256 bytea NOT NULL CHECK(octet_length(request_sha256)=32),
 result_json jsonb NOT NULL CHECK(jsonb_typeof(result_json)='object'),
 processed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(school_id,operation_id)
);
CREATE FUNCTION app_private.db08_no_self_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $db08$
DECLARE requester uuid;
BEGIN
 SELECT requester_id INTO requester FROM public.db08_approval_requests
 WHERE id=NEW.request_id AND school_id=NEW.school_id;
 IF requester IS NULL OR requester=NEW.actor_id THEN
  RAISE EXCEPTION 'Self approval prohibited' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$db08$;
CREATE TRIGGER db08_decision_self_guard BEFORE INSERT ON public.db08_approval_decisions
 FOR EACH ROW EXECUTE FUNCTION app_private.db08_no_self_approval();
CREATE FUNCTION app_private.db08_request_revision_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $db08$
BEGIN
 IF OLD.status NOT IN ('pending','returned')
 OR NEW.id IS DISTINCT FROM OLD.id OR NEW.school_id IS DISTINCT FROM OLD.school_id
 OR NEW.campus_id IS DISTINCT FROM OLD.campus_id
 OR NEW.policy_id IS DISTINCT FROM OLD.policy_id
 OR NEW.source_kind IS DISTINCT FROM OLD.source_kind
 OR NEW.requester_id IS DISTINCT FROM OLD.requester_id
 OR NEW.operation_id IS DISTINCT FROM OLD.operation_id
 OR NEW.revision<>OLD.revision+1 THEN
  RAISE EXCEPTION 'Approval request identity or revision invalid' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$db08$;
CREATE TRIGGER db08_request_revision_guard BEFORE UPDATE
 ON public.db08_approval_requests FOR EACH ROW
 EXECUTE FUNCTION app_private.db08_request_revision_guard();
CREATE FUNCTION app_private.db08_reject_audit_edit()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $db08$
BEGIN
 RAISE EXCEPTION 'Immutable DB08 evidence' USING ERRCODE='23514';
END;
$db08$;
CREATE TRIGGER db08_role_audit_no_edit BEFORE UPDATE OR DELETE ON public.db08_role_audit
 FOR EACH ROW EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_role_audit_no_truncate BEFORE TRUNCATE ON public.db08_role_audit
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_approval_sources_no_edit BEFORE UPDATE OR DELETE ON public.db08_approval_sources
 FOR EACH ROW EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_approval_sources_no_truncate BEFORE TRUNCATE ON public.db08_approval_sources
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_approval_decisions_no_edit BEFORE UPDATE OR DELETE ON public.db08_approval_decisions
 FOR EACH ROW EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_approval_decisions_no_truncate BEFORE TRUNCATE ON public.db08_approval_decisions
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_audit_events_no_edit BEFORE UPDATE OR DELETE ON public.db08_audit_events
 FOR EACH ROW EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_audit_events_no_truncate BEFORE TRUNCATE ON public.db08_audit_events
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_notification_events_no_edit BEFORE UPDATE OR DELETE ON public.db08_notification_events
 FOR EACH ROW EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_notification_events_no_truncate BEFORE TRUNCATE ON public.db08_notification_events
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_operation_receipts_no_edit BEFORE UPDATE OR DELETE ON public.db08_operation_receipts
 FOR EACH ROW EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_operation_receipts_no_truncate BEFORE TRUNCATE ON public.db08_operation_receipts
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_workflow_subjects_no_edit BEFORE UPDATE OR DELETE ON public.db08_workflow_subjects
 FOR EACH ROW EXECUTE FUNCTION app_private.db08_reject_audit_edit();
CREATE TRIGGER db08_workflow_subjects_no_truncate BEFORE TRUNCATE ON public.db08_workflow_subjects
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db08_reject_audit_edit();

ALTER TABLE public.db08_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_role_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_user_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_role_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_approval_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_approval_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_workflow_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_approval_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_approval_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_approval_delegations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_approval_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_document_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_notification_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_notification_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_user_shortcuts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db08_operation_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.db08_roles,
 public.db08_permissions,
 public.db08_role_grants,
 public.db08_user_overrides,
 public.db08_role_audit,
 public.db08_approval_policies,
 public.db08_approval_steps,
 public.db08_workflow_subjects,
 public.db08_approval_requests,
 public.db08_approval_sources,
 public.db08_approval_delegations,
 public.db08_approval_decisions,
 public.db08_audit_events,
 public.db08_document_templates,
 public.db08_notification_messages,
 public.db08_notification_events,
 public.db08_user_shortcuts,
 public.db08_operation_receipts FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db08_request_revision_guard() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db08_no_self_approval() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db08_reject_audit_edit() FROM PUBLIC,anon,authenticated;

