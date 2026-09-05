# Conceptual Database Model

## M15 double-elimination mapping

PostgreSQL adds `double_elimination_brackets` as the public aggregate root and
a private idempotency receipt table. Existing `matches`,
`match_dependencies`, `match_result_revisions`, and `division_placements`
remain the normalized tournament record. Dependencies explicitly route both
winners and losers. Grand Final 2 has a deterministic planned identity but no
played Match row until the reset condition is met; an unnecessary reset is
never persisted as a fake match.

Drift schema 9 adds `double_elimination_snapshots`,
`double_elimination_outbox`, and `double_elimination_checkpoints` through a
real v8-to-v9 migration. Existing rows and integrity triggers are preserved.
No statistics, losers-bracket-specific team identity, or court-queue columns
are added.

## M13 schema addition

PostgreSQL adds public single_elimination_brackets (plan/seed metadata),
organizer-readable immutable match_result_revisions and private idempotency
receipts. Existing matches, match_dependencies and division_placements carry
playable state; byes never become scored records. Direct client match writes
are revoked in favor of organizer-validated atomic commands. Drift schema 7
adds bracket snapshots/outbox/checkpoints/revisions via a real v6 migration.
The applied schema was preserved; the collision repair and regression migrations
are recorded in [M13](milestones/M13_SINGLE_ELIMINATION.md).

## M12 integrity changes

No new operational tables/enums. Drift v6 replaces format locks and adds final
score/result triggers; PostgreSQL validates equivalent score/start guards.
Existing records are preserved. Formats change only during Registration before
generated match history. Starting requires two complete teams and active matches
per division. Read-only setup responses expose readiness counts; command
payloads cannot supply them. No match synchronization is added.

## Scope and conventions

This document began as the high-level model. Milestone 3 adds the initial
PostgreSQL realization under `supabase/`, and Milestone 4 adds Android SQLite
schema version 1 through Drift. Both are evolvable Version 1 baselines rather
than permission to implement later feature work early.

Milestone 2 maps this conceptual model to pure-Dart records and typed IDs under
`lib/src/domain`. Those records are provider-neutral contracts, not database
rows. Names and relationships below do not prescribe tables, columns, indexes,
foreign keys, PostgreSQL types, SQLite types, or serialization formats.

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

## Milestone 7 account and player-claim realization

M7 adds nullable `user_profiles.player_id` as the private, unique link from an
Auth account to an existing permanent player. `players` is unchanged and still
contains no Auth user ID, email, role, or claim information. Android SQLite
does not mirror profiles, roles, or claims.

`player_claim_requests` stores client-generated UUID, requesting Auth user,
existing player, `pending`/`approved`/`rejected`/`cancelled` status, requested
and review timestamps, reviewer, optional bounded reason, optimistic version,
and tombstone metadata. Restrictive foreign keys and partial unique indexes
prevent multiple pending claims per account, multiple approved players per
account, and one player being approved for multiple accounts. Clients have no
hard-delete privilege.

Members use fixed RPCs to request or cancel their own pending claim and can
read only their own active claim/profile. Organizers may read the minimum
profile display name and pending-claim data needed for review. Atomic approval
locks the claim, profile, and player, rechecks both uniqueness conditions,
updates the private profile link, and finalizes review in one transaction.
Rejection never changes player identity or the profile link.

An `auth.users` trigger creates a private profile with a bounded optional
metadata display name or the safe `Community member` fallback. Metadata never
assigns roles or player links. Existing accounts without a profile receive the
same minimum profile when their account snapshot is first requested.

## Milestone 2 domain mapping

| Conceptual data | Pure-Dart representation | Boundary note |
| --- | --- | --- |
| Optional auth-account link | `AccountId?` on `PermanentPlayer` | Claim workflow, user profiles, roles, and authentication remain unimplemented. |
| Players | `PermanentPlayer` / `PlayerId` | Contains no stored wins, losses, titles, win rate, appearances, or partner statistics. |
| Events | `Event` / `EventId` | Validates only the approved adjacent lifecycle and UTC scheduled time. |
| Event divisions | `EventDivision` / `DivisionId` | Division name stays configurable; format uses only the four approved values. |
| Event participants | `EventParticipant` / `EventParticipantId` | References `PlayerId` rather than duplicating player identity. |
| Division participants | `DivisionParticipant` / `DivisionParticipantId` | Structural support does not decide whether multi-division entry is permitted. |
| Paid/Unpaid records | `ParticipantPayment` / `ParticipantPaymentId` | Optional division scope preserves `OPEN-008`; there is no payment transaction. |
| Temporary teams/members | `TemporaryTeam` / `TeamId` / immutable `PlayerId` list | Division-scoped; no fixed size or generation algorithm. |
| Matches | `Match` / `MatchId` | Structural status, sides, scores, and winner only; no generation, score rules, or progression. |
| Match dependencies | `MatchDependency` | Describes winner/loser routing to a destination side but does not execute it. |
| Court queue entries | `CourtQueueEntry` / `CourtQueueEntryId` | Zero-based structural order for the one court; no scheduling logic. |
| Finalized placements | `DivisionPlacement` / `DivisionPlacementId` | Requires a positive finish and performs no calculation. |
| Shared record metadata | `RecordMetadata` | Caller-supplied UTC times, nonnegative version, optional tombstone; no sync behavior. |

`PlayerRepository`, `EventRepository`, and `MatchRepository` are persistence
ports only. No SQL, migration, provider mapping, outbox, checkpoint, conflict
record, or production repository implementation is created in Milestone 2.

## Milestone 3 PostgreSQL realization

The hosted `public` schema implements 14 required tables:

| Boundary | Tables | Exposure |
| --- | --- | --- |
| Account identity and permission | `user_profiles`, `user_roles` | Authenticated owner/role-holder only; never anonymous. |
| Permanent community identity | `players` | Non-deleted rows are public; contains no Auth user ID. |
| Events and participation | `events`, `event_divisions`, `event_participants`, `division_participants` | Non-deleted rows are public. |
| Payment status | `participant_payments` | Organizer-only; stores `paid`/`unpaid`, not a transaction. |
| Temporary teams | `teams`, `team_members` | Non-deleted rows are public and division-scoped. |
| Tournament records | `matches`, `match_dependencies`, `court_queue_entries`, `division_placements` | Non-deleted rows are public; structural only. |

Domain entity IDs use client-supplied UUID primary keys. Mutable records carry
UTC-compatible `timestamptz` creation/update timestamps, nonnegative optimistic
versions, and nullable deletion tombstones. Foreign keys use restrictive
historical deletion except private Auth-owned profile/role rows, which follow
the Auth user lifecycle. Client roles receive no SQL `DELETE` privilege.

Check constraints use the exact M2 strings for event type/status, tournament
format, check-in, payment, team-formation method, match status, dependency
outcome, and destination slot. Money remains integer minor units with a
three-letter currency. Match scores are only structurally nonnegative; no
unapproved pickleball scoring rule is encoded.

Database triggers enforce adjacent event/match status changes and reject
cross-event or cross-division references for participants, scoped payments,
match teams/dependencies, queue entries, and placements. They do not generate a
tournament, advance a bracket, calculate standings, schedule a court, or
synchronize clients.

All exposed tables have RLS. A private `SECURITY DEFINER` function with an empty
search path checks normalized active organizer roles. Public client reads,
organizer official writes, private profile/role access, and organizer-only
payments are implemented as explicit grants and policies. No registration
trigger creates an organizer, and no client can modify `user_roles`.

The public display tables are included idempotently in the
`supabase_realtime` publication. Identity and payment tables are excluded.

The migrations intentionally create no player claim, skill rating, outbox,
checkpoint, failed-operation, conflict, or synchronization table. Those remain
deferred to their approved milestones and open decisions.

## Milestone 4 Android SQLite realization

Drift schema version 1 mirrors the twelve operational M3 tables and intentionally
omits `user_profiles` and `user_roles`. Table and column vocabulary follows M3,
while generated row classes remain infrastructure types rather than domain
entities.

| M2/M3 concept | Local Drift table | Mapping note |
| --- | --- | --- |
| Permanent players | `players` | UUID text is revalidated as `PlayerId`; no Auth/account column is stored. |
| Events | `events` | Money uses paired integer minor units/currency; timestamps normalize to UTC. |
| Divisions and participation | `event_divisions`, `event_participants`, `division_participants` | Restrictive foreign keys and active partial uniqueness match cloud relationships. |
| Payment status | `participant_payments` | Optional division scope remains structural and unresolved; no transaction details. |
| Temporary teams | `teams`, `team_members` | Division-scoped; members reference permanent player IDs and no team size is fixed. |
| Tournament records | `matches`, `match_dependencies` | Structural state and dependency routing only; no generation or advancement. |
| One-court/final records | `court_queue_entries`, `division_placements` | Structural order and placement only. |

SQLite stores synchronizable UUIDs as 36-character text because it has no native
UUID type. Domain constructors enforce canonical form when rows cross the
repository boundary. Drift stores `DateTime` values as ISO-8601 text to preserve
sub-second precision; PostgreSQL uses `timestamptz`. Both map without domain
information loss to UTC `DateTime`.

Foreign keys, validation checks, active partial unique indexes, adjacent
event/match transition triggers, and cross-event/division triggers align the
local structural protections with M3. The committed version-one snapshot is
`drift_schemas/app_database_v1.json`. There is no fake pre-version-one migration.

No local sync/outbox fields or tables exist in M4. Those conceptual records in
the synchronization section remain future M5 work.

## Milestone 5 player synchronization realization

Local schema version 2 preserves every M4 table and adds three infrastructure
tables for the permanent-player slice:

| Synchronization concept | Drift table | Purpose |
| --- | --- | --- |
| Durable operation intent | `sync_outbox_operations` | Stable operation/entity UUIDs, fixed entity/kind values, base version, deterministic player payload, UTC ordering/eligibility, attempts, claim state, and redacted failure information. |
| Pull cursor | `sync_pull_checkpoints` | Last authoritative `(updated_at, player_id)` tuple applied for deterministic player pulls. |
| Preserved conflict | `sync_conflicts` | Operation identity, expected version, local proposal, optional authoritative remote record/version, detection time, and unresolved/resolved state. |

These tables are separate infrastructure metadata, not domain records or a
claim that all operational tables synchronize. The v1→v2 migration creates
them and their indexes without changing the twelve M4 tables. Generated
snapshots use Drift's recognized `drift_schema_v1.json` and
`drift_schema_v2.json` names; the accepted legacy M4 snapshot remains intact.

The hosted M5 migration creates `private.player_sync_operation_receipts` and
two fixed public functions. Receipts are not Data API-readable and contain only
the validated request and accepted/conflict result needed for idempotent replay.
`apply_player_sync_operation` can mutate only `public.players`, checks the M3
organizer permission, validates an allowlisted payload, preserves tombstones,
and enforces exact optimistic-version advancement. `pull_player_sync_changes`
returns an organizer-authorized, tombstone-aware page ordered by
`(updated_at, id)`. Neither function accepts a table name or SQL fragment.

No profile, role, payment, event, team, match, queue, placement, or account-link
record is added to the synchronization slice. There is still no hard deletion,
derived player-stat counter, real community data, or final physical design for
future entities.

## Milestone 6 public event projection and fixtures

The public guest projection reads only active rows from `events` and
`event_divisions`. The Supabase adapter maps the existing PostgreSQL columns
through M2 UUID, enum, money, UTC metadata, version, and tombstone validation;
there is no parallel public schema or widget-level map parsing.

Android reuses the M4 local `events` and `event_divisions` tables as a
last-known public cache. A successful complete remote read is reconciled in one
SQLite transaction. The cache preserves UUIDs, integer-minor-unit fees, exact
enum values, UTC metadata, versions, and division relationships. Missing
remote active rows receive local cache tombstones; no event/division outbox,
dirty flag, cursor, or new table is introduced. A local row with a newer
version/timestamp is preserved as a conflict rather than overwritten.

The M6 data migration inserts three explicitly synthetic events and four
synthetic divisions using deterministic IDs prefixed `61000000-` and
`62000000-`. They exercise current, upcoming, and completed presentation only;
they include no people, accounts, payments, contact data, or credentials.
## M8 player-directory mapping

M8 does not change the `players` record shape. Public list/profile reads use
`id`, `display_name`, UTC metadata, version, and tombstone filtering only. A
fixed `search_public_players` function provides normalized substring search,
stable `(normalized name, id)` cursor ordering, and a hard 50-row maximum. It
is invoker-security and remains subject to existing player RLS. A partial
expression index supports active normalized-name ordering.

Android maps the same fields to the existing Drift `players` table. Public
pull reconciliation creates no outbox record and preserves pending/conflicted
local rows. Organizer creation uses the existing player plus outbox transaction.
No Auth UUID, email, claim, role, skill, statistics, merge, or event-specific
column is added to `players`.

## M9 event/division setup mapping

`event_divisions.tournament_format` is nullable in PostgreSQL and Drift schema
version 3. Domain `EventDivision.format` is optional. Null means not configured
yet; it is not a fifth format or evidence that no format is needed. Existing
non-null values remain unchanged. M12 owns format selection and generation.

Android adds separate event-aggregate outbox, checkpoint, and conflict tables.
The hosted private receipt table supports fixed idempotent application and is
denied to client roles. Records retain UUID, UTC, version, tombstone,
foreign-key, active-name uniqueness, and restrictive-delete constraints.

## M10 participation mapping

`event_participants` links one permanent `players` row to one `events` row and
stores the approved check-in enum. The active `(event_id, player_id)` index
prevents duplicate registration. `division_participants` links that participant
to one or more active divisions belonging to the same event; its active unique
index prevents duplicate assignments. `participant_payments` remains private,
and M10 creates one event-scoped row (`division_id` null) containing only
`unpaid` or `paid`. There is no amount or payment-processing column to migrate.

Android schema version 4 adds only `participation_outbox_operations`,
`participation_pull_checkpoints`, and `participation_conflicts`. PostgreSQL adds
a private receipt table and fixed aggregate apply/pull functions; it adds no
Auth identity, team, match, or sync columns to public domain rows.

## M11 player-skill and team mapping

`players.skill_level` is nullable and constrained to integers 1 through 5.
Existing rows remain null/Unrated; labels are presentation values, not stored
authority. PostgreSQL and Drift preserve the field through public reads and the
existing player synchronization protocol.

`teams` remain division-scoped temporary identities and `team_members` retain
permanent `player_id` references. M11 persists only complete two-member teams;
an odd eligible participant has no fake team row. Active membership must be a
checked-in, active event and division participant, and one player may have only
one active team in a division. Android schema version 5 adds bounded
`team_formation_outbox_operations`, `team_formation_pull_checkpoints`, and
`team_formation_conflicts`; they do not change the cloud domain tables.
## M14 round-robin mapping

`round_robin_tournaments` is the cloud aggregate root for a division schedule;
Android mirrors it as `round_robin_snapshots` with bounded outbox/checkpoint
tables. Existing `matches`, `match_result_revisions`, and
`division_placements` remain the operational source. Round and match positions
are stored in existing match columns; leg and resting-team information remains
in the validated deterministic plan. No dependency rows are created.

Standings totals are calculated from active completed matches and are not
stored. Once all expected matches complete, placement rows for every team are
replaced atomically using tombstones for prior placements. The private receipt
table stores idempotency results and is inaccessible to client roles.
