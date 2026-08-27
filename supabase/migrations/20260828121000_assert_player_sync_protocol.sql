do $$
declare
  test_user constant uuid := '70000000-0000-4000-8000-000000000001';
  test_player constant uuid := '70000000-0000-4000-8000-000000000003';
  first_operation constant uuid := '70000000-0000-4000-8000-000000000004';
  stale_operation constant uuid := '70000000-0000-4000-8000-000000000005';
  first_result jsonb;
  replay_result jsonb;
  stale_result jsonb;
  test_time constant timestamptz := '2026-08-28 00:00:00+00';
begin
  insert into auth.users (id, aud, role, created_at, updated_at)
  values (test_user, 'authenticated', 'authenticated', test_time, test_time);

  insert into public.user_roles (
    user_id, role, created_at, updated_at, version, deleted_at
  ) values (
    test_user, 'organizer', test_time, test_time, 0, null
  );

  perform set_config('request.jwt.claim.sub', test_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  first_result := public.apply_player_sync_operation(
    first_operation,
    test_player,
    'upsert',
    null,
    jsonb_build_object(
      'id', test_player,
      'display_name', 'M5 protocol assertion',
      'created_at', test_time,
      'updated_at', test_time,
      'version', 0,
      'deleted_at', null
    )
  );
  if first_result ->> 'status' <> 'accepted'
    or first_result ->> 'replayed' <> 'false'
  then
    raise exception 'Initial player synchronization operation was not accepted.';
  end if;

  replay_result := public.apply_player_sync_operation(
    first_operation,
    test_player,
    'upsert',
    null,
    jsonb_build_object(
      'id', test_player,
      'display_name', 'M5 protocol assertion',
      'created_at', test_time,
      'updated_at', test_time,
      'version', 0,
      'deleted_at', null
    )
  );
  if replay_result ->> 'status' <> 'accepted'
    or replay_result ->> 'replayed' <> 'true'
  then
    raise exception 'Player synchronization replay was not idempotent.';
  end if;

  begin
    perform public.apply_player_sync_operation(
      first_operation,
      test_player,
      'upsert',
      null,
      jsonb_build_object(
        'id', test_player,
        'display_name', 'Different request',
        'created_at', test_time,
        'updated_at', test_time,
        'version', 0,
        'deleted_at', null
      )
    );
    raise exception 'Reused operation ID with changed payload was accepted.';
  exception
    when sqlstate '22023' then null;
  end;

  stale_result := public.apply_player_sync_operation(
    stale_operation,
    test_player,
    'upsert',
    99,
    jsonb_build_object(
      'id', test_player,
      'display_name', 'Stale request',
      'created_at', test_time,
      'updated_at', test_time + interval '1 minute',
      'version', 100,
      'deleted_at', null
    )
  );
  if stale_result ->> 'status' <> 'conflict'
    or stale_result -> 'player' ->> 'version' <> '0'
  then
    raise exception 'Stale base version was not returned as a conflict.';
  end if;

  if (select count(*) from public.pull_player_sync_changes(null, null, 100)
      where id = test_player) <> 1
  then
    raise exception 'Authoritative player pull did not return the assertion record.';
  end if;

  delete from private.player_sync_operation_receipts where entity_id = test_player;
  delete from public.players where id = test_player;
  delete from public.user_roles
  where user_id = test_user and role = 'organizer';
  delete from auth.users where id = test_user;
end;
$$;
