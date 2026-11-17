-- Rollback-only Owner worklist assertions for live synthetic fixture.
begin;
do $grants$
begin
 if has_function_privilege('anon',
    'public.owner_admission_worklist(uuid,uuid,integer,integer)','EXECUTE')
    or not has_function_privilege('authenticated',
    'public.owner_admission_worklist(uuid,uuid,integer,integer)','EXECUTE')
 then raise exception 'Unsafe worklist privileges'; end if;
 if (select prosecdef from pg_proc where
  oid='public.owner_admission_worklist(uuid,uuid,integer,integer)'::regprocedure)
 then raise exception 'Public endpoint must be invoker'; end if;
end $grants$;
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
 v:=public.owner_admission_worklist(
  'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
  'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',50,0);
 if (v->>'total')::int<>5 or jsonb_array_length(v->'applications')<>5
 then raise exception 'Incorrect Owner worklist count'; end if;
 if exists(select 1 from jsonb_array_elements(v->'applications') a
   where a->>'campus_id'<>'e2308d36-ff0d-438d-97b4-95ed6d4c13c6'
     or a?'storage_path' or a?'approved_by'
     or jsonb_array_length(a->'documents')<>2)
 then raise exception 'Wrong campus, document metadata or sensitive projection'; end if;
 v:=public.owner_admission_worklist(
  'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
  'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',2,2);
 if (v->>'total')::int<>5 or jsonb_array_length(v->'applications')<>2
 then raise exception 'Pagination incorrect'; end if;
end $owner$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $unknown$
begin
 begin
  perform public.owner_admission_worklist(
   'aaa87efd-ba04-43e1-9fe6-7ad8d6cac654',
   'e2308d36-ff0d-438d-97b4-95ed6d4c13c6',50,0);
  raise exception 'Unauthorized actor can see applicants';
 exception when insufficient_privilege then null; end;
end $unknown$;
reset role;
rollback;
