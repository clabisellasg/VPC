create or replace function private.enforce_event_division_setup_lock()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.name is distinct from old.name
      or new.tournament_format is distinct from old.tournament_format
      or new.deleted_at is distinct from old.deleted_at)
    and exists (
      select 1 from public.events e
      where e.id = old.event_id
        and e.status <> 'upcoming'
        and e.deleted_at is null
    )
  then
    raise exception 'Event division setup is locked after UPCOMING.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
