-- Preserve the deterministic conditional-reset identity in every client view.
create or replace function private.double_elimination_json(
  p_division uuid,
  p_audit boolean default false
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'plan', b.plan,
    'reset_match_id', b.match_ids->>'de/finals/gf2',
    'created_at', b.created_at,
    'updated_at', b.updated_at,
    'version', b.version,
    'deleted_at', b.deleted_at,
    'matches', coalesce((
      select jsonb_agg(
        to_jsonb(m) || jsonb_build_object('planned_key', k.key)
        order by m.sequence_number, m.id
      )
      from jsonb_each_text(b.match_ids) k
      join public.matches m on m.id = k.value::uuid
      where m.deleted_at is null
    ), '[]'::jsonb),
    'revisions', case when p_audit then coalesce((
      select jsonb_agg(jsonb_build_object(
        'operation_id', r.operation_id,
        'previous', r.previous_result,
        'reason', r.reason,
        'recorded_at', r.recorded_at
      ) order by r.recorded_at, r.operation_id)
      from public.match_result_revisions r
      join public.matches m on m.id = r.match_id
      where m.division_id = p_division
    ), '[]'::jsonb) else '[]'::jsonb end
  )
  from public.double_elimination_brackets b
  where b.division_id = p_division and b.deleted_at is null;
$$;

do $$
begin
  if exists (
    select 1
    from public.double_elimination_brackets b
    where b.deleted_at is null
      and (
        b.match_ids->>'de/finals/gf2' is null
        or private.double_elimination_json(b.division_id, false)
             ->>'reset_match_id'
           is distinct from b.match_ids->>'de/finals/gf2'
      )
  ) then
    raise exception 'M15 reset-match identity projection assertion failed';
  end if;
end;
$$;

revoke all on function private.double_elimination_json(uuid, boolean)
  from public, anon, authenticated;
