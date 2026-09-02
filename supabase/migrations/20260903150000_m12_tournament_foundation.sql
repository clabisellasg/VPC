-- M12 only: formats and generic score/start integrity; no match generation.
create or replace function private.event_setup_json(p_event_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('event', to_jsonb(e),
    'divisions', coalesce((select jsonb_agg(to_jsonb(d) order by lower(d.name),d.id)
      from public.event_divisions d where d.event_id=e.id), '[]'::jsonb),
    'readiness', coalesce((select jsonb_agg(jsonb_build_object(
      'division_id', d.id,
      'complete_teams', (select count(*) from public.teams t where t.division_id=d.id and t.deleted_at is null
        and (select count(*) from public.team_members tm join public.players p on p.id=tm.player_id
          where tm.team_id=t.id and tm.deleted_at is null and p.deleted_at is null)=2),
      'active_matches', (select count(*) from public.matches m where m.division_id=d.id and m.deleted_at is null),
      'generated_matches', (select count(*) from public.matches m where m.division_id=d.id)
    ) order by d.id) from public.event_divisions d where d.event_id=e.id and d.deleted_at is null), '[]'::jsonb))
  from public.events e where e.id=p_event_id;
$$;

create or replace function private.enforce_event_division_setup_lock()
returns trigger language plpgsql set search_path = '' as $$
declare parent public.events%rowtype;
begin
  select * into parent from public.events where id=old.event_id for update;
  if (new.name is distinct from old.name or new.deleted_at is distinct from old.deleted_at)
    and parent.status <> 'upcoming' and parent.deleted_at is null then
    raise exception 'Event division setup is locked after UPCOMING.' using errcode='23514';
  end if;
  if new.tournament_format is distinct from old.tournament_format and
    (parent.status <> 'registration' or parent.deleted_at is not null or old.deleted_at is not null
      or exists(select 1 from public.matches where division_id=old.id)) then
    raise exception 'Tournament format selection is locked.' using errcode='23514';
  end if;
  return new;
end;
$$;

create or replace function private.enforce_event_format_before_start()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status='inProgress' and old.status<>'inProgress' then
    if not exists(select 1 from public.event_divisions where event_id=new.id and deleted_at is null)
      or exists(select 1 from public.event_divisions d where d.event_id=new.id and d.deleted_at is null and (
        d.tournament_format is null
        or (select count(*) from public.teams t where t.division_id=d.id and t.deleted_at is null
          and (select count(*) from public.team_members tm join public.players p on p.id=tm.player_id
            where tm.team_id=t.id and tm.deleted_at is null and p.deleted_at is null)=2)<2
        or not exists(select 1 from public.matches m where m.division_id=d.id and m.deleted_at is null)
      )) then
      raise exception 'Tournament structure required: configure formats, complete teams, and generated matches before starting.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

-- Existing values are validated, never rewritten or backfilled.
alter table public.matches add constraint matches_v1_final_score_check check (
  status <> 'completed' or (
    ((greatest(side_one_score,side_two_score)=11 and least(side_one_score,side_two_score) between 0 and 9)
      or (least(side_one_score,side_two_score)>=10 and abs(side_one_score::bigint-side_two_score::bigint)=2))
    and winner_team_id=case when side_one_score>side_two_score then side_one_team_id else side_two_team_id end
  )
);

create or replace function private.prevent_completed_result_correction()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.status='completed' and (new.side_one_score is distinct from old.side_one_score
    or new.side_two_score is distinct from old.side_two_score or new.winner_team_id is distinct from old.winner_team_id
    or new.side_one_team_id is distinct from old.side_one_team_id or new.side_two_team_id is distinct from old.side_two_team_id) then
    raise exception 'Completed result correction awaits OPEN-004.' using errcode='23514';
  end if;
  return new;
end;
$$;
create trigger matches_completed_result_lock before update on public.matches
for each row execute function private.prevent_completed_result_correction();
revoke all on function private.prevent_completed_result_correction() from public,anon,authenticated;

-- Existing fixed aggregate RPC handles format-only mutations, versions,
-- receipts and organizer checks; no new public command or grants are needed.
do $$
begin
  if has_function_privilege('anon','public.apply_event_setup_operation(uuid,uuid,bigint,jsonb)','execute')
    or not has_function_privilege('authenticated','public.apply_event_setup_operation(uuid,uuid,bigint,jsonb)','execute')
    or not exists(select 1 from pg_constraint where conrelid='public.matches'::regclass and conname='matches_v1_final_score_check')
    or exists(select 1 from pg_class where oid in ('public.events'::regclass,'public.event_divisions'::regclass,'public.matches'::regclass) and not relrowsecurity)
  then raise exception 'M12 catalog/security assertion failed'; end if;
end;
$$;
