-- DB11 verified Owner user controls: no actual invitations are sent.
begin;
do $grants$
begin
 if has_function_privilege('anon','public.owner_school_users(uuid)','EXECUTE')
 or has_function_privilege('anon','public.owner_set_staff_active(uuid,boolean)','EXECUTE')
 or has_function_privilege('authenticated',
     'app_private.owner_register_invited_user(uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
 or not has_function_privilege('service_role',
     'app_private.owner_register_invited_user(uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
 then raise exception 'DB11 user management grants unsafe';end if;
end $grants$;
create temporary table db11_staff_test(
 actor uuid,school uuid,campus uuid,employee uuid,role_id uuid
) on commit drop;
grant select on db11_staff_test to authenticated;

do $fixture$
declare v_school uuid;v_campus uuid;v_actor uuid;v_employee uuid:=gen_random_uuid();v_role uuid;
begin
 select r.user_id,r.school_id,c.id
 into strict v_actor,v_school,v_campus from public.user_roles r
 join public.campuses c on c.school_id=r.school_id
 where r.role='owner' and r.is_active and c.is_active limit 1;
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,
 encrypted_password,raw_app_meta_data,raw_user_meta_data,
 created_at,updated_at,invited_at,is_anonymous)
 values(v_employee,'00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated',
 'db11-staff-'||v_employee::text||'@example.invalid',
 null,'!no-real-password!','{}'::jsonb,'{}'::jsonb,now(),now(),now(),false);
 -- Mimic the sole server-side Edge Function role-registration call as DB admin.
 select (app_private.owner_register_invited_user(
  v_actor,v_employee,v_school,v_campus,'principal',
  'TEST Principal Staff','db11-staff-'||v_employee::text||'@example.invalid'
 )->>'role_id')::uuid into v_role;
 insert into db11_staff_test values(v_actor,v_school,v_campus,v_employee,v_role);
 if (select count(*) from app_private.owner_user_admin_events
 where target_user_id=v_employee and action='invite') <> 1
 then raise exception 'Invite audit not recorded';end if;
end $fixture$;

select set_config('request.jwt.claim.sub',
 (select actor::text from db11_staff_test),true);
set local role authenticated;
do $owner_controls$
declare f db11_staff_test%rowtype;v jsonb;
begin
 select * into strict f from db11_staff_test;
 v:=public.owner_user_invite_preflight(f.school,f.campus,'teacher');
 if v->>'eligible'<>'true' then
 raise exception 'Owner preflight failed';end if;
 begin
  perform public.owner_user_invite_preflight(f.school,f.campus,'owner');
  raise exception 'Owner self-created privileged user';
 exception when invalid_parameter_value then null;end;
 v:=public.owner_school_users(f.school);
 if not exists(select 1 from jsonb_array_elements(v) x
   where x->>'user_id'=f.employee::text and x->>'role'='principal')
 then raise exception 'Owner cannot see invited Principal';end if;
 if (public.owner_set_staff_active(f.role_id,false)->>'active')::boolean
 then raise exception 'Deactivate did not work';end if;
 if not (public.owner_set_staff_active(f.role_id,true)->>'active')::boolean
 then raise exception 'Reactivate did not work';end if;
 begin
  perform public.owner_set_staff_active((
    select id from public.user_roles where user_id=f.actor
    and role='owner' limit 1),false);
  raise exception 'Owner disabled their own privileged role';
 exception when insufficient_privilege then null;end;
end $owner_controls$;
reset role;
select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $unauthorized$
declare f db11_staff_test%rowtype;
begin
 select * into strict f from db11_staff_test;
 begin
   perform public.owner_school_users(f.school);
   raise exception 'Unknown actor read staff directory';
 exception when insufficient_privilege then null;end;
 begin
   perform public.owner_set_staff_active(f.role_id,false);
   raise exception 'Unknown actor disabled Principal role';
 exception when insufficient_privilege then null;end;
end $unauthorized$;
reset role;
rollback;
