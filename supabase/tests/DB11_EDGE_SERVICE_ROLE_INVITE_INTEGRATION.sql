-- DB11 Edge service_role RPC bridge; no invitation email or persistent user.
begin;
create temporary table db11_edge_test(
 actor_id uuid,school_id uuid,campus_id uuid,target_id uuid
) on commit drop;
grant select on db11_edge_test to service_role;
do $prepare$
declare v_actor uuid;v_school uuid;v_campus uuid;v_target uuid:=gen_random_uuid();
begin
 select r.user_id,r.school_id,c.id into strict v_actor,v_school,v_campus
 from public.user_roles r join public.campuses c on c.school_id=r.school_id
 where r.role='owner' and r.is_active and c.is_active limit 1;
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,
  encrypted_password,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,invited_at,is_anonymous)
 values(v_target,'00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated',
  'db11-service-'||v_target::text||'@example.invalid',
  null,'!no-real-password!','{}'::jsonb,'{}'::jsonb,
  now(),now(),now(),false);
 insert into db11_edge_test values(v_actor,v_school,v_campus,v_target);
end $prepare$;
set local role authenticated;
do $denied$
begin
 if has_function_privilege('authenticated',
   'public.server_register_invited_user(uuid,uuid,uuid,uuid,text,text,text)',
   'EXECUTE') then raise exception 'Auth users can invoke service bridge';end if;
end $denied$;
reset role;
set local role service_role;
do $edge$
declare v db11_edge_test%rowtype;result jsonb;
begin
 select * into strict v from db11_edge_test;
 result:=public.server_register_invited_user(
  v.actor_id,v.target_id,v.school_id,v.campus_id,
  'principal','TEST Principal Server',
  'db11-service-'||v.target_id::text||'@example.invalid');
 if result->>'status'<>'invited' then
  raise exception 'Edge-to-DB invitation failed';end if;
end $edge$;
reset role;
rollback;
