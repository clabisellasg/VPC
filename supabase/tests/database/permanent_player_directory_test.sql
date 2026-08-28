begin;
select plan(9);

select has_function(
  'public',
  'search_public_players',
  array['text', 'text', 'uuid', 'integer'],
  'bounded public player search exists'
);
select function_privs_are(
  'public',
  'search_public_players',
  array['text', 'text', 'uuid', 'integer'],
  'anon',
  array['EXECUTE'],
  'anonymous users can execute only the fixed search function'
);
select ok(
  (select proconfig @> array['search_path=""']
   from pg_proc
   where oid = 'public.search_public_players(text,text,uuid,integer)'::regprocedure),
  'search function has an empty search path'
);
select ok(
  not (select prosecdef from pg_proc
       where oid = 'public.search_public_players(text,text,uuid,integer)'::regprocedure),
  'search uses invoker security and remains subject to RLS'
);
select ok(
  has_table_privilege('anon', 'public.players', 'select'),
  'anonymous clients retain public player reads'
);
select ok(
  not has_table_privilege('anon', 'public.players', 'insert'),
  'anonymous player inserts remain denied'
);
select ok(
  not has_table_privilege('anon', 'public.user_profiles', 'select'),
  'profiles remain private'
);
select ok(
  not has_table_privilege('anon', 'public.user_roles', 'select'),
  'roles remain private'
);
select ok(
  not has_table_privilege('anon', 'public.player_claim_requests', 'select'),
  'claims remain private'
);

select * from finish();
rollback;
