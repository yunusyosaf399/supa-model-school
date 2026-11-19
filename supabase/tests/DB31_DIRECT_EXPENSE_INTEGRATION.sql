-- DB31 regression: no approval before recording or payment; receipts optional.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='25s';
do $db31$
declare v_record_status text;v_integrity text;
 v_request_fn text;v_payment_fn text;v_upload_fn text;v_list_fn text;
begin
 select pg_get_constraintdef(oid) into v_record_status
 from pg_constraint where conrelid='public.expense_requests'::regclass
  and conname='expense_requests_status_check';
 select pg_get_constraintdef(oid) into v_integrity
 from pg_constraint where conrelid='public.expense_requests'::regclass
  and conname='expense_requests_check';
 if v_record_status not like '%recorded%'
 or v_integrity not like '%recorded%' then
   raise exception 'Recorded expense status without Owner review unavailable';
 end if;
 select pg_get_functiondef('app_private.sms_expense_request(uuid,uuid,uuid,bigint,date,text,uuid)'::regprocedure)
 into v_request_fn;
 select pg_get_functiondef('app_private.sms_expense_payment(uuid,uuid,uuid,uuid,bigint,date,text,text,uuid)'::regprocedure)
 into v_payment_fn;
 select pg_get_functiondef('app_private.sms_expense_evidence_can_upload(text,text)'::regprocedure)
 into v_upload_fn;
 select pg_get_functiondef('app_private.sms_expense_evidence_list(uuid,uuid,uuid)'::regprocedure)
 into v_list_fn;
 if v_request_fn not like '%''recorded'',v_actor,p_operation%'
 or v_payment_fn not like '%(''recorded'',''approved'')%'
 or v_upload_fn not like '%(''pending'',''recorded'',''approved'')%'
 or v_upload_fn not like '%(''recorded'',''approved'')%'
 or v_list_fn not like '%(''recorded'',''approved'')%'
 then raise exception 'DB31 expense/evidence functions not updated';end if;
 if has_function_privilege('authenticated',
   'public.expense_review(uuid,uuid,uuid,text,text,uuid)','EXECUTE')
 or has_function_privilege('authenticated',
   'public.expense_evidence_review(uuid,uuid,uuid,text,text)','EXECUTE')
 then raise exception 'Legacy approval/review RPC still executable';end if;
 if not has_function_privilege('authenticated',
   'public.expense_request(uuid,uuid,uuid,bigint,date,text,uuid)','EXECUTE')
 or not has_function_privilege('authenticated',
   'public.expense_payment(uuid,uuid,uuid,uuid,bigint,date,text,text,uuid)','EXECUTE')
 then raise exception 'Direct expense entry and payment RPC missing';end if;
 if exists(select 1 from public.expense_attachments where evidence_kind not in ('invoice','receipt'))
 then raise exception 'Invalid expense attachment type';end if;
end;
$db31$;
rollback;
