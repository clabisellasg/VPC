-- M16 repair: a generated READY match becomes court-eligible only while its
-- event is In Progress. The applied M16 migration remains unchanged.
create or replace function private.court_queue_context(p_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
with match_rows as (
  select m.*, d.event_id, d.name division_name, d.tournament_format,
    coalesce(t1.display_label,
      (select string_agg(p.display_name,' / ' order by tm.player_id)
       from public.team_members tm join public.players p on p.id=tm.player_id
       where tm.team_id=t1.id and tm.deleted_at is null and p.deleted_at is null),
      'TBD') side_one_label,
    coalesce(t2.display_label,
      (select string_agg(p.display_name,' / ' order by tm.player_id)
       from public.team_members tm join public.players p on p.id=tm.player_id
       where tm.team_id=t2.id and tm.deleted_at is null and p.deleted_at is null),
      'TBD') side_two_label
  from public.matches m
  join public.event_divisions d on d.id=m.division_id
  join public.events e on e.id=d.event_id
  left join public.teams t1 on t1.id=m.side_one_team_id
  left join public.teams t2 on t2.id=m.side_two_team_id
  where d.event_id=p_event_id and e.status='inProgress'
    and e.deleted_at is null and d.deleted_at is null and m.deleted_at is null
    and d.tournament_format is not null
), active_queue as (
  select q.*, to_jsonb(mr) match
  from public.court_queue_entries q join match_rows mr on mr.id=q.match_id
  where q.event_id=p_event_id and q.deleted_at is null
    and mr.status in ('queued','inProgress')
)
select jsonb_build_object(
  'event_id',p_event_id,
  'current',(select to_jsonb(mr) from match_rows mr where mr.status='inProgress' order by mr.id limit 1),
  'current_entry',(select to_jsonb(aq) from active_queue aq where aq.match->>'status'='inProgress' order by aq.id limit 1),
  'queue',coalesce((select jsonb_agg(to_jsonb(aq) order by aq.queue_position,aq.id)
    from active_queue aq where aq.match->>'status'='queued'),'[]'::jsonb),
  'unqueued_ready',coalesce((select jsonb_agg(to_jsonb(mr) order by mr.division_id,coalesce(mr.sequence_number,0),mr.id)
    from match_rows mr where mr.status='queued' and mr.side_one_team_id is not null
      and mr.side_two_team_id is not null and not exists(
        select 1 from public.court_queue_entries q where q.match_id=mr.id and q.deleted_at is null)),'[]'::jsonb),
  'completed_history',coalesce((select jsonb_agg(to_jsonb(mr) order by mr.updated_at,mr.id)
    from match_rows mr where mr.status='completed' and exists(
      select 1 from public.court_queue_entries q where q.match_id=mr.id)),'[]'::jsonb),
  'disposition','synchronized')
where exists(select 1 from public.events e where e.id=p_event_id and e.deleted_at is null)
$$;

create or replace function public.apply_court_queue_operation(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_operation_id uuid; v_event_id uuid; v_action text; v_match_id uuid;
  v_expected_version bigint; v_event_status text; stamp timestamptz:=clock_timestamp();
  prior private.court_queue_operation_receipts%rowtype;
  ready_match record; next_position bigint;
  response jsonb; allowed_keys text[]:=array['operation_id','event_id','action','created_at','match_id','expected_match_version','entry_ids'];
begin
  if not private.is_organizer() then raise exception 'Organizer permission required' using errcode='42501'; end if;
  if jsonb_typeof(p_payload)<>'object' or exists(
    select 1 from jsonb_object_keys(p_payload) payload_key where not (payload_key=any(allowed_keys))) then
    raise exception 'Invalid court command payload' using errcode='23514';
  end if;
  v_operation_id:=(p_payload->>'operation_id')::uuid;
  v_event_id:=(p_payload->>'event_id')::uuid;
  v_action:=p_payload->>'action';
  v_expected_version:=(p_payload->>'expected_match_version')::bigint;
  if v_action not in ('reconcile','start') or jsonb_typeof(coalesce(p_payload->'entry_ids','{}'))<>'object' then
    raise exception 'Invalid court command' using errcode='23514'; end if;

  select * into prior from private.court_queue_operation_receipts receipt
    where receipt.operation_id=v_operation_id;
  if found then
    if prior.payload<>p_payload then raise exception 'Operation identity reused with changed payload' using errcode='40001'; end if;
    return prior.response;
  end if;
  select e.status into v_event_status from public.events e
    where e.id=v_event_id and e.deleted_at is null for update;
  if not found then raise exception 'Event not found' using errcode='P0002'; end if;

  if v_action='reconcile' then
    update public.court_queue_entries q set deleted_at=stamp,updated_at=stamp,version=q.version+1
    where q.event_id=v_event_id and q.deleted_at is null and (
      v_event_status<>'inProgress' or exists(
        select 1 from public.matches m where m.id=q.match_id
          and (m.deleted_at is not null or m.status not in ('queued','inProgress'))));
    select coalesce(max(q.queue_position),-1)+1 into next_position
      from public.court_queue_entries q where q.event_id=v_event_id and q.deleted_at is null;
    if v_event_status='inProgress' then
      for ready_match in
        select m.id,m.division_id from public.matches m
        join public.event_divisions d on d.id=m.division_id
        where d.event_id=v_event_id and d.deleted_at is null and m.deleted_at is null
          and m.status='queued' and m.side_one_team_id is not null and m.side_two_team_id is not null
          and not exists(select 1 from public.court_queue_entries q where q.match_id=m.id and q.deleted_at is null)
        order by d.id,coalesce(m.sequence_number,0),m.id
      loop
        if not (p_payload->'entry_ids' ? ready_match.id::text) then
          raise exception 'Queue candidates changed' using errcode='40001'; end if;
        insert into public.court_queue_entries(id,event_id,division_id,match_id,queue_position,created_at,updated_at,version)
        values((p_payload->'entry_ids'->>ready_match.id::text)::uuid,v_event_id,ready_match.division_id,ready_match.id,next_position,stamp,stamp,0);
        next_position:=next_position+1;
      end loop;
    end if;
  else
    if v_event_status<>'inProgress' then
      raise exception 'Court operation requires an In Progress event' using errcode='23514'; end if;
    v_match_id:=(p_payload->>'match_id')::uuid;
    if exists(select 1 from public.matches m join public.event_divisions d on d.id=m.division_id
      where d.event_id=v_event_id and m.status='inProgress' and m.deleted_at is null) then
      raise exception 'Another match is already Now Playing' using errcode='40001'; end if;
    update public.matches m set status='inProgress',updated_at=stamp,version=m.version+1
    from public.event_divisions d, public.court_queue_entries q
    where m.id=v_match_id and d.id=m.division_id and d.event_id=v_event_id
      and q.match_id=m.id and q.event_id=v_event_id and q.deleted_at is null
      and m.status='queued' and m.deleted_at is null and m.version=v_expected_version;
    if not found then raise exception 'Queued match changed or is ineligible' using errcode='40001'; end if;
  end if;
  response:=private.court_queue_context(v_event_id);
  insert into private.court_queue_operation_receipts(operation_id,event_id,payload,response,applied_by)
    values(v_operation_id,v_event_id,p_payload,response,(select auth.uid()));
  return response;
end $$;

revoke all on function private.court_queue_context(uuid) from public,anon,authenticated;
revoke all on function public.apply_court_queue_operation(jsonb) from public,anon,authenticated;
grant execute on function public.apply_court_queue_operation(jsonb) to authenticated;
notify pgrst, 'reload schema';
