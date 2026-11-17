-- Rollback-only extra-details persistence and idempotency.
begin;
select set_config('request.jwt.claim.sub',
 (select user_id::text from public.user_roles
  where role='owner' and is_active limit 1),true);
set local role authenticated;
do $full_form$
declare v_save jsonb;v_retry jsonb;v_list jsonb;
  v_op uuid:=gen_random_uuid();
begin
 v_save:=public.owner_save_admission_draft_v2(
  'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
  'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',
  '3157978d-2d08-451b-80d7-13dc83aeddbe',
  null,null,v_op,'TEST v2 Applicant',date '2018-05-20',
  '',null,null,'[]'::jsonb,
  '{"gender":"female","city":"Peshawar",
    "uses_transport":true,"requests_discount":false}'::jsonb);
 v_retry:=public.owner_save_admission_draft_v2(
  'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
  'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',
  '3157978d-2d08-451b-80d7-13dc83aeddbe',
  null,null,v_op,'TEST v2 Applicant',date '2018-05-20',
  '',null,null,'[]'::jsonb,
  '{"gender":"female","city":"Peshawar",
    "uses_transport":true,"requests_discount":false}'::jsonb);
 if v_save->>'application_id'<>v_retry->>'application_id' then
  raise exception 'Repeated Save Draft created duplicate'; end if;
 v_list:=public.owner_admission_worklist(
  'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
  'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',100,0);
 if not exists(select 1 from jsonb_array_elements(v_list->'applications') a
 where a->>'id'=v_save->>'application_id'
   and a->'extra_details'->>'city'='Peshawar'
   and a->'extra_details'->>'uses_transport'='true') then
  raise exception 'Saved form details could not be resumed'; end if;
end $full_form$;
reset role;
rollback;
