-- Regression assertion for playable-match numbering when an odd-team round has a BYE.
do $$
declare
  actor uuid;
  saved text:=current_setting('request.jwt.claim.sub',true);
  eid uuid:=md5('VPC M14 odd repair event')::uuid;
  did uuid:=md5('VPC M14 odd repair division')::uuid;
  team_ids uuid[]:=array[
    md5('VPC M14 odd repair team 1')::uuid,
    md5('VPC M14 odd repair team 2')::uuid,
    md5('VPC M14 odd repair team 3')::uuid
  ];
  team_id uuid;
  player_id uuid;
  participant_id uuid;
  assignment_id uuid;
  payload jsonb;
  response jsonb;
  team_versions jsonb:='{}'::jsonb;
  match_ids jsonb:='{}'::jsonb;
  i integer;
  j integer;
begin
  select user_id into actor
    from public.user_roles
    where role='organizer' and deleted_at is null
    limit 1;
  if actor is null then
    raise exception 'M14 odd-team assertion needs an existing organizer account';
  end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  begin
    insert into public.events(id,name,scheduled_at,event_type,status,court_label)
      values(eid,'VPC M14 Odd Repair Fixture',clock_timestamp(),'formal','registration','VPC Sample Court');
    insert into public.event_divisions(id,event_id,name,tournament_format)
      values(did,eid,'VPC M14 Odd Repair','singleRoundRobin');
    for i in 1..3 loop
      team_id:=team_ids[i];
      insert into public.teams(id,division_id,formation_method)
        values(team_id,did,'manual');
      team_versions:=team_versions||jsonb_build_object(team_id::text,0);
      for j in 1..2 loop
        player_id:=md5('VPC M14 odd repair player '||i||':'||j)::uuid;
        participant_id:=md5('VPC M14 odd repair participant '||i||':'||j)::uuid;
        assignment_id:=md5('VPC M14 odd repair assignment '||i||':'||j)::uuid;
        insert into public.players(id,display_name)
          values(player_id,'VPC M14 Odd Sample '||i||'-'||j);
        insert into public.event_participants(id,event_id,player_id,check_in_status)
          values(participant_id,eid,player_id,'checkedIn');
        insert into public.division_participants(id,division_id,event_participant_id)
          values(assignment_id,did,participant_id);
        insert into public.team_members(team_id,player_id) values(team_id,player_id);
      end loop;
    end loop;
    match_ids:=jsonb_build_object(
      'rr/r1/m1',md5('VPC M14 odd repair match 1')::uuid,
      'rr/r2/m1',md5('VPC M14 odd repair match 2')::uuid,
      'rr/r3/m1',md5('VPC M14 odd repair match 3')::uuid);
    payload:=jsonb_build_object(
      'operation_id',md5('VPC M14 odd repair generation')::uuid,
      'event_id',eid,
      'division_id',did,
      'action','generate',
      'expected_version',-1,
      'event_version',0,
      'division_version',0,
      'created_at',clock_timestamp(),
      'seed_order',to_jsonb(team_ids),
      'team_versions',team_versions,
      'match_ids',match_ids,
      'placement_ids','{}'::jsonb);
    response:=public.apply_round_robin_operation(payload);
    if jsonb_array_length(response->'tournament'->'matches')<>3
      or exists(
        select 1 from jsonb_array_elements(response->'tournament'->'matches') item
        where item->>'key' not in ('rr/r1/m1','rr/r2/m1','rr/r3/m1')
      ) then
      raise exception 'Odd-team playable match keys are not contiguous';
    end if;
    raise exception using errcode='P1402',message='Rollback M14 odd-team assertion';
  exception when sqlstate 'P1402' then null; end;
  if exists(select 1 from public.events where id=eid) then
    raise exception 'M14 odd-team assertion rollback failed';
  end if;
  perform set_config('request.jwt.claim.sub',coalesce(saved,''),true);
end $$;
