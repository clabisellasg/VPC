-- Deployment-time M7 security/catalog assertions.
do $$
declare
  function_name text;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'user_profiles'
      and column_name = 'player_id'
  ) then
    raise exception 'user_profiles.player_id is missing';
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'player_claim_requests'
      and c.relrowsecurity
  ) then
    raise exception 'player_claim_requests RLS is not enabled';
  end if;

  if has_table_privilege('anon', 'public.player_claim_requests', 'SELECT')
    or has_table_privilege('anon', 'public.player_claim_requests', 'INSERT')
    or has_table_privilege('authenticated', 'public.player_claim_requests', 'INSERT')
    or has_table_privilege('authenticated', 'public.player_claim_requests', 'UPDATE')
    or has_table_privilege('authenticated', 'public.user_roles', 'UPDATE')
  then
    raise exception 'M7 private table grants are too broad';
  end if;

  if not has_column_privilege(
    'authenticated', 'public.user_profiles', 'display_name', 'UPDATE'
  ) or has_column_privilege(
    'authenticated', 'public.user_profiles', 'player_id', 'UPDATE'
  ) then
    raise exception 'Profile column grants do not protect player links';
  end if;

  foreach function_name in array array[
    'get_current_account_snapshot',
    'list_claimable_players',
    'request_player_claim',
    'cancel_player_claim',
    'list_pending_player_claims',
    'approve_player_claim',
    'reject_player_claim'
  ] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = function_name
        and p.prosecdef
        and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=""%'
    ) then
      raise exception 'M7 function % is not a safe SECURITY DEFINER', function_name;
    end if;
  end loop;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'players'
      and column_name in ('auth_user_id', 'user_id', 'email')
  ) then
    raise exception 'Public players expose private account identity';
  end if;
end;
$$;
