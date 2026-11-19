-- DB31: no privileged table/API path is introduced by batch generation.
-- The actual posting function delegates every category to DB25's campus-locked
-- validated billing implementation, which records immutable charge rows.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='25s';
do $check$
declare
  v_private regprocedure;
  v_public regprocedure;
  v_function text;
begin
  v_private:=to_regprocedure('app_private.sms_fee_generate_categories(uuid,uuid,uuid,date,uuid[],text,uuid,boolean,uuid)');
  v_public:=to_regprocedure('public.fee_generate_categories(uuid,uuid,uuid,date,uuid[],text,uuid,boolean,uuid)');
  if v_private is null or v_public is null then
    raise exception 'DB31 batch billing function missing';end if;
  if has_function_privilege('anon',v_public,'EXECUTE')
    or has_function_privilege('anon',v_private,'EXECUTE')
    or not has_function_privilege('authenticated',v_public,'EXECUTE')
    or not has_function_privilege('authenticated',v_private,'EXECUTE')
  then raise exception 'DB31 fee billing RPC grants unsafe';end if;
  select pg_get_functiondef(v_private) into v_function;
  if position('sms_fee_role_authorized' in v_function)=0
    or position('sms_fee_generate_category' in v_function)=0
    or position('fee_operation_receipts' in v_function)=0
    or position('for update' in lower(v_function))=0
  then raise exception 'DB31 authorization, delegation, lock or retry guard missing';end if;
  if not exists(
    select 1 from pg_proc p where p.oid=v_private::oid and p.prosecdef
  ) then raise exception 'DB31 private function privilege boundary missing';end if;
  if exists(
    select 1 from pg_proc p where p.oid=v_public::oid and p.prosecdef
  ) then raise exception 'DB31 public function must remain invoker';end if;
end;
$check$;
rollback;
