-- Unexposed private schemas cannot be called through PostgREST directly.
-- This public SECURITY INVOKER bridge is callable ONLY by service_role.
create or replace function public.server_register_invited_user(
 p_actor uuid,p_target uuid,p_school uuid,p_campus uuid,
 p_role text,p_display_name text,p_expected_email text)
returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.owner_register_invited_user(
   p_actor,p_target,p_school,p_campus,p_role,p_display_name,p_expected_email);
$fn$;

revoke all on function public.server_register_invited_user(
 uuid,uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.server_register_invited_user(
 uuid,uuid,uuid,uuid,text,text,text) to service_role;
