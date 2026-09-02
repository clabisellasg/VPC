-- M11 community skill and bounded team-formation aggregate.
alter table public.players add column skill_level smallint;
alter table public.players add constraint players_skill_level_check
  check (skill_level is null or skill_level between 1 and 5);

drop function public.search_public_players(text, text, uuid, integer);
create function public.search_public_players(
  p_query text default '', p_after_name text default null,
  p_after_id uuid default null, p_limit integer default 50
)
returns table (
  id uuid, display_name text, skill_level smallint, created_at timestamptz,
  updated_at timestamptz, version bigint, deleted_at timestamptz,
  normalized_name text, has_more boolean
)
language plpgsql stable security invoker set search_path = '' as $$
declare
  normalized_query text := lower(regexp_replace(btrim(coalesce(p_query, '')), '[[:space:]]+', ' ', 'g'));
  normalized_after text := case when p_after_name is null then null else lower(regexp_replace(btrim(p_after_name), '[[:space:]]+', ' ', 'g')) end;
begin
  if p_limit is null or p_limit < 1 or p_limit > 50 then raise exception 'Player directory limit must be between 1 and 50.' using errcode = '22023'; end if;
  if (p_after_name is null) <> (p_after_id is null) then raise exception 'Player directory cursor fields must be supplied together.' using errcode = '22023'; end if;
  return query
  with eligible as (
    select p.id, p.display_name, p.skill_level, p.created_at, p.updated_at, p.version, p.deleted_at,
      lower(regexp_replace(btrim(p.display_name), '[[:space:]]+', ' ', 'g')) as normalized_name
    from public.players p where p.deleted_at is null
  ), ordered as (
    select e.* from eligible e where position(normalized_query in e.normalized_name) > 0
      and (normalized_after is null or (e.normalized_name, e.id) > (normalized_after, p_after_id))
    order by e.normalized_name, e.id limit p_limit + 1
  ), numbered as (
    select o.*, row_number() over (order by o.normalized_name, o.id) row_number,
      count(*) over () > p_limit has_more from ordered o
  )
  select n.id,n.display_name,n.skill_level,n.created_at,n.updated_at,n.version,n.deleted_at,n.normalized_name,n.has_more
  from numbered n where n.row_number <= p_limit order by n.normalized_name,n.id;
end $$;
revoke all on function public.search_public_players(text,text,uuid,integer) from public;
grant execute on function public.search_public_players(text,text,uuid,integer) to anon, authenticated;

-- Replace player synchronization while retaining its stable signature. Nullable
-- skill_level is now part of the fixed payload and authoritative result.
create or replace function public.apply_player_sync_operation(
  p_operation_id uuid, p_entity_id uuid, p_operation_kind text,
  p_base_version bigint, p_payload jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  receipt private.player_sync_operation_receipts%rowtype;
  current_player public.players%rowtype;
  accepted public.players%rowtype;
  requested_version bigint;
  created timestamp with time zone;
  updated timestamp with time zone;
  deleted timestamp with time zone;
  skill smallint;
  result jsonb;
begin
  if not private.is_organizer() then raise exception 'Organizer permission is required.' using errcode='42501'; end if;
  select * into receipt from private.player_sync_operation_receipts where operation_id=p_operation_id;
  if found then
    if receipt.entity_id is distinct from p_entity_id or receipt.operation_kind is distinct from p_operation_kind or receipt.base_version is distinct from p_base_version or receipt.request_payload is distinct from p_payload then
      raise exception 'Operation ID was reused with different content.' using errcode='22023';
    end if;
    return receipt.result_payload || jsonb_build_object('replayed',true);
  end if;
  if p_operation_kind not in ('upsert','tombstone') or p_payload is null or jsonb_typeof(p_payload)<>'object'
    or not (p_payload ?& array['id','display_name','skill_level','created_at','updated_at','version','deleted_at'])
    or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('id','display_name','skill_level','created_at','updated_at','version','deleted_at'))
    or (p_payload->>'id')::uuid is distinct from p_entity_id or btrim(coalesce(p_payload->>'display_name',''))=''
    or jsonb_typeof(p_payload->'skill_level') not in ('number','null')
  then raise exception 'Player synchronization payload is invalid.' using errcode='22023'; end if;
  skill := case when p_payload->'skill_level'='null'::jsonb then null else (p_payload->>'skill_level')::smallint end;
  if skill is not null and (skill<1 or skill>5) then raise exception 'Player skill must be from 1 to 5.' using errcode='22023'; end if;
  requested_version := (p_payload->>'version')::bigint;
  created := (p_payload->>'created_at')::timestamptz;
  updated := (p_payload->>'updated_at')::timestamptz;
  deleted := case when p_payload->'deleted_at'='null'::jsonb then null else (p_payload->>'deleted_at')::timestamptz end;
  select * into current_player from public.players where id=p_entity_id for update;
  if not found then
    if p_base_version is not null or requested_version<>0 then result:=jsonb_build_object('status','conflict','replayed',false,'player',null);
    else insert into public.players(id,display_name,skill_level,created_at,updated_at,version,deleted_at)
      values(p_entity_id,p_payload->>'display_name',skill,created,updated,requested_version,deleted) returning * into accepted;
      result:=jsonb_build_object('status','accepted','replayed',false,'player',to_jsonb(accepted)); end if;
  elsif p_base_version is null or current_player.version<>p_base_version then
    result:=jsonb_build_object('status','conflict','replayed',false,'player',to_jsonb(current_player));
  else
    if requested_version<>p_base_version+1 or created is distinct from current_player.created_at then raise exception 'Player synchronization version progression is invalid.' using errcode='22023'; end if;
    update public.players set display_name=p_payload->>'display_name',skill_level=skill,updated_at=updated,version=requested_version,deleted_at=deleted where id=p_entity_id returning * into accepted;
    result:=jsonb_build_object('status','accepted','replayed',false,'player',to_jsonb(accepted));
  end if;
  insert into private.player_sync_operation_receipts(operation_id,entity_id,operation_kind,base_version,request_payload,result_payload,applied_by)
    values(p_operation_id,p_entity_id,p_operation_kind,p_base_version,p_payload,result,auth.uid());
  return result;
end $$;

drop function public.pull_player_sync_changes(timestamp with time zone, uuid, integer);
create function public.pull_player_sync_changes(p_after_updated_at timestamptz default null,p_after_id uuid default null,p_limit integer default 100)
returns table(id uuid,display_name text,skill_level smallint,created_at timestamptz,updated_at timestamptz,version bigint,deleted_at timestamptz)
language plpgsql stable security definer set search_path='' as $$ begin
  if not private.is_organizer() then raise exception 'Organizer permission is required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>100 then raise exception 'Pull limit must be between 1 and 100.' using errcode='22023'; end if;
  return query select p.id,p.display_name,p.skill_level,p.created_at,p.updated_at,p.version,p.deleted_at from public.players p
    where p_after_updated_at is null or (p.updated_at,p.id)>(p_after_updated_at,p_after_id) order by p.updated_at,p.id limit p_limit;
end $$;
revoke all on function public.pull_player_sync_changes(timestamptz,uuid,integer) from public,anon;
grant execute on function public.pull_player_sync_changes(timestamptz,uuid,integer) to authenticated;

create table private.team_formation_operation_receipts(
  operation_id uuid primary key, event_id uuid not null, division_id uuid not null,
  request_payload jsonb not null, result_payload jsonb not null,
  applied_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
revoke all on private.team_formation_operation_receipts from public,anon,authenticated;

create or replace function private.enforce_team_member_eligibility()
returns trigger language plpgsql security definer set search_path='' as $$
declare target_division uuid; target_event uuid; lifecycle text;
begin
  select t.division_id,d.event_id,e.status into target_division,target_event,lifecycle
  from public.teams t join public.event_divisions d on d.id=t.division_id
  join public.events e on e.id=d.event_id where t.id=new.team_id and t.deleted_at is null and d.deleted_at is null;
  if lifecycle is distinct from 'registration' then raise exception 'Team formation is locked.' using errcode='23514'; end if;
  if not exists(select 1 from public.event_participants ep join public.division_participants dp on dp.event_participant_id=ep.id
    where ep.event_id=target_event and ep.player_id=new.player_id and ep.check_in_status='checkedIn' and ep.deleted_at is null
      and dp.division_id=target_division and dp.deleted_at is null) then raise exception 'Player is not eligible.' using errcode='23514'; end if;
  if exists(select 1 from public.team_members tm join public.teams t on t.id=tm.team_id
    where tm.player_id=new.player_id and tm.deleted_at is null and t.deleted_at is null and t.division_id=target_division and tm.team_id<>new.team_id)
  then raise exception 'Player already belongs to a team in this division.' using errcode='23505'; end if;
  return new;
end $$;
drop trigger if exists team_members_eligibility_guard on public.team_members;
create trigger team_members_eligibility_guard before insert or update of team_id,player_id,deleted_at on public.team_members
for each row when (new.deleted_at is null) execute function private.enforce_team_member_eligibility();

create or replace function public.get_team_formation_snapshot(p_event_id uuid,p_division_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.is_organizer() then raise exception 'Organizer permission is required.' using errcode='42501'; end if;
  if not exists(select 1 from public.event_divisions where id=p_division_id and event_id=p_event_id and deleted_at is null) then raise exception 'Division not found.' using errcode='P0002'; end if;
  select jsonb_build_object(
    'event_id',e.id,'division_id',p_division_id,'event_status',e.status,
    'eligible_players',coalesce((select jsonb_agg(jsonb_build_object('player_id',p.id,'display_name',p.display_name,'skill_level',p.skill_level,'paid',coalesce(pay.status='paid',false)) order by p.id)
      from public.event_participants ep join public.division_participants dp on dp.event_participant_id=ep.id and dp.division_id=p_division_id and dp.deleted_at is null
      join public.players p on p.id=ep.player_id and p.deleted_at is null
      left join public.participant_payments pay on pay.event_participant_id=ep.id and pay.division_id is null and pay.deleted_at is null
      where ep.event_id=p_event_id and ep.check_in_status='checkedIn' and ep.deleted_at is null),'[]'::jsonb),
    'teams',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'method',t.formation_method,'version',t.version,'updated_at',t.updated_at,
      'player_ids',(select jsonb_agg(tm.player_id order by tm.player_id) from public.team_members tm where tm.team_id=t.id and tm.deleted_at is null)) order by t.id)
      from public.teams t where t.division_id=p_division_id and t.deleted_at is null),'[]'::jsonb)
  ) into result from public.events e where e.id=p_event_id and e.deleted_at is null;
  return result;
end $$;
revoke all on function public.get_team_formation_snapshot(uuid,uuid) from public,anon;
grant execute on function public.get_team_formation_snapshot(uuid,uuid) to authenticated;

create or replace function public.apply_team_formation_operation(p_operation_id uuid,p_event_id uuid,p_division_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare receipt private.team_formation_operation_receipts%rowtype; item jsonb; member jsonb; now_utc timestamptz:=now(); result jsonb; current_base jsonb;
begin
  if not private.is_organizer() then raise exception 'Organizer permission is required.' using errcode='42501'; end if;
  select * into receipt from private.team_formation_operation_receipts where operation_id=p_operation_id;
  if found then if receipt.event_id is distinct from p_event_id or receipt.division_id is distinct from p_division_id or receipt.request_payload is distinct from p_payload then raise exception 'Operation ID was reused with different content.' using errcode='22023'; end if; return receipt.result_payload||jsonb_build_object('replayed',true); end if;
  if jsonb_typeof(p_payload)<>'object' or not(p_payload ?& array['event_id','division_id','teams','base_teams'])
    or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('event_id','division_id','teams','base_teams'))
    or (p_payload->>'event_id')::uuid is distinct from p_event_id or (p_payload->>'division_id')::uuid is distinct from p_division_id
    or jsonb_typeof(p_payload->'teams')<>'array' or jsonb_typeof(p_payload->'base_teams')<>'object' then raise exception 'Team payload is invalid.' using errcode='22023'; end if;
  if not exists(select 1 from public.event_divisions d join public.events e on e.id=d.event_id where d.id=p_division_id and d.event_id=p_event_id and d.deleted_at is null and e.deleted_at is null and e.status='registration') then raise exception 'Team formation is locked.' using errcode='23514'; end if;
  select coalesce(jsonb_object_agg(id::text,version),'{}'::jsonb) into current_base from public.teams where division_id=p_division_id and deleted_at is null;
  if current_base is distinct from p_payload->'base_teams' then raise exception 'Team formation version conflict.' using errcode='40001'; end if;
  for item in select value from jsonb_array_elements(p_payload->'teams') loop
    if jsonb_typeof(item)<>'object' or not(item ?& array['id','method','player_ids']) or item->>'method' not in ('manual','random','balanced') or jsonb_array_length(item->'player_ids')<>2 or (item->'player_ids'->>0)=(item->'player_ids'->>1) then raise exception 'Complete teams require two different players.' using errcode='22023'; end if;
  end loop;
  update public.team_members set deleted_at=now_utc,updated_at=now_utc,version=version+1 where deleted_at is null and team_id in(select id from public.teams where division_id=p_division_id and deleted_at is null);
  update public.teams set deleted_at=now_utc,updated_at=now_utc,version=version+1 where division_id=p_division_id and deleted_at is null;
  for item in select value from jsonb_array_elements(p_payload->'teams') loop
    insert into public.teams(id,division_id,formation_method,created_at,updated_at,version) values((item->>'id')::uuid,p_division_id,item->>'method',now_utc,now_utc,0);
    for member in select value from jsonb_array_elements(item->'player_ids') loop
      insert into public.team_members(team_id,player_id,created_at,updated_at,version) values((item->>'id')::uuid,(member#>>'{}')::uuid,now_utc,now_utc,0);
    end loop;
  end loop;
  result:=jsonb_build_object('status','accepted','replayed',false,'snapshot',public.get_team_formation_snapshot(p_event_id,p_division_id));
  insert into private.team_formation_operation_receipts(operation_id,event_id,division_id,request_payload,result_payload,applied_by) values(p_operation_id,p_event_id,p_division_id,p_payload,result,auth.uid());
  return result;
end $$;
revoke all on function public.apply_team_formation_operation(uuid,uuid,uuid,jsonb) from public,anon;
grant execute on function public.apply_team_formation_operation(uuid,uuid,uuid,jsonb) to authenticated;

create or replace function public.pull_team_formation_changes(p_after_updated_at timestamptz default null,p_after_division_id uuid default null,p_limit integer default 50)
returns table(division_id uuid,updated_at timestamptz,snapshot jsonb) language plpgsql stable security definer set search_path='' as $$ begin
  if not private.is_organizer() then raise exception 'Organizer permission is required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>50 then raise exception 'Pull limit must be between 1 and 50.' using errcode='22023'; end if;
  return query with changed as(select t.division_id,max(greatest(t.updated_at,coalesce(tm.updated_at,t.updated_at))) updated_at
    from public.teams t left join public.team_members tm on tm.team_id=t.id group by t.division_id)
    select c.division_id,c.updated_at,public.get_team_formation_snapshot(d.event_id,c.division_id) from changed c join public.event_divisions d on d.id=c.division_id
    where p_after_updated_at is null or(c.updated_at,c.division_id)>(p_after_updated_at,p_after_division_id) order by c.updated_at,c.division_id limit p_limit;
end $$;
revoke all on function public.pull_team_formation_changes(timestamptz,uuid,integer) from public,anon;
grant execute on function public.pull_team_formation_changes(timestamptz,uuid,integer) to authenticated;
