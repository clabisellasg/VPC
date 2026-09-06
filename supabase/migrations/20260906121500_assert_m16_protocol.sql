-- M16 security/protocol assertions use deterministic data and roll it back.
do $$
declare
  actor uuid; member_actor uuid; saved text:=current_setting('request.jwt.claim.sub',true);
  eid uuid:=md5('VPC M16 event')::uuid; did uuid:=md5('VPC M16 division')::uuid;
  t1 uuid:=md5('VPC M16 team one')::uuid; t2 uuid:=md5('VPC M16 team two')::uuid;
  t3 uuid:=md5('VPC M16 team three')::uuid; t4 uuid:=md5('VPC M16 team four')::uuid;
  m1 uuid:=md5('VPC M16 match one')::uuid; m2 uuid:=md5('VPC M16 match two')::uuid;
  q1 uuid:=md5('VPC M16 queue one')::uuid; q2 uuid:=md5('VPC M16 queue two')::uuid;
  payload jsonb; response jsonb; stage text:='fixture';
begin
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.apply_court_queue_operation('{}'); raise exception 'Anonymous write accepted';
    exception when insufficient_privilege then null; end;
  select user_id into actor from public.user_roles where role='organizer' and deleted_at is null limit 1;
  select u.id into member_actor from auth.users u where not exists(select 1 from public.user_roles r
    where r.user_id=u.id and r.role='organizer' and r.deleted_at is null) limit 1;
  if actor is null or member_actor is null then raise exception 'M16 assertions need existing organizer and member accounts'; end if;
  perform set_config('request.jwt.claim.sub',member_actor::text,true);
  begin perform public.apply_court_queue_operation('{}'); raise exception 'Member write accepted';
    exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  begin
    insert into public.events(id,name,scheduled_at,event_type,status,court_label)
      values(eid,'VPC M16 Rollback Fixture',clock_timestamp(),'formal','inProgress','VPC Sample Court');
    insert into public.event_divisions(id,event_id,name,tournament_format)
      values(did,eid,'VPC M16 Sample','singleElimination');
    insert into public.teams(id,division_id,formation_method) values
      (t1,did,'manual'),(t2,did,'manual'),(t3,did,'manual'),(t4,did,'manual');
    insert into public.matches(id,division_id,side_one_team_id,side_two_team_id,status,round_number,sequence_number) values
      (m1,did,t1,t2,'queued',1,1),(m2,did,t3,t4,'queued',1,2);
    payload:=jsonb_build_object('operation_id',md5('VPC M16 reconcile')::uuid,'event_id',eid,
      'action','reconcile','created_at',clock_timestamp(),'match_id',null,'expected_match_version',-1,
      'entry_ids',jsonb_build_object(m1::text,q1,m2::text,q2));
    stage:='reconcile'; response:=public.apply_court_queue_operation(payload);
    if jsonb_array_length(response->'queue')<>2 or public.apply_court_queue_operation(payload)<>response then
      raise exception 'Reconcile or identical replay failed'; end if;
    begin perform public.apply_court_queue_operation(payload||jsonb_build_object('created_at',clock_timestamp()+interval '1 second'));
      raise exception 'Changed replay accepted'; exception when serialization_failure then null; end;
    payload:=jsonb_build_object('operation_id',md5('VPC M16 stale start')::uuid,'event_id',eid,
      'action','start','created_at',clock_timestamp(),'match_id',m1,'expected_match_version',9,'entry_ids','{}'::jsonb);
    stage:='stale start';
    begin perform public.apply_court_queue_operation(payload); raise exception 'Stale start accepted';
      exception when serialization_failure then null; end;
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M16 start')::uuid,'expected_match_version',0);
    stage:='start'; response:=public.apply_court_queue_operation(payload);
    if response->'current'->>'id'<>m1::text or response->'current_entry'->>'match_id'<>m1::text then
      raise exception 'Current match or durable entry missing'; end if;
    payload:=payload||jsonb_build_object('operation_id',md5('VPC M16 second start')::uuid,'match_id',m2);
    stage:='second start';
    begin perform public.apply_court_queue_operation(payload); raise exception 'Second current match accepted';
      exception when serialization_failure then null; end;
    begin update public.matches set status='inProgress' where id=m2;
      raise exception 'Direct second current match accepted'; exception when unique_violation then null; end;
    raise exception using errcode='P1601',message='Rollback M16 synthetic assertions';
  exception when sqlstate 'P1601' then null;
    when others then raise exception 'M16 assertion stage % failed: %',stage,sqlerrm; end;
  if exists(select 1 from public.events where id=eid) then raise exception 'M16 fixture rollback failed'; end if;
  if has_function_privilege('anon','public.apply_court_queue_operation(jsonb)','execute')
    or has_table_privilege('anon','private.court_queue_operation_receipts','select') then
    raise exception 'M16 security boundary failed'; end if;
  perform set_config('request.jwt.claim.sub',coalesce(saved,''),true);
end $$;
