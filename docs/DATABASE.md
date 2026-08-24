# Conceptual Database Model

## Scope and conventions

This is a high-level model, not a final schema. It contains no SQL, migration,
storage-specific type, or final column definition. PostgreSQL and Android
SQLite representations will be designed in their appropriate milestones.

Shared records use client-generated UUIDs so Android can create identities
offline without a server round trip. Synchronizable records conceptually carry
an optimistic version, creation/update timestamps, and origin/operation
metadata as needed. Records that must be removed from active views use
tombstones so deletion can synchronize and historical integrity can be
preserved. Server-controlled timestamps remain authoritative after cloud
acceptance; clients retain enough local metadata to reconcile changes.

## Identity and permissions

- **Supabase auth users:** authenticated cloud identities. Authentication does
  not itself create or prove a player identity.
- **User profiles:** application-facing information associated one-to-one with
  an auth user.
- **User roles:** assignments of application roles to users.
- **Organizer permissions:** the authority required for management operations;
  enforced in application use cases and in the cloud through RLS and/or secure
  database functions.
- **Player claim requests (or equivalent secure claim concept):** requests to
  link an authenticated user to an existing player without replacing that
  player or its history. Verification and approval remain open.

An account link from a player to an auth user is optional. A player without an
account remains fully usable in events. Any accepted claim must preserve the
same player identity and all historical relationships.

## Permanent player data

- **Players:** reusable community identities referenced by every event in which
  they participate.
- **Optional account link:** associates at most the approved player identity
  with an authenticated user, subject to claim controls.
- **Approved skill information:** the limited input used by simple balanced
  team generation. Its scale and approval workflow are not yet decided.

Players are not recreated for each event. Duplicate detection rules arrive in
the player-directory milestone without merging unrelated histories silently.

## Events and participation

- **Events:** casual or formal competitions with the lifecycle `UPCOMING` →
  `REGISTRATION` → `IN PROGRESS` → `COMPLETED` → `ARCHIVED`.
- **Event divisions:** optional formal-event groupings such as Men, Women, Kids,
  Seniors, Mixed, and Open. An event need not contain all or any prescribed set
  of divisions.
- **Event participants:** links permanent players to an event and captures
  event-level participation state.
- **Division participants:** associates eligible event participants with a
  division when divisions are used.
- **Check-in status:** records whether a participant is present and therefore
  eligible for team/match generation.
- **Paid/Unpaid status:** records payment status and supports related totals;
  it never represents an in-app financial transaction.

Whether a player may enter multiple divisions and whether payment status is
event-wide or division-specific are open decisions.

## Temporary teams

- **Teams:** temporary competitive units belonging to a specific event and,
  when applicable, division.
- **Team members:** links eligible, checked-in participants to their temporary
  team.

Teams do not become reusable community identities. Whether Version 1 team size
is fixed at two or configurable is open.

## Tournament records

- **Matches:** scheduled contests, participants/teams, state, scores, result,
  and format context. Finalized matches are the statistical source of truth
  where practical.
- **Match dependencies:** directed progression relationships used to place
  winners or losers into later elimination matches without hard-coding UI
  layout as data.
- **Court queue entries:** ordered or stateful records for the one-court Now
  Playing and Up Next workflow.
- **Finalized division placements:** historical finish records such as champion
  and runner-up after a division is completed.

Match history and finalized placements are preserved. Exact scoring,
correction, tie-breaker, and double-elimination final rules remain open.

## Synchronization records

- **Local outbox:** durable Android operations created atomically with local
  mutations and carrying unique operation IDs.
- **Sync checkpoints:** per-scope cursors or watermarks used for incremental
  pull reconciliation.
- **Failed operations:** attempts that require retry, investigation, or a
  permanent-error state without losing the original intent.
- **Conflict records:** durable descriptions of version, lifecycle,
  authorization, dependency, or deletion conflicts needing policy or human
  handling.
- **Unique operation IDs:** client-generated UUIDs used by the cloud to dedupe
  retries and return the result of an already-applied mutation.

Outbox, checkpoint, failure, and conflict records are local coordination data.
The cloud may retain operation receipts or equivalent idempotency metadata, but
the exact persistence design is deferred.

## Relationship summary

- One auth user has an application profile and role assignments; an approved
  claim may link that user to one existing player record.
- One event has zero or more divisions and many event participants.
- Division participants refer to event participants, not duplicate players.
- One event/division has temporary teams; each team has team members drawn from
  eligible participants.
- Matches belong to an event/division and refer to temporary teams or other
  format-appropriate competitors.
- Match dependencies connect elimination matches; court queue entries schedule
  playable matches on the one court.
- Completed match records support finalized placements and derived individual
  and partner statistics.

See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership boundaries and
[SYNC.md](SYNC.md) for conceptual reconciliation behavior.
