begin;
select plan(14);

select col_is_null('public', 'event_divisions', 'tournament_format',
  'tournament format remains optional until M12');
select has_check('public', 'event_divisions', 'event_divisions_format_check',
  'non-null formats retain the approved enum check');
select has_function('public', 'apply_event_setup_operation', array['uuid','uuid','bigint','jsonb'],
  'fixed aggregate apply function exists');
select has_function('public', 'pull_event_setup_changes', array['timestamp with time zone','uuid','integer'],
  'fixed organizer pull function exists');
select function_privs_are('public', 'apply_event_setup_operation', array['uuid','uuid','bigint','jsonb'], 'anon', array[]::text[],
  'anonymous aggregate apply is denied');
select function_privs_are('public', 'apply_event_setup_operation', array['uuid','uuid','bigint','jsonb'], 'authenticated', array['EXECUTE'],
  'authenticated role can invoke the organizer-guarded RPC');
select function_privs_are('public', 'pull_event_setup_changes', array['timestamp with time zone','uuid','integer'], 'anon', array[]::text[],
  'anonymous pull is denied');
select has_table('private', 'event_setup_operation_receipts', 'private receipts exist');
select table_privs_are('private', 'event_setup_operation_receipts', 'anon', array[]::text[],
  'anonymous cannot read receipts');
select table_privs_are('private', 'event_setup_operation_receipts', 'authenticated', array[]::text[],
  'authenticated clients cannot read receipts');
select has_index('public', 'event_divisions', 'event_divisions_active_normalized_name_idx',
  'active normalized division names are unique');
select throws_ok(
  $$insert into public.event_divisions (
    id,event_id,name,tournament_format,created_at,updated_at,version
  ) values (
    '99000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    'Invalid','notAFormat',now(),now(),0
  )$$,
  '23514', null, 'invalid non-null format remains rejected');
select ok((select private.event_setup_json('71000000-0000-4000-8000-000000000001') is not null),
  'existing formatted fixture remains readable');
select ok((select count(*) >= 1 from public.event_divisions where tournament_format is not null),
  'existing non-null format values remain present');

select * from finish();
rollback;
