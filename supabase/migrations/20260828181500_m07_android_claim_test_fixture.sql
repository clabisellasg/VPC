-- Deliberately synthetic M7 Android manual-test fixture. This is public
-- player data, not schema. Remove only after all dependent claim history and
-- profile links have been safely cleared by a trusted operator.
insert into public.players (
  id,
  display_name,
  created_at,
  updated_at,
  version,
  deleted_at
) values (
  '73000000-0000-4000-8000-000000000002',
  'M7 Android Synthetic Claim Player',
  '2026-08-28 18:15:00+00',
  '2026-08-28 18:15:00+00',
  0,
  null
)
on conflict (id) do nothing;
