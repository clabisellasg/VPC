create table private.player_sync_operation_receipts (
  operation_id uuid primary key,
  entity_id uuid not null,
  operation_kind text not null,
  base_version bigint,
  request_payload jsonb not null,
  result_payload jsonb not null,
  applied_by uuid not null,
  created_at timestamptz not null default now(),
  constraint player_sync_receipt_operation_kind_check
    check (operation_kind in ('upsert', 'tombstone')),
  constraint player_sync_receipt_base_version_check
    check (base_version is null or base_version >= 0),
  constraint player_sync_receipt_user_fk
    foreign key (applied_by) references auth.users (id) on delete restrict
);

create index player_sync_receipts_entity_idx
  on private.player_sync_operation_receipts (entity_id, created_at);

revoke all on table private.player_sync_operation_receipts
  from public, anon, authenticated;

create or replace function public.apply_player_sync_operation(
  p_operation_id uuid,
  p_entity_id uuid,
  p_operation_kind text,
  p_base_version bigint,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_receipt private.player_sync_operation_receipts%rowtype;
  current_player public.players%rowtype;
  accepted_player public.players%rowtype;
  requested_version bigint;
  requested_created_at timestamptz;
  requested_updated_at timestamptz;
  requested_deleted_at timestamptz;
  result jsonb;
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;

  if p_operation_id is null or p_entity_id is null then
    raise exception 'Operation and entity IDs are required.' using errcode = '22023';
  end if;

  select * into existing_receipt
  from private.player_sync_operation_receipts
  where operation_id = p_operation_id;

  if found then
    if existing_receipt.entity_id is distinct from p_entity_id
      or existing_receipt.operation_kind is distinct from p_operation_kind
      or existing_receipt.base_version is distinct from p_base_version
      or existing_receipt.request_payload is distinct from p_payload
    then
      raise exception 'Operation ID was reused with different content.'
        using errcode = '22023';
    end if;
    return existing_receipt.result_payload || jsonb_build_object('replayed', true);
  end if;

  if p_operation_kind is null
    or p_operation_kind not in ('upsert', 'tombstone')
    or p_payload is null
    or jsonb_typeof(p_payload) <> 'object'
    or not (p_payload ?& array[
      'id', 'display_name', 'created_at', 'updated_at', 'version', 'deleted_at'
    ])
    or exists (
      select 1
      from jsonb_object_keys(p_payload) as payload_keys(payload_key)
      where payload_key not in (
        'id', 'display_name', 'created_at', 'updated_at', 'version', 'deleted_at'
      )
    )
  then
    raise exception 'Player synchronization payload is invalid.' using errcode = '22023';
  end if;

  if jsonb_typeof(p_payload -> 'id') <> 'string'
    or jsonb_typeof(p_payload -> 'display_name') <> 'string'
    or jsonb_typeof(p_payload -> 'created_at') <> 'string'
    or jsonb_typeof(p_payload -> 'updated_at') <> 'string'
    or jsonb_typeof(p_payload -> 'version') <> 'number'
    or jsonb_typeof(p_payload -> 'deleted_at') not in ('string', 'null')
    or (p_payload ->> 'id')::uuid is distinct from p_entity_id
    or coalesce(btrim(p_payload ->> 'display_name'), '') = ''
    or not (coalesce(p_payload ->> 'version', '') ~ '^[0-9]+$')
  then
    raise exception 'Player synchronization payload values are invalid.' using errcode = '22023';
  end if;

  requested_version := (p_payload ->> 'version')::bigint;
  requested_created_at := (p_payload ->> 'created_at')::timestamptz;
  requested_updated_at := (p_payload ->> 'updated_at')::timestamptz;
  requested_deleted_at := case
    when p_payload -> 'deleted_at' = 'null'::jsonb then null
    else (p_payload ->> 'deleted_at')::timestamptz
  end;

  if requested_updated_at < requested_created_at
    or (requested_deleted_at is not null and requested_deleted_at < requested_updated_at)
    or (p_operation_kind = 'upsert' and requested_deleted_at is not null)
    or (p_operation_kind = 'tombstone' and requested_deleted_at is null)
  then
    raise exception 'Player synchronization timestamps or operation kind are invalid.'
      using errcode = '22023';
  end if;

  select * into current_player
  from public.players
  where id = p_entity_id
  for update;

  if not found then
    if p_base_version is not null or requested_version <> 0 then
      result := jsonb_build_object(
        'status', 'conflict',
        'replayed', false,
        'player', null
      );
    else
      insert into public.players (
        id, display_name, created_at, updated_at, version, deleted_at
      ) values (
        p_entity_id,
        p_payload ->> 'display_name',
        requested_created_at,
        requested_updated_at,
        requested_version,
        requested_deleted_at
      ) returning * into accepted_player;
      result := jsonb_build_object(
        'status', 'accepted',
        'replayed', false,
        'player', to_jsonb(accepted_player)
      );
    end if;
  elsif p_base_version is null or current_player.version <> p_base_version then
    result := jsonb_build_object(
      'status', 'conflict',
      'replayed', false,
      'player', to_jsonb(current_player)
    );
  else
    if requested_version <> p_base_version + 1
      or requested_created_at is distinct from current_player.created_at
    then
      raise exception 'Player synchronization version progression is invalid.'
        using errcode = '22023';
    end if;
    update public.players
    set display_name = p_payload ->> 'display_name',
        updated_at = requested_updated_at,
        version = requested_version,
        deleted_at = requested_deleted_at
    where id = p_entity_id
    returning * into accepted_player;
    result := jsonb_build_object(
      'status', 'accepted',
      'replayed', false,
      'player', to_jsonb(accepted_player)
    );
  end if;

  insert into private.player_sync_operation_receipts (
    operation_id,
    entity_id,
    operation_kind,
    base_version,
    request_payload,
    result_payload,
    applied_by
  ) values (
    p_operation_id,
    p_entity_id,
    p_operation_kind,
    p_base_version,
    p_payload,
    result,
    auth.uid()
  );

  return result;
end;
$$;

revoke all on function public.apply_player_sync_operation(
  uuid, uuid, text, bigint, jsonb
) from public, anon;
grant execute on function public.apply_player_sync_operation(
  uuid, uuid, text, bigint, jsonb
) to authenticated;

create or replace function public.pull_player_sync_changes(
  p_after_updated_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 100
)
returns table (
  id uuid,
  display_name text,
  created_at timestamptz,
  updated_at timestamptz,
  version bigint,
  deleted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;
  if p_limit < 1 or p_limit > 100 then
    raise exception 'Pull limit must be between 1 and 100.' using errcode = '22023';
  end if;
  if (p_after_updated_at is null) <> (p_after_id is null) then
    raise exception 'Pull checkpoint values must be both present or absent.'
      using errcode = '22023';
  end if;

  return query
  select
    player.id,
    player.display_name,
    player.created_at,
    player.updated_at,
    player.version,
    player.deleted_at
  from public.players as player
  where p_after_updated_at is null
     or (player.updated_at, player.id) > (p_after_updated_at, p_after_id)
  order by player.updated_at, player.id
  limit p_limit;
end;
$$;

revoke all on function public.pull_player_sync_changes(
  timestamptz, uuid, integer
) from public, anon;
grant execute on function public.pull_player_sync_changes(
  timestamptz, uuid, integer
) to authenticated;
