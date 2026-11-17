begin;
do $perm$
begin
 if has_function_privilege('anon','public.principal_session_context()','EXECUTE')
   or not has_function_privilege('authenticated','public.principal_session_context()','EXECUTE')
 then raise exception 'Incorrect Principal session grants'; end if;
end $perm$;
select set_config('request.jwt.claim.sub',(select user_id::text from public.user_roles where role='owner' and is_active limit 1),true);
set local role authenticated;
do $owner$
begin
 begin
  perform public.principal_session_context();
  raise exception 'Owner was promoted to Principal';
 exception when insufficient_privilege then null; end;
end $owner$;
reset role;
create temporary table db10_principal_identity(
 user_id uuid,school_id uuid,campus_id uuid) on commit drop;
grant select on db10_principal_identity to authenticated;
do $new$
declare v_id uuid := gen_random_uuid();v_school uuid;v_campus uuid;
begin
 select r.school_id,c.id into strict v_school,v_campus
 from public.user_roles r
 join public.campuses c on c.school_id=r.school_id and c.is_active
 where r.role='owner' and r.is_active limit 1;
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,
 encrypted_password,raw_app_meta_data,raw_user_meta_data,
 created_at,updated_at,is_anonymous)
 values(v_id,'00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated',
 'test-principal-'||v_id||'@example.invalid',now(),
 '!no-real-password!','{}'::jsonb,'{}'::jsonb,now(),now(),false);
 insert into public.user_profiles(user_id,display_name,is_active)
 values(v_id,'TEST Principal',true);
 insert into public.user_roles(user_id,school_id,campus_id,role,is_active)
 values(v_id,v_school,v_campus,'principal',true);
 insert into db10_principal_identity values(v_id,v_school,v_campus);
end $new$;
select set_config('request.jwt.claim.sub',(select user_id::text from db10_principal_identity),true);
set local role authenticated;
do $principal$
declare v jsonb;f db10_principal_identity%rowtype;
begin
 select * into strict f from db10_principal_identity;
 v:=public.principal_session_context();
 if v->>'user_id'<>f.user_id::text
   or v->>'school_id'<>f.school_id::text
   or jsonb_array_length(v->'campuses')<>1
   or v->'campuses'->0->>'id'<>f.campus_id::text
 then raise exception 'Incorrect authenticated Principal context'; end if;
end $principal$;
reset role;
rollback;
