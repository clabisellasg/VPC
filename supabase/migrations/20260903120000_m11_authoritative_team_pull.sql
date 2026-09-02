-- Preserve complete authoritative metadata and history in the existing pull
-- protocol. Cursor order remains (aggregate updated_at, division_id).
create or replace function public.pull_team_formation_changes(
  p_after_updated_at timestamptz default null,
  p_after_division_id uuid default null,
  p_limit integer default 50
)
returns table(division_id uuid, updated_at timestamptz, snapshot jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 or
     (p_after_updated_at is null) <> (p_after_division_id is null) then
    raise exception 'Invalid team pull cursor or limit.' using errcode = '22023';
  end if;
  return query
  with changed as (
    select t.division_id,
      max(greatest(t.updated_at, coalesce(tm.updated_at, t.updated_at))) as changed_at
    from public.teams t
    left join public.team_members tm on tm.team_id = t.id
    group by t.division_id
  )
  select c.division_id, c.changed_at, jsonb_build_object(
    'event_id', d.event_id,
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
      'id', t.id, 'division_id', t.division_id,
      'formation_method', t.formation_method, 'display_label', t.display_label,
      'created_at', t.created_at, 'updated_at', t.updated_at,
      'deleted_at', t.deleted_at, 'version', t.version
    ) order by t.id) from public.teams t where t.division_id = c.division_id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object(
      'team_id', tm.team_id, 'player_id', tm.player_id,
      'created_at', tm.created_at, 'updated_at', tm.updated_at,
      'deleted_at', tm.deleted_at, 'version', tm.version
    ) order by tm.team_id, tm.player_id)
    from public.team_members tm join public.teams t on t.id = tm.team_id
    where t.division_id = c.division_id), '[]'::jsonb)
  )
  from changed c join public.event_divisions d on d.id = c.division_id
  where p_after_updated_at is null or
    (c.changed_at, c.division_id) > (p_after_updated_at, p_after_division_id)
  order by c.changed_at, c.division_id limit p_limit;
end;
$$;
revoke all on function public.pull_team_formation_changes(timestamptz,uuid,integer) from public, anon;
grant execute on function public.pull_team_formation_changes(timestamptz,uuid,integer) to authenticated;

do $$ begin
  if has_function_privilege('anon', 'public.pull_team_formation_changes(timestamptz,uuid,integer)', 'execute') then
    raise exception 'Anonymous team pull must remain denied';
  end if;
  if not has_function_privilege('authenticated', 'public.pull_team_formation_changes(timestamptz,uuid,integer)', 'execute') then
    raise exception 'Authenticated team pull grant is missing';
  end if;
end $$;

-- Read-only hosted assertions. Existing accounts are neither changed nor
-- exposed; fixtures are not inserted. Fresh empty local stacks may have no
-- organizer yet, in which case only the permission/catalog assertions run.
do $$
declare
  actor uuid;
  previous_claim text := current_setting('request.jwt.claim.sub', true);
  item record;
  value jsonb;
  expected jsonb;
  seen integer := 0;
  total integer;
  cursor_time timestamptz := null;
  cursor_id uuid := null;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.pull_team_formation_changes(null, null, 1);
    raise exception 'Unauthenticated pull unexpectedly allowed';
  exception when insufficient_privilege then null;
  end;
  select ur.user_id into actor from public.user_roles ur
    where ur.role = 'organizer' and ur.deleted_at is null limit 1;
  if actor is not null then
    perform set_config('request.jwt.claim.sub', actor::text, true);
    select count(distinct t.division_id) into total from public.teams t;
    loop
      select * into item from public.pull_team_formation_changes(cursor_time, cursor_id, 1);
      exit when not found;
      if cursor_time is not null and
        (item.updated_at, item.division_id) <= (cursor_time, cursor_id) then
        raise exception 'Team pull did not strictly advance';
      end if;
      for value in select jsonb_array_elements(item.snapshot->'teams') loop
        select jsonb_build_object('created_at', t.created_at,
          'updated_at', t.updated_at, 'deleted_at', t.deleted_at, 'version', t.version)
          into expected from public.teams t where t.id = (value->>'id')::uuid;
        if expected is distinct from jsonb_build_object(
          'created_at', value->'created_at', 'updated_at', value->'updated_at',
          'deleted_at', value->'deleted_at', 'version', value->'version') then
          raise exception 'Team pull metadata mismatch';
        end if;
      end loop;
      for value in select jsonb_array_elements(item.snapshot->'members') loop
        select jsonb_build_object('created_at', tm.created_at,
          'updated_at', tm.updated_at, 'deleted_at', tm.deleted_at, 'version', tm.version)
          into expected from public.team_members tm
          where tm.team_id = (value->>'team_id')::uuid and tm.player_id = (value->>'player_id')::uuid;
        if expected is distinct from jsonb_build_object(
          'created_at', value->'created_at', 'updated_at', value->'updated_at',
          'deleted_at', value->'deleted_at', 'version', value->'version') then
          raise exception 'Team member pull metadata mismatch';
        end if;
      end loop;
      cursor_time := item.updated_at;
      cursor_id := item.division_id;
      seen := seen + 1;
      if seen > total then raise exception 'Team pull pagination repeated data'; end if;
    end loop;
    if seen <> total then raise exception 'Team pull pagination skipped data'; end if;
  else
    raise notice 'No organizer exists: data-dependent team pull assertions skipped';
  end if;
  perform set_config('request.jwt.claim.sub', coalesce(previous_claim, ''), true);
end $$;
