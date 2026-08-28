begin;
select plan(22);

select has_table('public', 'player_claim_requests', 'claim table exists');
select has_column('public', 'user_profiles', 'player_id', 'private profile stores player link');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.player_claim_requests'::regclass),
  'claim RLS is enabled'
);
select ok(
  not has_table_privilege('anon', 'public.player_claim_requests', 'select'),
  'anonymous clients have no claim-table read grant'
);
select ok(
  not has_table_privilege('authenticated', 'public.player_claim_requests', 'insert'),
  'members cannot bypass request RPC'
);
select ok(
  not has_column_privilege('authenticated', 'public.user_profiles', 'player_id', 'update'),
  'members cannot directly link players'
);
select ok(
  not has_table_privilege('authenticated', 'public.user_roles', 'update'),
  'members cannot edit roles'
);
select function_returns(
  'public', 'approve_player_claim', array['uuid'], 'jsonb',
  'atomic approval function exists'
);

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  (
    '74000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
    'member@example.invalid', '{"display_name":"M7 Test Member"}', now(), now()
  ),
  (
    '74000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
    'organizer@example.invalid', '{"display_name":"M7 Test Organizer"}', now(), now()
  ),
  (
    '74000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
    'other@example.invalid', '{"display_name":"M7 Other Member"}', now(), now()
  );

insert into public.user_roles (user_id, role)
values ('74000000-0000-4000-8000-000000000002', 'organizer');
insert into public.players (id, display_name)
values
  ('75000000-0000-4000-8000-000000000001', 'M7 Claim Test One'),
  ('75000000-0000-4000-8000-000000000002', 'M7 Claim Test Two');

set local role anon;
select throws_ok(
  $$select public.get_current_account_snapshot()$$,
  '42501',
  'permission denied for function get_current_account_snapshot',
  'anonymous profile access is denied'
);
select throws_ok(
  $$select public.request_player_claim(
    '76000000-0000-4000-8000-000000000001',
    '75000000-0000-4000-8000-000000000001'
  )$$,
  '42501',
  'permission denied for function request_player_claim',
  'anonymous claim writes are denied'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '74000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  public.get_current_account_snapshot() ->> 'authorization',
  'member',
  'ordinary account maps to member'
);
select lives_ok(
  $$select public.request_player_claim(
    '76000000-0000-4000-8000-000000000001',
    '75000000-0000-4000-8000-000000000001'
  )$$,
  'member can request own claim'
);
select throws_ok(
  $$select public.request_player_claim(
    '76000000-0000-4000-8000-000000000002',
    '75000000-0000-4000-8000-000000000002'
  )$$,
  '23505',
  null,
  'duplicate pending claim is rejected'
);
select is(
  (select count(*)::integer from public.player_claim_requests),
  1,
  'member sees only own claim'
);
select throws_ok(
  $$select public.approve_player_claim('76000000-0000-4000-8000-000000000001')$$,
  '42501',
  'Organizer permission is required.',
  'member cannot approve'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '74000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  (select count(*)::integer from public.player_claim_requests),
  0,
  'member cannot read another claim'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '74000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  public.get_current_account_snapshot() ->> 'authorization',
  'organizer',
  'trusted role maps to organizer'
);
select is(
  (select count(*)::integer from public.list_pending_player_claims()),
  1,
  'organizer can list pending claims'
);
select lives_ok(
  $$select public.approve_player_claim('76000000-0000-4000-8000-000000000001')$$,
  'organizer can atomically approve'
);
select is(
  (
    select player_id::text from public.user_profiles
    where user_id = '74000000-0000-4000-8000-000000000001'
  ),
  '75000000-0000-4000-8000-000000000001',
  'approval links the private profile'
);
select throws_ok(
  $$select public.approve_player_claim('76000000-0000-4000-8000-000000000001')$$,
  'P0001',
  'The pending claim changed.',
  'repeated approval is concurrency safe'
);
reset role;

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'players'
      and column_name in ('auth_user_id', 'user_id', 'email')
  ),
  'public players expose no account identifier'
);

select * from finish();
rollback;
