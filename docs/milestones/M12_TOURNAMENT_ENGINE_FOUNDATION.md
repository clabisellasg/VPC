# M12 — Tournament Engine Foundation

**COMPLETED**. Clean updated main baseline `6096d24`, branch
`milestone/m12-tournament-engine-foundation`. Dependencies: M2 and M11.

## Contracts and invariants

Study `lib/src/domain/tournament/tournament_contracts.dart`,
`tournament_invariant_validator.dart`, and `test/domain/tournament/` first.
Pure Dart contracts define TournamentGenerationRequest, TournamentGenerator,
TournamentPlan, PlannedMatch, PlannedMatchKey, direct/outcome participant sources
and typed TournamentGenerationFailure. Immutable plans use canonical JSON/value
equality: metadata keys sorted, explicit match-list order retained. Planned keys
are structural labels; persistence UUIDs are assigned outside the engine later.

Canonical input uses a complete unique organizer order or stable TeamId ordering.
The reusable conformance harness checks equal plans/keys for canonical inputs,
non-mutation and invariants. Its single fixture match is test-only, not a format
implementation. Production generation returns a typed unimplemented failure.

Generic validation covers insufficient input, invalid/missing format, scope,
deleted/incomplete teams and members, duplicate membership/keys/direct placement,
missing/self/cyclic outcome references, duplicate outcomes, self-play and invalid
state/result combinations. Typed enums exclude invalid winner/loser kinds.
Future format validators may permit repeated direct-team placements; their
cardinality/progression rules remain M13–M15.

## Score and match rules

OPEN-003 is resolved: one game, target 11, win by two, no cap. Valid: 11–0, 11–9,
12–10, 15–13. Invalid: 10–8, 11–10, 12–9, 13–10, draws and negatives.
`ValidatedScore` follows the existing typed ValidationFailure convention;
`MatchResult` derives the winning TeamId. Completed Match must agree with it.

The stored state sequence remains `scheduled → queued → inProgress → completed`.
Queued is the existing intermediate state, not new court-queue behavior. No new
ready enum. Same-state, skipped, backward and terminal transitions are rejected.
Incomplete matches cannot have final winners. Completed-result correction stays
prohibited; OPEN-004 remains M13's decision.

## Formats, start guard and platforms

Organizer events show active divisions and the four existing formats. Selection
is allowed during Registration before any generated match history, including
tombstoned matches. No default or additional format, no generated matches.
The screen explains M13 Single Elimination, M14 Single/Double Round Robin and
M15 Double Elimination. Guests/members cannot change formats.

Selection reuses the M9 fixed event/division aggregate and version checks.
Android v6 migrates format-lock and score/result triggers without changing
tables/records. Format, event version and outbox commit atomically. Pending
selection survives restart; acknowledgement/pull preserves later local intent
and conflicts. Web waits for cloud authority and never opens SQLite.

Every active division needs a format, two valid complete teams and active
generated matches before starting. Readiness is read-only evidence, never
accepted as mutation payload. Application/local mutation checks and PostgreSQL
enforce the guard independently. New events normally remain in Registration
until M13–M15. No placeholder matches or match synchronization. Unknown local
readiness fails closed; authoritative event reading/reconciliation remains
possible without an Android match cache.

## Schema and security

`20260903150000_m12_tournament_foundation.sql` updates private event readiness,
format/start guards and score/result integrity. Existing RLS, organizer checks,
fixed payloads, optimistic versions and private receipts remain in place.
`20260903150500_assert_m12_tournament_foundation.sql` checks anonymous/member
denial, organizer format selection/replay, invalid formats, start locks and
score examples. All synthetic assertion rows and receipts roll back; no real
records, roles, accounts, secrets or credentials are added. No dependencies
are upgraded.

## Validation and manual acceptance

Focused tests cover score examples/winners, generic invariants, fake strategy
conformance, format/start locks, atomic rollback, real SQLite close/reopen,
reconnect, conflicts and enlarged-text UI. Final automated validation passed
**249 tests**, formatting (202 files, no changes), static analysis, Web production
build and Android debug APK build. Initial lint findings were corrected before
the full test suite; no rules were weakened.

Required commands: locked pub get, build_runner, Drift dump/helper generation
and freshness, formatting, analyze, all tests, Web/debug APK builds, linked
migration history/dry-run/push/lint, hosted checks, Git whitespace, link and
credential scans. All those commands passed, including repeated generated-file
hash verification and the v5→v6 migration test. Dependencies are unchanged.
Linked histories agree through `20260903150500`; both M12 migrations and their
rollback-only assertions passed. Lint reports no schema errors. Anonymous
public reads returned 200 and private reads/aggregate writes returned 401.
pgTAP was skipped: Docker's `dockerDesktopLinuxEngine` pipe is unavailable.
Web emitted the existing optional Cupertino font-family warning; build passed.
Artifacts: `build/web` and `build/app/outputs/flutter-apk/app-debug.apk` (ignored).

M12 Android manual acceptance was confirmed by the user on the connected
Android 14 phone (23021RAAEG). WTA 1's Openplay division retained its saved
Single Round Robin format; offline Double Round Robin selection reported
pending, survived restart and synchronized after reconnect. The user also
confirmed four-format, enlarged-text and guest/member permission checks.
The start guard correctly kept the event in Registration without generated
match structure. The user confirmed the Web M12 walkthrough: saved formats
persist after refresh, the start guard remains enforced, browser navigation
and narrow/wide layouts work, and guests/members cannot edit formats.
Configured Web startup/public events/account navigation were also inspected
with no captured browser errors. The browser-verification CLI was unavailable;
the available browser tool was used instead. Repeatable procedure: use synthetic
Registration events: check guest/member denial, four formats, null selection,
no created matches, start blocked without generated structure, responsive and
enlarged text. Android: select offline, Pending, restart, reconnect, one result.
Web: online-only selection, refresh/direct routes, no SQLite/console errors.
Recheck affected M6–M11 shared screens, not unrelated earlier walkthroughs.

No brackets, schedules, match generation/progression, standings, champion or
queue behavior is implemented. M13–M16 retain ownership. OPEN-004/005/006/009/010
remain open. Android and Web manual acceptance are confirmed; M13 is not started.
