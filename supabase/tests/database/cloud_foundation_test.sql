begin;

select plan(35);

select has_table('public', 'user_profiles', 'user_profiles exists');
select has_table('public', 'user_roles', 'user_roles exists');
select has_table('public', 'players', 'players exists');
select has_table('public', 'events', 'events exists');
select has_table('public', 'event_divisions', 'event_divisions exists');
select has_table('public', 'event_participants', 'event_participants exists');
select has_table('public', 'division_participants', 'division_participants exists');
select has_table('public', 'participant_payments', 'participant_payments exists');
select has_table('public', 'teams', 'teams exists');
select has_table('public', 'team_members', 'team_members exists');
select has_table('public', 'matches', 'matches exists');
select has_table('public', 'match_dependencies', 'match_dependencies exists');
select has_table('public', 'court_queue_entries', 'court_queue_entries exists');
select has_table('public', 'division_placements', 'division_placements exists');

select is(
  (
    select count(*)::integer
    from pg_constraint
    where connamespace = 'public'::regnamespace
      and conname = any (array[
        'event_divisions_event_fk',
        'event_participants_event_fk',
        'event_participants_player_fk',
        'division_participants_division_fk',
        'division_participants_event_participant_fk',
        'participant_payments_event_participant_fk',
        'participant_payments_division_fk',
        'teams_division_fk',
        'team_members_team_fk',
        'team_members_player_fk',
        'matches_division_fk',
        'matches_side_one_team_fk',
        'matches_side_two_team_fk',
        'matches_winner_team_fk',
        'match_dependencies_source_match_fk',
        'match_dependencies_destination_match_fk',
        'court_queue_entries_event_fk',
        'court_queue_entries_division_fk',
        'court_queue_entries_match_fk',
        'division_placements_division_fk',
        'division_placements_team_fk'
      ])
  ),
  21,
  'important historical relationships use foreign keys'
);

select is(
  (
    select count(*)::integer
    from pg_class
    where relnamespace = 'public'::regnamespace
      and relkind = 'r'
      and relname = any (array[
        'user_profiles',
        'user_roles',
        'players',
        'events',
        'event_divisions',
        'event_participants',
        'division_participants',
        'participant_payments',
        'teams',
        'team_members',
        'matches',
        'match_dependencies',
        'court_queue_entries',
        'division_placements'
      ])
      and relrowsecurity
  ),
  14,
  'RLS is enabled on every exposed table'
);

select is(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee in ('anon', 'authenticated')
      and privilege_type = 'DELETE'
  ),
  0,
  'client roles receive no hard-delete grants'
);

select is(
  (
    select count(*)::integer
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = any (array[
        'players',
        'events',
        'event_divisions',
        'event_participants',
        'division_participants',
        'teams',
        'team_members',
        'matches',
        'match_dependencies',
        'court_queue_entries',
        'division_placements'
      ])
  ),
  11,
  'public display tables are in the Realtime publication'
);

select throws_ok(
  $$
    insert into public.events (
      id, name, scheduled_at, event_type, status, court_label
    ) values (
      '10000000-0000-4000-8000-000000000001',
      'Invalid event',
      now(),
      'league',
      'upcoming',
      'Community Court'
    )
  $$,
  '23514',
  'event_type accepts only M2 values'
);

select throws_ok(
  $$
    insert into public.events (
      id,
      name,
      scheduled_at,
      event_type,
      status,
      entry_fee_minor_units,
      entry_fee_currency,
      court_label
    ) values (
      '10000000-0000-4000-8000-000000000002',
      'Invalid fee',
      now(),
      'casual',
      'upcoming',
      -1,
      'PHP',
      'Community Court'
    )
  $$,
  '23514',
  'event money rejects negative minor units'
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'ordinary@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'organizer@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

insert into public.user_profiles (user_id, display_name) values
  ('20000000-0000-4000-8000-000000000001', 'Ordinary Test User'),
  ('20000000-0000-4000-8000-000000000002', 'Organizer Test User');

insert into public.user_roles (user_id, role)
values ('20000000-0000-4000-8000-000000000002', 'organizer');

insert into public.players (id, display_name)
values
  ('30000000-0000-4000-8000-000000000001', 'Test Player One'),
  ('30000000-0000-4000-8000-000000000002', 'Test Player Two');

insert into public.events (
  id, name, scheduled_at, event_type, status, court_label
) values (
  '40000000-0000-4000-8000-000000000001',
  'Test Event',
  now(),
  'formal',
  'upcoming',
  'Community Court'
);

insert into public.event_divisions (
  id, event_id, name, tournament_format
) values (
  '50000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  'Open',
  'singleElimination'
);

insert into public.event_participants (
  id, event_id, player_id, check_in_status
) values (
  '60000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  'checkedIn'
);

insert into public.teams (id, division_id, formation_method, display_label)
values
  (
    '70000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000001',
    'manual',
    'Test Team One'
  ),
  (
    '70000000-0000-4000-8000-000000000002',
    '50000000-0000-4000-8000-000000000001',
    'manual',
    'Test Team Two'
  );

select throws_ok(
  $$
    insert into public.matches (
      id,
      division_id,
      side_one_team_id,
      side_two_team_id,
      status,
      side_one_score,
      side_two_score
    ) values (
      '80000000-0000-4000-8000-000000000001',
      '50000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000002',
      'completed',
      11,
      8
    )
  $$,
  '23514',
  'completed match requires a valid winner'
);

select throws_ok(
  $$
    update public.events
    set status = 'completed'
    where id = '40000000-0000-4000-8000-000000000001'
  $$,
  '23514',
  'event lifecycle rejects skipped transitions'
);

set local role anon;

select lives_ok(
  $$ select id from public.players where deleted_at is null $$,
  'guest can read non-deleted public player data'
);

select throws_ok(
  $$
    insert into public.players (id, display_name)
    values ('30000000-0000-4000-8000-000000000003', 'Forbidden Guest')
  $$,
  '42501',
  'guest cannot write official data'
);

select throws_ok(
  $$ select * from public.participant_payments $$,
  '42501',
  'guest cannot read participant payments'
);

select throws_ok(
  $$ select * from public.user_profiles $$,
  '42501',
  'guest cannot read user profiles'
);

select throws_ok(
  $$ select * from public.user_roles $$,
  '42501',
  'guest cannot read user roles'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '20000000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select throws_ok(
  $$
    insert into public.players (id, display_name)
    values ('30000000-0000-4000-8000-000000000004', 'Forbidden Player')
  $$,
  '42501',
  'ordinary authenticated user cannot write official data'
);

select results_eq(
  $$ select count(*)::bigint from public.user_profiles $$,
  array[1::bigint],
  'authenticated user can read only their own profile'
);

select throws_ok(
  $$
    insert into public.user_roles (user_id, role)
    values ('20000000-0000-4000-8000-000000000001', 'organizer')
  $$,
  '42501',
  'authenticated user cannot grant themselves organizer permission'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '20000000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

select lives_ok(
  $$
    insert into public.players (id, display_name)
    values ('30000000-0000-4000-8000-000000000005', 'Organizer Added')
  $$,
  'organizer can insert official data'
);

select lives_ok(
  $$
    update public.events
    set name = 'Organizer Updated Event'
    where id = '40000000-0000-4000-8000-000000000001'
  $$,
  'organizer can update official data'
);

select lives_ok(
  $$
    insert into public.participant_payments (
      id, event_participant_id, status
    ) values (
      '90000000-0000-4000-8000-000000000001',
      '60000000-0000-4000-8000-000000000001',
      'paid'
    )
  $$,
  'organizer can record payment status'
);

select results_eq(
  $$ select count(*)::bigint from public.participant_payments $$,
  array[1::bigint],
  'organizer can read payment status'
);

select results_eq(
  $$ select count(*)::bigint from public.user_roles $$,
  array[1::bigint],
  'organizer can read only their own active role row'
);

reset role;

select * from finish();
rollback;
