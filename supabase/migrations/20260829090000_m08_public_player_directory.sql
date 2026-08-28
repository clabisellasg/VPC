-- M8 fixed, bounded public-player search. This remains subject to players RLS.
create index if not exists players_active_normalized_name_id_idx
on public.players (
  lower(regexp_replace(btrim(display_name), '[[:space:]]+', ' ', 'g')),
  id
)
where deleted_at is null;

create or replace function public.search_public_players(
  p_query text default '',
  p_after_name text default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  display_name text,
  created_at timestamptz,
  updated_at timestamptz,
  version bigint,
  deleted_at timestamptz,
  normalized_name text,
  has_more boolean
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  normalized_query text := lower(
    regexp_replace(btrim(coalesce(p_query, '')), '[[:space:]]+', ' ', 'g')
  );
  normalized_after text := case
    when p_after_name is null then null
    else lower(
      regexp_replace(btrim(p_after_name), '[[:space:]]+', ' ', 'g')
    )
  end;
begin
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'Player directory limit must be between 1 and 50.'
      using errcode = '22023';
  end if;
  if (p_after_name is null) <> (p_after_id is null) then
    raise exception 'Player directory cursor fields must be supplied together.'
      using errcode = '22023';
  end if;

  return query
  with eligible as (
    select
      p.id,
      p.display_name,
      p.created_at,
      p.updated_at,
      p.version,
      p.deleted_at,
      lower(
        regexp_replace(btrim(p.display_name), '[[:space:]]+', ' ', 'g')
      ) as normalized_name
    from public.players as p
    where p.deleted_at is null
  ),
  ordered as (
    select e.*
    from eligible as e
    where position(normalized_query in e.normalized_name) > 0
      and (
        normalized_after is null
        or (e.normalized_name, e.id) > (normalized_after, p_after_id)
      )
    order by e.normalized_name, e.id
    limit p_limit + 1
  ),
  numbered as (
    select o.*, row_number() over (order by o.normalized_name, o.id) as row_number,
      count(*) over () > p_limit as has_more
    from ordered as o
  )
  select
    n.id,
    n.display_name,
    n.created_at,
    n.updated_at,
    n.version,
    n.deleted_at,
    n.normalized_name,
    n.has_more
  from numbered as n
  where n.row_number <= p_limit
  order by n.normalized_name, n.id;
end;
$$;

revoke all on function public.search_public_players(text, text, uuid, integer)
from public;
grant execute on function public.search_public_players(text, text, uuid, integer)
to anon, authenticated;
