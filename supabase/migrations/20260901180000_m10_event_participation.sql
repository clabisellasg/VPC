create table private.participation_operation_receipts (
  operation_id uuid primary key,
  event_participant_id uuid not null references public.event_participants (id) on delete restrict,
  base_version bigint,
  request_payload jsonb not null,
  result_payload jsonb not null,
  applied_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint participation_receipt_base_version_check
    check (base_version is null or base_version >= 0)
);

revoke all on table private.participation_operation_receipts
  from public, anon, authenticated;

create or replace function private.participation_json(p_participant_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'participant', to_jsonb(ep),
    'divisions', coalesce((
      select jsonb_agg(to_jsonb(dp) order by dp.id)
      from public.division_participants dp
      where dp.event_participant_id = ep.id
    ), '[]'::jsonb),
    'payment', (
      select to_jsonb(pp)
      from public.participant_payments pp
      where pp.event_participant_id = ep.id and pp.division_id is null
      order by pp.created_at, pp.id limit 1
    ),
    'player_display_name', p.display_name
  )
  from public.event_participants ep
  join public.players p on p.id = ep.player_id
  where ep.id = p_participant_id;
$$;

create or replace function public.apply_participation_operation(
  p_operation_id uuid,
  p_event_participant_id uuid,
  p_base_version bigint,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior private.participation_operation_receipts%rowtype;
  current_participant public.event_participants%rowtype;
  event_status text;
  participant_data jsonb;
  payment_data jsonb;
  division_data jsonb;
  requested_version bigint;
  structural_change boolean := false;
  result jsonb;
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;
  if p_operation_id is null or p_event_participant_id is null
    or p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or not (p_payload ?& array['participant','divisions','payment','player_display_name'])
    or exists (select 1 from jsonb_object_keys(p_payload) k
               where k not in ('participant','divisions','payment','player_display_name'))
    or jsonb_typeof(p_payload->'participant') <> 'object'
    or jsonb_typeof(p_payload->'divisions') <> 'array'
    or jsonb_typeof(p_payload->'payment') <> 'object'
  then
    raise exception 'Participation payload is invalid.' using errcode = '22023';
  end if;

  select * into prior from private.participation_operation_receipts
  where operation_id = p_operation_id;
  if found then
    if prior.event_participant_id is distinct from p_event_participant_id
      or prior.base_version is distinct from p_base_version
      or prior.request_payload is distinct from p_payload
    then
      raise exception 'Operation ID was reused with different content.' using errcode = '22023';
    end if;
    return prior.result_payload || jsonb_build_object('replayed', true);
  end if;

  participant_data := p_payload->'participant';
  payment_data := p_payload->'payment';
  if (participant_data->>'id')::uuid is distinct from p_event_participant_id
    or participant_data->>'check_in_status' not in ('notPresent','checkedIn')
    or not (participant_data->>'version' ~ '^[0-9]+$')
    or (payment_data->>'event_participant_id')::uuid is distinct from p_event_participant_id
    or payment_data->>'division_id' is not null
    or payment_data->>'status' not in ('unpaid','paid')
    or not (payment_data->>'version' ~ '^[0-9]+$')
    or not exists (
      select 1 from public.players p
      where p.id = (participant_data->>'player_id')::uuid and p.deleted_at is null
    )
  then
    raise exception 'Participation values are invalid.' using errcode = '22023';
  end if;

  select status into event_status from public.events
  where id = (participant_data->>'event_id')::uuid and deleted_at is null;
  if event_status is null then
    raise exception 'The event is unavailable.' using errcode = '23514';
  end if;
  requested_version := (participant_data->>'version')::bigint;
  select * into current_participant from public.event_participants
  where id = p_event_participant_id for update;

  if not found then
    if p_base_version is not null or requested_version <> 0 or event_status <> 'registration' then
      result := jsonb_build_object('status','conflict','participation',null,'replayed',false);
    else
      insert into public.event_participants (
        id,event_id,player_id,check_in_status,created_at,updated_at,version,deleted_at
      ) values (
        p_event_participant_id,(participant_data->>'event_id')::uuid,
        (participant_data->>'player_id')::uuid,participant_data->>'check_in_status',
        (participant_data->>'created_at')::timestamptz,
        (participant_data->>'updated_at')::timestamptz,requested_version,
        nullif(participant_data->>'deleted_at','')::timestamptz
      );
    end if;
  elsif p_base_version is null or current_participant.version <> p_base_version then
    result := jsonb_build_object(
      'status','conflict','participation',private.participation_json(p_event_participant_id),'replayed',false
    );
  else
    if requested_version <> p_base_version + 1
      or current_participant.event_id is distinct from (participant_data->>'event_id')::uuid
      or current_participant.player_id is distinct from (participant_data->>'player_id')::uuid
    then
      raise exception 'Participant identity or version is invalid.' using errcode = '23514';
    end if;
    structural_change := current_participant.deleted_at is distinct from
      nullif(participant_data->>'deleted_at','')::timestamptz;
    if event_status <> 'registration' and structural_change then
      raise exception 'Event lifecycle locks roster structure.' using errcode = '23514';
    end if;
    if event_status in ('upcoming','completed','archived') then
      raise exception 'Event lifecycle does not permit participation changes.' using errcode = '23514';
    end if;
    update public.event_participants set
      check_in_status = participant_data->>'check_in_status',
      updated_at = (participant_data->>'updated_at')::timestamptz,
      version = requested_version,
      deleted_at = nullif(participant_data->>'deleted_at','')::timestamptz
    where id = p_event_participant_id;
  end if;

  if result is null then
    if event_status <> 'registration' and exists (
      select 1
      from jsonb_array_elements(p_payload->'divisions') d
      full join public.division_participants old
        on old.id = (d.value->>'id')::uuid
       and old.event_participant_id = p_event_participant_id
      where coalesce(old.division_id::text,'') is distinct from coalesce(d.value->>'division_id','')
         or coalesce(old.deleted_at::text,'') is distinct from coalesce(d.value->>'deleted_at','')
    ) then
      raise exception 'Event lifecycle locks division assignments.' using errcode = '23514';
    end if;
    for division_data in select value from jsonb_array_elements(p_payload->'divisions') loop
      if (division_data->>'event_participant_id')::uuid is distinct from p_event_participant_id
        or not exists (
          select 1 from public.event_divisions d
          where d.id = (division_data->>'division_id')::uuid
            and d.event_id = (participant_data->>'event_id')::uuid
            and (d.deleted_at is null or division_data->>'deleted_at' is not null)
        )
      then
        raise exception 'Division assignment is invalid.' using errcode = '23514';
      end if;
      insert into public.division_participants (
        id,division_id,event_participant_id,created_at,updated_at,version,deleted_at
      ) values (
        (division_data->>'id')::uuid,(division_data->>'division_id')::uuid,
        p_event_participant_id,(division_data->>'created_at')::timestamptz,
        (division_data->>'updated_at')::timestamptz,(division_data->>'version')::bigint,
        nullif(division_data->>'deleted_at','')::timestamptz
      ) on conflict (id) do update set
        division_id=excluded.division_id,updated_at=excluded.updated_at,
        version=excluded.version,deleted_at=excluded.deleted_at
      where public.division_participants.event_participant_id=excluded.event_participant_id;
    end loop;
    insert into public.participant_payments (
      id,event_participant_id,division_id,status,created_at,updated_at,version,deleted_at
    ) values (
      (payment_data->>'id')::uuid,p_event_participant_id,null,payment_data->>'status',
      (payment_data->>'created_at')::timestamptz,
      (payment_data->>'updated_at')::timestamptz,(payment_data->>'version')::bigint,
      nullif(payment_data->>'deleted_at','')::timestamptz
    ) on conflict (id) do update set
      status=excluded.status,updated_at=excluded.updated_at,
      version=excluded.version,deleted_at=excluded.deleted_at
    where public.participant_payments.event_participant_id=excluded.event_participant_id
      and public.participant_payments.division_id is null;
    result := jsonb_build_object(
      'status','accepted','participation',private.participation_json(p_event_participant_id),'replayed',false
    );
  end if;

  insert into private.participation_operation_receipts (
    operation_id,event_participant_id,base_version,request_payload,result_payload,applied_by
  ) values (p_operation_id,p_event_participant_id,p_base_version,p_payload,result,auth.uid());
  return result;
end;
$$;

revoke all on function public.apply_participation_operation(uuid,uuid,bigint,jsonb)
  from public, anon;
grant execute on function public.apply_participation_operation(uuid,uuid,bigint,jsonb)
  to authenticated;

create or replace function public.pull_participation_changes(
  p_after_updated_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns table (participation jsonb, updated_at timestamptz, event_participant_id uuid)
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
    or ((p_after_updated_at is null) <> (p_after_id is null)) then
    raise exception 'Participation pull parameters are invalid.' using errcode = '22023';
  end if;
  return query
  select private.participation_json(ep.id),ep.updated_at,ep.id
  from public.event_participants ep
  where p_after_updated_at is null or (ep.updated_at,ep.id) > (p_after_updated_at,p_after_id)
  order by ep.updated_at,ep.id
  limit p_limit;
end;
$$;

revoke all on function public.pull_participation_changes(timestamptz,uuid,integer)
  from public, anon;
grant execute on function public.pull_participation_changes(timestamptz,uuid,integer)
  to authenticated;
