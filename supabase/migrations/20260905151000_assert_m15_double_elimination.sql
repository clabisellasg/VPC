-- M15 security and protocol assertions use one rolled-back synthetic bracket.
do $$
declare
  actor uuid; member_actor uuid; saved text:=current_setting('request.jwt.claim.sub',true);
  eid uuid:=md5('VPC M15 event')::uuid; did uuid:=md5('VPC M15 division')::uuid;
  t1 uuid:=md5('VPC M15 team one')::uuid; t2 uuid:=md5('VPC M15 team two')::uuid;
  p uuid; ep uuid; i int; j int; wb uuid:=md5('VPC M15 WB')::uuid;
  gf1 uuid:=md5('VPC M15 GF1')::uuid; gf2 uuid:=md5('VPC M15 GF2')::uuid;
  plan jsonb; proposed jsonb; payload jsonb; response jsonb; root_version int; stage text:='fixture';
begin
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='double_elimination_brackets' and c.relrowsecurity) then
    raise exception 'Double Elimination RLS is missing'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.apply_double_elimination_operation('{}'); raise exception 'Anonymous write accepted';
    exception when insufficient_privilege then null; end;
  select user_id into actor from public.user_roles where role='organizer' and deleted_at is null limit 1;
  select u.id into member_actor from auth.users u where not exists(select 1 from public.user_roles r
    where r.user_id=u.id and r.role='organizer' and r.deleted_at is null) limit 1;
  if actor is null or member_actor is null then raise exception 'M15 assertions need existing organizer and member accounts'; end if;
  perform set_config('request.jwt.claim.sub',member_actor::text,true);
  begin perform public.apply_double_elimination_operation('{}'); raise exception 'Member write accepted';
    exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  begin
    insert into public.events(id,name,scheduled_at,event_type,status,court_label)
      values(eid,'VPC M15 Rollback Fixture',clock_timestamp(),'formal','registration','VPC Sample Court');
    insert into public.event_divisions(id,event_id,name,tournament_format)
      values(did,eid,'VPC M15 Sample','doubleElimination');
    for i in 1..2 loop
      insert into public.teams(id,division_id,formation_method) values(case when i=1 then t1 else t2 end,did,'manual');
      for j in 1..2 loop
        p:=md5('VPC M15 player '||i||':'||j)::uuid; ep:=md5('VPC M15 participant '||i||':'||j)::uuid;
        insert into public.players(id,display_name) values(p,'VPC M15 Sample '||i||'-'||j);
        insert into public.event_participants(id,event_id,player_id,check_in_status) values(ep,eid,p,'checkedIn');
        insert into public.division_participants(id,division_id,event_participant_id)
          values(md5(ep::text||did::text)::uuid,did,ep);
        insert into public.team_members(team_id,player_id) values(case when i=1 then t1 else t2 end,p);
      end loop;
    end loop;
    plan:=jsonb_build_object('eventId',eid,'divisionId',did,'format','doubleElimination',
      'metadata',jsonb_build_object('bracketSize','2','seedOrder',to_jsonb(array[t1,t2])::text,'resetKey','de/finals/gf2'),
      'matches',jsonb_build_array(
        jsonb_build_object('key','de/wb/r1/m1','eventId',eid,'divisionId',did,'sideOne',jsonb_build_object('teamId',t1),
          'sideTwo',jsonb_build_object('teamId',t2),'round',1,'section','winners','status','queued'),
        jsonb_build_object('key','de/finals/gf1','eventId',eid,'divisionId',did,
          'sideOne',jsonb_build_object('matchKey','de/wb/r1/m1','outcome','winner'),
          'sideTwo',jsonb_build_object('matchKey','de/wb/r1/m1','outcome','loser'),
          'round',1,'section','grandFinal','status','scheduled'),
        jsonb_build_object('key','de/finals/gf2','eventId',eid,'divisionId',did,
          'sideOne',jsonb_build_object('matchKey','de/finals/gf1','outcome','winner'),
          'sideTwo',jsonb_build_object('matchKey','de/finals/gf1','outcome','loser'),
          'round',2,'section','resetFinal','status','scheduled')));
    proposed:=jsonb_build_object('plan',plan,'created_at',clock_timestamp(),'updated_at',clock_timestamp(),'version',0,'deleted_at',null,
      'matches',jsonb_build_array(
        jsonb_build_object('planned_key','de/wb/r1/m1','id',wb,'division_id',did,'status','queued',
          'side_one_team_id',t1,'side_two_team_id',t2,'side_one_score',null,'side_two_score',null,'winner_team_id',null,
          'round_number',1,'sequence_number',1,'created_at',clock_timestamp(),'updated_at',clock_timestamp(),'version',0,'deleted_at',null),
        jsonb_build_object('planned_key','de/finals/gf1','id',gf1,'division_id',did,'status','scheduled',
          'side_one_team_id',null,'side_two_team_id',null,'side_one_score',null,'side_two_score',null,'winner_team_id',null,
          'round_number',1,'sequence_number',2,'created_at',clock_timestamp(),'updated_at',clock_timestamp(),'version',0,'deleted_at',null)),
      'revisions','[]'::jsonb);
    payload:=jsonb_build_object('operation_id',md5('VPC M15 generate')::uuid,'event_id',eid,'division_id',did,'action','generate',
      'expected_version',-1,'event_version',0,'division_version',0,'created_at',clock_timestamp(),
      'seed_order',jsonb_build_array(t1,t2),'team_versions',jsonb_build_object(t1::text,0,t2::text,0),
      'match_ids',jsonb_build_object('de/wb/r1/m1',wb,'de/finals/gf1',gf1,'de/finals/gf2',gf2),
      'placement_ids','{}'::jsonb,'match_key',null,'score_one',null,'score_two',null,'reason',null,'proposed',proposed);
    stage:='generate'; raise notice 'M15 assertion generate';
    response:=public.apply_double_elimination_operation(payload);
    if jsonb_array_length(response->'bracket'->'matches')<>2 or public.apply_double_elimination_operation(payload)<>response then
      raise exception 'Generation or replay failed'; end if;
    begin perform public.apply_double_elimination_operation(payload||jsonb_build_object('reason','changed'));
      raise exception 'Changed replay accepted'; exception when unique_violation then null; end;
    update public.events set status='inProgress',version=1 where id=eid;

    -- Start and complete the winners final; its winner and loser feed Grand Final 1.
    proposed:=response->'bracket'; proposed:=jsonb_set(proposed,'{version}','1');
    proposed:=jsonb_set(proposed,'{matches,0,status}','"inProgress"');
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M15 start WB')::uuid,'action','start','expected_version',0,
      'event_version',1,'match_key','de/wb/r1/m1','proposed',proposed);
    stage:='start WB'; raise notice 'M15 assertion start WB';
    response:=public.apply_double_elimination_operation(payload);
    proposed:=response->'bracket'; proposed:=jsonb_set(proposed,'{version}','2');
    proposed:=jsonb_set(proposed,'{matches,0,status}','"completed"');
    proposed:=jsonb_set(proposed,'{matches,0,side_one_score}','11'); proposed:=jsonb_set(proposed,'{matches,0,side_two_score}','5');
    proposed:=jsonb_set(proposed,'{matches,0,winner_team_id}',to_jsonb(t1));
    proposed:=jsonb_set(proposed,'{matches,1,status}','"queued"');
    proposed:=jsonb_set(proposed,'{matches,1,side_one_team_id}',to_jsonb(t1));
    proposed:=jsonb_set(proposed,'{matches,1,side_two_team_id}',to_jsonb(t2));
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M15 result WB')::uuid,'action','result','expected_version',1,
      'score_one',11,'score_two',5,'placement_ids','{}'::jsonb,'proposed',proposed);
    stage:='result WB'; raise notice 'M15 assertion result WB';
    response:=public.apply_double_elimination_operation(payload);

    -- The losers-side finalist wins GF1, so the deterministic reset final appears.
    proposed:=response->'bracket'; proposed:=jsonb_set(proposed,'{version}','3');
    proposed:=jsonb_set(proposed,'{matches,1,status}','"inProgress"');
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M15 start GF1')::uuid,'action','start','expected_version',2,
      'match_key','de/finals/gf1','score_one',null,'score_two',null,'proposed',proposed);
    stage:='start GF1'; raise notice 'M15 assertion start GF1';
    response:=public.apply_double_elimination_operation(payload);
    proposed:=response->'bracket'; proposed:=jsonb_set(proposed,'{version}','4');
    proposed:=jsonb_set(proposed,'{matches,1,status}','"completed"');
    proposed:=jsonb_set(proposed,'{matches,1,side_one_score}','5'); proposed:=jsonb_set(proposed,'{matches,1,side_two_score}','11');
    proposed:=jsonb_set(proposed,'{matches,1,winner_team_id}',to_jsonb(t2));
    proposed:=jsonb_set(proposed,'{matches}',(proposed->'matches')||jsonb_build_array(
      jsonb_build_object('planned_key','de/finals/gf2','id',gf2,'division_id',did,'status','queued',
        'side_one_team_id',t2,'side_two_team_id',t1,'side_one_score',null,'side_two_score',null,'winner_team_id',null,
        'round_number',2,'sequence_number',3,'created_at',clock_timestamp(),'updated_at',clock_timestamp(),'version',0,'deleted_at',null)));
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M15 result GF1')::uuid,'action','result','expected_version',3,
      'score_one',5,'score_two',11,'placement_ids','{}'::jsonb,'proposed',proposed);
    stage:='result GF1'; raise notice 'M15 assertion result GF1';
    response:=public.apply_double_elimination_operation(payload);
    if jsonb_array_length(response->'bracket'->'matches')<>3 then raise exception 'Reset final was not activated'; end if;

    proposed:=response->'bracket'; proposed:=jsonb_set(proposed,'{version}','5');
    proposed:=jsonb_set(proposed,'{matches,2,status}','"inProgress"');
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M15 start GF2')::uuid,'action','start','expected_version',4,
      'match_key','de/finals/gf2','score_one',null,'score_two',null,'proposed',proposed);
    stage:='start GF2'; raise notice 'M15 assertion start GF2';
    response:=public.apply_double_elimination_operation(payload);
    proposed:=response->'bracket'; proposed:=jsonb_set(proposed,'{version}','6');
    proposed:=jsonb_set(proposed,'{matches,2,status}','"completed"');
    proposed:=jsonb_set(proposed,'{matches,2,side_one_score}','11'); proposed:=jsonb_set(proposed,'{matches,2,side_two_score}','7');
    proposed:=jsonb_set(proposed,'{matches,2,winner_team_id}',to_jsonb(t2));
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M15 result GF2')::uuid,'action','result','expected_version',5,
      'score_one',11,'score_two',7,'placement_ids',jsonb_build_object('1',md5('VPC M15 place 1')::uuid,'2',md5('VPC M15 place 2')::uuid),
      'proposed',proposed);
    stage:='result GF2'; raise notice 'M15 assertion result GF2';
    response:=public.apply_double_elimination_operation(payload);
    if (select team_id from public.division_placements where division_id=did and position=1 and deleted_at is null) is distinct from t2
      or (select team_id from public.division_placements where division_id=did and position=2 and deleted_at is null) is distinct from t1 then
      raise exception 'Reset champion or runner-up is incorrect'; end if;

    -- Final correction is allowed with an audit; changing GF1 is blocked by played GF2.
    root_version:=(response->'bracket'->>'version')::int;
    proposed:=response->'bracket'; proposed:=jsonb_set(proposed,'{version}',to_jsonb(root_version+1));
    proposed:=jsonb_set(proposed,'{matches,2,side_one_score}','5'); proposed:=jsonb_set(proposed,'{matches,2,side_two_score}','11');
    proposed:=jsonb_set(proposed,'{matches,2,winner_team_id}',to_jsonb(t1));
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M15 correct GF2')::uuid,'action','correct','expected_version',root_version,
      'match_key','de/finals/gf2','score_one',5,'score_two',11,'reason','VPC synthetic final correction',
      'placement_ids',jsonb_build_object('1',md5('VPC M15 corrected place 1')::uuid,'2',md5('VPC M15 corrected place 2')::uuid),'proposed',proposed);
    if root_version is distinct from (payload->>'expected_version')::int
      or root_version is distinct from (select version from public.double_elimination_brackets where division_id=did and deleted_at is null)
      or (payload->>'event_version')::bigint is distinct from (select version from public.events where id=eid)
      or (payload->>'division_version')::bigint is distinct from (select version from public.event_divisions where id=did)
      or (proposed->>'version')::bigint is distinct from root_version+1
      or (payload->'proposed'->>'version')::bigint is distinct from root_version+1 then
      raise exception 'version diagnostic root % payload %, stored %, proposed %/%, event %/%, division %/%',root_version,payload->>'expected_version',
        (select version from public.double_elimination_brackets where division_id=did and deleted_at is null),proposed->>'version',payload->'proposed'->>'version',
        payload->>'event_version',(select version from public.events where id=eid),payload->>'division_version',
        (select version from public.event_divisions where id=did);
    end if;
    stage:='correct GF2'; raise notice 'M15 assertion correct GF2';
    response:=public.apply_double_elimination_operation(payload);
    if not exists(select 1 from public.match_result_revisions where operation_id=md5('VPC M15 correct GF2')::uuid)
      or (select team_id from public.division_placements where division_id=did and position=1 and deleted_at is null) is distinct from t1 then
      raise exception 'Final correction audit or placement failed'; end if;
    root_version:=(response->'bracket'->>'version')::int;
    proposed:=response->'bracket'; proposed:=jsonb_set(proposed,'{version}',to_jsonb(root_version+1));
    proposed:=jsonb_set(proposed,'{matches,1,side_one_score}','11');
    proposed:=jsonb_set(proposed,'{matches,1,side_two_score}','5');
    proposed:=jsonb_set(proposed,'{matches,1,winner_team_id}',to_jsonb(t1));
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M15 blocked correction')::uuid,'expected_version',root_version,
      'match_key','de/finals/gf1','score_one',11,'score_two',5,'reason','VPC blocked downstream correction','proposed',proposed);
    stage:='blocked GF1 correction';
    begin perform public.apply_double_elimination_operation(payload); raise exception 'Played downstream correction accepted';
      exception when check_violation then null; end;
    raise exception using errcode='P1501',message='Rollback M15 synthetic assertions';
  exception when sqlstate 'P1501' then null;
    when others then raise exception 'M15 assertion stage % failed: %',stage,sqlerrm; end;
  if exists(select 1 from public.events where id=eid) then raise exception 'M15 fixture rollback failed'; end if;
  if has_function_privilege('anon','public.apply_double_elimination_operation(jsonb)','EXECUTE')
    or has_table_privilege('anon','public.matches','INSERT')
    or has_table_privilege('authenticated','public.double_elimination_brackets','UPDATE') then
    raise exception 'M15 security grants failed'; end if;
  perform set_config('request.jwt.claim.sub',coalesce(saved,''),true);
end $$;
