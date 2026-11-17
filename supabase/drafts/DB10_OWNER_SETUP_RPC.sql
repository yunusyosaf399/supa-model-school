-- DB10 / Owner onboarding RPC bridge (review-only; not a deployed migration)
-- Uses existing tested app_private authorization + atomic business operations.
-- Explicitly no table grants, no service-role key, and no anonymous RPC access.
--
-- After reviewing, generate a migration filename with:
--   supabase migration new db10_owner_setup_rpc
-- and include this SQL. Verify with local PostgreSQL RLS fixtures before deploying.

create or replace function public.db10_owner_complete_initial_setup(
  p_school_id uuid,
  p_campus_id uuid,
  p_school_name text,
  p_campus_name text,
  p_currency_code text,
  p_timezone_name text,
  p_year_label text,
  p_year_starts_on date,
  p_year_ends_on date,
  p_expected_school_revision bigint,
  p_expected_campus_revision bigint
) returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select app_private.complete_owner_initial_setup(
    p_school_id, p_campus_id, p_school_name, p_campus_name,
    p_currency_code, p_timezone_name, p_year_label,
    p_year_starts_on, p_year_ends_on,
    p_expected_school_revision, p_expected_campus_revision
  );
$$;

create or replace function public.db10_owner_create_class_with_sections(
  p_school_id uuid,
  p_campus_id uuid,
  p_academic_year_id uuid,
  p_class_name text,
  p_sort_order integer,
  p_sections text[]
) returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select app_private.owner_create_class_with_sections(
    p_school_id, p_campus_id, p_academic_year_id,
    p_class_name, p_sort_order, p_sections
  );
$$;

create or replace function public.db10_owner_dashboard_snapshot(
  p_school_id uuid,
  p_campus_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.owner_dashboard_snapshot(p_school_id, p_campus_id);
$$;

-- Supabase/Postgres can grant EXECUTE on new functions to PUBLIC by default.
-- Always revoke first, then opt-in only authenticated users; inner functions
-- enforce verified owner+school/campus membership and reject anonymous actors.
revoke all on function public.db10_owner_complete_initial_setup(
  uuid,uuid,text,text,text,text,text,date,date,bigint,bigint
) from public, anon, authenticated;
revoke all on function public.db10_owner_create_class_with_sections(
  uuid,uuid,uuid,text,integer,text[]
) from public, anon, authenticated;
revoke all on function public.db10_owner_dashboard_snapshot(
  uuid,uuid
) from public, anon, authenticated;

grant execute on function public.db10_owner_complete_initial_setup(
  uuid,uuid,text,text,text,text,text,date,date,bigint,bigint
) to authenticated;
grant execute on function public.db10_owner_create_class_with_sections(
  uuid,uuid,uuid,text,integer,text[]
) to authenticated;
grant execute on function public.db10_owner_dashboard_snapshot(
  uuid,uuid
) to authenticated;
