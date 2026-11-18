-- DB29D: chart account code constraint requires uppercase A-Z0-9.
create or replace function app_private.sms_expense_create_account(
 p_school uuid,p_campus uuid,p_name text,p_kind text,
 p_masked text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
 v_name text:=btrim(coalesce(p_name,''));
 v_masked text:=nullif(btrim(coalesce(p_masked,'')),'');
 v_tz text;v_payload jsonb;v_previous jsonb;v_ledger uuid;
 v_account uuid;v_result jsonb;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Owner-only account setup' using errcode='42501';end if;
 if p_operation is null or length(v_name) not between 2 and 160
  or coalesce(p_kind,'') not in ('cash','bank')
  or (v_masked is not null and length(v_masked) not between 4 and 20)
 then raise exception 'Invalid payment account details' using errcode='22023';end if;
 select timezone_name into v_tz from public.schools
 where id=p_school and status='active' for update;
 if v_tz is null or not exists(select 1 from public.campuses
 where id=p_campus and school_id=p_school and is_active)
 then raise exception 'Invalid campus' using errcode='42501';end if;
 v_payload:=jsonb_build_object('campus',p_campus,'name',v_name,
  'kind',p_kind,'masked',v_masked);
 v_previous:=app_private.sms_expense_existing(p_school,p_operation,'account',v_payload);
 if v_previous is not null then return v_previous;end if;
 insert into public.ledger_accounts(
 school_id,campus_id,code,name,account_type,account_scope)
 values(p_school,p_campus,'SMFA_'||upper(p_kind)||'_'||
   upper(substr(replace(p_operation::text,'-',''),1,12)),
   v_name,'asset','campus') returning id into v_ledger;
 insert into public.financial_accounts(
 school_id,campus_id,ledger_account_id,ledger_account_type,account_kind,
 display_name,masked_reference,opened_on,status,created_by)
 values(p_school,p_campus,v_ledger,'asset',p_kind,v_name,
 v_masked,(now() at time zone v_tz)::date,'active',v_actor)
 returning id into v_account;
 v_result:=jsonb_build_object('saved',true,'account_id',v_account);
 return app_private.sms_expense_record(p_school,p_operation,'account',v_payload,v_result);
end;$fn$;
revoke all on function
 app_private.sms_expense_create_account(uuid,uuid,text,text,text,uuid)
 from public,anon;
grant execute on function
 app_private.sms_expense_create_account(uuid,uuid,text,text,text,uuid)
 to authenticated;
