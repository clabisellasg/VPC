-- Volta Paddle Club Milestone 3: initial Supabase cloud foundation.
-- This migration contains no production seed data and creates no organizer.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.user_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint user_profiles_display_name_check check (btrim(display_name) <> ''),
  constraint user_profiles_version_check check (version >= 0),
  constraint user_profiles_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.user_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  primary key (user_id, role),
  constraint user_roles_role_check check (role = 'organizer'),
  constraint user_roles_version_check check (version >= 0),
  constraint user_roles_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.players (
  id uuid primary key,
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint players_display_name_check check (btrim(display_name) <> ''),
  constraint players_version_check check (version >= 0),
  constraint players_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.events (
  id uuid primary key,
  name text not null,
  scheduled_at timestamptz not null,
  event_type text not null,
  status text not null,
  entry_fee_minor_units bigint,
  entry_fee_currency text,
  court_label text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint events_name_check check (btrim(name) <> ''),
  constraint events_court_label_check check (btrim(court_label) <> ''),
  constraint events_event_type_check check (event_type in ('casual', 'formal')),
  constraint events_status_check check (
    status in ('upcoming', 'registration', 'inProgress', 'completed', 'archived')
  ),
  constraint events_entry_fee_check check (
    (entry_fee_minor_units is null and entry_fee_currency is null)
    or (
      entry_fee_minor_units >= 0
      and entry_fee_currency ~ '^[A-Z]{3}$'
    )
  ),
  constraint events_version_check check (version >= 0),
  constraint events_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.event_divisions (
  id uuid primary key,
  event_id uuid not null,
  name text not null,
  tournament_format text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint event_divisions_event_fk foreign key (event_id)
    references public.events (id) on delete restrict,
  constraint event_divisions_name_check check (btrim(name) <> ''),
  constraint event_divisions_format_check check (
    tournament_format in (
      'singleElimination',
      'doubleElimination',
      'singleRoundRobin',
      'doubleRoundRobin'
    )
  ),
  constraint event_divisions_version_check check (version >= 0),
  constraint event_divisions_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.event_participants (
  id uuid primary key,
  event_id uuid not null,
  player_id uuid not null,
  check_in_status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint event_participants_event_fk foreign key (event_id)
    references public.events (id) on delete restrict,
  constraint event_participants_player_fk foreign key (player_id)
    references public.players (id) on delete restrict,
  constraint event_participants_check_in_check check (
    check_in_status in ('notPresent', 'checkedIn')
  ),
  constraint event_participants_version_check check (version >= 0),
  constraint event_participants_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.division_participants (
  id uuid primary key,
  division_id uuid not null,
  event_participant_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint division_participants_division_fk foreign key (division_id)
    references public.event_divisions (id) on delete restrict,
  constraint division_participants_event_participant_fk
    foreign key (event_participant_id)
    references public.event_participants (id) on delete restrict,
  constraint division_participants_version_check check (version >= 0),
  constraint division_participants_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.participant_payments (
  id uuid primary key,
  event_participant_id uuid not null,
  division_id uuid,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint participant_payments_event_participant_fk
    foreign key (event_participant_id)
    references public.event_participants (id) on delete restrict,
  constraint participant_payments_division_fk foreign key (division_id)
    references public.event_divisions (id) on delete restrict,
  constraint participant_payments_status_check check (status in ('unpaid', 'paid')),
  constraint participant_payments_version_check check (version >= 0),
  constraint participant_payments_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.teams (
  id uuid primary key,
  division_id uuid not null,
  formation_method text not null,
  display_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint teams_division_fk foreign key (division_id)
    references public.event_divisions (id) on delete restrict,
  constraint teams_formation_method_check check (
    formation_method in ('manual', 'random', 'balanced')
  ),
  constraint teams_display_label_check check (
    display_label is null or btrim(display_label) <> ''
  ),
  constraint teams_version_check check (version >= 0),
  constraint teams_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.team_members (
  team_id uuid not null,
  player_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  primary key (team_id, player_id),
  constraint team_members_team_fk foreign key (team_id)
    references public.teams (id) on delete restrict,
  constraint team_members_player_fk foreign key (player_id)
    references public.players (id) on delete restrict,
  constraint team_members_version_check check (version >= 0),
  constraint team_members_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.matches (
  id uuid primary key,
  division_id uuid not null,
  side_one_team_id uuid,
  side_two_team_id uuid,
  status text not null,
  side_one_score integer,
  side_two_score integer,
  winner_team_id uuid,
  round_number integer,
  sequence_number integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint matches_division_fk foreign key (division_id)
    references public.event_divisions (id) on delete restrict,
  constraint matches_side_one_team_fk foreign key (side_one_team_id)
    references public.teams (id) on delete restrict,
  constraint matches_side_two_team_fk foreign key (side_two_team_id)
    references public.teams (id) on delete restrict,
  constraint matches_winner_team_fk foreign key (winner_team_id)
    references public.teams (id) on delete restrict,
  constraint matches_status_check check (
    status in ('scheduled', 'queued', 'inProgress', 'completed')
  ),
  constraint matches_side_distinct_check check (
    side_one_team_id is null
    or side_two_team_id is null
    or side_one_team_id <> side_two_team_id
  ),
  constraint matches_side_one_score_check check (
    side_one_score is null or side_one_score >= 0
  ),
  constraint matches_side_two_score_check check (
    side_two_score is null or side_two_score >= 0
  ),
  constraint matches_round_number_check check (
    round_number is null or round_number > 0
  ),
  constraint matches_sequence_number_check check (
    sequence_number is null or sequence_number > 0
  ),
  constraint matches_completed_state_check check (
    (
      status = 'completed'
      and side_one_team_id is not null
      and side_two_team_id is not null
      and side_one_score is not null
      and side_two_score is not null
      and winner_team_id in (side_one_team_id, side_two_team_id)
    )
    or (status <> 'completed' and winner_team_id is null)
  ),
  constraint matches_version_check check (version >= 0),
  constraint matches_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.match_dependencies (
  source_match_id uuid not null,
  source_outcome text not null,
  destination_match_id uuid not null,
  destination_slot text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  primary key (
    source_match_id,
    source_outcome,
    destination_match_id,
    destination_slot
  ),
  constraint match_dependencies_source_match_fk foreign key (source_match_id)
    references public.matches (id) on delete restrict,
  constraint match_dependencies_destination_match_fk
    foreign key (destination_match_id)
    references public.matches (id) on delete restrict,
  constraint match_dependencies_source_outcome_check check (
    source_outcome in ('winner', 'loser')
  ),
  constraint match_dependencies_destination_slot_check check (
    destination_slot in ('sideOne', 'sideTwo')
  ),
  constraint match_dependencies_not_self_check check (
    source_match_id <> destination_match_id
  ),
  constraint match_dependencies_version_check check (version >= 0),
  constraint match_dependencies_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.court_queue_entries (
  id uuid primary key,
  event_id uuid not null,
  division_id uuid,
  match_id uuid not null,
  queue_position bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint court_queue_entries_event_fk foreign key (event_id)
    references public.events (id) on delete restrict,
  constraint court_queue_entries_division_fk foreign key (division_id)
    references public.event_divisions (id) on delete restrict,
  constraint court_queue_entries_match_fk foreign key (match_id)
    references public.matches (id) on delete restrict,
  constraint court_queue_entries_position_check check (queue_position >= 0),
  constraint court_queue_entries_version_check check (version >= 0),
  constraint court_queue_entries_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create table public.division_placements (
  id uuid primary key,
  division_id uuid not null,
  team_id uuid not null,
  position integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint division_placements_division_fk foreign key (division_id)
    references public.event_divisions (id) on delete restrict,
  constraint division_placements_team_fk foreign key (team_id)
    references public.teams (id) on delete restrict,
  constraint division_placements_position_check check (position > 0),
  constraint division_placements_version_check check (version >= 0),
  constraint division_placements_timestamp_check check (
    updated_at >= created_at
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create index players_display_name_idx
  on public.players (lower(display_name));
create index events_status_scheduled_at_idx
  on public.events (status, scheduled_at);
create index event_divisions_event_id_idx
  on public.event_divisions (event_id);
create unique index event_divisions_active_name_idx
  on public.event_divisions (event_id, lower(name))
  where deleted_at is null;
create index event_participants_player_id_idx
  on public.event_participants (player_id);
create unique index event_participants_active_player_idx
  on public.event_participants (event_id, player_id)
  where deleted_at is null;
create index division_participants_event_participant_idx
  on public.division_participants (event_participant_id);
create unique index division_participants_active_entry_idx
  on public.division_participants (division_id, event_participant_id)
  where deleted_at is null;
create unique index participant_payments_active_event_scope_idx
  on public.participant_payments (event_participant_id)
  where division_id is null and deleted_at is null;
create unique index participant_payments_active_division_scope_idx
  on public.participant_payments (event_participant_id, division_id)
  where division_id is not null and deleted_at is null;
create index teams_division_id_idx on public.teams (division_id);
create index team_members_player_id_idx on public.team_members (player_id);
create index matches_division_status_idx
  on public.matches (division_id, status, sequence_number);
create index match_dependencies_destination_idx
  on public.match_dependencies (destination_match_id);
create unique index match_dependencies_active_destination_slot_idx
  on public.match_dependencies (destination_match_id, destination_slot)
  where deleted_at is null;
create unique index court_queue_entries_active_position_idx
  on public.court_queue_entries (event_id, queue_position)
  where deleted_at is null;
create unique index court_queue_entries_active_match_idx
  on public.court_queue_entries (match_id)
  where deleted_at is null;
create unique index division_placements_active_position_idx
  on public.division_placements (division_id, position)
  where deleted_at is null;
create unique index division_placements_active_team_idx
  on public.division_placements (division_id, team_id)
  where deleted_at is null;
create index user_roles_active_user_idx
  on public.user_roles (user_id)
  where deleted_at is null;

create or replace function private.is_organizer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = (select auth.uid())
      and role = 'organizer'
      and deleted_at is null
  );
$$;

create or replace function private.enforce_event_status_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status
    and not (
      (old.status = 'upcoming' and new.status = 'registration')
      or (old.status = 'registration' and new.status = 'inProgress')
      or (old.status = 'inProgress' and new.status = 'completed')
      or (old.status = 'completed' and new.status = 'archived')
    )
  then
    raise exception 'Invalid event status transition from % to %', old.status, new.status
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.enforce_match_status_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status
    and not (
      (old.status = 'scheduled' and new.status = 'queued')
      or (old.status = 'queued' and new.status = 'inProgress')
      or (old.status = 'inProgress' and new.status = 'completed')
    )
  then
    raise exception 'Invalid match status transition from % to %', old.status, new.status
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_division_participant_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  division_event_id uuid;
  participant_event_id uuid;
begin
  select event_id into division_event_id
  from public.event_divisions
  where id = new.division_id;

  select event_id into participant_event_id
  from public.event_participants
  where id = new.event_participant_id;

  if division_event_id is not null
    and participant_event_id is not null
    and division_event_id <> participant_event_id
  then
    raise exception 'Division participant must belong to the same event as the division'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_payment_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  division_event_id uuid;
  participant_event_id uuid;
begin
  if new.division_id is null then
    return new;
  end if;

  select event_id into division_event_id
  from public.event_divisions
  where id = new.division_id;

  select event_id into participant_event_id
  from public.event_participants
  where id = new.event_participant_id;

  if division_event_id is not null
    and participant_event_id is not null
    and division_event_id <> participant_event_id
  then
    raise exception 'Division-scoped payment must use the participant event'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_match_team_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.side_one_team_id is not null and exists (
    select 1 from public.teams
    where id = new.side_one_team_id and division_id <> new.division_id
  ) then
    raise exception 'Match side one team must belong to the match division'
      using errcode = '23514';
  end if;

  if new.side_two_team_id is not null and exists (
    select 1 from public.teams
    where id = new.side_two_team_id and division_id <> new.division_id
  ) then
    raise exception 'Match side two team must belong to the match division'
      using errcode = '23514';
  end if;

  if new.winner_team_id is not null and exists (
    select 1 from public.teams
    where id = new.winner_team_id and division_id <> new.division_id
  ) then
    raise exception 'Match winner team must belong to the match division'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_match_dependency_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  source_division_id uuid;
  destination_division_id uuid;
begin
  select division_id into source_division_id
  from public.matches
  where id = new.source_match_id;

  select division_id into destination_division_id
  from public.matches
  where id = new.destination_match_id;

  if source_division_id is not null
    and destination_division_id is not null
    and source_division_id <> destination_division_id
  then
    raise exception 'Match dependency must remain within one division'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_queue_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  match_division_id uuid;
  match_event_id uuid;
begin
  select m.division_id, d.event_id
    into match_division_id, match_event_id
  from public.matches as m
  join public.event_divisions as d on d.id = m.division_id
  where m.id = new.match_id;

  if match_event_id is not null and match_event_id <> new.event_id then
    raise exception 'Court queue match must belong to the queue event'
      using errcode = '23514';
  end if;

  if new.division_id is not null
    and match_division_id is not null
    and new.division_id <> match_division_id
  then
    raise exception 'Court queue division must match the match division'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_placement_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.teams
    where id = new.team_id and division_id <> new.division_id
  ) then
    raise exception 'Placement team must belong to the placement division'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on all functions in schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_organizer() to authenticated;

create trigger events_status_transition_guard
before update of status on public.events
for each row execute function private.enforce_event_status_transition();

create trigger matches_status_transition_guard
before update of status on public.matches
for each row execute function private.enforce_match_status_transition();

create trigger division_participants_scope_guard
before insert or update of division_id, event_participant_id
on public.division_participants
for each row execute function private.validate_division_participant_scope();

create trigger participant_payments_scope_guard
before insert or update of division_id, event_participant_id
on public.participant_payments
for each row execute function private.validate_payment_scope();

create trigger matches_team_scope_guard
before insert or update of division_id, side_one_team_id, side_two_team_id, winner_team_id
on public.matches
for each row execute function private.validate_match_team_scope();

create trigger match_dependencies_scope_guard
before insert or update of source_match_id, destination_match_id
on public.match_dependencies
for each row execute function private.validate_match_dependency_scope();

create trigger court_queue_entries_scope_guard
before insert or update of event_id, division_id, match_id
on public.court_queue_entries
for each row execute function private.validate_queue_scope();

create trigger division_placements_scope_guard
before insert or update of division_id, team_id
on public.division_placements
for each row execute function private.validate_placement_scope();

alter table public.user_profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.players enable row level security;
alter table public.events enable row level security;
alter table public.event_divisions enable row level security;
alter table public.event_participants enable row level security;
alter table public.division_participants enable row level security;
alter table public.participant_payments enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.matches enable row level security;
alter table public.match_dependencies enable row level security;
alter table public.court_queue_entries enable row level security;
alter table public.division_placements enable row level security;

revoke all on table
  public.user_profiles,
  public.user_roles,
  public.players,
  public.events,
  public.event_divisions,
  public.event_participants,
  public.division_participants,
  public.participant_payments,
  public.teams,
  public.team_members,
  public.matches,
  public.match_dependencies,
  public.court_queue_entries,
  public.division_placements
from public, anon, authenticated;

grant select on table
  public.players,
  public.events,
  public.event_divisions,
  public.event_participants,
  public.division_participants,
  public.teams,
  public.team_members,
  public.matches,
  public.match_dependencies,
  public.court_queue_entries,
  public.division_placements
to anon, authenticated;

grant insert, update on table
  public.players,
  public.events,
  public.event_divisions,
  public.event_participants,
  public.division_participants,
  public.teams,
  public.team_members,
  public.matches,
  public.match_dependencies,
  public.court_queue_entries,
  public.division_placements
to authenticated;

grant select, insert, update on table public.participant_payments to authenticated;
grant select, insert, update on table public.user_profiles to authenticated;
grant select on table public.user_roles to authenticated;

alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated;

create policy user_profiles_read_own
on public.user_profiles for select to authenticated
using (user_id = (select auth.uid()) and deleted_at is null);

create policy user_profiles_insert_own
on public.user_profiles for insert to authenticated
with check (user_id = (select auth.uid()) and deleted_at is null);

create policy user_profiles_update_own
on public.user_profiles for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy user_roles_read_own
on public.user_roles for select to authenticated
using (user_id = (select auth.uid()) and deleted_at is null);

create policy participant_payments_organizer_read
on public.participant_payments for select to authenticated
using ((select private.is_organizer()));

create policy participant_payments_organizer_insert
on public.participant_payments for insert to authenticated
with check ((select private.is_organizer()));

create policy participant_payments_organizer_update
on public.participant_payments for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy players_public_read
on public.players for select to anon, authenticated
using (deleted_at is null);
create policy players_organizer_insert
on public.players for insert to authenticated
with check ((select private.is_organizer()));
create policy players_organizer_update
on public.players for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy events_public_read
on public.events for select to anon, authenticated
using (deleted_at is null);
create policy events_organizer_insert
on public.events for insert to authenticated
with check ((select private.is_organizer()));
create policy events_organizer_update
on public.events for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy event_divisions_public_read
on public.event_divisions for select to anon, authenticated
using (deleted_at is null);
create policy event_divisions_organizer_insert
on public.event_divisions for insert to authenticated
with check ((select private.is_organizer()));
create policy event_divisions_organizer_update
on public.event_divisions for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy event_participants_public_read
on public.event_participants for select to anon, authenticated
using (deleted_at is null);
create policy event_participants_organizer_insert
on public.event_participants for insert to authenticated
with check ((select private.is_organizer()));
create policy event_participants_organizer_update
on public.event_participants for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy division_participants_public_read
on public.division_participants for select to anon, authenticated
using (deleted_at is null);
create policy division_participants_organizer_insert
on public.division_participants for insert to authenticated
with check ((select private.is_organizer()));
create policy division_participants_organizer_update
on public.division_participants for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy teams_public_read
on public.teams for select to anon, authenticated
using (deleted_at is null);
create policy teams_organizer_insert
on public.teams for insert to authenticated
with check ((select private.is_organizer()));
create policy teams_organizer_update
on public.teams for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy team_members_public_read
on public.team_members for select to anon, authenticated
using (deleted_at is null);
create policy team_members_organizer_insert
on public.team_members for insert to authenticated
with check ((select private.is_organizer()));
create policy team_members_organizer_update
on public.team_members for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy matches_public_read
on public.matches for select to anon, authenticated
using (deleted_at is null);
create policy matches_organizer_insert
on public.matches for insert to authenticated
with check ((select private.is_organizer()));
create policy matches_organizer_update
on public.matches for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy match_dependencies_public_read
on public.match_dependencies for select to anon, authenticated
using (deleted_at is null);
create policy match_dependencies_organizer_insert
on public.match_dependencies for insert to authenticated
with check ((select private.is_organizer()));
create policy match_dependencies_organizer_update
on public.match_dependencies for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy court_queue_entries_public_read
on public.court_queue_entries for select to anon, authenticated
using (deleted_at is null);
create policy court_queue_entries_organizer_insert
on public.court_queue_entries for insert to authenticated
with check ((select private.is_organizer()));
create policy court_queue_entries_organizer_update
on public.court_queue_entries for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

create policy division_placements_public_read
on public.division_placements for select to anon, authenticated
using (deleted_at is null);
create policy division_placements_organizer_insert
on public.division_placements for insert to authenticated
with check ((select private.is_organizer()));
create policy division_placements_organizer_update
on public.division_placements for update to authenticated
using ((select private.is_organizer()))
with check ((select private.is_organizer()));

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
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
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end;
$$;
