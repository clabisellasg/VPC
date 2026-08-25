# M02 — Domain and Persistence Contracts

## Goal and result

Milestone 2 establishes a pure-Dart vocabulary and persistence-contract boundary
shared by future application, SQLite, Supabase, synchronization, and tournament
work. It defines immutable records, validated value objects and state
transitions, provider-neutral repository ports, and typed expected failures. It
does not store, synchronize, display, or generate tournament data.

## Implemented domain concepts

- Nominal identifiers for accounts, players, events, divisions, event and
  division participants, participant payments, teams, matches, court queue
  entries, and division placements.
- `Money`, deterministic record metadata, the approved enums, and typed domain
  failures/repository results.
- Permanent players; events and their forward-only lifecycle; configurable
  event divisions; event/division participation; and scoped Paid/Unpaid records.
- Division-scoped temporary teams with immutable permanent-player references.
- Structural matches, match dependencies, one-court queue entries, and
  finalized division placements.
- Pure-Dart `PlayerRepository`, `EventRepository`, and `MatchRepository` ports.

## Important files

- `lib/src/domain/common/`: typed failures/results, UUID IDs, Money, metadata,
  validation helpers, and approved enums.
- `lib/src/domain/players/`: permanent player model and player repository port.
- `lib/src/domain/events/`: event lifecycle, divisions, participation/payment
  records, and event repository port.
- `lib/src/domain/teams/temporary_team.dart`: immutable temporary team record.
- `lib/src/domain/matches/`: structural match state, dependency description,
  and match repository port.
- `lib/src/domain/court/court_queue_entry.dart`: structural single-court order.
- `lib/src/domain/results/division_placement.dart`: finalized placement record.
- `test/domain/`: focused value, entity, transition, and repository-contract
  tests. Repository implementations here are test fakes only.

## Value and metadata policies

Each entity ID is a separate nominal Dart type over a lowercase canonical UUID
string. Blank, malformed, or noncanonical strings raise `ValidationFailure`;
ID creation/generation is intentionally absent. Equal IDs must have both the
same concrete type and value, so a `PlayerId` is not equal or assignable to a
`TeamId`.

`Money` stores a nonnegative integer number of minor units and a normalized
three-letter ISO-style currency code. It defaults to `PHP`, permits zero, never
uses `double`, and represents no payment-processing behavior.

`RecordMetadata` requires caller-supplied UTC `createdAt` and `updatedAt`
timestamps, a nonnegative record version, and an optional UTC `deletedAt`
tombstone. Update/deletion chronology is validated. Domain entities do not read
the system clock, increment versions, or perform synchronization.

## State machines and expected failures

The event state machine accepts only adjacent forward movement:

`upcoming` → `registration` → `inProgress` → `completed` → `archived`

Skipping, moving backward, moving from `archived`, and requesting the current
state all raise `InvalidStateTransitionFailure`. Match structural status follows
the same explicit adjacent-only convention:

`scheduled` → `queued` → `inProgress` → `completed`

A completed match requires two distinct team sides, nonnegative structural
scores for both sides, and a winner that is one of those sides. No sport-specific
score rule or outcome calculation is inferred.

Constructors use typed `DomainFailure` subtypes for expected validation and
transition failures. Repository calls return `RepositoryResult<T>`, containing
either a value or a typed failure for validation, not-found, version conflict,
persistence unavailability, unauthorized access, or an unknown repository
failure. No SQLite, Supabase, HTTP, or Flutter exception crosses the port.

## Relationships and repository boundaries

Players are permanent records. Event participants refer to a `PlayerId`; a
division participant refers to its event participant. A payment refers to an
event participant and may optionally carry a division scope, preserving the
open payment-scope decision. Teams are temporary, division-scoped collections
of `PlayerId`s and do not enforce a two-player size. Matches and placements
refer to those temporary teams by ID.

Repository ports expose typed IDs, domain records, domain-safe query objects,
`Future`, `Stream`, and `RepositoryResult`. They contain read, observation, and
save operations only. They expose no provider row/response/JSON/platform type
and no hard-delete operation. SQLite, Supabase, synchronized, cached, and
production in-memory implementations remain future work.

## Tests and commands

Run all tests, including the pure-domain suites, with:

```powershell
flutter test
```

Run only the M2 suites with:

```powershell
flutter test test/domain
```

Formatting, analysis, Web, and Android regression checks use the commands in
the repository [README](../../README.md).

All 36 M2 domain tests and the five unchanged M1 tests pass locally. Formatting,
static analysis, the Web production build, and Android debug APK build also
pass. The artifacts are local build outputs only; nothing was deployed.

## Known limitations and deliberately open decisions

This milestone intentionally does not resolve:

1. Existing-player claim verification/approval (`OPEN-001`).
2. Balanced-team player skill scale (`OPEN-002`).
3. Exact score validation (`OPEN-003`).
4. Correcting completed results after progression (`OPEN-004`).
5. Round-robin tie-breaker order (`OPEN-005`).
6. Double-elimination grand-final reset (`OPEN-006`).
7. Multiple divisions per player/event (`OPEN-007`).
8. Event-wide versus division-specific payment status (`OPEN-008`).
9. Simultaneous-organizer conflict/control policy (`OPEN-009`).
10. Free Flutter Web/PWA hosting provider (`OPEN-010`).
11. Version 1 authentication methods (`OPEN-011`).
12. Fixed-two versus configurable team size (`OPEN-012`).

There is no SQLite schema or repository, Supabase/PostgreSQL implementation,
authentication, synchronization, tournament generation, bracket progression,
round-robin standings, score-rule implementation, or new UI feature in M2. The
M1 bootstrap remains unchanged.
