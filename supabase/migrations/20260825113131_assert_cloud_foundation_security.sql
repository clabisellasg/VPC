-- Hosted catalog assertions for the Milestone 3 security baseline.
-- This migration creates no persistent application object.

do $$
declare
  target_table text;
  helper_is_definer boolean;
  helper_settings text[];
begin
  foreach target_table in array array[
    'user_profiles',
    'user_roles',
    'players',
    'events',
    'event_divisions',
    'event_participants',
    'division_participants',
    'participant_payments',
    'teams',
    'team_members',
    'matches',
    'match_dependencies',
    'court_queue_entries',
    'division_placements'
  ]
  loop
    if to_regclass(format('public.%I', target_table)) is null then
      raise exception 'Required table is missing: public.%', target_table;
    end if;

    if not exists (
      select 1
      from pg_class
      where oid = to_regclass(format('public.%I', target_table))
        and relrowsecurity
    ) then
      raise exception 'RLS is not enabled on public.%', target_table;
    end if;

    if has_table_privilege('anon', format('public.%I', target_table), 'DELETE')
      or has_table_privilege(
        'authenticated',
        format('public.%I', target_table),
        'DELETE'
      )
    then
      raise exception 'Client hard-delete privilege found on public.%', target_table;
    end if;
  end loop;

  foreach target_table in array array[
    'players',
    'events',
    'event_divisions',
    'event_participants',
    'division_participants',
    'teams',
    'team_members',
    'matches',
    'match_dependencies',
    'court_queue_entries',
    'division_placements'
  ]
  loop
    if not has_table_privilege(
      'anon',
      format('public.%I', target_table),
      'SELECT'
    ) then
      raise exception 'Anonymous public-read grant missing on public.%', target_table;
    end if;

    if has_table_privilege('anon', format('public.%I', target_table), 'INSERT')
      or has_table_privilege('anon', format('public.%I', target_table), 'UPDATE')
    then
      raise exception 'Anonymous write privilege found on public.%', target_table;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = target_table
    ) then
      raise exception 'Realtime publication is missing public.%', target_table;
    end if;
  end loop;

  foreach target_table in array array[
    'participant_payments',
    'user_profiles',
    'user_roles'
  ]
  loop
    if has_table_privilege('anon', format('public.%I', target_table), 'SELECT') then
      raise exception 'Anonymous private-data grant found on public.%', target_table;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.user_roles', 'INSERT')
    or has_table_privilege('authenticated', 'public.user_roles', 'UPDATE')
    or has_table_privilege('authenticated', 'public.user_roles', 'DELETE')
  then
    raise exception 'Authenticated clients can modify user_roles';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'players'
      and column_name in ('user_id', 'auth_user_id', 'account_id')
  ) then
    raise exception 'Public players table exposes an authentication identifier';
  end if;

  select p.prosecdef, p.proconfig
    into helper_is_definer, helper_settings
  from pg_proc as p
  join pg_namespace as n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'is_organizer'
    and p.pronargs = 0;

  if helper_is_definer is distinct from true then
    raise exception 'private.is_organizer() is not SECURITY DEFINER';
  end if;

  if coalesce(array_to_string(helper_settings, ','), '') not like '%search_path=""%'
  then
    raise exception 'private.is_organizer() does not use an empty search_path';
  end if;

  if has_function_privilege('anon', 'private.is_organizer()', 'EXECUTE') then
    raise exception 'Anonymous role can execute private.is_organizer()';
  end if;

  if not has_function_privilege(
    'authenticated',
    'private.is_organizer()',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role cannot execute private.is_organizer()';
  end if;

  if (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'user_profiles',
        'user_roles',
        'players',
        'events',
        'event_divisions',
        'event_participants',
        'division_participants',
        'participant_payments',
        'teams',
        'team_members',
        'matches',
        'match_dependencies',
        'court_queue_entries',
        'division_placements'
      ])
  ) <> 40 then
    raise exception 'Unexpected Milestone 3 RLS policy count';
  end if;
end;
$$;
