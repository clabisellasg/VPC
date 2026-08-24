# Testing Strategy

## Current status

Milestone 0 established the intended strategy. Milestone 1 now contains a
Flutter test harness and five focused bootstrap/environment tests. No database,
backend, authentication, domain, tournament, persistence, or synchronization
test exists because those implementations remain outside the active milestone.

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
