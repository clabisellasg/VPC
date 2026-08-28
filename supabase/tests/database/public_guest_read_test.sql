begin;

select plan(8);

select has_table('public', 'events', 'public events table exists');
select has_table(
  'public',
  'event_divisions',
  'public event divisions table exists'
);

select results_eq(
  $$ select count(*)::bigint from public.events
     where id::text like '61000000-%' and deleted_at is null $$,
  array[3::bigint],
  'three active synthetic M6 events exist'
);

select results_eq(
  $$ select count(*)::bigint from public.event_divisions
     where id::text like '62000000-%' and deleted_at is null $$,
  array[4::bigint],
  'four active synthetic M6 divisions exist'
);

set local role anon;
select set_config('request.jwt.claims', '{}', true);

select results_eq(
  $$ select count(*)::bigint from public.events
     where id::text like '61000000-%' $$,
  array[3::bigint],
  'anonymous clients can read synthetic public events'
);

select results_eq(
  $$ select count(*)::bigint from public.event_divisions
     where id::text like '62000000-%' $$,
  array[4::bigint],
  'anonymous clients can read synthetic public divisions'
);

select throws_ok(
  $$ insert into public.events (
       id, name, scheduled_at, event_type, status, court_label
     ) values (
       '61000000-0000-4000-8000-000000000099', 'Denied', now(),
       'casual', 'upcoming', 'Denied'
     ) $$,
  '42501',
  null,
  'anonymous event writes are denied'
);

select throws_ok(
  $$ insert into public.event_divisions (
       id, event_id, name, tournament_format
     ) values (
       '62000000-0000-4000-8000-000000000099',
       '61000000-0000-4000-8000-000000000001',
       'Denied', 'singleElimination'
     ) $$,
  '42501',
  null,
  'anonymous division writes are denied'
);

select * from finish();
rollback;
