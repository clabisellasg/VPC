-- Add the public event label to queue responses without changing the applied
-- core queue implementation or exposing any private event/account data.
alter function private.court_queue_context(uuid)
  rename to court_queue_context_core;

create function private.court_queue_context(p_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select private.court_queue_context_core(p_event_id)
    || jsonb_build_object('event_name',e.name)
  from public.events e
  where e.id=p_event_id and e.deleted_at is null
$$;

revoke all on function private.court_queue_context_core(uuid),
  private.court_queue_context(uuid) from public,anon,authenticated;
notify pgrst, 'reload schema';
