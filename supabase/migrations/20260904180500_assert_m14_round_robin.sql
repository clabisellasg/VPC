-- M14 hosted assertions use a rolled-back synthetic fixture.
do $$
declare
  actor uuid; member_actor uuid; saved text:=current_setting('request.jwt.claim.sub',true);
  eid uuid:=md5('VPC M14 event')::uuid; did uuid:=md5('VPC M14 division')::uuid;
  team_one uuid:=md5('VPC M14 team one')::uuid; team_two uuid:=md5('VPC M14 team two')::uuid;
  player_id uuid; participant_id uuid; assignment_id uuid;
  payload jsonb; response jsonb; match_id uuid:=md5('VPC M14 match')::uuid;
  i int; j int;
begin
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='round_robin_tournaments' and c.relrowsecurity) then
    raise exception 'Round-robin RLS is missing';
  end if;
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.apply_round_robin_operation('{}'); raise exception 'Anonymous write accepted';
    exception when insufficient_privilege then null; end;
  select user_id into actor from public.user_roles where role='organizer' and deleted_at is null limit 1;
  select u.id into member_actor from auth.users u where not exists(select 1 from public.user_roles r
    where r.user_id=u.id and r.role='organizer' and r.deleted_at is null) limit 1;
  if actor is null or member_actor is null then raise exception 'M14 assertions need existing organizer and member accounts'; end if;
  perform set_config('request.jwt.claim.sub',member_actor::text,true);
  begin perform public.apply_round_robin_operation('{}'); raise exception 'Member write accepted';
    exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  begin
    insert into public.events(id,name,scheduled_at,event_type,status,court_label)
      values(eid,'VPC M14 Rollback Fixture',clock_timestamp(),'formal','registration','VPC Sample Court');
    insert into public.event_divisions(id,event_id,name,tournament_format)
      values(did,eid,'VPC M14 Sample','singleRoundRobin');
    for i in 1..2 loop
      insert into public.teams(id,division_id,formation_method)
        values(case when i=1 then team_one else team_two end,did,'manual');
      for j in 1..2 loop
        player_id:=md5('VPC M14 player '||i||':'||j)::uuid;
        participant_id:=md5('VPC M14 participant '||i||':'||j)::uuid;
        assignment_id:=md5('VPC M14 assignment '||i||':'||j)::uuid;
        insert into public.players(id,display_name) values(player_id,'VPC M14 Sample '||i||'-'||j);
        insert into public.event_participants(id,event_id,player_id,check_in_status)
          values(participant_id,eid,player_id,'checkedIn');
        insert into public.division_participants(id,division_id,event_participant_id)
          values(assignment_id,did,participant_id);
        insert into public.team_members(team_id,player_id)
          values(case when i=1 then team_one else team_two end,player_id);
      end loop;
    end loop;
    payload:=jsonb_build_object(
      'operation_id',md5('VPC M14 generate')::uuid,'event_id',eid,'division_id',did,'action','generate',
      'expected_version',-1,'event_version',0,'division_version',0,'created_at',clock_timestamp(),
      'seed_order',jsonb_build_array(team_one,team_two),
      'team_versions',jsonb_build_object(team_one::text,0,team_two::text,0),
      'match_ids',jsonb_build_object('rr/r1/m1',match_id),'placement_ids','{}'::jsonb);
    response:=public.apply_round_robin_operation(payload);
    if jsonb_array_length(response->'tournament'->'matches')<>1
      or public.apply_round_robin_operation(payload)<>response then
      raise exception 'Generation or identical replay failed';
    end if;
    begin perform public.apply_round_robin_operation(payload||jsonb_build_object('reason','changed'));
      raise exception 'Changed payload replay accepted'; exception when unique_violation then null; end;
    update public.events set status='inProgress' where id=eid;
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M14 start')::uuid,'action','start',
      'expected_version',0,'match_key','rr/r1/m1');
    response:=public.apply_round_robin_operation(payload);
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M14 result')::uuid,'action','result',
      'expected_version',1,'score_one',11,'score_two',7,
      'placement_ids',jsonb_build_object('1',md5('VPC M14 placement 1')::uuid,'2',md5('VPC M14 placement 2')::uuid));
    response:=public.apply_round_robin_operation(payload);
    if (select team_id from public.division_placements where division_id=did and position=1 and deleted_at is null)
      is distinct from team_one then raise exception 'Derived champion is incorrect'; end if;
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M14 correction')::uuid,'action','correct',
      'expected_version',2,'score_one',5,'score_two',11,'reason','VPC M14 correction',
      'placement_ids',jsonb_build_object('1',md5('VPC M14 corrected placement 1')::uuid,
        '2',md5('VPC M14 corrected placement 2')::uuid));
    response:=public.apply_round_robin_operation(payload);
    if (select team_id from public.division_placements where division_id=did and position=1 and deleted_at is null)
      is distinct from team_two or not exists(select 1 from public.match_result_revisions
        where operation_id=md5('VPC M14 correction')::uuid) then
      raise exception 'Correction standings or immutable audit failed';
    end if;
    raise exception using errcode='P1401',message='Rollback M14 synthetic assertions';
  exception when sqlstate 'P1401' then null; end;
  if exists(select 1 from public.events where id=eid) then raise exception 'M14 fixture rollback failed'; end if;
  if has_function_privilege('anon','public.apply_round_robin_operation(jsonb)','EXECUTE')
    or has_table_privilege('anon','public.matches','INSERT')
    or has_table_privilege('authenticated','public.match_result_revisions','UPDATE') then
    raise exception 'M14 security grants failed';
  end if;
  perform set_config('request.jwt.claim.sub',coalesce(saved,''),true);
end $$;
