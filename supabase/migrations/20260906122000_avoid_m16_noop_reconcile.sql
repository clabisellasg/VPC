-- Avoid producing idempotency receipts/outbox work for unchanged refreshes by
-- exposing whether an active queue entry has become ineligible.
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
  'has_ineligible_entries',exists(
    select 1 from public.court_queue_entries q where q.event_id=p_event_id and q.deleted_at is null
      and not exists(select 1 from active_queue aq where aq.id=q.id)),
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

revoke all on function private.court_queue_context(uuid) from public,anon,authenticated;
notify pgrst, 'reload schema';
