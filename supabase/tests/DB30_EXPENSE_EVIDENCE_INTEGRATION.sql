-- DB30 local Supabase test, no remote credentials or object bytes.
-- Ensures privacy boundaries even when a client guesses UUIDs and paths.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='25s';
do $check$
declare v_table_oid oid;
begin
 select to_regclass('public.expense_attachments') into v_table_oid;
 if v_table_oid is null or not (select relrowsecurity from pg_class where oid=v_table_oid)
 then raise exception 'Expense evidence RLS missing';end if;
 if has_table_privilege('authenticated','public.expense_attachments','SELECT')
  or has_table_privilege('authenticated','public.expense_attachments','UPDATE')
  or has_table_privilege('authenticated','public.expense_attachments','INSERT')
  or has_table_privilege('anon','public.expense_attachments','SELECT')
 then raise exception 'Evidence base table is directly exposed';end if;
 if not exists(select 1 from storage.buckets
  where id='sms-expense-evidence' and public=false and file_size_limit=10485760
   and allowed_mime_types @> array['application/pdf','image/jpeg','image/png','image/webp']::text[])
 then raise exception 'Private evidence bucket missing or unsafe';end if;
 if not exists(select 1 from pg_policies
  where schemaname='storage' and tablename='objects'
   and policyname='db30_expense_evidence_immutable_insert' and cmd='INSERT'
   and roles @> array['authenticated']::name[])
 or not exists(select 1 from pg_policies
  where schemaname='storage' and tablename='objects'
   and policyname='db30_expense_evidence_registered_read' and cmd='SELECT')
 then raise exception 'Storage insert or authenticated read boundary missing';end if;
 if has_function_privilege('anon',
  'public.expense_evidence_register(uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
 or not has_function_privilege('authenticated',
  'public.expense_evidence_register(uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
 or has_function_privilege('anon',
  'public.expense_evidence_review(uuid,uuid,uuid,text,text)','EXECUTE')
 then raise exception 'Insecure evidence RPC grants';end if;
 if coalesce(app_private.sms_expense_evidence_can_upload('sms-expense-evidence',
  '99999999-9999-4999-8999-999999999999/88888888-8888-4888-8888-888888888888/77777777-7777-4777-8777-777777777777/request/66666666-6666-4666-8666-666666666666.pdf'),false)
 or coalesce(app_private.sms_expense_evidence_can_read('sms-expense-evidence',
  'made-up-object.pdf'),false)
 then raise exception 'Unregistered or unauthorized object accessible';end if;
end;$check$;
rollback;
