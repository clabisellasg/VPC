-- Repair the M15 command's composite-row version guard. The original function
-- is otherwise preserved byte-for-byte from PostgreSQL's canonical definition.
do $repair$
declare definition text; old_guard text; new_guard text;
begin
  select pg_get_functiondef('public.apply_double_elimination_operation(jsonb)'::regprocedure)
    into definition;
  old_guard:=$guard$if coalesce(bracket_row.version,-1)<>expected
    or event_row.version is distinct from (p_payload->>'event_version')::bigint
    or division_row.version is distinct from (p_payload->>'division_version')::bigint
    or (proposed->>'version')::bigint<>expected+1 then
    raise exception 'Tournament version conflict' using errcode='40001'; end if;$guard$;
  new_guard:=$guard$if coalesce((select b.version from public.double_elimination_brackets b
      where b.division_id=did and b.deleted_at is null),-1)<>expected
    or not exists(select 1 from public.events e
      where e.id=eid and e.version=(p_payload->>'event_version')::bigint)
    or not exists(select 1 from public.event_divisions d
      where d.id=did and d.version=(p_payload->>'division_version')::bigint)
    or (proposed->>'version')::bigint<>expected+1 then
    raise exception 'Tournament version conflict' using errcode='40001'; end if;$guard$;
  if strpos(definition,old_guard)=0 then
    raise exception 'Expected M15 version guard was not found';
  end if;
  execute replace(definition,old_guard,new_guard);
end $repair$;
