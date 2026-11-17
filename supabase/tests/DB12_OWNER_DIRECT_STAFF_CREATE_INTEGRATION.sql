-- DB12: credentialed staff registration, no permanent Auth user or password.
begin;
do $grants$
begin
 if has_function_privilege('authenticated',
 'public.server_register_created_user(uuid,uuid,uuid,uuid,text,text,text)',
 'EXECUTE') or
 has_function_privilege('service_role',
 'public.server_register_invited_user(uuid,uuid,uuid,uuid,text,text,text)',
 'EXECUTE') or
 not has_function_privilege('service_role',
 'public.server_register_created_user(uuid,uuid,uuid,uuid,text,text,text)',
 'EXECUTE') then
  raise exception 'DB12 privileged account registration grants invalid';
 end if;
end $grants$;

create temporary table db12_created(
 actor uuid,school uuid,campus uuid,target uuid
) on commit drop;
grant select on db12_created to authenticated,service_role;

do $new$
declare v_actor uuid;v_school uuid;v_campus uuid;v_target uuid:=gen_random_uuid();
begin
 select r.user_id,r.school_id,c.id into strict v_actor,v_school,v_campus
 from public.user_roles r join public.campuses c on c.school_id=r.school_id
 where r.role='owner' and r.is_active and c.is_active limit 1;
 insert into auth.users(
  id,instance_id,aud,role,email,email_confirmed_at,encrypted_password,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_anonymous
 ) values(
  v_target,'00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated',
  'db12-created-'||v_target::text||'@example.invalid',
  now(),'!not-a-real-password!','{}'::jsonb,'{}'::jsonb,
  now(),now(),false
 );
 insert into db12_created values(v_actor,v_school,v_campus,v_target);
end $new$;

set local role service_role;
do $service$
declare f db12_created%rowtype;r jsonb;
begin
 select * into strict f from db12_created;
 r:=public.server_register_created_user(
  f.actor,f.target,f.school,f.campus,
  'teacher','TEST Created Teacher',
  'db12-created-'||f.target::text||'@example.invalid');
 if r->>'status'<>'created' or r->>'user_id'<>f.target::text then
   raise exception 'Direct staff role assignment not confirmed';
 end if;
end $service$;
reset role;

do $assert$
declare f db12_created%rowtype;
begin
 select * into strict f from db12_created;
 if (select count(*) from app_private.owner_user_admin_events
    where target_user_id=f.target and action='create')<>1 or
    not exists(select 1 from public.user_roles r
      where r.user_id=f.target and r.role='teacher'
      and r.campus_id=f.campus and r.is_active) then
   raise exception 'Created user role or audit is inconsistent';
 end if;
end $assert$;

select set_config('request.jwt.claim.sub',
 (select target::text from db12_created),true);
set local role authenticated;
do $staff$
declare f db12_created%rowtype;r jsonb;
begin
 select * into strict f from db12_created;
 r:=public.staff_session_context();
 if r->>'role'<>'teacher' or r->>'campus_id'<>f.campus::text then
  raise exception 'Staff login context mismatched';
 end if;
 begin
  perform public.owner_school_users(f.school);
  raise exception 'Staff accessed Owner user management';
 exception when insufficient_privilege then null;end;
 begin
  perform public.principal_session_context();
  raise exception 'Staff accessed Principal membership';
 exception when insufficient_privilege then null;end;
end $staff$;
reset role;
rollback;
