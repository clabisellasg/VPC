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
      where e.id = old.event_id and e.status <> 'upcoming'
    )
  then
    raise exception 'Event division setup is locked after UPCOMING.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists event_divisions_setup_lock_guard
  on public.event_divisions;
create trigger event_divisions_setup_lock_guard
before update of name, tournament_format, deleted_at
on public.event_divisions
for each row execute function private.enforce_event_division_setup_lock();

create or replace function private.enforce_event_format_before_start()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'inProgress' and old.status <> 'inProgress'
    and exists (
      select 1 from public.event_divisions d
      where d.event_id = new.id
        and d.deleted_at is null
        and d.tournament_format is null
    )
  then
    raise exception 'Tournament formats must be configured before this event can begin.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists events_format_required_guard on public.events;
create trigger events_format_required_guard
before update of status on public.events
for each row execute function private.enforce_event_format_before_start();
