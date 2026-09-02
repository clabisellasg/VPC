do $$
begin
  if has_function_privilege('anon', 'public.apply_participation_operation(uuid,uuid,bigint,jsonb)', 'execute') then
    raise exception 'anon must not execute participation mutations';
  end if;
  if not has_function_privilege('authenticated', 'public.apply_participation_operation(uuid,uuid,bigint,jsonb)', 'execute') then
    raise exception 'authenticated organizer command grant is missing';
  end if;
  if has_table_privilege('anon', 'public.participant_payments', 'select') then
    raise exception 'payments must remain private';
  end if;
  if has_table_privilege('anon', 'private.participation_operation_receipts', 'select')
    or has_table_privilege('authenticated', 'private.participation_operation_receipts', 'select') then
    raise exception 'participation receipts must remain private';
  end if;
end;
$$;
