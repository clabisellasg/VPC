-- Catalog assertions for the append-only M16 round-order repair.
do $$
declare
  definition text;
begin
  select pg_get_functiondef(
    'public.apply_court_queue_operation(jsonb)'::regprocedure
  ) into definition;
  if definition not like '%m.round_number%' or
     definition not like '%m.sequence_number%' then
    raise exception 'M16 queue command must order by round and match position';
  end if;
  if has_function_privilege(
    'anon',
    'public.apply_court_queue_operation(jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Anonymous queue mutation permission detected';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.apply_court_queue_operation_m16_unordered(jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Core unordered queue command must remain private';
  end if;
end
$$;
