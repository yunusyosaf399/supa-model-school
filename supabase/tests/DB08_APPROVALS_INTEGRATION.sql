-- DB08 fictional schema acceptance. ISOLATED LOCAL Postgres ONLY; ROLLBACK.
-- Auth fixture: create TWO local users:
-- sms-adm-admin-a@example.invalid and sms-adm-reviewer-b@example.invalid
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';
DO $fixture$
DECLARE
 a uuid; b uuid;
 s uuid:='11111111-1111-4111-8111-111111111111';
 ca uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 cb uuid:='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 policy uuid:='80000000-0000-4000-8000-000000000001';
 req uuid:='80000000-0000-4000-8000-000000000002';
 cat uuid:='80000000-0000-4000-8000-000000000003';
 expense uuid:='80000000-0000-4000-8000-000000000004';
 n integer;
BEGIN
 SELECT id INTO a FROM auth.users WHERE email='sms-adm-admin-a@example.invalid';
 SELECT id INTO b FROM auth.users WHERE email='sms-adm-reviewer-b@example.invalid';
 IF a IS NULL OR b IS NULL THEN RAISE EXCEPTION 'Create two fictional local Auth test users'; END IF;
 INSERT INTO public.schools(id,name,currency_code,timezone_name)
 VALUES(s,'Fictional Approvals School','PKR','Asia/Karachi');
 INSERT INTO public.campuses(id,school_id,code,name) VALUES
 (ca,s,'A','Campus A'),(cb,s,'B','Campus B');
 INSERT INTO public.user_profiles(user_id,display_name) VALUES
 (a,'Fictional Requester'),(b,'Fictional Reviewer');
 INSERT INTO public.db08_roles(role_code,label,scope)
 VALUES ('owner','School Owner','school'),('teacher','School Teacher','campus'),
 ('store_keeper','Store Keeper','campus'),('accountant','Accountant','campus');
 INSERT INTO public.db08_permissions(code,domain,description)
 VALUES('finance.approve_expense','finance','Approve authorized campus expense');
 INSERT INTO public.db08_role_grants(
 school_id,role_code,permission_code,allowed,granted_by)
 VALUES(s,'accountant','finance.approve_expense',true,a);
 INSERT INTO public.user_roles(user_id,school_id,campus_id,role)
 VALUES (a,s,ca,'teacher'),(b,s,ca,'accountant');
 INSERT INTO public.db08_approval_policies(
 id,school_id,campus_id,action_code,version_no,min_amount_minor,status,
 approved_by,activated_at)
 VALUES(policy,s,ca,'expense',1,1000,'active',b,now());
 INSERT INTO public.db08_approval_steps(
 school_id,policy_id,step_no,approver_role)
 VALUES(s,policy,1,'accountant');
 INSERT INTO public.expense_categories(id,school_id,code,name,expense_kind)
 VALUES(cat,s,'SUPPLIES','Office Supplies','operating');
 INSERT INTO public.expense_requests(
 id,school_id,campus_id,category_id,expense_kind,
 requested_amount_minor,expense_date,purpose,requester_id,request_operation_id)
 VALUES(expense,s,ca,cat,'operating',2000,'2026-04-01',
 'Fictional authorized request',a,'88888888-0000-4000-8000-000000000001');
 INSERT INTO public.db08_approval_requests(
 id,school_id,campus_id,policy_id,source_kind,requester_id,
 amount_minor,operation_id,reason)
 VALUES(req,s,ca,policy,'expense',a,2000,
 '88888888-0000-4000-8000-000000000002','Fictional expense approval');
 INSERT INTO public.db08_approval_sources(
 request_id,school_id,campus_id,source_kind,expense_request_id)
 VALUES(req,s,ca,'expense',expense);
 -- Cannot approve own request even through privileged SQL.
 BEGIN
  INSERT INTO public.db08_approval_decisions(
   school_id,request_id,policy_id,step_no,decision,actor_id,reason,operation_id)
  VALUES(s,req,policy,1,'approved',a,'Self decision denied',
  '88888888-0000-4000-8000-000000000003');
  RAISE EXCEPTION 'Self approval accepted';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 INSERT INTO public.db08_approval_decisions(
 school_id,request_id,policy_id,step_no,decision,actor_id,reason,operation_id)
 VALUES(s,req,policy,1,'approved',b,'Valid second reviewer',
 '88888888-0000-4000-8000-000000000004');
 BEGIN
  INSERT INTO public.db08_approval_decisions(
   school_id,request_id,policy_id,step_no,decision,actor_id,reason,operation_id)
  VALUES(s,req,policy,1,'approved',b,'Duplicate step not allowed',
  '88888888-0000-4000-8000-000000000005');
  RAISE EXCEPTION 'Duplicate review accepted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 BEGIN
  UPDATE public.db08_approval_decisions SET decision='rejected'
   WHERE request_id=req;
  RAISE EXCEPTION 'Immutable approval was rewritten';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 BEGIN
  INSERT INTO public.db08_approval_sources(
   request_id,school_id,campus_id,source_kind,expense_request_id)
  VALUES(req,s,cb,'expense',expense);
  RAISE EXCEPTION 'Cross-campus approval source accepted';
 EXCEPTION WHEN unique_violation OR foreign_key_violation THEN NULL;
 END;
 INSERT INTO public.db08_audit_events(
 school_id,campus_id,actor_id,event_code,target_entity,target_id)
 VALUES(s,ca,b,'finance.expense_approved','expense',expense);
 INSERT INTO public.db08_notification_messages(
 school_id,campus_id,recipient_id,event_code,subject,body_text,operation_id)
 VALUES(s,ca,a,'expense_approved','Expense approved',
 'Your expense request was approved',
 '88888888-0000-4000-8000-000000000006');
 INSERT INTO public.db08_document_templates(
 school_id,campus_id,kind,locale,version_no,template_json,status,approved_by)
 VALUES(s,ca,'receipt','en',1,'{"layout":"A4"}','active',b);
 INSERT INTO public.db08_operation_receipts(
 school_id,operation_id,action_code,actor_id,request_sha256,result_json)
 VALUES(s,'88888888-0000-4000-8000-000000000007','approve',b,
 decode(repeat('ab',32),'hex'),'{"accepted":true}');
 SELECT count(*) INTO n FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='public' AND c.relrowsecurity
 AND c.relname LIKE 'db08\_%' ESCAPE '\';
 IF n<>18 THEN RAISE EXCEPTION 'DB08 RLS not enabled on 18 tables: %',n; END IF;
 IF pg_catalog.has_table_privilege('authenticated','public.db08_approval_decisions','INSERT')
 OR pg_catalog.has_table_privilege('anon','public.db08_audit_events','SELECT')
 THEN RAISE EXCEPTION 'Direct client privileges not revoked'; END IF;
END;
$fixture$;
\echo DB08 local fictional assertions passed - ROLLBACK
ROLLBACK;
