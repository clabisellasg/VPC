-- Repair the correction dependency identifier collision; applied history remains unchanged.
create or replace function public.apply_single_elimination_operation(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  op uuid; eid uuid; did uuid; action text; expected bigint;
  e public.events%rowtype; d public.event_divisions%rowtype;
  b public.single_elimination_brackets%rowtype; prior private.single_elimination_receipts%rowtype;
  current_match public.matches%rowtype; target public.matches%rowtype;
  stamp timestamptz:=clock_timestamp(); response jsonb; plan jsonb; planned jsonb:='[]';
  ordered uuid[]; positions int[]:=array[1,2]; expanded int[]; seeds int; seed int; n int; i int;
  round_no int:=1; size int; sources jsonb[]; next_sources jsonb[];
  one jsonb; two jsonb; item jsonb; key text; mid uuid; one_id uuid; two_id uuid;
  score_one int; score_two int; win uuid; loss uuid; reason text; dependency_row record; final_id uuid;
begin
  if not private.is_organizer() then raise exception 'Organizer permission required' using errcode='42501'; end if;
  if jsonb_typeof(p_payload)<>'object' or exists(select 1 from jsonb_object_keys(p_payload) k where k not in
    ('operation_id','event_id','division_id','action','expected_version','event_version','division_version','created_at',
      'seed_order','team_versions','match_ids','match_key','score_one','score_two','reason','placement_ids')) then
    raise exception 'Invalid tournament command' using errcode='23514';
  end if;
  op:=(p_payload->>'operation_id')::uuid; eid:=(p_payload->>'event_id')::uuid; did:=(p_payload->>'division_id')::uuid;
  action:=p_payload->>'action'; expected:=(p_payload->>'expected_version')::bigint;
  if op is null or eid is null or did is null or expected is null or action not in ('generate','start','result','correct') then
    raise exception 'Incomplete tournament command' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended(op::text,13));
  select * into prior from private.single_elimination_receipts where operation_id=op;
  if found then
    if prior.payload<>p_payload then raise exception 'Operation identity reused with changed payload' using errcode='23505'; end if;
    return prior.response;
  end if;
  select * into e from public.events where id=eid and deleted_at is null for update;
  select * into d from public.event_divisions where id=did and event_id=eid and deleted_at is null for update;
  if e.id is null or d.id is null or d.tournament_format is distinct from 'singleElimination' then
    raise exception 'A Single Elimination division is required' using errcode='23514'; end if;
  select * into b from public.single_elimination_brackets where division_id=did and deleted_at is null for update;
  if coalesce(b.version,-1)<>expected or e.version is distinct from (p_payload->>'event_version')::bigint
    or d.version is distinct from (p_payload->>'division_version')::bigint then
    raise exception 'Tournament version conflict' using errcode='40001'; end if;
  if action='generate' then
    if e.status<>'registration' or exists(select 1 from public.matches m where m.division_id=did and
      (m.status in ('inProgress','completed') or m.side_one_score is not null or m.side_two_score is not null)) then
      raise exception 'Tournament generation is locked' using errcode='23514'; end if;
    if b.id is null and exists(select 1 from public.matches where division_id=did and deleted_at is null) then
      raise exception 'An active tournament structure already exists' using errcode='23514'; end if;
    select array_agg(v::uuid order by ord) into ordered from jsonb_array_elements_text(p_payload->'seed_order') with ordinality as x(v,ord);
    n:=coalesce(array_length(ordered,1),0);
    if n<2 or n<>(select count(distinct t) from unnest(ordered) t) or
      n<>(select count(*) from public.teams where division_id=did and deleted_at is null) or
      n<>(select count(*) from jsonb_each(p_payload->'team_versions')) or
      exists(select 1 from unnest(ordered) tid left join public.teams t on t.id=tid where
        t.id is null or t.division_id<>did or t.deleted_at is not null or
        t.version is distinct from (p_payload->'team_versions'->>t.id::text)::bigint or
        (select count(*) from public.team_members tm join public.players p on p.id=tm.player_id
          where tm.team_id=t.id and tm.deleted_at is null and p.deleted_at is null)<>2) or
      exists(select tm.player_id from public.team_members tm join public.teams t on t.id=tm.team_id
        where t.id=any(ordered) and tm.deleted_at is null group by tm.player_id having count(*)>1) then
      raise exception 'Teams are incomplete, changed or outside the division' using errcode='23514'; end if;
    perform 1 from public.teams where id=any(ordered) for update;
    while cardinality(positions)<n loop
      expanded:=array[]::int[]; seeds:=cardinality(positions)*2+1;
      foreach seed in array positions loop expanded:=expanded||array[seed,seeds-seed]; end loop;
      positions:=expanded;
    end loop;
    size:=cardinality(positions); sources:=array[]::jsonb[];
    foreach seed in array positions loop sources:=array_append(sources,case when seed<=n then jsonb_build_object('teamId',ordered[seed]) else null end); end loop;
    while cardinality(sources)>1 loop
      next_sources:=array[]::jsonb[];
      for i in 1..cardinality(sources) by 2 loop
        one:=sources[i];two:=sources[i+1];
        if one is null or two is null then next_sources:=array_append(next_sources,coalesce(one,two)); continue; end if;
        key:='se/r'||round_no||'/m'||((i+1)/2);
        planned:=planned||jsonb_build_array(jsonb_build_object('key',key,'eventId',eid,'divisionId',did,'sideOne',one,'sideTwo',two,
          'round',round_no,'section','main','status',case when one?'teamId' and two?'teamId' then 'queued' else 'scheduled' end,'score',null,'winner',null));
        next_sources:=array_append(next_sources,jsonb_build_object('matchKey',key,'outcome','winner'));
      end loop;
      sources:=next_sources;round_no:=round_no+1;
    end loop;
    if jsonb_array_length(planned)<>n-1 or (select count(*) from jsonb_each(p_payload->'match_ids'))<>n-1 or
      (select count(distinct v) from jsonb_each_text(p_payload->'match_ids') x(k,v))<>n-1 then
      raise exception 'Invalid match identities' using errcode='23514'; end if;
    -- Tombstones retain the prior generation. No audit or played match is removed.
    update public.match_dependencies set deleted_at=stamp,updated_at=stamp,version=version+1
      where deleted_at is null and source_match_id in(select id from public.matches where division_id=did);
    update public.matches set deleted_at=stamp,updated_at=stamp,version=version+1 where division_id=did and deleted_at is null;
    update public.single_elimination_brackets set deleted_at=stamp,updated_at=stamp where id=b.id;
    for item in select value from jsonb_array_elements(planned) loop
      mid:=(p_payload->'match_ids'->>(item->>'key'))::uuid;
      if mid is null then raise exception 'Missing planned match identity' using errcode='23514'; end if;
      insert into public.matches(id,division_id,side_one_team_id,side_two_team_id,status,round_number,sequence_number,created_at,updated_at,version)
      values(mid,did,(item->'sideOne'->>'teamId')::uuid,(item->'sideTwo'->>'teamId')::uuid,item->>'status',
        (item->>'round')::int,split_part(item->>'key','/m',2)::int,stamp,stamp,0);
    end loop;
    for item in select value from jsonb_array_elements(planned) loop
      foreach key in array array['sideOne','sideTwo'] loop
        if item->key?'matchKey' then
          insert into public.match_dependencies(source_match_id,source_outcome,destination_match_id,destination_slot,created_at,updated_at)
          values((p_payload->'match_ids'->>(item->key->>'matchKey'))::uuid,'winner',(p_payload->'match_ids'->>(item->>'key'))::uuid,key,stamp,stamp);
        end if;
      end loop;
    end loop;
    plan:=jsonb_build_object('eventId',eid,'divisionId',did,'format','singleElimination','matches',planned,
      'metadata',jsonb_build_object('bracketSize',size::text,'seedOrder',to_jsonb(ordered)::text,'seedPositions',to_jsonb(positions)::text));
    insert into public.single_elimination_brackets(id,division_id,plan,match_ids,version,created_at,updated_at)
      values(op,did,plan,p_payload->'match_ids',expected+1,coalesce(b.created_at,stamp),stamp);
  else
    if e.status<>'inProgress' or b.id is null then raise exception 'Event must be In Progress' using errcode='23514'; end if;
    mid:=(b.match_ids->>(p_payload->>'match_key'))::uuid;
    select * into current_match from public.matches where id=mid and division_id=did and deleted_at is null for update;
    if current_match.id is null or current_match.side_one_team_id is null or current_match.side_two_team_id is null then
      raise exception 'Both match participants must be resolved' using errcode='23514'; end if;
    if action='start' then
      if current_match.status<>'queued' then raise exception 'Only a ready match may start' using errcode='23514'; end if;
      update public.matches set status='inProgress',version=version+1,updated_at=stamp where id=mid;
    else
      score_one:=(p_payload->>'score_one')::int;score_two:=(p_payload->>'score_two')::int;
      if score_one is null or score_two is null or score_one<0 or score_two<0 or not (
        (greatest(score_one,score_two)=11 and least(score_one,score_two)<=9) or
        (least(score_one,score_two)>=10 and abs(score_one::bigint-score_two::bigint)=2)) then
        raise exception 'Invalid final score' using errcode='23514'; end if;
      win:=case when score_one>score_two then current_match.side_one_team_id else current_match.side_two_team_id end;
      loss:=case when score_one>score_two then current_match.side_two_team_id else current_match.side_one_team_id end;
      if action='correct' then
        reason:=btrim(p_payload->>'reason');
        if current_match.status<>'completed' or reason is null or reason='' then raise exception 'Completed result and correction reason required' using errcode='23514'; end if;
        if current_match.winner_team_id<>win and exists(
          with recursive affected(id) as (
            select md.destination_match_id from public.match_dependencies md where md.source_match_id=mid and md.deleted_at is null
            union select md.destination_match_id from public.match_dependencies md join affected a on md.source_match_id=a.id where md.deleted_at is null)
          select 1 from affected a join public.matches m on m.id=a.id where m.status in ('inProgress','completed') or m.side_one_score is not null or m.side_two_score is not null) then
          raise exception 'Affected downstream match has started' using errcode='23514'; end if;
        insert into public.match_result_revisions values(op,mid,to_jsonb(current_match),reason,stamp);
        perform set_config('vpc.result_correction',op::text,true);
      elsif action<>'result' or current_match.status<>'inProgress' then
        raise exception 'Start the ready match before recording its result' using errcode='23514';
      end if;
      update public.matches set status='completed',side_one_score=score_one,side_two_score=score_two,
        winner_team_id=win,updated_at=stamp,version=version+1 where id=mid;
      for dependency_row in select md.* from public.match_dependencies md where md.source_match_id=mid and md.deleted_at is null loop
        if dependency_row.source_outcome<>'winner' then raise exception 'Invalid Single Elimination dependency' using errcode='23514'; end if;
        select * into target from public.matches where id=dependency_row.destination_match_id and division_id=did for update;
        one_id:=case when dependency_row.destination_slot='sideOne' then win else target.side_one_team_id end;
        two_id:=case when dependency_row.destination_slot='sideTwo' then win else target.side_two_team_id end;
        if one_id is distinct from target.side_one_team_id or two_id is distinct from target.side_two_team_id then
          if target.status not in ('scheduled','queued') then raise exception 'Downstream match has started' using errcode='23514'; end if;
          update public.matches set side_one_team_id=one_id,side_two_team_id=two_id,
            status=case when one_id is not null and two_id is not null then 'queued' else 'scheduled' end,
            updated_at=stamp,version=version+1 where id=target.id;
        end if;
      end loop;
      final_id:=(b.match_ids->>(b.plan->'matches'->-1->>'key'))::uuid;
      if mid=final_id then
        update public.division_placements set deleted_at=stamp,updated_at=stamp,version=version+1 where division_id=did and deleted_at is null;
        insert into public.division_placements(id,division_id,team_id,position,created_at,updated_at)
          values((p_payload->'placement_ids'->>'1')::uuid,did,win,1,stamp,stamp),((p_payload->'placement_ids'->>'2')::uuid,did,loss,2,stamp,stamp);
      end if;
    end if;
    update public.single_elimination_brackets set version=version+1,updated_at=stamp where id=b.id;
  end if;
  response:=public.get_single_elimination_context(eid,did);
  insert into private.single_elimination_receipts(operation_id,payload,response) values(op,p_payload,response);
  return response;
end $$;
