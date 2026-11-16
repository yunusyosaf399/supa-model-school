-- REVIEW DRAFT ONLY — DO NOT APPLY TO THE CONNECTED LIVE PROJECT.
-- Add after tested DB01. Never put service-role secrets in Flutter.
-- This is a small additive user preference table, NOT an auth mechanism.
begin;

create table public.user_ui_preferences (
  user_id uuid primary key
    references public.user_profiles(user_id) on delete cascade,
  theme_mode text not null default 'system'
    check (theme_mode in ('system','light','dark')),
  preferred_campus_id uuid references public.campuses(id) on delete set null,
  compact_navigation boolean not null default false,
  dashboard_shortcuts text[] not null default
    array['new_admission','collect_fee','attendance','expenses']::text[],
  updated_at timestamptz not null default now(),
  check (cardinality(dashboard_shortcuts) <= 6),
  check (dashboard_shortcuts <@ array[
    'new_admission','collect_fee','attendance','expenses',
    'students','reports','sync_center'
  ]::text[])
);

create index user_ui_preferences_campus_idx
  on public.user_ui_preferences(preferred_campus_id)
  where preferred_campus_id is not null;

alter table public.user_ui_preferences enable row level security;
revoke all on public.user_ui_preferences from public, anon, authenticated;
grant select,insert,update on public.user_ui_preferences to authenticated;

create policy ui_prefs_own_read on public.user_ui_preferences
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy ui_prefs_own_insert on public.user_ui_preferences
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (
      preferred_campus_id is null
      or (select app_private.can_read_campus(preferred_campus_id))
    )
  );

create policy ui_prefs_own_update on public.user_ui_preferences
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (
      preferred_campus_id is null
      or (select app_private.can_read_campus(preferred_campus_id))
    )
  );

-- No delete policy; a trusted account-removal process performs deletion.
commit;

-- BEFORE ANY DEPLOYMENT:
-- 1. Create a migration with the locally installed Supabase CLI.
-- 2. Test unauthenticated deny, own read/write, other-user deny,
--    unauthorized preferred campus reject and revoked campus handling.
-- 3. Confirm additional identity/campus constraints and advisor results.
-- 4. The UI does not yet read or save preferences. Values are in-memory.
