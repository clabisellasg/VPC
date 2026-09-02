do $$ begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='players' and column_name='skill_level' and is_nullable='YES') then raise exception 'players.skill_level must be nullable'; end if;
  if has_function_privilege('anon','public.apply_team_formation_operation(uuid,uuid,uuid,jsonb)','execute') then raise exception 'anon must not apply teams'; end if;
  if has_function_privilege('authenticated','public.apply_team_formation_operation(uuid,uuid,uuid,jsonb)','execute') is not true then raise exception 'authenticated command grant missing'; end if;
  if has_table_privilege('anon','private.team_formation_operation_receipts','select') then raise exception 'receipts must remain private'; end if;
end $$;
