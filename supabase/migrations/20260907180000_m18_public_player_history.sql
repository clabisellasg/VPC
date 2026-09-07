-- M18 derives public player history from current operational rows.  It stores
-- no counters and intentionally returns no account, payment, or sync data.
create or replace function public.read_public_player_history(p_player_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with player_exists as (
    select p.id from public.players p
    where p.id = p_player_id and p.deleted_at is null
  ), completed_matches as (
    select
      m.id as match_id, m.updated_at as completed_at,
      e.id as event_id, e.name as event_name,
      d.id as division_id, d.name as division_name, d.tournament_format,
      m.round_number, m.side_one_score, m.side_two_score, m.winner_team_id,
      case when m.side_one_team_id = own.team_id then m.side_one_team_id else m.side_two_team_id end as own_team_id,
      case when m.side_one_team_id = own.team_id then m.side_two_team_id else m.side_one_team_id end as opponent_team_id
    from public.matches m
    join public.event_divisions d on d.id = m.division_id and d.deleted_at is null
    join public.events e on e.id = d.event_id and e.deleted_at is null
    join public.team_members own on own.player_id = p_player_id
      and own.team_id in (m.side_one_team_id, m.side_two_team_id) and own.deleted_at is null
    join public.teams t on t.id = own.team_id and t.deleted_at is null
    where m.status = 'completed' and m.deleted_at is null
      and m.side_one_team_id is not null and m.side_two_team_id is not null
      and m.side_one_score is not null and m.side_two_score is not null
      and m.winner_team_id is not null
  ), match_json as (
    select jsonb_build_object(
      'match_id', cm.match_id, 'event_id', cm.event_id, 'event_name', cm.event_name,
      'division_id', cm.division_id, 'division_name', cm.division_name,
      'format', cm.tournament_format, 'completed_at', cm.completed_at,
      'round_number', cm.round_number,
      'points_for', case when cm.own_team_id = (select m.side_one_team_id from public.matches m where m.id=cm.match_id) then cm.side_one_score else cm.side_two_score end,
      'points_against', case when cm.own_team_id = (select m.side_one_team_id from public.matches m where m.id=cm.match_id) then cm.side_two_score else cm.side_one_score end,
      'won', cm.winner_team_id = cm.own_team_id,
      'team_name', coalesce((select string_agg(p.display_name, ' / ' order by lower(p.display_name), p.id)
        from public.team_members tm join public.players p on p.id=tm.player_id and p.deleted_at is null
        where tm.team_id=cm.own_team_id and tm.deleted_at is null), 'Team'),
      'opponent_name', coalesce((select string_agg(p.display_name, ' / ' order by lower(p.display_name), p.id)
        from public.team_members tm join public.players p on p.id=tm.player_id and p.deleted_at is null
        where tm.team_id=cm.opponent_team_id and tm.deleted_at is null), 'Opponent')
    ) as value, cm.* from completed_matches cm
  ), appearances as (
    select distinct e.id, e.name, e.updated_at
    from public.event_participants ep
    join public.events e on e.id=ep.event_id and e.deleted_at is null and e.status in ('completed','archived')
    where ep.player_id=p_player_id and ep.check_in_status='checkedIn' and ep.deleted_at is null
  ), partners as (
    select partner.id, partner.display_name,
      count(*) filter (where cm.winner_team_id=cm.own_team_id) as wins,
      count(*) as matches
    from completed_matches cm
    join public.team_members tm on tm.team_id=cm.own_team_id and tm.deleted_at is null and tm.player_id<>p_player_id
    join public.players partner on partner.id=tm.player_id and partner.deleted_at is null
    group by partner.id, partner.display_name
  )
  select case when exists(select 1 from player_exists) then jsonb_build_object(
    'summary', jsonb_build_object(
      'matches_played',(select count(*) from completed_matches),
      'wins',(select count(*) from completed_matches where winner_team_id=own_team_id),
      'losses',(select count(*) from completed_matches where winner_team_id<>own_team_id),
      'event_appearances',(select count(*) from appearances),
      'division_appearances',(select count(distinct division_id) from completed_matches),
      'championships',(select count(*) from public.division_placements dp join public.teams t on t.id=dp.team_id join public.team_members tm on tm.team_id=t.id where tm.player_id=p_player_id and dp.position=1 and dp.deleted_at is null and t.deleted_at is null and tm.deleted_at is null),
      'runner_up_finishes',(select count(*) from public.division_placements dp join public.teams t on t.id=dp.team_id join public.team_members tm on tm.team_id=t.id where tm.player_id=p_player_id and dp.position=2 and dp.deleted_at is null and t.deleted_at is null and tm.deleted_at is null),
      'points_for',(select coalesce(sum((value->>'points_for')::int),0) from match_json),
      'points_against',(select coalesce(sum((value->>'points_against')::int),0) from match_json)
    ),
    'matches',coalesce((select jsonb_agg(value order by completed_at desc, match_id desc) from match_json),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(jsonb_build_object('event_id',id,'event_name',name,'completed_at',updated_at) order by updated_at desc,id desc) from appearances),'[]'::jsonb),
    'partners',coalesce((select jsonb_agg(jsonb_build_object('player_id',id,'display_name',display_name,'matches_played',matches,'wins',wins,'losses',matches-wins) order by lower(display_name),id) from partners),'[]'::jsonb)
  ) else null end;
$$;

revoke all on function public.read_public_player_history(uuid) from public;
grant execute on function public.read_public_player_history(uuid) to anon, authenticated;
