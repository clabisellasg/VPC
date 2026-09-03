-- Synthetic fixtures and all operation receipts roll back. No accounts or
-- organizer roles are created and no existing community data is changed.
do $$
declare actor uuid; member_actor uuid; saved text:=current_setting('request.jwt.claim.sub',true);
  eid uuid:=md5('VPC M13 event')::uuid; did uuid; team uuid; player uuid; participant uuid;
  n int; i int; j int; round_no int; width int; pos int; bracket_size int;
  order_ids jsonb; versions jsonb; ids jsonb; payload jsonb; response jsonb; repeated jsonb;
  k text; op uuid; counter int:=0; root_version bigint; played jsonb; match_key text;
begin
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.apply_single_elimination_operation('{}'); raise exception 'Anonymous write accepted';
    exception when insufficient_privilege then null; end;
  select user_id into actor from public.user_roles where role='organizer' and deleted_at is null limit 1;
  select u.id into member_actor from auth.users u where not exists(select 1 from public.user_roles r where r.user_id=u.id and r.role='organizer' and r.deleted_at is null) limit 1;
  if actor is null or member_actor is null then raise exception 'M13 assertions need existing organizer and member accounts'; end if;
  perform set_config('request.jwt.claim.sub',member_actor::text,true);
  begin perform public.apply_single_elimination_operation('{}'); raise exception 'Member write accepted';
    exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  begin
    insert into public.events(id,name,scheduled_at,event_type,status,court_label)
      values(eid,'VPC M13 Rollback Fixture',clock_timestamp(),'formal','registration','VPC Sample Court');
    for n in 2..8 loop
      did:=md5('VPC M13 division '||n)::uuid;
      insert into public.event_divisions(id,event_id,name,tournament_format) values(did,eid,'VPC Sample '||n,'singleElimination');
      order_ids:='[]';versions:='{}';ids:='{}';
      for i in 1..n loop
        team:=md5('VPC M13 team '||n||':'||i)::uuid;
        insert into public.teams(id,division_id,formation_method) values(team,did,'manual');
        order_ids:=order_ids||to_jsonb(team);versions:=versions||jsonb_build_object(team::text,0);
        for j in 1..2 loop
          player:=md5('VPC M13 player '||n||':'||i||':'||j)::uuid;
          participant:=md5('VPC M13 participant '||n||':'||i||':'||j)::uuid;
          insert into public.players(id,display_name) values(player,'VPC M13 Sample '||n||'-'||i||'-'||j);
          insert into public.event_participants(id,event_id,player_id,check_in_status) values(participant,eid,player,'checkedIn');
          insert into public.division_participants(id,division_id,event_participant_id) values(md5(participant::text||'division')::uuid,did,participant);
          insert into public.team_members(team_id,player_id) values(team,player);
        end loop;
      end loop;
      -- Include only real planned matches, using the same documented seed slots.
      bracket_size:=2;while bracket_size<n loop bracket_size:=bracket_size*2;end loop;
      width:=bracket_size/2;round_no:=1;
      while width>0 loop
        for pos in 1..width loop
          -- First-round byes remove exactly size-N slots. Seed placement means
          -- real first-round cells can be determined by the independent helper
          -- expression below, not by a stored match row.
          k:='se/r'||round_no||'/m'||pos;
          ids:=ids||jsonb_build_object(k,md5('VPC M13 match '||n||':'||k)::uuid);
        end loop;
        width:=width/2;round_no:=round_no+1;
      end loop;
      -- For non-powers of two the known first-round bye cells are removed.
      if n=3 then ids:=ids-'se/r1/m1';end if;
      if n=5 then ids:=ids-'se/r1/m1'-'se/r1/m3'-'se/r1/m4';end if;
      if n=6 then ids:=ids-'se/r1/m1'-'se/r1/m3';end if;
      if n=7 then ids:=ids-'se/r1/m1';end if;
      op:=md5('VPC M13 generate '||n)::uuid;
      payload:=jsonb_build_object('operation_id',op,'event_id',eid,'division_id',did,'action','generate',
        'expected_version',-1,'event_version',0,'division_version',0,'created_at',clock_timestamp(),
        'seed_order',order_ids,'team_versions',versions,'match_ids',ids,'placement_ids','{}'::jsonb,
        'match_key',null,'score_one',null,'score_two',null,'reason',null);
      response:=public.apply_single_elimination_operation(payload);
      if jsonb_array_length(response->'bracket'->'matches')<>n-1 then raise exception 'Wrong playable match count';end if;
      if exists(select 1 from public.matches where division_id=did and status='completed') then raise exception 'Bye recorded as played';end if;
      repeated:=public.apply_single_elimination_operation(payload);
      if repeated<>response then raise exception 'Replay was not identical';end if;
      begin perform public.apply_single_elimination_operation(payload||jsonb_build_object('reason','changed'));
        raise exception 'Changed-payload replay accepted'; exception when unique_violation then null;end;
    end loop;
    update public.events set status='inProgress',version=1 where id=eid;
    did:=md5('VPC M13 division 4')::uuid;
    response:=public.get_single_elimination_context(eid,did);
    -- Play the first semifinal, audit an allowed winner-changing correction,
    -- then finish the other semifinal and final.
    for played in select value from jsonb_array_elements(response->'bracket'->'matches') loop
      match_key:=played->>'planned_key';
      foreach k in array array['start','result'] loop
        response:=public.get_single_elimination_context(eid,did);
        counter:=counter+1;op:=md5('VPC M13 result '||counter)::uuid;
        payload:=jsonb_build_object('operation_id',op,'event_id',eid,'division_id',did,'action',k,
          'expected_version',(response->'bracket'->>'version')::bigint,'event_version',1,'division_version',0,
          'created_at',clock_timestamp(),'seed_order','[]'::jsonb,'team_versions','{}'::jsonb,'match_ids','{}'::jsonb,
          'placement_ids',jsonb_build_object('1',md5(op::text||'one')::uuid,'2',md5(op::text||'two')::uuid),
          'match_key',match_key,'score_one',11,'score_two',3,'reason',null);
        response:=public.apply_single_elimination_operation(payload);
        if public.apply_single_elimination_operation(payload)<>response then raise exception 'Result replay failed';end if;
      end loop;
      if match_key='se/r1/m1' then
        payload:=payload||jsonb_build_object('operation_id',md5('VPC M13 correction')::uuid,'action','correct',
          'expected_version',(response->'bracket'->>'version')::bigint,'score_one',9,'score_two',11,'reason','VPC synthetic reversed score');
        response:=public.apply_single_elimination_operation(payload);
        if not exists(select 1 from public.match_result_revisions where operation_id=md5('VPC M13 correction')::uuid) then raise exception 'Missing immutable revision';end if;
      end if;
    end loop;
    if (select count(*) from public.division_placements where division_id=did and deleted_at is null)<>2 then raise exception 'Final placements missing';end if;
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M13 blocked correction')::uuid,'action','correct','match_key','se/r1/m1',
      'expected_version',(response->'bracket'->>'version')::bigint,'score_one',11,'score_two',9,'reason','VPC blocked correction');
    begin perform public.apply_single_elimination_operation(payload);raise exception 'Played downstream correction accepted';
      exception when check_violation then null;end;
    begin update public.match_result_revisions set reason='changed';raise exception 'Revision update accepted';
      exception when check_violation then null;end;
    raise exception using errcode='P1301',message='Rollback M13 synthetic assertions';
  exception when sqlstate 'P1301' then null;end;
  if exists(select 1 from public.events where id=eid) then raise exception 'M13 fixture rollback failed';end if;
  if has_table_privilege('anon','public.matches','INSERT') or has_table_privilege('authenticated','public.matches','UPDATE')
    or has_table_privilege('anon','public.match_result_revisions','SELECT')
    or has_function_privilege('anon','public.apply_single_elimination_operation(jsonb)','EXECUTE') then
    raise exception 'M13 security grants failed';end if;
  perform set_config('request.jwt.claim.sub',coalesce(saved,''),true);
end $$;
