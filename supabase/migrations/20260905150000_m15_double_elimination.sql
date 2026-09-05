-- M15: deterministic Double Elimination brackets with conditional reset final.
create table public.double_elimination_brackets (
  id uuid primary key,
  division_id uuid not null references public.event_divisions(id) on delete restrict,
  plan jsonb not null check (jsonb_typeof(plan)='object'),
  match_ids jsonb not null check (jsonb_typeof(match_ids)='object'),
  version bigint not null check(version>=0),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  check(updated_at>=created_at and (deleted_at is null or deleted_at>=updated_at))
);
create unique index double_elimination_active_division
  on public.double_elimination_brackets(division_id) where deleted_at is null;
create index double_elimination_pull_cursor
  on public.double_elimination_brackets(updated_at,id);

create table private.double_elimination_receipts (
  operation_id uuid primary key,
  payload jsonb not null,
  response jsonb not null,
  recorded_at timestamptz not null default clock_timestamp()
);

alter table public.double_elimination_brackets enable row level security;
revoke all on public.double_elimination_brackets from public,anon,authenticated;
grant select on public.double_elimination_brackets to anon,authenticated;
create policy double_elimination_public_read on public.double_elimination_brackets
  for select to anon,authenticated using(deleted_at is null);

create function private.double_elimination_json(p_division uuid,p_audit boolean default false)
returns jsonb language sql stable set search_path='' as $$
  select jsonb_build_object(
    'plan',b.plan,'created_at',b.created_at,'updated_at',b.updated_at,
    'version',b.version,'deleted_at',b.deleted_at,
    'matches',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('planned_key',k.key)
      order by m.sequence_number,m.id)
      from jsonb_each_text(b.match_ids) k join public.matches m on m.id=k.value::uuid
      where m.deleted_at is null),'[]'::jsonb),
    'revisions',case when p_audit then coalesce((select jsonb_agg(jsonb_build_object(
      'operation_id',r.operation_id,'previous',r.previous_result,'reason',r.reason,
      'recorded_at',r.recorded_at) order by r.recorded_at,r.operation_id)
      from public.match_result_revisions r join public.matches m on m.id=r.match_id
      where m.division_id=p_division),'[]'::jsonb) else '[]'::jsonb end)
  from public.double_elimination_brackets b
  where b.division_id=p_division and b.deleted_at is null;
$$;

create function public.get_double_elimination_context(p_event_id uuid,p_division_id uuid)
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
    'bracket',private.double_elimination_json(d.id,private.is_organizer())) into response
  from public.events e join public.event_divisions d on d.event_id=e.id
  where e.id=p_event_id and d.id=p_division_id and e.deleted_at is null and d.deleted_at is null;
  if response is null then raise exception 'Event division not found' using errcode='P0002'; end if;
  return response;
end $$;

create function private.validate_double_elimination_plan(
  p_plan jsonb,p_event uuid,p_division uuid,p_teams uuid[])
returns void language plpgsql stable set search_path='' as $$
declare item jsonb; source jsonb; position int:=0; source_position int; key text;
  winners int:=0; losers int:=0; gf1 int:=0; gf2 int:=0; direct_ids uuid[];
begin
  if jsonb_typeof(p_plan)<>'object' or p_plan->>'eventId'<>p_event::text
    or p_plan->>'divisionId'<>p_division::text or p_plan->>'format'<>'doubleElimination'
    or jsonb_typeof(p_plan->'matches')<>'array'
    or jsonb_array_length(p_plan->'matches')<>2*cardinality(p_teams)-1 then
    raise exception 'Invalid Double Elimination plan' using errcode='23514';
  end if;
  if (select count(distinct value->>'key') from jsonb_array_elements(p_plan->'matches'))
      <>jsonb_array_length(p_plan->'matches') then
    raise exception 'Duplicate planned match key' using errcode='23514';
  end if;
  for item in select value from jsonb_array_elements(p_plan->'matches') loop
    position:=position+1; key:=item->>'key';
    if item->>'eventId'<>p_event::text or item->>'divisionId'<>p_division::text
      or (item->>'round')::int<1 or item->>'section' not in ('winners','losers','grandFinal','resetFinal') then
      raise exception 'Invalid planned match scope' using errcode='23514';
    end if;
    winners:=winners+(item->>'section'='winners')::int;
    losers:=losers+(item->>'section'='losers')::int;
    gf1:=gf1+(key='de/finals/gf1' and item->>'section'='grandFinal')::int;
    gf2:=gf2+(key='de/finals/gf2' and item->>'section'='resetFinal')::int;
    foreach source in array array[item->'sideOne',item->'sideTwo'] loop
      if source?'teamId' then
        if (source->>'teamId')::uuid<>all(p_teams) then
          raise exception 'Planned team is outside the division' using errcode='23514'; end if;
        direct_ids:=array_append(direct_ids,(source->>'teamId')::uuid);
      elsif source?'matchKey' then
        if source->>'outcome' not in ('winner','loser') then
          raise exception 'Invalid planned outcome' using errcode='23514'; end if;
        select ord::int into source_position from jsonb_array_elements(p_plan->'matches') with ordinality x(value,ord)
          where value->>'key'=source->>'matchKey';
        if source_position is null or source_position>=position then
          raise exception 'Missing, cyclic or forward dependency' using errcode='23514'; end if;
      else raise exception 'Invalid planned participant source' using errcode='23514';
      end if;
    end loop;
  end loop;
  if winners<>cardinality(p_teams)-1 or losers<>greatest(cardinality(p_teams)-2,0)
    or gf1<>1 or gf2<>1 or cardinality(direct_ids)<>cardinality(p_teams)
    or (select count(distinct x) from unnest(direct_ids) x)<>cardinality(p_teams) then
    raise exception 'Invalid winners, losers, final or seed structure' using errcode='23514';
  end if;
end $$;

create function public.apply_double_elimination_operation(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  op uuid; eid uuid; did uuid; action text; expected bigint; stamp timestamptz:=clock_timestamp();
  event_row public.events%rowtype; division_row public.event_divisions%rowtype;
  bracket_row public.double_elimination_brackets%rowtype;
  receipt_row private.double_elimination_receipts%rowtype; current_match public.matches%rowtype;
  existing_match public.matches%rowtype;
  proposed jsonb; plan jsonb; proposed_match jsonb; planned jsonb; source jsonb;
  ordered uuid[]; team_count int; match_count int; sequence_no int:=0;
  planned_key text; match_id uuid; expected_team uuid; actual_team uuid;
  score_one int; score_two int; expected_winner uuid; reason text; response jsonb;
  gf1 jsonb; gf2 jsonb; target_proposed jsonb; champion uuid; runner_up uuid;
  is_downstream boolean;
begin
  if not private.is_organizer() then raise exception 'Organizer permission required' using errcode='42501'; end if;
  if jsonb_typeof(p_payload)<>'object' or exists(select 1 from jsonb_object_keys(p_payload) k where k not in
    ('operation_id','event_id','division_id','action','expected_version','event_version','division_version','created_at',
     'seed_order','team_versions','match_ids','match_key','score_one','score_two','reason','placement_ids','proposed')) then
    raise exception 'Invalid Double Elimination command' using errcode='23514';
  end if;
  op:=(p_payload->>'operation_id')::uuid; eid:=(p_payload->>'event_id')::uuid;
  did:=(p_payload->>'division_id')::uuid; action:=p_payload->>'action';
  expected:=(p_payload->>'expected_version')::bigint; proposed:=p_payload->'proposed';
  if op is null or eid is null or did is null or expected is null
    or action not in ('generate','start','result','correct') or jsonb_typeof(proposed)<>'object' then
    raise exception 'Incomplete Double Elimination command' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended(op::text,15));
  select * into receipt_row from private.double_elimination_receipts r where r.operation_id=op;
  if found then
    if receipt_row.payload<>p_payload then raise exception 'Operation identity reused with changed payload' using errcode='23505'; end if;
    return receipt_row.response;
  end if;
  select * into event_row from public.events e where e.id=eid and e.deleted_at is null for update;
  select * into division_row from public.event_divisions d where d.id=did and d.event_id=eid and d.deleted_at is null for update;
  if event_row.id is null or division_row.id is null or division_row.tournament_format is distinct from 'doubleElimination' then
    raise exception 'A Double Elimination division is required' using errcode='23514'; end if;
  select * into bracket_row from public.double_elimination_brackets b where b.division_id=did and b.deleted_at is null for update;
  if coalesce(bracket_row.version,-1)<>expected
    or event_row.version is distinct from (p_payload->>'event_version')::bigint
    or division_row.version is distinct from (p_payload->>'division_version')::bigint
    or (proposed->>'version')::bigint<>expected+1 then
    raise exception 'Tournament version conflict' using errcode='40001'; end if;
  plan:=proposed->'plan';

  if action='generate' then
    if event_row.status<>'registration' or exists(select 1 from public.matches m where m.division_id=did and m.deleted_at is null
      and (m.status in ('inProgress','completed') or m.side_one_score is not null or m.side_two_score is not null)) then
      raise exception 'Tournament generation is locked' using errcode='23514'; end if;
    if bracket_row.id is null and exists(select 1 from public.matches m where m.division_id=did and m.deleted_at is null) then
      raise exception 'An active tournament structure already exists' using errcode='23514'; end if;
    select array_agg(v::uuid order by ord) into ordered from jsonb_array_elements_text(p_payload->'seed_order') with ordinality x(v,ord);
    team_count:=coalesce(cardinality(ordered),0);
    if team_count<2 or team_count<>(select count(distinct x) from unnest(ordered) x)
      or team_count<>(select count(*) from public.teams t where t.division_id=did and t.deleted_at is null)
      or team_count<>(select count(*) from jsonb_each(p_payload->'team_versions'))
      or exists(select 1 from unnest(ordered) tid left join public.teams t on t.id=tid where t.id is null
        or t.division_id<>did or t.deleted_at is not null
        or t.version is distinct from (p_payload->'team_versions'->>t.id::text)::bigint
        or (select count(*) from public.team_members tm join public.players p on p.id=tm.player_id
          where tm.team_id=t.id and tm.deleted_at is null and p.deleted_at is null)<>2)
      or exists(select tm.player_id from public.team_members tm join public.teams t on t.id=tm.team_id
        where t.id=any(ordered) and tm.deleted_at is null group by tm.player_id having count(*)>1) then
      raise exception 'Teams are incomplete, changed or outside the division' using errcode='23514'; end if;
    perform private.validate_double_elimination_plan(plan,eid,did,ordered);
    if (select count(*) from jsonb_each(p_payload->'match_ids'))<>2*team_count-1
      or (select count(distinct value) from jsonb_each_text(p_payload->'match_ids'))<>2*team_count-1
      or jsonb_array_length(proposed->'matches')<>2*team_count-2 then
      raise exception 'Invalid stable match identities' using errcode='23514'; end if;
    update public.match_dependencies set deleted_at=stamp,updated_at=stamp,version=version+1
      where deleted_at is null and source_match_id in(select id from public.matches where division_id=did);
    update public.matches set deleted_at=stamp,updated_at=stamp,version=version+1 where division_id=did and deleted_at is null;
    update public.double_elimination_brackets set deleted_at=stamp,updated_at=stamp where id=bracket_row.id;
  else
    if event_row.status<>'inProgress' or bracket_row.id is null or plan<>bracket_row.plan then
      raise exception 'Event must be In Progress with its active bracket' using errcode='23514'; end if;
    match_id:=(bracket_row.match_ids->>(p_payload->>'match_key'))::uuid;
    select * into current_match from public.matches m where m.id=match_id and m.division_id=did and m.deleted_at is null for update;
    if current_match.id is null then raise exception 'Match is unavailable' using errcode='23514'; end if;
    if action='start' and current_match.status<>'queued' then
      raise exception 'Only a ready match may start' using errcode='23514';
    elsif action in ('result','correct') then
      score_one:=(p_payload->>'score_one')::int; score_two:=(p_payload->>'score_two')::int;
      if score_one is null or score_two is null or score_one<0 or score_two<0 or not (
        (greatest(score_one,score_two)=11 and least(score_one,score_two)<=9) or
        (least(score_one,score_two)>=10 and abs(score_one::bigint-score_two::bigint)=2)) then
        raise exception 'Invalid final score' using errcode='23514'; end if;
      if action='result' and current_match.status<>'inProgress' then
        raise exception 'Start the ready match before recording its result' using errcode='23514'; end if;
      if action='correct' then
        reason:=btrim(p_payload->>'reason');
        if current_match.status<>'completed' or reason is null or reason='' then
          raise exception 'Completed result and correction reason required' using errcode='23514'; end if;
        if exists(with recursive affected(match_key) as (
          select value->>'key' from jsonb_array_elements(plan->'matches') where
            value->'sideOne'->>'matchKey'=p_payload->>'match_key' or value->'sideTwo'->>'matchKey'=p_payload->>'match_key'
          union all select p.value->>'key' from affected a cross join jsonb_array_elements(plan->'matches') p(value)
            where p.value->'sideOne'->>'matchKey'=a.match_key or p.value->'sideTwo'->>'matchKey'=a.match_key)
          select 1 from affected a join jsonb_array_elements(proposed->'matches') pm(value) on pm.value->>'planned_key'=a.match_key
          join public.matches m on m.id=(pm.value->>'id')::uuid
          where m.status in ('inProgress','completed') or m.side_one_score is not null or m.side_two_score is not null) then
          raise exception 'Affected downstream match has started' using errcode='23514'; end if;
        insert into public.match_result_revisions(operation_id,match_id,previous_result,reason,recorded_at)
          values(op,match_id,to_jsonb(current_match),reason,stamp);
        perform set_config('vpc.result_correction',op::text,true);
      end if;
    end if;
  end if;

  -- Validate every proposed actual match against the immutable plan and source outcomes.
  match_count:=0;
  for proposed_match in select value from jsonb_array_elements(proposed->'matches') loop
    match_count:=match_count+1; planned_key:=proposed_match->>'planned_key'; match_id:=(proposed_match->>'id')::uuid;
    planned:=null;
    select value into planned from jsonb_array_elements(plan->'matches') where value->>'key'=planned_key;
    if planned is null or proposed_match->>'division_id'<>did::text
      or (bracket_row.id is not null and bracket_row.match_ids->>planned_key is distinct from match_id::text)
      or (bracket_row.id is null and p_payload->'match_ids'->>planned_key is distinct from match_id::text) then
      raise exception 'Proposed match identity or scope is invalid' using errcode='23514'; end if;
    if planned_key=p_payload->>'match_key' then target_proposed:=proposed_match; end if;
    foreach source in array array[planned->'sideOne',planned->'sideTwo'] loop
      if source?'teamId' then expected_team:=(source->>'teamId')::uuid;
      else
        select case source->>'outcome' when 'winner' then (pm.value->>'winner_team_id')::uuid
          else case when (pm.value->>'winner_team_id')::uuid=(pm.value->>'side_one_team_id')::uuid
            then (pm.value->>'side_two_team_id')::uuid else (pm.value->>'side_one_team_id')::uuid end end
          into expected_team from jsonb_array_elements(proposed->'matches') pm(value)
          where pm.value->>'planned_key'=source->>'matchKey' and pm.value->>'status'='completed';
      end if;
      actual_team:=case when source=planned->'sideOne' then (proposed_match->>'side_one_team_id')::uuid
        else (proposed_match->>'side_two_team_id')::uuid end;
      if actual_team is distinct from expected_team then raise exception 'Invalid winner or loser progression' using errcode='23514'; end if;
    end loop;
    if (proposed_match->>'side_one_team_id') is not null
      and proposed_match->>'side_one_team_id'=proposed_match->>'side_two_team_id' then
      raise exception 'A team cannot play itself' using errcode='23514'; end if;
    if proposed_match->>'status'='completed' then
      score_one:=(proposed_match->>'side_one_score')::int; score_two:=(proposed_match->>'side_two_score')::int;
      expected_winner:=case when score_one>score_two then (proposed_match->>'side_one_team_id')::uuid
        else (proposed_match->>'side_two_team_id')::uuid end;
      if score_one is null or score_two is null or not ((greatest(score_one,score_two)=11 and least(score_one,score_two)<=9)
        or (least(score_one,score_two)>=10 and abs(score_one::bigint-score_two::bigint)=2))
        or (proposed_match->>'winner_team_id')::uuid is distinct from expected_winner then
        raise exception 'Invalid completed match result' using errcode='23514'; end if;
    elsif proposed_match->'side_one_score'<>'null'::jsonb or proposed_match->'side_two_score'<>'null'::jsonb
      or proposed_match->'winner_team_id'<>'null'::jsonb then
      raise exception 'Incomplete match cannot have a final result' using errcode='23514';
    elsif proposed_match->>'status' in ('queued','inProgress') and
      ((proposed_match->>'side_one_team_id') is null or (proposed_match->>'side_two_team_id') is null) then
      raise exception 'Ready match requires two teams' using errcode='23514';
    elsif proposed_match->>'status'='scheduled' and
      (proposed_match->>'side_one_team_id') is not null and (proposed_match->>'side_two_team_id') is not null then
      raise exception 'Resolved match must be ready' using errcode='23514';
    end if;

    if action<>'generate' then
      select * into existing_match from public.matches m where m.id=match_id and m.deleted_at is null;
      if existing_match.id is null then
        if planned_key<>'de/finals/gf2' then raise exception 'Unexpected new match' using errcode='23514'; end if;
      elsif match_id<>current_match.id then
        is_downstream:=false;
        if action in ('result','correct') then
          select exists(with recursive affected(match_key) as (
            select value->>'key' from jsonb_array_elements(plan->'matches') where
              value->'sideOne'->>'matchKey'=p_payload->>'match_key' or value->'sideTwo'->>'matchKey'=p_payload->>'match_key'
            union all select p.value->>'key' from affected a cross join jsonb_array_elements(plan->'matches') p(value)
              where p.value->'sideOne'->>'matchKey'=a.match_key or p.value->'sideTwo'->>'matchKey'=a.match_key)
            select 1 from affected where match_key=planned_key) into is_downstream;
        end if;
        if not is_downstream and (
          existing_match.side_one_team_id is distinct from (proposed_match->>'side_one_team_id')::uuid
          or existing_match.side_two_team_id is distinct from (proposed_match->>'side_two_team_id')::uuid
          or existing_match.status is distinct from proposed_match->>'status'
          or existing_match.side_one_score is distinct from (proposed_match->>'side_one_score')::int
          or existing_match.side_two_score is distinct from (proposed_match->>'side_two_score')::int
          or existing_match.winner_team_id is distinct from (proposed_match->>'winner_team_id')::uuid) then
          raise exception 'Unrelated match state cannot change' using errcode='23514';
        end if;
      end if;
    end if;
  end loop;
  if action='start' and (target_proposed is null or target_proposed->>'status'<>'inProgress'
      or target_proposed->'side_one_score'<>'null'::jsonb or target_proposed->'side_two_score'<>'null'::jsonb) then
    raise exception 'Invalid match start proposal' using errcode='23514';
  elsif action in ('result','correct') and (target_proposed is null or target_proposed->>'status'<>'completed'
      or (target_proposed->>'side_one_score')::int is distinct from score_one
      or (target_proposed->>'side_two_score')::int is distinct from score_two) then
    raise exception 'Result proposal does not match the command' using errcode='23514';
  end if;
  gf1=(select value from jsonb_array_elements(proposed->'matches') where value->>'planned_key'='de/finals/gf1');
  gf2=(select value from jsonb_array_elements(proposed->'matches') where value->>'planned_key'='de/finals/gf2');
  if gf2 is not null and (gf1 is null or gf1->>'status'<>'completed'
    or gf1->>'winner_team_id' is distinct from gf1->>'side_two_team_id') then
    raise exception 'Reset final is not necessary' using errcode='23514'; end if;
  if gf1 is not null and gf1->>'status'='completed' and gf1->>'winner_team_id'=gf1->>'side_two_team_id' and gf2 is null then
    raise exception 'Reset final is required' using errcode='23514'; end if;

  -- Persist only fixed tournament records represented by the validated proposal.
  sequence_no:=0;
  for proposed_match in select value from jsonb_array_elements(proposed->'matches') loop
    sequence_no:=sequence_no+1; match_id:=(proposed_match->>'id')::uuid;
    insert into public.matches(id,division_id,side_one_team_id,side_two_team_id,status,side_one_score,side_two_score,
      winner_team_id,round_number,sequence_number,created_at,updated_at,version)
    values(match_id,did,(proposed_match->>'side_one_team_id')::uuid,(proposed_match->>'side_two_team_id')::uuid,
      proposed_match->>'status',(proposed_match->>'side_one_score')::int,(proposed_match->>'side_two_score')::int,
      (proposed_match->>'winner_team_id')::uuid,(proposed_match->>'round_number')::int,sequence_no,stamp,stamp,
      (proposed_match->>'version')::bigint)
    on conflict(id) do update set side_one_team_id=excluded.side_one_team_id,side_two_team_id=excluded.side_two_team_id,
      status=excluded.status,side_one_score=excluded.side_one_score,side_two_score=excluded.side_two_score,
      winner_team_id=excluded.winner_team_id,updated_at=stamp,version=excluded.version,deleted_at=null;
  end loop;
  update public.matches set deleted_at=stamp,updated_at=stamp,version=version+1
    where division_id=did and deleted_at is null and id not in
      (select (value->>'id')::uuid from jsonb_array_elements(proposed->'matches'));

  update public.match_dependencies set deleted_at=stamp,updated_at=stamp,version=version+1
    where deleted_at is null and source_match_id in(select id from public.matches where division_id=did);
  for planned in select value from jsonb_array_elements(plan->'matches') loop
    if exists(select 1 from public.matches where id=(coalesce(bracket_row.match_ids,p_payload->'match_ids')->>(planned->>'key'))::uuid and deleted_at is null) then
      foreach source in array array[planned->'sideOne',planned->'sideTwo'] loop
        if source?'matchKey' and exists(select 1 from public.matches where
          id=(coalesce(bracket_row.match_ids,p_payload->'match_ids')->>(source->>'matchKey'))::uuid and deleted_at is null) then
          insert into public.match_dependencies(source_match_id,source_outcome,destination_match_id,destination_slot,
            created_at,updated_at,version)
          values((coalesce(bracket_row.match_ids,p_payload->'match_ids')->>(source->>'matchKey'))::uuid,
            source->>'outcome',(coalesce(bracket_row.match_ids,p_payload->'match_ids')->>(planned->>'key'))::uuid,
            case when source=planned->'sideOne' then 'sideOne' else 'sideTwo' end,stamp,stamp,0)
          on conflict(source_match_id,source_outcome,destination_match_id,destination_slot) do update
            set deleted_at=null,updated_at=stamp,version=public.match_dependencies.version+1;
        end if;
      end loop;
    end if;
  end loop;

  if bracket_row.id is null or action='generate' then
    insert into public.double_elimination_brackets(id,division_id,plan,match_ids,version,created_at,updated_at)
      values(op,did,plan,p_payload->'match_ids',expected+1,stamp,stamp);
  else
    update public.double_elimination_brackets set version=expected+1,updated_at=stamp where id=bracket_row.id;
  end if;
  update public.division_placements set deleted_at=stamp,updated_at=stamp,version=version+1
    where division_id=did and deleted_at is null;
  if gf2 is not null and gf2->>'status'='completed' then
    champion:=(gf2->>'winner_team_id')::uuid;
    runner_up:=case when champion=(gf2->>'side_one_team_id')::uuid then (gf2->>'side_two_team_id')::uuid else (gf2->>'side_one_team_id')::uuid end;
  elsif gf1 is not null and gf1->>'status'='completed' and gf1->>'winner_team_id'=gf1->>'side_one_team_id' then
    champion:=(gf1->>'winner_team_id')::uuid; runner_up:=(gf1->>'side_two_team_id')::uuid;
  end if;
  if champion is not null then
    if p_payload->'placement_ids'->>'1' is null or p_payload->'placement_ids'->>'2' is null then
      raise exception 'Champion and runner-up identities are required' using errcode='23514'; end if;
    insert into public.division_placements(id,division_id,team_id,position,created_at,updated_at)
      values((p_payload->'placement_ids'->>'1')::uuid,did,champion,1,stamp,stamp),
        ((p_payload->'placement_ids'->>'2')::uuid,did,runner_up,2,stamp,stamp);
  end if;
  response:=public.get_double_elimination_context(eid,did);
  insert into private.double_elimination_receipts(operation_id,payload,response) values(op,p_payload,response);
  return response;
end $$;

create function public.pull_double_elimination_changes(
  p_after_updated_at timestamptz default null,p_after_id uuid default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_organizer() then raise exception 'Organizer permission required' using errcode='42501'; end if;
  if p_limit is null or p_limit<1 or p_limit>50 or (p_after_updated_at is null)<>(p_after_id is null) then
    raise exception 'Invalid bounded cursor' using errcode='23514'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'updated_at',b.updated_at,
    'event_id',d.event_id,'division_id',d.id,'context',public.get_double_elimination_context(d.event_id,d.id))
    order by b.updated_at,b.id) from (select * from public.double_elimination_brackets
      where p_after_updated_at is null or (updated_at,id)>(p_after_updated_at,p_after_id)
      order by updated_at,id limit p_limit) b join public.event_divisions d on d.id=b.division_id),'[]'::jsonb);
end $$;

revoke all on function private.double_elimination_json(uuid,boolean),
  private.validate_double_elimination_plan(jsonb,uuid,uuid,uuid[]),
  public.get_double_elimination_context(uuid,uuid),public.apply_double_elimination_operation(jsonb),
  public.pull_double_elimination_changes(timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function public.get_double_elimination_context(uuid,uuid) to anon,authenticated;
grant execute on function public.apply_double_elimination_operation(jsonb),
  public.pull_double_elimination_changes(timestamptz,uuid,integer) to authenticated;

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename='double_elimination_brackets') then
    alter publication supabase_realtime add table public.double_elimination_brackets;
  end if;
end $$;
