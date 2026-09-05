# Testing Strategy

## M15 validation

M15 tests deterministic 2-, 3-, 4-, 5-, and 8-team generation, standard seed
placement, staged loser routing, non-power-of-two BYEs, acyclic dependencies,
no-reset and reset finals, champion/runner-up placement, correction audit and
downstream locks, transactional Drift persistence/rollback, schema v8-to-v9
migration, and responsive guest/organizer presentation. Ordinary Flutter tests
use in-memory repositories/databases and make no network calls.

Hosted rollback assertions cover anonymous/member denial, organizer
generation, replay identity, progression through both brackets, reset-final
activation, placements, allowed/blocked correction, and immutable audit rows.
The full Flutter suite passes all 329 tests; formatting, analysis, Web
production compilation, and Android debug APK compilation pass. Linked history
agrees through `20260905151500`, its dry run is empty, and lint reports no
errors (only pre-existing M13/M14 PL/pgSQL warnings). Publishable-key smoke
checks allow anonymous bracket reads while denying anonymous profile, role,
payment, and mutation access. The user confirmed the mandatory physical
Android and Web walkthroughs, including both grand-final outcomes, reset-final
convergence, BYEs, progression, corrections, guest access, offline restart,
responsive layouts, and cross-device convergence. Local pgTAP is skipped
because the installed Docker client cannot reach its Linux engine.

Final regressions cover deterministic reset-match identity for legacy queued
Android payloads, semantic participation-conflict acknowledgement, bounded Web
roster pagination, and clear invalid-team eligibility failures. Repeated
build-runner generation was current. The explicit Drift schema dump command
again stalled in the Windows build-hook launcher and was interrupted; the
committed v9 snapshot and generated migration helper remained unchanged and
the v8-to-v9 migration tests passed.

## M14 validation

M14 adds deterministic 2–8-team circle-method, odd-team BYE, Single/Double
formula, standings, all OPEN-005 tie-break stages, correction/audit, placement,
Drift v7→v8, offline outbox/restart/reconciliation, hosted idempotency/RLS, and
responsive presentation coverage. Focused regressions additionally cover
odd-team hosted match keys, accumulated and undoable manual team previews,
multi-participant registration, drag-based seed ordering, and explicit
Champion/Runner-up labels before event completion.

The user confirmed mandatory Android and Web walkthrough categories A–F,
including schedules, BYEs, both legs, results, tie-break standings, final
placements, correction, regeneration/lifecycle locks, Android offline restart
and reconnect, Web online-only behavior, permissions, guest reads,
responsiveness, and accessibility. Docker's Linux daemon remained unavailable,
so local pgTAP was not executed; hosted rollback assertions supplied database
coverage. No remote CI run is claimed.

The final Flutter acceptance suite passed all 308 tests; formatting and static
analysis were clean, and production Web and Android debug APK builds passed.
Linked migration history agrees through `20260904181500`, the dry run is
empty, and linked lint reports no errors (only previously documented
PL/pgSQL type/shadow warnings). Publishable-key smoke checks returned 200 for
public events and Round Robin schedules, denied private payments/profiles/roles,
and rejected an anonymous event write.

The v8 schema snapshot had already been exported during implementation.
The final build-runner freshness pass and Drift migration-helper regeneration
completed with unchanged outputs, and all v7→v8/fresh-schema tests passed. A
repeat `drift_dev schema dump` invocation stalled in the Windows build-hook
launcher and was interrupted after repeated no-output waits; no generated or
source file was lost or substituted.

## M13 validation

Hosted repair and rollback assertions passed for 2–8-team generation, correction
traversal, winner propagation, started/completed downstream rejection, final
placements, immutable audit, unauthorized/stale rejection and replay identity.
Histories agree through 20260904132000; linked lint has no errors and three
non-blocking warnings described in [M13](milestones/M13_SINGLE_ELIMINATION.md).
Focused engine/local/migration regressions passed (34 tests), plus two responsive
bracket layout tests. Final static analysis, formatting and all 275 Flutter tests passed.
Production Web and Android debug APK builds passed. Publishable-key anonymous
public reads/private-data denial and tournament-command denial passed. Relative
documentation links, credential-pattern scan and both Git diff checks passed.
Docker CLI exists but its Linux engine is unavailable; local pgTAP was not run.
The user confirmed mandatory M13 physical Android and Web walkthroughs after
the dialog-lifecycle, persistent-preview, and horizontal-navigation fixes.
Additional regressions cover those fixes and the user-requested exclusion of
already registered players from the add-participant picker. No remote CI run
is claimed.

## M12 validation

M12 adds score/winner, generic tournament invariant/conformance, format-selection
permission/lifecycle, SQLite v5→v6, real restart/reconnect, rollback/conflict and
320/1000-pixel enlarged-text widget tests. Ordinary tests use fakes/in-memory or
temporary SQLite and do not contact the network.

Final M12 automated checks passed: `flutter pub get`, repeated build_runner/Drift
schema dump/helper generation with unchanged generated hashes, formatting,
`flutter analyze`, **249 Flutter tests**, `flutter build web` and
`flutter build apk --debug`. Documentation links, credential-pattern scan,
domain import-boundary inspection and Git whitespace checks passed. Android ID
remains `com.voltapaddleclub.vpc`; only Android/Web platform directories exist.
The optional Cupertino font warning did not prevent the Web build. No dependency
upgrade or remote GitHub Actions run occurred.

The two M12 hosted migrations applied to the accepted Tokyo project. SQL
assertions passed for denied anonymous/member commands, organizer selection,
idempotent replay, changed-payload rejection, invalid formats/start locks and
score examples; synthetic records/receipts rolled back. Linked history agrees
and lint reports no schema errors. Publishable-key public events/divisions/
players reads return 200; private payment/profile/role reads and anonymous
aggregate commands return 401. Docker's Linux daemon is unavailable, so local
pgTAP was not executed. The user confirmed M12 physical Android acceptance,
including offline pending selection, restart/reconnect, start guard, four formats,
enlarged text and guest/member denial. The user also confirmed the Web M12
walkthrough: saved-format persistence, start guard, navigation/layout and
guest/member restrictions. Configured Web startup rendered public events
and account navigation with no captured browser errors;
no remote CI run is claimed.

## Current status

Milestone 0 established the intended strategy, Milestone 1 introduced the
Flutter bootstrap harness, and Milestone 2 added pure-domain/contract suites.
Milestone 3 adds Supabase configuration and database-security coverage.
Milestone 4 adds deterministic in-memory SQLite, generated-schema freshness,
production repository-adapter, transaction, lifecycle, and platform-boundary
coverage. Milestone 5 adds the player synchronization vertical-slice suite.
Milestone 6 adds public guest navigation, query/mapping, Android public-cache,
and responsive UI coverage. Milestone 7 adds account/session, role, secure
player-claim, and authorization-gated synchronization coverage. Remaining-
entity synchronization and tournament-engine tests remain future work.

## Milestone 6 coverage and execution

- Pure tests cover status-authoritative current/upcoming/completed grouping,
  deterministic ordering, tombstone exclusion, immutable divisions, and UTC
  presentation.
- Supabase adapter tests cover valid event/division maps, invalid UUID/status/
  timestamp rejection, safe error redaction, and the narrow two-table gateway.
- In-memory Drift tests cover initial cached reads, atomic remote reconciliation,
  missed adjacent lifecycle advancement, absent-row tombstones, preservation of
  a newer local row, and proof that public pulls create no player outbox work.
- Reader/provider tests cover remote lookup, cached fallback, typed
  unconfigured failure, Android composition, and proof that Web never asks the
  local database factory to initialize SQLite.
- Widget/controller tests cover guest access, shared navigation, all three
  groups, stable details and missing-event states, divisions, loading/empty/
  error/unconfigured/cached states, safe retry, duplicate-refresh coalescing,
  stale-controller disposal, narrow/wide navigation, and semantic event-card
  actions. Fakes prevent ordinary-test network access.
- `public_guest_read_test.sql` retains eight pgTAP assertions for required
  tables, exact synthetic fixtures, anonymous reads, and anonymous event/
  division write denial.

The M6 implementation run resolved locked dependencies, formatted 102 files
without change, found no analyzer issue, and passed all 116 Flutter tests. The
Web production build produced `build/web`; the Android debug build produced
`build/app/outputs/flutter-apk/app-debug.apk`. Web repeated the accepted
optional Cupertino-font diagnostic and successful Wasm dry run. Android
repeated the accepted SDK XML-version warning and passed without a license
failure.

The hosted seed migration applied to the linked Tokyo project, migration
history agrees, and linked database lint reports no errors. Publishable-key
smoke checks returned `200` with exactly three fixture events and four fixture
divisions; anonymous event/division writes returned `401`, and private
payment/profile/role endpoints remained hidden with `404`. Denied fixture IDs
were confirmed absent. Docker's engine was unavailable, so the retained pgTAP
file was not executed locally.

A configured in-app browser walkthrough passed guest entry, groups, details,
divisions, explicit refresh, route reload, back/forward, narrow/wide layouts,
and console inspection. Browser-level network interruption was unavailable, so
that Web-specific manual case remains automated only.

The configured application was then installed on a physical `23021RAAEG`
running Android 14 (API 34). The owner confirmed all required checks: launch,
guest shell, three event groups and fixtures, details/divisions, Android Back,
refresh, process reopen, increased-font usability, online-to-offline cached
reopen with an honest indication, restored-connectivity refresh, and reopening
the installed application after USB disconnection. This completes the M6
physical-device gate. No remote GitHub Actions run is claimed because this
branch is not pushed.

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
## Milestone 7 account, role, and claim coverage

M7 adds deterministic tests for immutable account/claim models, UTC review
invariants, session restoration, signed-out/authenticated transitions,
confirmation-required registration, sign-in/sign-out/refresh, unconfigured
builds, typed error redaction, guest-route preservation, form validation,
provider overrides, member/organizer presentation, protected-route flash
prevention, player search, claim review, responsive Web composition, and the
authenticated M5 synchronization gate. Ordinary Flutter tests use fakes and
contain no network access, live credential, token, or personal email.

`supabase/tests/database/accounts_roles_player_claiming_test.sql` retains 22
pgTAP assertions for schema, RLS/grants, profile-link protection, guest denial,
member isolation, duplicate pending claims, organizer authorization, atomic
approval, repeat/concurrent safety, and absence of Auth identity on public
players. Docker's executable is installed but its engine was unavailable, so
this suite was not run locally. The applied assertion migration and hosted
anonymous/authenticated smoke checks provide separate deployment evidence and
must not be described as a local pgTAP pass.

The M7 implementation run uses:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
npx --yes supabase@2.115.0 migration list --linked
npx --yes supabase@2.115.0 db lint --linked --fail-on error
git diff --check
```

Manual acceptance additionally requires the documented configured Web flow
and the 26-step physical Android walkthrough. Both were completed on
2026-08-28 and are recorded in the M7 implementation document.

Final M7 validation passed formatting, static analysis, all 132 Flutter tests,
the Web production build, and the Android debug APK build. Linked migration
history matched through `20260828181500`; the hosted migration dry-run was up
to date and linked database lint returned no schema errors. Anonymous hosted
smoke checks returned `200` for events/divisions and `401` for profiles, roles,
claims, official writes, and the claim RPC. Public fixture rows exposed no Auth
ID or email fields. The retained 22-assertion pgTAP suite was not run locally
because the installed Docker executable could not reach its engine.
## Milestone 8 player-directory coverage

M8 adds deterministic tests for search normalization, bounded stable paging,
duplicate warnings and acknowledgement, injected UUID/time, public row
validation/redaction, tombstones, Android cache reconciliation, pending-write
preservation, Web's no-SQLite boundary, public routes, missing profiles,
organizer presentation guards, and narrow/wide layouts. Tests use fakes and
in-memory Drift; ordinary `flutter test` performs no live network request.

Hosted function/RLS validation and both mandatory manual walkthroughs are
recorded in the M8 implementation record only after actually run.

The M8 implementation run currently passes 159 Flutter tests, static analysis,
Web production compilation, and Android debug APK compilation. Linked database
lint passes and anonymous hosted smoke checks enforce the intended public and
private boundaries. Local pgTAP was skipped because Docker is unavailable.
Physical Android and Web acceptance passed on 2026-08-29. The conditional
manual conflict injection was skipped because no safe control exists; in-memory
tests verify conflict visibility and prohibit automatic resolution.

## Milestone 9 event/division coverage

M9 tests cover quick casual/formal setup, normalized division uniqueness,
nullable-format preservation, lifecycle gates, Drift v2→v3 migration,
aggregate/outbox atomicity and rollback, and pending-intent pull protection.
Cloud pgTAP/catalog assertions cover nullability, enum checks, fixed RPC
privileges, private receipts, and normalized uniqueness. Ordinary Flutter tests
use fakes/in-memory Drift and make no network requests. Regression coverage also
verifies repeated singleton-checkpoint reconciliation and immediate Android
local pending results without waiting for cloud access.

The 2026-09-01 M9 acceptance passed formatting, static analysis, all 174
Flutter tests, Web production build, Android debug APK build, linked
migration agreement, linked database lint, hosted anonymous read/write security
smoke checks, and mandatory Web/physical-Android walkthroughs. Local pgTAP was
not run because Docker was unavailable; the SQL assertions remain committed.
Manual conflict injection and later lifecycle advancement were not performed
because M9 provides no safe conflict control or tournament-format selector;
deterministic tests cover both boundaries without changing accepted fixtures.

## Milestone 10 participation coverage

M10 adds deterministic service tests for registration, division scope,
lifecycle locks, check-in correction, and Paid/Unpaid correction. In-memory
Drift tests cover aggregate/outbox atomicity, rollback, active duplicate
rejection, UTC/version/status round trips, and the v3→v4 migration. SQL pgTAP
assertions cover fixed RPC privileges, private payments/receipts, active
uniqueness, and anonymous mutation denial. Ordinary Flutter tests use no live
network or credentials. The final suite passed all 183 tests, formatting,
analysis, Web production build, and Android debug APK build. Linked migration
history, linked database lint, hosted anonymous read/privacy/write-denial
smoke checks, and the mandatory Web and physical-Android walkthroughs also
passed. Local pgTAP was not run because the installed Docker client had no
available daemon; its SQL assertions remain committed.

## Milestone 11 team-formation coverage

M11 adds pure Dart tests for the 1–5/null skill boundary, exact doubles teams,
manual formation, deterministic seeded random pairing, deterministic
strongest-with-weakest balancing, strength spread, odd-player handling,
unrated blocking, and preview-without-persistence. Drift tests cover eligible
checked-in selection and atomic team/member/outbox persistence. Schema migration
tests preserve existing Unrated players through v4-to-v5 and verify skill round
trips and the three bounded team synchronization tables. Full validation and
manual device/browser evidence are recorded in the M11 milestone record.

The final suite now includes 201 tests. Nine dedicated team-pull regressions
cover exact cloud microseconds and UTC conversion for teams/members, null and
tombstoned metadata, repeated-pull idempotence, actual file-backed SQLite restart,
strict equal-time cursor ordering, pending/conflicted protection, mapping/FK
failures, and atomic rollback when checkpoint writing fails. Cloud metadata
and durable checkpoint gaps are corrected; no UI behavior changed, so the
previous user-confirmed Android/Web walkthroughs are retained.

Migration `20260903120000_m11_authoritative_team_pull.sql` applied successfully;
its read-only assertions compare cloud metadata and test pagination against
existing records without modifying them. Anonymous team pull returns 401,
public player/event reads return 200, and private profile/role reads return 401.
Local pgTAP remains skipped because the Docker daemon is unavailable. Final
command outcomes are recorded in the M11 milestone record; no remote CI run is
claimed.
## Milestone 14 round-robin coverage

M14 tests the circle method for 2–8 odd/even teams, Single/Double formulas,
pair cardinality, reversed second-leg display sides, BYE rests, canonical seed
ordering, every accepted tie-break stage, incomplete/tombstoned/corrected
results, final placement derivation, transactional generation/rollback,
immutable correction audit, schema v7-to-v8 migration, and responsive preview.
Ordinary Flutter tests use fakes or in-memory Drift and make no network calls.

Hosted rollback assertions cover organizer authorization, anonymous/member
denial, deterministic generation, identical and changed-payload replay,
server-side score validation, final placements, correction, and audit
preservation. Docker pgTAP remains conditional; manual Android/Web acceptance
is recorded only after it is actually performed.
