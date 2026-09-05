-- Keep a distinct stable error message so hosted assertions can prove the
-- isolated M15 version guard is the active source of optimistic conflicts.
create or replace function private.assert_double_elimination_versions(
  p_event uuid,p_division uuid,p_expected bigint,p_payload jsonb,p_proposed jsonb)
returns void language plpgsql stable set search_path='' as $$
begin
  if coalesce((select b.version from public.double_elimination_brackets b
      where b.division_id=p_division and b.deleted_at is null),-1)<>p_expected
    or not exists(select 1 from public.events e where e.id=p_event
      and e.version=(p_payload->>'event_version')::bigint)
    or not exists(select 1 from public.event_divisions d where d.id=p_division
      and d.version=(p_payload->>'division_version')::bigint)
    or (p_proposed->>'version')::bigint<>p_expected+1 then
    raise exception 'Double Elimination optimistic version conflict' using errcode='40001';
  end if;
end $$;
