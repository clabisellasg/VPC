-- Isolate optimistic-version checks from the large command function so local
-- PL/pgSQL row variables cannot affect identifier resolution.
create function private.assert_double_elimination_versions(
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
    raise exception 'Tournament version conflict' using errcode='40001';
  end if;
end $$;
revoke all on function private.assert_double_elimination_versions(uuid,uuid,bigint,jsonb,jsonb)
  from public,anon,authenticated;

do $repair$
declare definition text; old_guard text; new_guard text;
begin
  select pg_get_functiondef('public.apply_double_elimination_operation(jsonb)'::regprocedure)
    into definition;
  old_guard:=$guard$if coalesce((select b.version from public.double_elimination_brackets b
      where b.division_id=did and b.deleted_at is null),-1)<>expected
    or not exists(select 1 from public.events e
      where e.id=eid and e.version=(p_payload->>'event_version')::bigint)
    or not exists(select 1 from public.event_divisions d
      where d.id=did and d.version=(p_payload->>'division_version')::bigint)
    or (proposed->>'version')::bigint<>expected+1 then
    raise exception 'Tournament version conflict' using errcode='40001'; end if;$guard$;
  new_guard:=$guard$perform private.assert_double_elimination_versions(
    eid,did,expected,p_payload,proposed);$guard$;
  if strpos(definition,old_guard)=0 then
    raise exception 'Expected repaired M15 version guard was not found';
  end if;
  execute replace(definition,old_guard,new_guard);
end $repair$;
