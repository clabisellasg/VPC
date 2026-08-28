do $$
begin
  if to_regprocedure(
    'public.search_public_players(text,text,uuid,integer)'
  ) is null then
    raise exception 'M8 public player search function is missing';
  end if;

  if not has_function_privilege(
    'anon',
    'public.search_public_players(text,text,uuid,integer)',
    'execute'
  ) then
    raise exception 'Anonymous clients require public player search access';
  end if;

  if has_table_privilege('anon', 'public.user_profiles', 'select')
     or has_table_privilege('anon', 'public.user_roles', 'select')
     or has_table_privilege('anon', 'public.player_claim_requests', 'select') then
    raise exception 'M8 must not weaken private account or claim boundaries';
  end if;

  if has_table_privilege('anon', 'public.players', 'insert')
     or has_table_privilege('anon', 'public.players', 'update') then
    raise exception 'Anonymous player writes must remain denied';
  end if;
end;
$$;
