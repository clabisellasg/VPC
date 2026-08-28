-- Milestone 6 synthetic public fixtures.
-- These rows are intentionally fictional and contain no player, account,
-- payment, contact, or credential data. This is a data migration, not schema.

insert into public.events (
  id,
  name,
  scheduled_at,
  event_type,
  status,
  entry_fee_minor_units,
  entry_fee_currency,
  court_label,
  created_at,
  updated_at,
  version,
  deleted_at
)
values
  (
    '61000000-0000-4000-8000-000000000001',
    'VPC Demo Current Court Session',
    '2026-08-28 02:00:00+00',
    'casual',
    'inProgress',
    0,
    'PHP',
    'VPC Sample Court',
    '2026-08-28 00:00:00+00',
    '2026-08-28 00:00:00+00',
    0,
    null
  ),
  (
    '61000000-0000-4000-8000-000000000002',
    'VPC Demo September Open',
    '2026-09-20 01:00:00+00',
    'formal',
    'upcoming',
    15000,
    'PHP',
    'VPC Sample Court',
    '2026-08-28 00:00:00+00',
    '2026-08-28 00:00:00+00',
    0,
    null
  ),
  (
    '61000000-0000-4000-8000-000000000003',
    'VPC Demo Completed Round Robin',
    '2026-08-16 01:00:00+00',
    'formal',
    'completed',
    10000,
    'PHP',
    'VPC Sample Court',
    '2026-08-16 00:00:00+00',
    '2026-08-16 06:00:00+00',
    3,
    null
  )
on conflict (id) do nothing;

insert into public.event_divisions (
  id,
  event_id,
  name,
  tournament_format,
  created_at,
  updated_at,
  version,
  deleted_at
)
values
  (
    '62000000-0000-4000-8000-000000000001',
    '61000000-0000-4000-8000-000000000001',
    'Sample Open',
    'singleRoundRobin',
    '2026-08-28 00:00:00+00',
    '2026-08-28 00:00:00+00',
    0,
    null
  ),
  (
    '62000000-0000-4000-8000-000000000002',
    '61000000-0000-4000-8000-000000000002',
    'Sample Mixed',
    'singleElimination',
    '2026-08-28 00:00:00+00',
    '2026-08-28 00:00:00+00',
    0,
    null
  ),
  (
    '62000000-0000-4000-8000-000000000003',
    '61000000-0000-4000-8000-000000000002',
    'Sample Open',
    'doubleElimination',
    '2026-08-28 00:00:00+00',
    '2026-08-28 00:00:00+00',
    0,
    null
  ),
  (
    '62000000-0000-4000-8000-000000000004',
    '61000000-0000-4000-8000-000000000003',
    'Sample Open',
    'doubleRoundRobin',
    '2026-08-16 00:00:00+00',
    '2026-08-16 06:00:00+00',
    2,
    null
  )
on conflict (id) do nothing;
