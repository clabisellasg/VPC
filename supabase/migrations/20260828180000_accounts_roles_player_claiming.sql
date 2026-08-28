-- Volta Paddle Club Milestone 7: accounts, roles, and player claiming.
-- Auth identities and account-to-player links remain private. No organizer is
-- created by this migration.

alter table public.user_profiles
  add column player_id uuid references public.players (id) on delete restrict;

create unique index user_profiles_active_player_idx
  on public.user_profiles (player_id)
  where player_id is not null and deleted_at is null;

create table public.player_claim_requests (
  id uuid primary key,
  requesting_user_id uuid not null references auth.users (id) on delete restrict,
  player_id uuid not null references public.players (id) on delete restrict,
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id) on delete restrict,
  review_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0,
  deleted_at timestamptz,
  constraint player_claim_requests_status_check check (
    status in ('pending', 'approved', 'rejected', 'cancelled')
  ),
  constraint player_claim_requests_version_check check (version >= 0),
  constraint player_claim_requests_reason_check check (
    review_reason is null or char_length(btrim(review_reason)) between 1 and 500
  ),
  constraint player_claim_requests_review_check check (
    (status in ('pending', 'cancelled') and reviewed_at is null and reviewed_by is null)
    or (status in ('approved', 'rejected') and reviewed_at is not null and reviewed_by is not null)
  ),
  constraint player_claim_requests_timestamp_check check (
    updated_at >= created_at
    and requested_at >= created_at
    and (reviewed_at is null or reviewed_at >= requested_at)
    and (deleted_at is null or deleted_at >= updated_at)
  )
);

create unique index player_claim_requests_pending_user_idx
  on public.player_claim_requests (requesting_user_id)
  where status = 'pending' and deleted_at is null;
create unique index player_claim_requests_approved_user_idx
  on public.player_claim_requests (requesting_user_id)
  where status = 'approved' and deleted_at is null;
create unique index player_claim_requests_approved_player_idx
  on public.player_claim_requests (player_id)
  where status = 'approved' and deleted_at is null;
create index player_claim_requests_pending_order_idx
  on public.player_claim_requests (requested_at, id)
  where status = 'pending' and deleted_at is null;

create or replace function private.safe_profile_display_name(p_user auth.users)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when nullif(btrim(p_user.raw_user_meta_data ->> 'display_name'), '') is not null
      and char_length(btrim(p_user.raw_user_meta_data ->> 'display_name')) <= 80
      then btrim(p_user.raw_user_meta_data ->> 'display_name')
    else 'Community member'
  end;
$$;

create or replace function private.create_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_profiles (user_id, display_name)
  values (new.id, private.safe_profile_display_name(new))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger create_user_profile_after_signup
after insert on auth.users
for each row execute function private.create_user_profile();

create or replace function private.player_claim_json(
  p_claim public.player_claim_requests
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p_claim) || jsonb_build_object(
    'claimant_display_name', (
      select up.display_name
      from public.user_profiles as up
      where up.user_id = p_claim.requesting_user_id
        and up.deleted_at is null
    ),
    'player_display_name', (
      select p.display_name
      from public.players as p
      where p.id = p_claim.player_id
    )
  );
$$;

create or replace function public.get_current_account_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  auth_user auth.users%rowtype;
  profile public.user_profiles%rowtype;
  claim public.player_claim_requests%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  select * into auth_user from auth.users where id = current_user_id;
  insert into public.user_profiles (user_id, display_name)
  values (current_user_id, private.safe_profile_display_name(auth_user))
  on conflict (user_id) do nothing;

  select * into profile
  from public.user_profiles
  where user_id = current_user_id and deleted_at is null;

  select * into claim
  from public.player_claim_requests
  where requesting_user_id = current_user_id and deleted_at is null
  order by
    case status when 'pending' then 0 when 'approved' then 1 else 2 end,
    updated_at desc,
    id
  limit 1;

  return jsonb_build_object(
    'profile', to_jsonb(profile),
    'authorization', case when private.is_organizer() then 'organizer' else 'member' end,
    'claim', case when claim.id is null then null else private.player_claim_json(claim) end
  );
end;
$$;

create or replace function public.list_claimable_players(
  p_search text default '',
  p_limit integer default 50
)
returns setof public.players
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if p_limit < 1 or p_limit > 50 then
    raise exception 'Player search limit must be between 1 and 50.' using errcode = '22023';
  end if;
  return query
    select p.*
    from public.players as p
    where p.deleted_at is null
      and (btrim(p_search) = '' or p.display_name ilike '%' || btrim(p_search) || '%')
      and not exists (
        select 1 from public.user_profiles as up
        where up.player_id = p.id and up.deleted_at is null
      )
    order by lower(p.display_name), p.id
    limit p_limit;
end;
$$;

create or replace function public.request_player_claim(
  p_claim_id uuid,
  p_player_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  claim public.player_claim_requests%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if p_claim_id is null or p_player_id is null then
    raise exception 'Claim and player IDs are required.' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.user_profiles
    where user_id = current_user_id and player_id is not null and deleted_at is null
  ) then
    raise exception 'This account is already linked.' using errcode = '23505';
  end if;
  if not exists (
    select 1 from public.players where id = p_player_id and deleted_at is null
  ) then
    raise exception 'The player is unavailable.' using errcode = '23503';
  end if;
  if exists (
    select 1 from public.user_profiles
    where player_id = p_player_id and deleted_at is null
  ) then
    raise exception 'The player is already linked.' using errcode = '23505';
  end if;

  insert into public.player_claim_requests (
    id, requesting_user_id, player_id, status
  ) values (
    p_claim_id, current_user_id, p_player_id, 'pending'
  ) returning * into claim;
  return private.player_claim_json(claim);
end;
$$;

create or replace function public.cancel_player_claim(p_claim_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claim public.player_claim_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  select * into claim
  from public.player_claim_requests
  where id = p_claim_id and requesting_user_id = auth.uid() and deleted_at is null
  for update;
  if claim.id is null or claim.status <> 'pending' then
    raise exception 'The pending claim is unavailable.' using errcode = 'P0001';
  end if;
  update public.player_claim_requests
  set status = 'cancelled', updated_at = now(), version = version + 1
  where id = claim.id returning * into claim;
  return private.player_claim_json(claim);
end;
$$;

create or replace function public.list_pending_player_claims()
returns setof jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;
  return query
    select private.player_claim_json(c)
    from public.player_claim_requests as c
    where c.status = 'pending' and c.deleted_at is null
    order by c.requested_at, c.id;
end;
$$;

create or replace function public.approve_player_claim(p_claim_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  reviewer uuid := auth.uid();
  claim public.player_claim_requests%rowtype;
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;
  select * into claim
  from public.player_claim_requests
  where id = p_claim_id and deleted_at is null
  for update;
  if claim.id is null or claim.status <> 'pending' then
    raise exception 'The pending claim changed.' using errcode = 'P0001';
  end if;

  perform 1 from public.user_profiles
  where user_id = claim.requesting_user_id and deleted_at is null
  for update;
  perform 1 from public.players where id = claim.player_id for update;

  if exists (
    select 1 from public.user_profiles
    where user_id = claim.requesting_user_id
      and player_id is not null and deleted_at is null
  ) then
    raise exception 'The account is already linked.' using errcode = '23505';
  end if;
  if exists (
    select 1 from public.user_profiles
    where player_id = claim.player_id and deleted_at is null
  ) then
    raise exception 'The player is already linked.' using errcode = '23505';
  end if;

  update public.user_profiles
  set player_id = claim.player_id, updated_at = now(), version = version + 1
  where user_id = claim.requesting_user_id and deleted_at is null;
  if not found then
    raise exception 'The account profile is unavailable.' using errcode = '23503';
  end if;

  update public.player_claim_requests
  set status = 'approved', reviewed_at = now(), reviewed_by = reviewer,
      updated_at = now(), version = version + 1
  where id = claim.id returning * into claim;
  return private.player_claim_json(claim);
end;
$$;

create or replace function public.reject_player_claim(
  p_claim_id uuid,
  p_review_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claim public.player_claim_requests%rowtype;
  reason text := nullif(btrim(p_review_reason), '');
begin
  if not private.is_organizer() then
    raise exception 'Organizer permission is required.' using errcode = '42501';
  end if;
  if reason is not null and char_length(reason) > 500 then
    raise exception 'Review reason is too long.' using errcode = '22023';
  end if;
  select * into claim
  from public.player_claim_requests
  where id = p_claim_id and deleted_at is null
  for update;
  if claim.id is null or claim.status <> 'pending' then
    raise exception 'The pending claim changed.' using errcode = 'P0001';
  end if;
  update public.player_claim_requests
  set status = 'rejected', reviewed_at = now(), reviewed_by = auth.uid(),
      review_reason = reason, updated_at = now(), version = version + 1
  where id = claim.id returning * into claim;
  return private.player_claim_json(claim);
end;
$$;

alter table public.player_claim_requests enable row level security;
revoke all on table public.player_claim_requests from public, anon, authenticated;
grant select on table public.player_claim_requests to authenticated;

create policy player_claim_requests_read_own_or_organizer
on public.player_claim_requests for select to authenticated
using (
  deleted_at is null
  and (requesting_user_id = (select auth.uid()) or (select private.is_organizer()))
);

create policy user_profiles_organizer_review_read
on public.user_profiles for select to authenticated
using (deleted_at is null and (select private.is_organizer()));

-- Members may change only their account-facing display name. In particular,
-- they cannot set player_id, role data, metadata, or tombstones directly.
revoke update on table public.user_profiles from authenticated;
grant update (display_name) on table public.user_profiles to authenticated;

revoke all on function private.safe_profile_display_name(auth.users) from public, anon, authenticated;
revoke all on function private.create_user_profile() from public, anon, authenticated;
revoke all on function private.player_claim_json(public.player_claim_requests) from public, anon, authenticated;

revoke all on function public.get_current_account_snapshot() from public, anon, authenticated;
revoke all on function public.list_claimable_players(text, integer) from public, anon, authenticated;
revoke all on function public.request_player_claim(uuid, uuid) from public, anon, authenticated;
revoke all on function public.cancel_player_claim(uuid) from public, anon, authenticated;
revoke all on function public.list_pending_player_claims() from public, anon, authenticated;
revoke all on function public.approve_player_claim(uuid) from public, anon, authenticated;
revoke all on function public.reject_player_claim(uuid, text) from public, anon, authenticated;

grant execute on function public.get_current_account_snapshot() to authenticated;
grant execute on function public.list_claimable_players(text, integer) to authenticated;
grant execute on function public.request_player_claim(uuid, uuid) to authenticated;
grant execute on function public.cancel_player_claim(uuid) to authenticated;
grant execute on function public.list_pending_player_claims() to authenticated;
grant execute on function public.approve_player_claim(uuid) to authenticated;
grant execute on function public.reject_player_claim(uuid, text) to authenticated;
