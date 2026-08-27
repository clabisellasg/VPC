# Testing Strategy

## Current status

Milestone 0 established the intended strategy, Milestone 1 introduced the
Flutter bootstrap harness, and Milestone 2 added pure-domain/contract suites.
Milestone 3 adds Supabase configuration and database-security coverage.
Milestone 4 adds deterministic in-memory SQLite, generated-schema freshness,
production repository-adapter, transaction, lifecycle, and platform-boundary
coverage. Milestone 5 adds the player synchronization vertical-slice suite.
Authentication flows, remaining-entity synchronization, and tournament-engine
tests remain future work.

## Milestone 5 coverage and execution

- Drift migration verification starts from the committed v1 schema, inserts an
  M4 player, migrates to v2, validates the schema, and proves the player
  survived while all three synchronization tables and indexes were added.
- In-memory SQLite tests cover constrained outbox/checkpoint/conflict storage,
  stable operation UUIDs, deterministic ordering, stale in-flight recovery,
  tombstone and UTC/version payloads, and checkpoint persistence.
- Repository tests prove player mutation plus outbox commit atomically and a
  forced duplicate-operation failure rolls back the player update completely.
- Coordinator tests cover one active run, bounded batches, accepted and replayed
  uploads, authorization blocking, retryable backoff with injected jitter,
  conflict preservation, authoritative pull, and disposal.
- Pull tests cover equal-version idempotency, newer-remote application,
  tombstones, and pending-local-versus-remote conflicts with neither silent
  local-wins nor remote-wins behavior.
- Realtime/runtime tests cover initial foreground triggering, refresh hints,
  burst coalescing, duplicate-start prevention, and subscription/timer disposal.
- Ordinary Flutter tests use in-memory Drift, fake clock/IDs/jitter/gateways,
  and no network, credentials, Docker, emulator, or Supabase account.
- `player_sync_vertical_slice_test.sql` contains ten pgTAP catalog and
  anonymous/non-organizer security assertions. Docker was unavailable, so this
  file was retained but not executed locally.
- Hosted assertion migrations validated private receipts, safe function grants
  and `search_path`, organizer-only apply/pull, create, replay idempotency,
  changed-payload rejection, stale-version conflict, authoritative pull, and
  complete removal of temporary assertion records.
- Publishable-key smoke checks returned `200` for public player reads and `401`
  for payment/profile/role reads and anonymous apply/pull calls. Linked history
  matches and linked database lint reports no errors.

The final acceptance run passed formatting, analysis, all 85 Flutter tests,
the Web production build, and Android debug APK build. Outputs are `build/web`
and `build/app/outputs/flutter-apk/app-debug.apk`; both remain ignored. The Web
build repeated the accepted optional Cupertino-font diagnostic and successful
Wasm dry run. Android repeated the accepted SDK XML-version warning and passed
without a license failure. No remote GitHub Actions run is claimed.

## Milestone 4 coverage and execution

- Fresh schema creation verifies explicit version 1 and all twelve operational
  tables, with no local profile, role, or synchronization table.
- Constraint tests cover foreign-key enforcement, active uniqueness, exact enum
  mapping, state/scope trigger installation, and invalid stored UUID mapping.
- Round-trip tests cover client UUIDs, integer-minor-unit money, every approved
  enum name, UTC sub-second timestamps, optimistic versions, and tombstones.
- Transaction tests prove both full multi-table commit and full rollback after
  a later member insert fails.
- Production `PlayerRepository`, `EventRepository`, and `MatchRepository`
  adapters are tested for save, lookup, observation, filtering, tombstone
  exclusion, missing records, version conflicts, lifecycle constraints, and
  refusal to discard an unsupported account link.
- Lifecycle/platform tests cover database close and the explicit null local
  persistence boundary on Web and unsupported native platforms.
- Tests use in-memory SQLite. They require no emulator, Internet, Supabase,
  credentials, authenticated account, or community data.
- CI regenerates `app_database.g.dart`, re-exports the version-one Drift schema,
  and fails on a generated diff before formatting, analysis, tests, and builds.
- The final local run formatted 63 files with no change, found no analyzer
  issue, and passed all 65 Flutter tests: 47 M1–M3 tests plus 18 M4 tests.
- `flutter build web` produced `build/web`; `flutter build apk --debug`
  produced `build/app/outputs/flutter-apk/app-debug.apk`.
- The Web build repeated the non-fatal optional Cupertino-icons font diagnostic
  and passed its Wasm dry run. The first M4 native build downloaded CMake
  `3.22.1` through Gradle using the existing Android SDK license state; the APK
  build then passed without a direct `sqlite3_flutter_libs` dependency.
- Repeated generation produced no Dart output, and repeated schema export kept
  both generated-artifact SHA-256 hashes unchanged.

## Milestone 3 coverage and execution

- Six focused Flutter tests cover absent, complete, partial, and invalid
  Supabase configuration, value-redacting failures, skipped initialization, and
  exactly-once initialization through a test double. They make no network call.
- `supabase/tests/database/cloud_foundation_test.sql` contains 35 pgTAP
  assertions for required tables, foreign keys/checks, RLS, no client hard
  delete, guest read/write behavior, payment/profile/role privacy, organizer
  writes, and prevention of role self-escalation.
- The pgTAP suite was not executed. Docker is installed but its engine is not
  running, and Supabase CLI `2.115.0` still invokes a Docker-based runner for
  `supabase test db --linked`. The command failed before SQL execution.
- A hosted assertion migration successfully verified all 14 required tables,
  RLS on each, 40 expected policies, public/private grants, absence of client
  DELETE grants, safe organizer-helper configuration, public player/Auth
  separation, and 11 Realtime publication entries.
- Publishable-key REST checks returned `200` for all public-table reads, `401`
  for payment/profile/role reads, and `401` for an anonymous player insert. No
  test data was created.
- Linked migration histories agree and `supabase db lint --linked` reports no
  schema error. The dashboard Security Advisor was unavailable without a
  separately authenticated browser session; no advisor result is claimed.
- Full authenticated organizer end-to-end testing is deferred until M7 creates
  an approved authentication flow. Policy definitions and pgTAP coverage exist
  now.
- `flutter pub get`, Dart formatting verification, `flutter analyze`, and all
  47 Flutter tests passed. `flutter build web` produced `build/web`, and
  `flutter build apk --debug` produced
  `build/app/outputs/flutter-apk/app-debug.apk`.
- The first Android build attempt exhausted native memory after stale 2 GB
  Kotlin/JVM daemons accumulated. Stopping those daemons and limiting the
  validation run to one in-process compiler worker allowed the decisive build
  to pass. The accepted Gradle configuration was restored afterward. The only
  remaining Android output was the known non-fatal SDK XML-version warning; no
  license error occurred.

## Milestone 2 automated coverage

- Typed IDs: canonical UUID validation, blank/malformed rejection, nominal
  equality, value equality, and all required ID types.
- Money and metadata: zero/positive minor units, currency normalization and
  validation, equality, UTC timestamps, chronology, nonnegative versions, and
  tombstones.
- Events and participation: exact approved enums, every adjacent lifecycle
  transition, invalid transition classes, configurable division names, typed
  player participation, and optional payment division scope.
- Players and teams: permanent identity, optional account link, immutable
  `PlayerId` membership, empty/duplicate rejection, and non-fixed team size.
- Matches, court, and results: structural statuses/transitions/scores,
  completed-state consistency, dependency routing values, queue ordering, and
  positive finalized placement.
- Repositories: test-only fakes implement all three provider-neutral ports, and
  success/failure results carry domain values or typed failures.
- Existing M1 widget and environment tests remain unchanged and continue to
  protect the bootstrap presentation.

The domain import boundary is also checked with a repository search prohibiting
Flutter, Riverpod, GoRouter, Supabase, SQLite/Drift, `dart:io`, and `dart:html`
imports under `lib/src/domain`.

## Milestone 2 local validation

The following commands passed locally with Flutter `3.47.1` stable and Dart
`3.13.1`:

```text
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
git diff --check
git diff --cached --check
```

All 41 tests passed: the five unchanged M1 bootstrap/environment tests and 36
M2 domain/contract tests. The Web build produced `build/web`; the decisive
Android build produced `build/app/outputs/flutter-apk/app-debug.apk` without a
license error. The prohibited-import search returned no match, relative
Markdown links resolved, and dependency manifests remained unchanged.

The Web build repeated the non-fatal optional Cupertino-icons font diagnostic
documented in M1. Android repeated the non-fatal SDK XML-version compatibility
warning documented in M1. Neither warning affected an artifact. GitHub Actions
has not run remotely because M2 is not pushed as part of this milestone.

## Milestone 1 automated coverage

- `test/app_test.dart` builds the app under `ProviderScope`, verifies the `/`
  bootstrap route, display name, status, environment label, and absence of the
  generated counter demo. It also verifies visible handling for an unknown
  route.
- `test/core/config/app_environment_test.dart` verifies the default
  `development` environment, all three supported mappings, and rejection of an
  unsupported value.
- Tests require no network, database, Supabase project, authenticated account,
  or tournament fixture.

## Milestone 1 local validation

The following commands passed locally with Flutter `3.47.1` stable and Dart
`3.13.1`:

```text
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

The Web build produced `build/web`, and the Android build produced
`build/app/outputs/flutter-apk/app-debug.apk`. Flutter Doctor continued to show
Android license status as unknown because of a compatibility mismatch with the
new Android CLI, but the debug APK build passed without a license error.

The Web build emitted a non-fatal optional Cupertino-icons font diagnostic; no
Cupertino icon package is used or approved in Milestone 1. The Android build
emitted a non-fatal SDK XML-version warning. The first Android build also
exposed an excessive generated Gradle heap request and a missing required NDK;
project-local Gradle memory limits were reduced and official NDK
`28.2.13676358` was installed before the successful retry.

The GitHub Actions workflow has not run remotely because this branch was not
pushed as part of Milestone 1. Local validation is the current evidence.

## Test layers

### Pure Dart unit tests

Exercise domain value objects, lifecycle transitions, eligibility rules,
derived calculations, and application-independent policies. These tests should
be fast, deterministic, and independent of Flutter or persistence.

### Tournament-engine fixtures and invariants

Use fixed inputs and expected structures for all four approved formats,
including small fields, byes, progression, and completion. Invariant/property
coverage should verify that participants are neither lost nor duplicated,
dependencies remain valid, matches do not become playable prematurely,
deterministic inputs yield deterministic outputs, and finalized results agree
with placements. Open format rules must be resolved before their assertions are
defined.

### Repository tests

Run common repository contract suites against implementations where practical.
Verify mapping, lifecycle behavior, authorization assumptions at boundaries,
version handling, tombstones, and stable identities without coupling use cases
to a storage technology.

### SQLite persistence and migration tests

Test schema creation and each later migration from supported prior versions,
transaction rollback, constraints, local queries, atomic local-write/outbox
creation, checkpoint persistence, and restart recovery. No SQLite schema or
migration exists in Milestone 0.

### PostgreSQL migration and RLS tests

Apply future migrations to a disposable test database, test forward migration
and constraints, and verify RLS/database-function behavior for guests, players,
organizers, unauthorized users, and claim flows. Include attempts to bypass
client-side checks. No PostgreSQL migration exists in Milestone 0.

### Synchronization and conflict tests

Cover duplicate delivery, retry after ambiguous timeout, out-of-order network
arrival, ordered dependent operations, reconnect, incremental pull,
checkpoint restart, tombstones, optimistic-version conflicts, permission
changes, dependency conflicts, permanent failures, and two-organizer edits.
Critical conflicts must never silently become last-write-wins.

### Flutter widget tests

Verify shared UI states and interactions, guest versus organizer controls,
loading/empty/error states, lifecycle presentation, check-in/payment state, and
prominent Now Playing/Up Next presentation. Platform-specific behavior should
be injected through boundaries rather than hidden in widgets.

### Integration tests

Exercise use cases across the presentation, repository, persistence, and cloud
security boundaries. Include account-to-player claiming, event setup,
participation, team formation, each tournament format, queue progression,
completion, history, and statistics as their milestones are delivered.

### Android offline interruption tests

On a representative Android device or emulator, interrupt connectivity and the
application at critical points: before/after a local commit, during push,
during response loss, during pull, and during restart. Verify important
organizer work remains usable, the outbox survives, retries are idempotent, and
reconciliation does not lose confirmed results.

### Web and iPhone Safari verification

Verify responsive Flutter Web/PWA behavior in supported browsers and on iPhone
Safari. Cover public reading, authentication, and every online organizer flow.
Confirm the UI communicates online-only mutation limitations rather than
promising native iPhone offline support.

### End-to-end tournament rehearsal

Before Version 1 release, simulate and then run a community pilot from event
creation through registration, check-in, payments, team formation, every
relevant format/queue action, interruption recovery, completion, history, and
statistics. Record timing, operator mistakes, conflicts, recovery actions, and
release-blocking defects.

## Milestone acceptance evidence

Each milestone records the commands, environments, and outcomes used to satisfy
its acceptance gate. Tests must not encode unresolved open decisions as though
they were approved requirements. Failing or deferred coverage is documented
and cannot be silently treated as passing.
