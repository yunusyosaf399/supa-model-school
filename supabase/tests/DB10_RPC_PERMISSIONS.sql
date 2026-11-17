-- DB10 read-only permission smoke test. Run after installing RPC wrappers.
-- This tests grants only; run authenticated Owner / other-campus / anon end-to-end
-- execution cases in a disposable DB before deployment.
do $$
declare
  p record;
begin
  for p in
    select oid, proname from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in (
        'db10_owner_complete_initial_setup',
        'db10_owner_create_class_with_sections',
        'db10_owner_dashboard_snapshot'
      )
  loop
    if has_function_privilege('anon', p.oid, 'EXECUTE')
      or not has_function_privilege('authenticated', p.oid, 'EXECUTE')
      or (select prosecdef from pg_proc where oid=p.oid)
    then
      raise exception 'Unsafe DB10 RPC permissions: %', p.proname;
    end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace='public'::regnamespace
      and proname in ('db10_owner_complete_initial_setup',
                      'db10_owner_create_class_with_sections',
                      'db10_owner_dashboard_snapshot')) <> 3 then
    raise exception 'Expected exactly three DB10 RPC functions';
  end if;
end $$;
