-- Intended to run after installing the DB10 Owner directory RPC.
-- Rollback-only context simulation; not a full PostgREST end-to-end test.
begin;
select set_config('request.jwt.claim.sub',
  (select user_id::text from public.user_roles
   where role='owner' and is_active and campus_id is null limit 1),true);
set local role authenticated;
do $test$
declare v jsonb;
begin
 select public.owner_student_directory(
  'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654'::uuid,
  'e2308d36-ff0d-438d-97b4-95ed6d4c13c6'::uuid,100,0
 ) into v;
 if (v->>'total')::int<>32 or jsonb_array_length(v->'students')<>32
 then raise exception 'Directory count or returned page incorrect: %',v; end if;
 if exists(select 1 from jsonb_array_elements(v->'students') x
   where x->>'campus_id'<>'e2308d36-ff0d-438d-97b4-95ed6d4c13c6')
 then raise exception 'Campus scope leaked'; end if;
 if exists(select 1 from jsonb_array_elements(v->'students') x
   where x ? 'phone' or x ? 'date_of_birth' or x ? 'guardian_id')
 then raise exception 'Unneeded child details leaked'; end if;
 select public.owner_student_directory(
   'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
   'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',10,10
 ) into v;
 if (v->>'total')::int<>32 or jsonb_array_length(v->'students')<>10
 then raise exception 'Pagination incorrect'; end if;
end $test$;
reset role;
select set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $unauthorized$
begin
 begin
  perform public.owner_student_directory(
   'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
   'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',100,0);
  raise exception 'Unknown actor was allowed';
 exception when insufficient_privilege then null; end;
end $unauthorized$;
reset role;
rollback;
