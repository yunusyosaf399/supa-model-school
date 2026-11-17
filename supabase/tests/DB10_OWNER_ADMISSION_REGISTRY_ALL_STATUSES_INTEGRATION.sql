begin;
select set_config('app.registry_test_id',(
  select id::text from public.admission_applications
  where applicant_name='TEST Admission Applicant 001' limit 1),true);
-- Transaction-only state swap; leaves live records unchanged.
update public.admission_applications
 set admission_status='submitted',approval_state='pending',
  submitted_at=now(),updated_at=now()
 where id=current_setting('app.registry_test_id')::uuid;
select set_config('request.jwt.claim.sub',(
  select r.user_id::text from public.user_roles r
  join public.user_profiles p on p.user_id=r.user_id
  join auth.users u on u.id=r.user_id
  where r.role='owner' and r.is_active and p.is_active
    and u.email_confirmed_at is not null limit 1),true);
set local role authenticated;
do $owner$
declare result jsonb;
begin
 result:=public.owner_admission_worklist(
  'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
  'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',50,0);
 if (result->>'total')::integer<>5 or
   not exists(select 1 from jsonb_array_elements(result->'applications') a
     where a->>'id'=current_setting('app.registry_test_id')
       and a->>'status'='submitted' and a->>'approval_state'='pending')
 then raise exception 'Submitted applications invisible to Owner';end if;
 if exists(select 1 from jsonb_array_elements(result->'applications') a
   where a?'storage_path' or a?'object_path') then
   raise exception 'Owner list exposed private Storage paths';end if;
end $owner$;
reset role;
rollback;
