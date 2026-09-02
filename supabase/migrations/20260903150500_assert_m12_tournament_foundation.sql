-- Transactional synthetic assertions. All fixture rows and receipts roll back.
-- Existing organizer/member IDs are read internally, never printed or changed.
do $$
declare
  actor uuid; member_actor uuid;
  prior_claim text := current_setting('request.jwt.claim.sub',true);
  e constant uuid := '12000000-0000-4000-8000-000000009001';
  d constant uuid := '12000000-0000-4000-8000-000000009002';
  op constant uuid := '12000000-0000-4000-8000-000000009003';
  payload jsonb; result jsonb; score record;
begin
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.apply_event_setup_operation(op,e,0,'{}');
    raise exception 'Anonymous command unexpectedly allowed';
  exception when insufficient_privilege then null; end;
  select ur.user_id into actor from public.user_roles ur where ur.role='organizer' and ur.deleted_at is null limit 1;
  select u.id into member_actor from auth.users u where not exists(
    select 1 from public.user_roles r where r.user_id=u.id and r.role='organizer' and r.deleted_at is null) limit 1;
  if member_actor is not null then
    perform set_config('request.jwt.claim.sub',member_actor::text,true);
    begin
      perform public.apply_event_setup_operation(op,e,0,'{}');
      raise exception 'Member command unexpectedly allowed';
    exception when insufficient_privilege then null; end;
  else raise notice 'No member available: member command assertion skipped'; end if;
  if actor is null then raise exception 'M12 hosted assertions require an existing organizer'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  begin
    insert into public.events(id,name,scheduled_at,event_type,status,court_label)
      values(e,'VPC M12 Transactional Fixture',now(),'formal','registration','Sample Court');
    insert into public.event_divisions(id,event_id,name,tournament_format) values(d,e,'Sample Open',null);
    payload := private.event_setup_json(e) - 'readiness';
    payload := jsonb_set(payload,'{event,version}','1');
    payload := jsonb_set(payload,'{divisions,0,version}','1');
    payload := jsonb_set(payload,'{divisions,0,tournament_format}','"singleElimination"');
    result := public.apply_event_setup_operation(op,e,0,payload);
    if result->>'status'<>'accepted' then raise exception 'Format selection failed'; end if;
    if exists(select 1 from public.matches where division_id=d) then raise exception 'Selection generated matches'; end if;
    result := public.apply_event_setup_operation(op,e,0,payload);
    if result->>'replayed'<>'true' then raise exception 'Format replay failed'; end if;
    begin
      perform public.apply_event_setup_operation(op,e,0,jsonb_set(payload,'{divisions,0,tournament_format}','"doubleElimination"'));
      raise exception 'Changed-payload replay unexpectedly allowed';
    exception when invalid_parameter_value then null; end;
    begin
      update public.event_divisions set tournament_format='inventedFormat' where id=d;
      raise exception 'Invalid format unexpectedly allowed';
    exception when check_violation then null; end;
    begin
      update public.events set status='inProgress' where id=e;
      raise exception 'Empty event unexpectedly started';
    exception when check_violation then null; end;
    insert into public.teams(id,division_id,formation_method) values
      ('12000000-0000-4000-8000-000000009004',d,'manual'),
      ('12000000-0000-4000-8000-000000009005',d,'manual');
    -- Pure test structure, not a tournament generator or persisted fixture.
    insert into public.matches(id,division_id,status) values('12000000-0000-4000-8000-000000009006',d,'scheduled');
    begin
      update public.event_divisions set tournament_format='doubleRoundRobin' where id=d;
      raise exception 'Generated format unexpectedly changed';
    exception when check_violation then null; end;
    begin
      update public.events set status='inProgress' where id=e;
      raise exception 'Incomplete teams unexpectedly allowed to start';
    exception when check_violation then null; end;
    for score in select * from (values(11,0,true),(11,9,true),(12,10,true),(15,13,true),
      (10,8,false),(11,10,false),(12,9,false),(13,10,false),(11,11,false),(-1,11,false)) v(a,b,valid)
    loop
      begin
        insert into public.matches(id,division_id,status,side_one_team_id,side_two_team_id,side_one_score,side_two_score,winner_team_id)
        values('12000000-0000-4000-8000-000000009007',d,'completed',
          '12000000-0000-4000-8000-000000009004','12000000-0000-4000-8000-000000009005',score.a,score.b,
          '12000000-0000-4000-8000-000000009004');
        if not score.valid then raise exception 'Invalid final score accepted'; end if;
        raise exception using errcode='P1201',message='Rollback score fixture';
      exception when sqlstate 'P1201' then null;
        when check_violation then if score.valid then raise exception 'Valid final score rejected'; end if;
      end;
    end loop;
    raise exception using errcode='P1202',message='Rollback M12 fixtures';
  exception when sqlstate 'P1202' then null; end;
  if exists(select 1 from public.events where id=e) then raise exception 'M12 fixture rollback failed'; end if;
  perform set_config('request.jwt.claim.sub',coalesce(prior_claim,''),true);
end $$;
