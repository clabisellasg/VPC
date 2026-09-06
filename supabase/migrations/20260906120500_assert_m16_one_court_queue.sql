do $$
begin
  if to_regclass('private.court_queue_operation_receipts') is null then
    raise exception 'M16 receipt table missing'; end if;
  if has_table_privilege('anon','private.court_queue_operation_receipts','select')
    or has_table_privilege('authenticated','private.court_queue_operation_receipts','select') then
    raise exception 'M16 receipts must remain private'; end if;
  if not has_function_privilege('anon','public.get_court_queue_context(uuid)','execute')
    or not has_function_privilege('authenticated','public.get_court_queue_context(uuid)','execute') then
    raise exception 'Public court queue read grant missing'; end if;
  if has_function_privilege('anon','public.apply_court_queue_operation(jsonb)','execute')
    or not has_function_privilege('authenticated','public.apply_court_queue_operation(jsonb)','execute') then
    raise exception 'Court mutation grants are incorrect'; end if;
  if not exists(select 1 from pg_trigger where tgname='matches_one_current_court_guard' and not tgisinternal) then
    raise exception 'One-current-match guard missing'; end if;
  if not exists(select 1 from pg_proc where oid='public.apply_court_queue_operation(jsonb)'::regprocedure
    and prosecdef and proconfig @> array['search_path=""']) then
    raise exception 'Court command security/search_path is incorrect'; end if;
end $$;
