-- Round Robin sequence_number restarts within each round. Preserve durable
-- arrival batches while ordering matches inside a batch by round, then match
-- position. Keep the already-applied M16 command implementation intact behind
-- a least-privilege wrapper.
alter function public.apply_court_queue_operation(jsonb)
  rename to apply_court_queue_operation_m16_unordered;

create function public.apply_court_queue_operation(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  core_response jsonb;
  v_event_id uuid;
begin
  core_response := public.apply_court_queue_operation_m16_unordered(p_payload);
  v_event_id := (core_response->>'event_id')::uuid;

  update public.court_queue_entries q
  set queue_position=q.queue_position+100000000
  where q.event_id=v_event_id and q.deleted_at is null;

  with ranked as (
    select q.id,
      row_number() over (
        order by q.created_at,d.id,coalesce(m.round_number,0),
          coalesce(m.sequence_number,0),m.id
      )-1 as queue_position
    from public.court_queue_entries q
    join public.matches m on m.id=q.match_id
    join public.event_divisions d on d.id=m.division_id
    where q.event_id=v_event_id and q.deleted_at is null
  )
  update public.court_queue_entries q
  set queue_position=ranked.queue_position
  from ranked
  where q.id=ranked.id;

  return private.court_queue_context(v_event_id);
end
$$;

revoke all on function public.apply_court_queue_operation_m16_unordered(jsonb)
  from public,anon,authenticated;
revoke all on function public.apply_court_queue_operation(jsonb) from public;
grant execute on function public.apply_court_queue_operation(jsonb)
  to authenticated;

-- Repair active entries created by the earlier sequence-before-round order.
update public.court_queue_entries q
set queue_position=q.queue_position+100000000
where q.deleted_at is null;

with ranked as (
  select q.id,
    row_number() over (
      partition by q.event_id
      order by q.created_at,d.id,coalesce(m.round_number,0),
        coalesce(m.sequence_number,0),m.id
    )-1 as queue_position
  from public.court_queue_entries q
  join public.matches m on m.id=q.match_id
  join public.event_divisions d on d.id=m.division_id
  where q.deleted_at is null
)
update public.court_queue_entries q
set queue_position=ranked.queue_position
from ranked
where q.id=ranked.id;

notify pgrst, 'reload schema';
