-- M13: fixed Single Elimination commands. No round-robin/losers/queue behavior.
create table public.single_elimination_brackets (
  id uuid primary key,
  division_id uuid not null references public.event_divisions(id) on delete restrict,
  plan jsonb not null check (jsonb_typeof(plan)='object'),
  match_ids jsonb not null check (jsonb_typeof(match_ids)='object'),
  version bigint not null check(version>=0),
  created_at timestamptz not null, updated_at timestamptz not null, deleted_at timestamptz,
  check(updated_at>=created_at and (deleted_at is null or deleted_at>=updated_at))
);
create unique index single_elimination_active_division on public.single_elimination_brackets(division_id) where deleted_at is null;
create index single_elimination_pull_cursor on public.single_elimination_brackets(updated_at,id);
create table public.match_result_revisions (
  operation_id uuid primary key,
  match_id uuid not null references public.matches(id) on delete restrict,
  previous_result jsonb not null check(jsonb_typeof(previous_result)='object'),
  reason text not null check(length(btrim(reason))>0),
  recorded_at timestamptz not null
);
create table private.single_elimination_receipts (
  operation_id uuid primary key, payload jsonb not null, response jsonb not null,
  recorded_at timestamptz not null default clock_timestamp()
);
alter table public.single_elimination_brackets enable row level security;
alter table public.match_result_revisions enable row level security;
revoke all on public.single_elimination_brackets, public.match_result_revisions from public,anon,authenticated;
grant select on public.single_elimination_brackets to anon,authenticated;
grant select on public.match_result_revisions to authenticated;
create policy bracket_public_read on public.single_elimination_brackets for select to anon,authenticated using(deleted_at is null);
create policy revision_organizer_read on public.match_result_revisions for select to authenticated using((select private.is_organizer()));
-- Direct organizer row writes cannot bypass progression/audit checks.
revoke insert,update on public.matches,public.match_dependencies,public.division_placements from anon,authenticated;

create function private.immutable_match_revision() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Result revisions are immutable' using errcode='23514'; end $$;
create trigger match_revision_immutable before update or delete on public.match_result_revisions
for each row execute function private.immutable_match_revision();

create or replace function private.prevent_completed_result_correction()
returns trigger language plpgsql set search_path='' as $$
begin
  if old.status='completed' and (new.side_one_score is distinct from old.side_one_score
    or new.side_two_score is distinct from old.side_two_score or new.winner_team_id is distinct from old.winner_team_id
    or new.side_one_team_id is distinct from old.side_one_team_id or new.side_two_team_id is distinct from old.side_two_team_id) then
    if new.side_one_team_id is distinct from old.side_one_team_id or new.side_two_team_id is distinct from old.side_two_team_id
      or not exists(select 1 from public.match_result_revisions r where r.match_id=old.id
        and r.operation_id::text=current_setting('vpc.result_correction',true)
        and r.previous_result=to_jsonb(old)) then
      raise exception 'An authorized audited result correction is required' using errcode='23514';
    end if;
  end if;
  return new;
end $$;

create function private.single_elimination_json(p_division uuid,p_audit boolean default false)
returns jsonb language sql stable set search_path='' as $$
  select jsonb_build_object('plan',b.plan,'created_at',b.created_at,'updated_at',b.updated_at,'version',b.version,'deleted_at',b.deleted_at,
    'matches',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('planned_key',k.key) order by m.round_number,m.sequence_number)
      from jsonb_each_text(b.match_ids) k join public.matches m on m.id=k.value::uuid),'[]'::jsonb),
    'revisions',case when p_audit then coalesce((select jsonb_agg(jsonb_build_object('operation_id',r.operation_id,
      'previous',r.previous_result,'reason',r.reason,'recorded_at',r.recorded_at) order by r.recorded_at,r.operation_id)
      from public.match_result_revisions r join public.matches m on m.id=r.match_id where m.division_id=p_division),'[]'::jsonb) else '[]'::jsonb end)
  from public.single_elimination_brackets b where b.division_id=p_division and b.deleted_at is null;
$$;

create function public.get_single_elimination_context(p_event_id uuid,p_division_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare response jsonb;
begin
  select jsonb_build_object('event',to_jsonb(e),'division',to_jsonb(d),
    'teams',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object(
      'label',coalesce(t.display_label,(select string_agg(p.display_name,' / ' order by tm.player_id)
        from public.team_members tm join public.players p on p.id=tm.player_id where tm.team_id=t.id and tm.deleted_at is null)),
      'members',coalesce((select jsonb_agg(to_jsonb(tm) order by tm.player_id) from public.team_members tm where tm.team_id=t.id and tm.deleted_at is null),'[]'::jsonb)) order by t.id)
      from public.teams t where t.division_id=d.id and t.deleted_at is null),'[]'::jsonb),
    'bracket',private.single_elimination_json(d.id,private.is_organizer())) into response
  from public.events e join public.event_divisions d on d.event_id=e.id
  where e.id=p_event_id and d.id=p_division_id and e.deleted_at is null and d.deleted_at is null;
  if response is null then raise exception 'Event division not found' using errcode='P0002'; end if;
  return response;
end $$;

create function public.apply_single_elimination_operation(p_payload jsonb)
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
  score_one int; score_two int; win uuid; loss uuid; reason text; dep record; final_id uuid;
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
            select destination_match_id from public.match_dependencies where source_match_id=mid and deleted_at is null
            union select dep.destination_match_id from public.match_dependencies dep join affected a on dep.source_match_id=a.id where dep.deleted_at is null)
          select 1 from affected a join public.matches m on m.id=a.id where m.status in ('inProgress','completed') or m.side_one_score is not null or m.side_two_score is not null) then
          raise exception 'Affected downstream match has started' using errcode='23514'; end if;
        insert into public.match_result_revisions values(op,mid,to_jsonb(current_match),reason,stamp);
        perform set_config('vpc.result_correction',op::text,true);
      elsif action<>'result' or current_match.status<>'inProgress' then
        raise exception 'Start the ready match before recording its result' using errcode='23514';
      end if;
      update public.matches set status='completed',side_one_score=score_one,side_two_score=score_two,
        winner_team_id=win,updated_at=stamp,version=version+1 where id=mid;
      for dep in select * from public.match_dependencies where source_match_id=mid and deleted_at is null loop
        if dep.source_outcome<>'winner' then raise exception 'Invalid Single Elimination dependency' using errcode='23514'; end if;
        select * into target from public.matches where id=dep.destination_match_id and division_id=did for update;
        one_id:=case when dep.destination_slot='sideOne' then win else target.side_one_team_id end;
        two_id:=case when dep.destination_slot='sideTwo' then win else target.side_two_team_id end;
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

revoke all on function private.immutable_match_revision(),private.single_elimination_json(uuid,boolean) from public,anon,authenticated;
create function public.pull_single_elimination_changes(p_after_updated_at timestamptz default null,p_after_id uuid default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_organizer() then raise exception 'Organizer permission required' using errcode='42501'; end if;
  if p_limit is null or p_limit<1 or p_limit>50 or (p_after_updated_at is null)<>(p_after_id is null) then
    raise exception 'Invalid bounded cursor' using errcode='23514'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'updated_at',b.updated_at,'event_id',d.event_id,'division_id',d.id,
    'bracket',private.single_elimination_json(d.id,true),
    'matches',coalesce((select jsonb_agg(to_jsonb(m) order by m.round_number,m.sequence_number,m.id) from public.matches m where m.division_id=d.id),'[]'::jsonb),
    'dependencies',coalesce((select jsonb_agg(to_jsonb(dep) order by dep.source_match_id,dep.destination_match_id) from public.match_dependencies dep
       join public.matches m on m.id=dep.source_match_id where m.division_id=d.id),'[]'::jsonb),
    'placements',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at,p.id) from public.division_placements p where p.division_id=d.id),'[]'::jsonb)
    ) order by b.updated_at,b.id)
    from (select * from public.single_elimination_brackets where p_after_updated_at is null or (updated_at,id)>(p_after_updated_at,p_after_id)
      order by updated_at,id limit p_limit) b join public.event_divisions d on d.id=b.division_id),'[]'::jsonb);
end $$;
revoke all on function public.pull_single_elimination_changes(timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function public.pull_single_elimination_changes(timestamptz,uuid,integer) to authenticated;
revoke all on function public.get_single_elimination_context(uuid,uuid),public.apply_single_elimination_operation(jsonb) from public,anon,authenticated;
grant execute on function public.get_single_elimination_context(uuid,uuid) to anon,authenticated;
grant execute on function public.apply_single_elimination_operation(jsonb) to authenticated;
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='single_elimination_brackets') then
    alter publication supabase_realtime add table public.single_elimination_brackets;
  end if;
end $$;
