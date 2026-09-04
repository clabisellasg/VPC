-- M14: fixed Single/Double Round Robin schedules, results, and derived placements.
create table public.round_robin_tournaments (
  id uuid primary key,
  division_id uuid not null references public.event_divisions(id) on delete restrict,
  plan jsonb not null check (jsonb_typeof(plan)='object'),
  match_ids jsonb not null check (jsonb_typeof(match_ids)='object'),
  version bigint not null default 0 check (version>=0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (updated_at>=created_at and (deleted_at is null or deleted_at>=updated_at))
);
create unique index round_robin_active_division on public.round_robin_tournaments(division_id) where deleted_at is null;
create index round_robin_pull_cursor on public.round_robin_tournaments(updated_at,id);

create table private.round_robin_receipts (
  operation_id uuid primary key,
  payload jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.round_robin_tournaments enable row level security;
revoke all on public.round_robin_tournaments from public,anon,authenticated;
grant select on public.round_robin_tournaments to anon,authenticated;
create policy round_robin_public_read on public.round_robin_tournaments
  for select to anon,authenticated using(deleted_at is null);

create function private.round_robin_json(p_division uuid,p_audit boolean default false)
returns jsonb language sql stable set search_path='' as $$
  select jsonb_build_object(
    'plan',rr.plan,'created_at',rr.created_at,'updated_at',rr.updated_at,
    'version',rr.version,'deleted_at',rr.deleted_at,
    'matches',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('planned_key',k.key)
      order by m.round_number,m.sequence_number,m.id)
      from jsonb_each_text(rr.match_ids) k join public.matches m on m.id=k.value::uuid),'[]'::jsonb),
    'revisions',case when p_audit then coalesce((select jsonb_agg(jsonb_build_object(
      'operation_id',r.operation_id,'previous',r.previous_result,'reason',r.reason,
      'recorded_at',r.recorded_at) order by r.recorded_at,r.operation_id)
      from public.match_result_revisions r join public.matches m on m.id=r.match_id
      where m.division_id=p_division),'[]'::jsonb) else '[]'::jsonb end)
  from public.round_robin_tournaments rr
  where rr.division_id=p_division and rr.deleted_at is null;
$$;

create function public.get_round_robin_context(p_event_id uuid,p_division_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare response jsonb;
begin
  select jsonb_build_object('event',to_jsonb(e),'division',to_jsonb(d),
    'teams',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object(
      'label',coalesce(t.display_label,(select string_agg(p.display_name,' / ' order by tm.player_id)
        from public.team_members tm join public.players p on p.id=tm.player_id
        where tm.team_id=t.id and tm.deleted_at is null)),
      'members',coalesce((select jsonb_agg(to_jsonb(tm) order by tm.player_id)
        from public.team_members tm where tm.team_id=t.id and tm.deleted_at is null),'[]'::jsonb)) order by t.id)
      from public.teams t where t.division_id=d.id and t.deleted_at is null),'[]'::jsonb),
    'tournament',private.round_robin_json(d.id,private.is_organizer())) into response
  from public.events e join public.event_divisions d on d.event_id=e.id
  where e.id=p_event_id and d.id=p_division_id and e.deleted_at is null and d.deleted_at is null;
  if response is null then raise exception 'Event division not found' using errcode='P0002'; end if;
  return response;
end $$;

create function public.apply_round_robin_operation(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  op uuid; eid uuid; did uuid; action text; expected bigint;
  event_row public.events%rowtype; division_row public.event_divisions%rowtype;
  tournament_row public.round_robin_tournaments%rowtype;
  receipt_row private.round_robin_receipts%rowtype; match_row public.matches%rowtype;
  stamp timestamptz:=clock_timestamp(); response jsonb; plan jsonb; planned jsonb:='[]';
  ordered uuid[]; slots uuid[]; rotated uuid[]; team_count int; slot_count int;
  rounds_per_leg int; leg_count int; leg_no int; round_in_leg int; round_no int;
  pair_no int; item jsonb; resting jsonb:='{}'; key text; match_id uuid;
  side_one uuid; side_two uuid; score_one int; score_two int; winner uuid; reason text;
  standing_row record;
begin
  if not private.is_organizer() then raise exception 'Organizer permission required' using errcode='42501'; end if;
  if jsonb_typeof(p_payload)<>'object' or exists(select 1 from jsonb_object_keys(p_payload) k where k not in
    ('operation_id','event_id','division_id','action','expected_version','event_version','division_version','created_at',
     'seed_order','team_versions','match_ids','match_key','score_one','score_two','reason','placement_ids')) then
    raise exception 'Invalid round-robin command' using errcode='23514';
  end if;
  op:=(p_payload->>'operation_id')::uuid; eid:=(p_payload->>'event_id')::uuid;
  did:=(p_payload->>'division_id')::uuid; action:=p_payload->>'action';
  expected:=(p_payload->>'expected_version')::bigint;
  if op is null or eid is null or did is null or expected is null or action not in ('generate','start','result','correct') then
    raise exception 'Incomplete round-robin command' using errcode='23514';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(op::text,14));
  select * into receipt_row from private.round_robin_receipts r where r.operation_id=op;
  if found then
    if receipt_row.payload<>p_payload then raise exception 'Operation identity reused with changed payload' using errcode='23505'; end if;
    return receipt_row.response;
  end if;
  select * into event_row from public.events e where e.id=eid and e.deleted_at is null for update;
  select * into division_row from public.event_divisions d
    where d.id=did and d.event_id=eid and d.deleted_at is null for update;
  if event_row.id is null or division_row.id is null or division_row.tournament_format not in ('singleRoundRobin','doubleRoundRobin') then
    raise exception 'A Round Robin division is required' using errcode='23514';
  end if;
  select * into tournament_row from public.round_robin_tournaments rr
    where rr.division_id=did and rr.deleted_at is null for update;
  if coalesce(tournament_row.version,-1)<>expected
    or event_row.version is distinct from (p_payload->>'event_version')::bigint
    or division_row.version is distinct from (p_payload->>'division_version')::bigint then
    raise exception 'Tournament version conflict' using errcode='40001';
  end if;

  if action='generate' then
    if event_row.status<>'registration' or exists(select 1 from public.matches m
      where m.division_id=did and m.deleted_at is null and
      (m.status in ('inProgress','completed') or m.side_one_score is not null or m.side_two_score is not null)) then
      raise exception 'Tournament generation is locked' using errcode='23514';
    end if;
    if tournament_row.id is null and exists(select 1 from public.matches m where m.division_id=did and m.deleted_at is null) then
      raise exception 'An active tournament structure already exists' using errcode='23514';
    end if;
    select array_agg(v::uuid order by ord) into ordered
      from jsonb_array_elements_text(p_payload->'seed_order') with ordinality as x(v,ord);
    team_count:=coalesce(array_length(ordered,1),0);
    if team_count<2 or team_count<>(select count(distinct tid) from unnest(ordered) tid)
      or team_count<>(select count(*) from public.teams t where t.division_id=did and t.deleted_at is null)
      or team_count<>(select count(*) from jsonb_each(p_payload->'team_versions'))
      or exists(select 1 from unnest(ordered) tid left join public.teams t on t.id=tid where
        t.id is null or t.division_id<>did or t.deleted_at is not null
        or t.version is distinct from (p_payload->'team_versions'->>t.id::text)::bigint
        or (select count(*) from public.team_members tm join public.players p on p.id=tm.player_id
          where tm.team_id=t.id and tm.deleted_at is null and p.deleted_at is null)<>2)
      or exists(select tm.player_id from public.team_members tm join public.teams t on t.id=tm.team_id
        where t.id=any(ordered) and tm.deleted_at is null group by tm.player_id having count(*)>1) then
      raise exception 'Teams are incomplete, changed or outside the division' using errcode='23514';
    end if;
    perform 1 from public.teams t where t.id=any(ordered) for update;
    slots:=ordered;
    if team_count%2=1 then slots:=array_append(slots,null::uuid); end if;
    slot_count:=array_length(slots,1); rounds_per_leg:=slot_count-1;
    leg_count:=case when division_row.tournament_format='doubleRoundRobin' then 2 else 1 end;
    for round_in_leg in 1..rounds_per_leg loop
      for pair_no in 1..(slot_count/2) loop
        side_one:=slots[pair_no]; side_two:=slots[slot_count+1-pair_no];
        if side_one is null or side_two is null then
          resting:=resting||jsonb_build_object(round_in_leg::text,coalesce(side_one,side_two));
        else
          key:='rr/r'||round_in_leg||'/m'||pair_no;
          planned:=planned||jsonb_build_array(jsonb_build_object('key',key,'eventId',eid,'divisionId',did,
            'sideOne',jsonb_build_object('teamId',side_one),'sideTwo',jsonb_build_object('teamId',side_two),
            'round',round_in_leg,'section','leg1','status','queued'));
        end if;
      end loop;
      rotated:=array[slots[1],slots[slot_count]];
      if slot_count>2 then rotated:=rotated||slots[2:slot_count-1]; end if;
      slots:=rotated;
    end loop;
    if leg_count=2 then
      for item in select value from jsonb_array_elements(planned) loop
        round_no:=(item->>'round')::int+rounds_per_leg;
        key:='rr/r'||round_no||'/m'||split_part(item->>'key','/m',2);
        planned:=planned||jsonb_build_array(jsonb_build_object('key',key,'eventId',eid,'divisionId',did,
          'sideOne',item->'sideTwo','sideTwo',item->'sideOne','round',round_no,'section','leg2','status','queued'));
      end loop;
      for round_in_leg in 1..rounds_per_leg loop
        if resting ? (round_in_leg::text) then
          resting:=resting||jsonb_build_object(
            (round_in_leg+rounds_per_leg)::text,resting->(round_in_leg::text));
        end if;
      end loop;
    end if;
    if jsonb_array_length(planned)<>team_count*(team_count-1)/2*leg_count
      or (select count(*) from jsonb_each(p_payload->'match_ids'))<>jsonb_array_length(planned)
      or (select count(distinct v) from jsonb_each_text(p_payload->'match_ids') x(k,v))<>jsonb_array_length(planned) then
      raise exception 'Invalid round-robin match identities' using errcode='23514';
    end if;
    update public.matches set deleted_at=stamp,updated_at=stamp,version=version+1
      where division_id=did and deleted_at is null;
    update public.round_robin_tournaments set deleted_at=stamp,updated_at=stamp where id=tournament_row.id;
    for item in select value from jsonb_array_elements(planned) loop
      match_id:=(p_payload->'match_ids'->>(item->>'key'))::uuid;
      if match_id is null then raise exception 'Missing planned match identity' using errcode='23514'; end if;
      insert into public.matches(id,division_id,side_one_team_id,side_two_team_id,status,round_number,sequence_number,created_at,updated_at,version)
      values(match_id,did,(item->'sideOne'->>'teamId')::uuid,(item->'sideTwo'->>'teamId')::uuid,'queued',
        (item->>'round')::int,split_part(item->>'key','/m',2)::int,stamp,stamp,0);
    end loop;
    plan:=jsonb_build_object('eventId',eid,'divisionId',did,'format',division_row.tournament_format,
      'matches',planned,'metadata',jsonb_build_object('seedOrder',to_jsonb(ordered)::text,
      'roundsPerLeg',rounds_per_leg::text,'legs',leg_count::text,'restingByRound',resting::text));
    insert into public.round_robin_tournaments(id,division_id,plan,match_ids,version,created_at,updated_at)
      values(op,did,plan,p_payload->'match_ids',expected+1,coalesce(tournament_row.created_at,stamp),stamp);
  else
    if event_row.status<>'inProgress' or tournament_row.id is null then
      raise exception 'Event must be In Progress' using errcode='23514';
    end if;
    team_count:=jsonb_array_length((tournament_row.plan->'metadata'->>'seedOrder')::jsonb);
    match_id:=(tournament_row.match_ids->>(p_payload->>'match_key'))::uuid;
    select * into match_row from public.matches m
      where m.id=match_id and m.division_id=did and m.deleted_at is null for update;
    if match_row.id is null or match_row.side_one_team_id is null or match_row.side_two_team_id is null then
      raise exception 'Round-robin match is unavailable' using errcode='23514';
    end if;
    if action='start' then
      if match_row.status<>'queued' then raise exception 'Only a ready match may start' using errcode='23514'; end if;
      update public.matches set status='inProgress',version=version+1,updated_at=stamp where id=match_id;
    else
      score_one:=(p_payload->>'score_one')::int; score_two:=(p_payload->>'score_two')::int;
      if score_one is null or score_two is null or score_one<0 or score_two<0 or not (
        (greatest(score_one,score_two)=11 and least(score_one,score_two)<=9) or
        (least(score_one,score_two)>=10 and abs(score_one::bigint-score_two::bigint)=2)) then
        raise exception 'Invalid final score' using errcode='23514';
      end if;
      winner:=case when score_one>score_two then match_row.side_one_team_id else match_row.side_two_team_id end;
      if action='correct' then
        reason:=btrim(p_payload->>'reason');
        if match_row.status<>'completed' or reason is null or reason='' then
          raise exception 'Completed result and correction reason required' using errcode='23514';
        end if;
        insert into public.match_result_revisions(operation_id,match_id,previous_result,reason,recorded_at)
          values(op,match_id,to_jsonb(match_row),reason,stamp);
        perform set_config('vpc.result_correction',op::text,true);
      elsif action<>'result' or match_row.status<>'inProgress' then
        raise exception 'Start the ready match before recording its result' using errcode='23514';
      end if;
      update public.matches set status='completed',side_one_score=score_one,side_two_score=score_two,
        winner_team_id=winner,updated_at=stamp,version=version+1 where id=match_id;

      if not exists(select 1 from public.matches m where m.division_id=did and m.deleted_at is null and m.status<>'completed') then
        if (select count(*) from jsonb_each(p_payload->'placement_ids'))<>team_count
          or (select count(distinct value) from jsonb_each_text(p_payload->'placement_ids'))<>team_count then
          raise exception 'Every final standing requires a unique placement identity' using errcode='23514';
        end if;
        update public.division_placements set deleted_at=stamp,updated_at=stamp,version=version+1
          where division_id=did and deleted_at is null;
        for standing_row in
          with seed as (
            select v::uuid team_id,ord::int seed
              from jsonb_array_elements_text((tournament_row.plan->'metadata'->>'seedOrder')::jsonb)
              with ordinality x(v,ord)
          ), base as (
            select s.team_id,s.seed,
              count(m.id) filter(where m.status='completed')::int played,
              count(m.id) filter(where m.status='completed' and m.winner_team_id=s.team_id)::int wins,
              coalesce(sum(case when m.status='completed' and m.side_one_team_id=s.team_id then m.side_one_score when m.status='completed' then m.side_two_score end),0)::int points_for,
              coalesce(sum(case when m.status='completed' and m.side_one_team_id=s.team_id then m.side_two_score when m.status='completed' then m.side_one_score end),0)::int points_against
            from seed s left join public.matches m on m.division_id=did and m.deleted_at is null
              and s.team_id in(m.side_one_team_id,m.side_two_team_id) group by s.team_id,s.seed
          ), mini_wins as (
            select b.*,coalesce((select count(*) from public.matches m join base o on o.team_id=
              case when m.side_one_team_id=b.team_id then m.side_two_team_id else m.side_one_team_id end
              where m.division_id=did and m.deleted_at is null and m.status='completed'
                and b.team_id in(m.side_one_team_id,m.side_two_team_id) and o.wins=b.wins and m.winner_team_id=b.team_id),0)::int mini_wins
            from base b
          ), mini_diff as (
            select b.*,coalesce((select sum(case when m.side_one_team_id=b.team_id then m.side_one_score-m.side_two_score else m.side_two_score-m.side_one_score end)
              from public.matches m join mini_wins o on o.team_id=case when m.side_one_team_id=b.team_id then m.side_two_team_id else m.side_one_team_id end
              where m.division_id=did and m.deleted_at is null and m.status='completed'
                and b.team_id in(m.side_one_team_id,m.side_two_team_id) and o.wins=b.wins and o.mini_wins=b.mini_wins),0)::int mini_diff
            from mini_wins b
          )
          select m.*,row_number() over(order by wins desc,mini_wins desc,mini_diff desc,
            (points_for-points_against) desc,points_for desc,seed)::int position from mini_diff m
        loop
          insert into public.division_placements(id,division_id,team_id,position,created_at,updated_at)
          values((p_payload->'placement_ids'->>standing_row.position::text)::uuid,did,
            standing_row.team_id,standing_row.position,stamp,stamp);
        end loop;
      end if;
    end if;
    update public.round_robin_tournaments set version=version+1,updated_at=stamp where id=tournament_row.id;
  end if;
  response:=public.get_round_robin_context(eid,did);
  insert into private.round_robin_receipts(operation_id,payload,response) values(op,p_payload,response);
  return response;
end $$;

create function public.pull_round_robin_changes(
  p_after_updated_at timestamptz default null,p_after_id uuid default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_organizer() then raise exception 'Organizer permission required' using errcode='42501'; end if;
  if p_limit is null or p_limit<1 or p_limit>50 or (p_after_updated_at is null)<>(p_after_id is null) then
    raise exception 'Invalid bounded cursor' using errcode='23514';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',rr.id,'updated_at',rr.updated_at,'event_id',d.event_id,'division_id',d.id,
    'context',public.get_round_robin_context(d.event_id,d.id)) order by rr.updated_at,rr.id)
    from (select * from public.round_robin_tournaments
      where p_after_updated_at is null or (updated_at,id)>(p_after_updated_at,p_after_id)
      order by updated_at,id limit p_limit) rr join public.event_divisions d on d.id=rr.division_id),'[]'::jsonb);
end $$;

revoke all on function private.round_robin_json(uuid,boolean),
  public.get_round_robin_context(uuid,uuid),public.apply_round_robin_operation(jsonb),
  public.pull_round_robin_changes(timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function public.get_round_robin_context(uuid,uuid) to anon,authenticated;
grant execute on function public.apply_round_robin_operation(jsonb),
  public.pull_round_robin_changes(timestamptz,uuid,integer) to authenticated;

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename='round_robin_tournaments') then
    alter publication supabase_realtime add table public.round_robin_tournaments;
  end if;
end $$;
