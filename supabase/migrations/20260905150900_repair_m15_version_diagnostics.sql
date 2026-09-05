-- Finalize the isolated version guard with actionable server-side diagnostics.
create or replace function private.assert_double_elimination_versions(
  p_event uuid,p_division uuid,p_expected bigint,p_payload jsonb,p_proposed jsonb)
returns void language plpgsql stable set search_path='' as $$
declare stored_bracket bigint; stored_event bigint; stored_division bigint;
begin
  select b.version into stored_bracket from public.double_elimination_brackets b
    where b.division_id=p_division and b.deleted_at is null;
  select e.version into stored_event from public.events e where e.id=p_event;
  select d.version into stored_division from public.event_divisions d where d.id=p_division;
  if coalesce(stored_bracket,-1)<>p_expected
    or stored_event is distinct from (p_payload->>'event_version')::bigint
    or stored_division is distinct from (p_payload->>'division_version')::bigint
    or (p_proposed->>'version')::bigint<>p_expected+1 then
    raise exception 'Double Elimination optimistic version conflict: bracket %/%, event %/%, division %/%, proposal %',
      stored_bracket,p_expected,stored_event,p_payload->>'event_version',stored_division,
      p_payload->>'division_version',p_proposed->>'version' using errcode='40001';
  end if;
end $$;
