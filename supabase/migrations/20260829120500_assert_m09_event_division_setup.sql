do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='event_divisions'
      and column_name='tournament_format' and is_nullable <> 'YES'
  ) then raise exception 'event_divisions.tournament_format must be nullable'; end if;
  if has_function_privilege('anon', 'public.apply_event_setup_operation(uuid,uuid,bigint,jsonb)', 'EXECUTE')
  then raise exception 'anonymous aggregate mutation must be denied'; end if;
  if not has_function_privilege('authenticated', 'public.apply_event_setup_operation(uuid,uuid,bigint,jsonb)', 'EXECUTE')
  then raise exception 'authenticated aggregate RPC grant is missing'; end if;
end $$;
