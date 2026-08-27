do $$
begin
  if to_regclass('private.player_sync_operation_receipts') is null then
    raise exception 'Missing private player synchronization receipts.';
  end if;
  if to_regprocedure(
    'public.apply_player_sync_operation(uuid,uuid,text,bigint,jsonb)'
  ) is null then
    raise exception 'Missing player synchronization apply function.';
  end if;
  if to_regprocedure(
    'public.pull_player_sync_changes(timestamp with time zone,uuid,integer)'
  ) is null then
    raise exception 'Missing player synchronization pull function.';
  end if;
  if has_table_privilege('anon', 'private.player_sync_operation_receipts', 'select')
    or has_table_privilege('authenticated', 'private.player_sync_operation_receipts', 'select')
  then
    raise exception 'Synchronization receipts must remain private.';
  end if;
  if has_function_privilege(
    'anon',
    'public.apply_player_sync_operation(uuid,uuid,text,bigint,jsonb)',
    'execute'
  ) then
    raise exception 'Anonymous clients must not execute synchronization writes.';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.apply_player_sync_operation(uuid,uuid,text,bigint,jsonb)',
    'execute'
  ) then
    raise exception 'Authenticated clients require the guarded synchronization function.';
  end if;
  if exists (
    select 1
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'apply_player_sync_operation', 'pull_player_sync_changes'
      )
      and procedure.prosecdef is not true
  ) then
    raise exception 'Synchronization functions must use their explicit permission checks.';
  end if;
  if exists (
    select 1
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'apply_player_sync_operation', 'pull_player_sync_changes'
      )
      and coalesce(array_to_string(procedure.proconfig, ','), '')
        not like '%search_path=""%'
  ) then
    raise exception 'Synchronization functions must use an empty search_path.';
  end if;
end;
$$;
