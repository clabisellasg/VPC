begin;
select plan(14);

select has_table('public', 'event_participants', 'event participants exist');
select has_table('public', 'division_participants', 'division participants exist');
select has_table('public', 'participant_payments', 'participant payments exist');
select has_table('private', 'participation_operation_receipts', 'private receipts exist');
select has_function('public', 'apply_participation_operation', array['uuid','uuid','bigint','jsonb'],
  'fixed aggregate apply function exists');
select has_function('public', 'pull_participation_changes', array['timestamp with time zone','uuid','integer'],
  'bounded organizer pull function exists');
select function_privs_are('public', 'apply_participation_operation', array['uuid','uuid','bigint','jsonb'], 'anon', array[]::text[],
  'anonymous aggregate mutation is denied');
select function_privs_are('public', 'apply_participation_operation', array['uuid','uuid','bigint','jsonb'], 'authenticated', array['EXECUTE'],
  'authenticated role can invoke organizer-guarded command');
select table_privs_are('public', 'participant_payments', 'anon', array[]::text[],
  'anonymous users have no payment access');
select table_privs_are('private', 'participation_operation_receipts', 'authenticated', array[]::text[],
  'client roles cannot inspect idempotency receipts');
select has_index('public', 'event_participants', 'event_participants_active_player_idx',
  'active event registration is unique per player');
select has_index('public', 'division_participants', 'division_participants_active_entry_idx',
  'active division assignment is unique');
select policy_cmd_is('public', 'participant_payments', 'participant_payments_organizer_read', 'SELECT',
  'payment read remains organizer-only by policy');
select throws_ok(
  $$select public.apply_participation_operation(
    'a0000000-0000-4000-8000-000000000001',
    'a0000000-0000-4000-8000-000000000002',
    null,
    '{}'::jsonb
  )$$,
  '42501', null, 'unauthenticated command is rejected before payload processing');

select * from finish();
rollback;
