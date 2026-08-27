begin;
select plan(10);

select has_table(
  'private',
  'player_sync_operation_receipts',
  'private synchronization receipt table exists'
);
select has_function(
  'public',
  'apply_player_sync_operation',
  array['uuid', 'uuid', 'text', 'bigint', 'jsonb'],
  'narrow player apply function exists'
);
select has_function(
  'public',
  'pull_player_sync_changes',
  array['timestamp with time zone', 'uuid', 'integer'],
  'checkpointed player pull function exists'
);
select ok(
  not has_table_privilege('anon', 'private.player_sync_operation_receipts', 'select'),
  'anonymous clients cannot read receipts'
);
select ok(
  not has_table_privilege('authenticated', 'private.player_sync_operation_receipts', 'select'),
  'authenticated clients cannot read receipts directly'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.apply_player_sync_operation(uuid,uuid,text,bigint,jsonb)',
    'execute'
  ),
  'anonymous clients cannot call player synchronization writes'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.apply_player_sync_operation(uuid,uuid,text,bigint,jsonb)',
    'execute'
  ),
  'authenticated role can call the organizer-guarded function'
);

set local role anon;
select throws_ok(
  $$select public.apply_player_sync_operation(
    '10000000-0000-4000-8000-000000000001'::uuid,
    '10000000-0000-4000-8000-000000000002'::uuid,
    'upsert',
    null,
    '{}'::jsonb
  )$$,
  '42501',
  'permission denied for function apply_player_sync_operation',
  'anonymous apply is denied'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.apply_player_sync_operation(
    '10000000-0000-4000-8000-000000000004'::uuid,
    '10000000-0000-4000-8000-000000000005'::uuid,
    'upsert',
    null,
    '{}'::jsonb
  )$$,
  '42501',
  'Organizer permission is required.',
  'non-organizer apply is denied'
);
select throws_ok(
  $$select * from public.pull_player_sync_changes(null, null, 10)$$,
  '42501',
  'Organizer permission is required.',
  'non-organizer tombstone-aware pull is denied'
);
reset role;

select * from finish();
rollback;
