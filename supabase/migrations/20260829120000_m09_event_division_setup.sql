alter table public.event_divisions
  alter column tournament_format drop not null;

create unique index if not exists event_divisions_active_normalized_name_idx
  on public.event_divisions (event_id, lower(regexp_replace(btrim(name), '\s+', ' ', 'g')))
  where deleted_at is null;

create table private.event_setup_operation_receipts (
  operation_id uuid primary key,
  event_id uuid not null references public.events (id) on delete restrict,
  base_version bigint,
  request_payload jsonb not null,
  result_payload jsonb not null,
  applied_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint event_setup_receipt_base_version_check
    check (base_version is null or base_version >= 0)
);

revoke all on table private.event_setup_operation_receipts
  from public, anon, authenticated;

create or replace function private.event_setup_json(p_event_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'event', to_jsonb(e),
    'divisions', coalesce((
      select jsonb_agg(to_jsonb(d) order by lower(d.name), d.id)
      from public.event_divisions d
      where d.event_id = e.id
    ), '[]'::jsonb)
  )
  from public.events e
  where e.id = p_event_id;
$$;

create or replace function public.apply_event_setup_operation(
  p_operation_id uuid,
  p_event_id uuid,
  p_base_version bigint,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior private.event_setup_operation_receipts%rowtype;
  current_event public.events%rowtype;
  event_data jsonb;
  division_data jsonb;
  requested_status text;
  requested_version bigint;
  result jsonb;
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;
  if p_operation_id is null or p_event_id is null
    or p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or not (p_payload ?& array['event', 'divisions'])
    or exists (
      select 1 from jsonb_object_keys(p_payload) k
      where k not in ('event', 'divisions')
    )
    or jsonb_typeof(p_payload -> 'event') <> 'object'
    or jsonb_typeof(p_payload -> 'divisions') <> 'array'
  then
    raise exception 'Event setup payload is invalid.' using errcode = '22023';
  end if;

  select * into prior
  from private.event_setup_operation_receipts
  where operation_id = p_operation_id;
  if found then
    if prior.event_id is distinct from p_event_id
      or prior.base_version is distinct from p_base_version
      or prior.request_payload is distinct from p_payload
    then
      raise exception 'Operation ID was reused with different content.' using errcode = '22023';
    end if;
    return prior.result_payload || jsonb_build_object('replayed', true);
  end if;

  event_data := p_payload -> 'event';
  if not (event_data ?& array[
      'id','name','scheduled_at','event_type','status','entry_fee_minor_units',
      'entry_fee_currency','court_label','created_at','updated_at','version','deleted_at'
    ])
    or exists (
      select 1 from jsonb_object_keys(event_data) k
      where k not in (
        'id','name','scheduled_at','event_type','status','entry_fee_minor_units',
        'entry_fee_currency','court_label','created_at','updated_at','version','deleted_at'
      )
    )
    or (event_data ->> 'id')::uuid is distinct from p_event_id
    or coalesce(btrim(event_data ->> 'name'), '') = ''
    or coalesce(btrim(event_data ->> 'court_label'), '') = ''
    or event_data ->> 'event_type' not in ('casual', 'formal')
    or event_data ->> 'status' not in ('upcoming','registration','inProgress','completed','archived')
    or not (event_data ->> 'version' ~ '^[0-9]+$')
  then
    raise exception 'Event setup values are invalid.' using errcode = '22023';
  end if;

  requested_status := event_data ->> 'status';
  requested_version := (event_data ->> 'version')::bigint;
  select * into current_event from public.events where id = p_event_id for update;

  if not found then
    if p_base_version is not null or requested_version <> 0
      or requested_status <> 'upcoming'
    then
      result := jsonb_build_object('status', 'conflict', 'setup', null, 'replayed', false);
    else
      insert into public.events (
        id,name,scheduled_at,event_type,status,entry_fee_minor_units,
        entry_fee_currency,court_label,created_at,updated_at,version,deleted_at
      ) values (
        p_event_id, event_data->>'name', (event_data->>'scheduled_at')::timestamptz,
        event_data->>'event_type', requested_status,
        nullif(event_data->>'entry_fee_minor_units','')::bigint,
        event_data->>'entry_fee_currency', event_data->>'court_label',
        (event_data->>'created_at')::timestamptz,
        (event_data->>'updated_at')::timestamptz, requested_version,
        nullif(event_data->>'deleted_at','')::timestamptz
      );
    end if;
  elsif p_base_version is null or current_event.version <> p_base_version then
    result := jsonb_build_object(
      'status', 'conflict', 'setup', private.event_setup_json(p_event_id), 'replayed', false
    );
  else
    if requested_version <> p_base_version + 1
      or (current_event.status <> 'upcoming' and (
        current_event.name is distinct from event_data->>'name'
        or current_event.scheduled_at is distinct from (event_data->>'scheduled_at')::timestamptz
        or current_event.event_type is distinct from event_data->>'event_type'
        or current_event.court_label is distinct from event_data->>'court_label'
      ))
    then
      raise exception 'Event setup is locked or version progression is invalid.' using errcode = '23514';
    end if;
    update public.events set
      name = event_data->>'name',
      scheduled_at = (event_data->>'scheduled_at')::timestamptz,
      event_type = event_data->>'event_type',
      status = requested_status,
      entry_fee_minor_units = nullif(event_data->>'entry_fee_minor_units','')::bigint,
      entry_fee_currency = event_data->>'entry_fee_currency',
      court_label = event_data->>'court_label',
      updated_at = (event_data->>'updated_at')::timestamptz,
      version = requested_version,
      deleted_at = nullif(event_data->>'deleted_at','')::timestamptz
    where id = p_event_id;
  end if;

  if result is null then
    for division_data in select value from jsonb_array_elements(p_payload->'divisions')
    loop
      if not (division_data ?& array[
          'id','event_id','name','tournament_format','created_at','updated_at','version','deleted_at'
        ])
        or (division_data->>'event_id')::uuid is distinct from p_event_id
        or coalesce(btrim(division_data->>'name'), '') = ''
        or (division_data->>'tournament_format' is not null and
            division_data->>'tournament_format' not in (
              'singleElimination','doubleElimination','singleRoundRobin','doubleRoundRobin'
            ))
      then
        raise exception 'Division setup values are invalid.' using errcode = '22023';
      end if;
      insert into public.event_divisions (
        id,event_id,name,tournament_format,created_at,updated_at,version,deleted_at
      ) values (
        (division_data->>'id')::uuid,p_event_id,division_data->>'name',
        division_data->>'tournament_format',
        (division_data->>'created_at')::timestamptz,
        (division_data->>'updated_at')::timestamptz,
        (division_data->>'version')::bigint,
        nullif(division_data->>'deleted_at','')::timestamptz
      ) on conflict (id) do update set
        name = excluded.name,
        tournament_format = excluded.tournament_format,
        updated_at = excluded.updated_at,
        version = excluded.version,
        deleted_at = excluded.deleted_at
      where public.event_divisions.event_id = excluded.event_id;
    end loop;

    if requested_status = 'inProgress' and exists (
      select 1 from public.event_divisions
      where event_id = p_event_id and deleted_at is null and tournament_format is null
    ) then
      raise exception 'Tournament formats must be configured before this event can begin.'
        using errcode = '23514';
    end if;
    result := jsonb_build_object(
      'status', 'accepted', 'setup', private.event_setup_json(p_event_id), 'replayed', false
    );
  end if;

  insert into private.event_setup_operation_receipts (
    operation_id,event_id,base_version,request_payload,result_payload,applied_by
  ) values (p_operation_id,p_event_id,p_base_version,p_payload,result,auth.uid());
  return result;
end;
$$;

revoke all on function public.apply_event_setup_operation(uuid,uuid,bigint,jsonb)
  from public, anon;
grant execute on function public.apply_event_setup_operation(uuid,uuid,bigint,jsonb)
  to authenticated;

create or replace function public.pull_event_setup_changes(
  p_after_updated_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns table (setup jsonb, updated_at timestamptz, event_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;
  if p_limit < 1 or p_limit > 50
    or ((p_after_updated_at is null) <> (p_after_id is null))
  then
    raise exception 'Event pull parameters are invalid.' using errcode = '22023';
  end if;
  return query
  select private.event_setup_json(e.id), e.updated_at, e.id
  from public.events e
  where p_after_updated_at is null or (e.updated_at,e.id) > (p_after_updated_at,p_after_id)
  order by e.updated_at,e.id
  limit p_limit;
end;
$$;

revoke all on function public.pull_event_setup_changes(timestamptz,uuid,integer)
  from public, anon;
grant execute on function public.pull_event_setup_changes(timestamptz,uuid,integer)
  to authenticated;
