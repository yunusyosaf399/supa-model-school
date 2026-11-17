-- Read-only authenticated document metadata; never exposes storage path.
begin;
do $permissions$
begin
  if has_function_privilege('anon','public.owner_admission_documents(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.owner_admission_documents(uuid)','EXECUTE') then
    raise exception 'Unsafe document status grant';
  end if;
end $permissions$;

select set_config('app.test_application',(
  select id::text from public.admission_applications
  where applicant_name='TEST Admission Applicant 001'
  limit 1),true);
select set_config('request.jwt.claim.sub',(
  select r.user_id::text from public.user_roles r
  join public.user_profiles p on p.user_id=r.user_id
  join auth.users u on u.id=r.user_id
  where r.role='owner' and r.is_active and r.campus_id is null
    and p.is_active and u.email_confirmed_at is not null
    and u.deleted_at is null and u.is_anonymous is not true limit 1),true);
set local role authenticated;
do $owner$
declare v jsonb;
begin
  v:=public.owner_admission_documents(current_setting('app.test_application')::uuid);
  if jsonb_array_length(v)<>2 or exists(
    select 1 from jsonb_array_elements(v) d
    where d->>'id' is null or d->>'revision' is null
      or d?'storage_path' or d?'file_bytes' or d?'verified_by'
  ) then raise exception 'Invalid document metadata projection'; end if;
end $owner$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $deny$
begin
  begin
    perform public.owner_admission_documents(current_setting('app.test_application')::uuid);
    raise exception 'Unknown actor allowed';
  exception when insufficient_privilege then null; end;
end $deny$;
reset role;
rollback;
