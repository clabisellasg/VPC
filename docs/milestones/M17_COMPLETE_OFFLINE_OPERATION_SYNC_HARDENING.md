# M17 — Complete Offline Tournament Operation and Sync Hardening

## Scope

M17 completes the Android synchronization boundary for the 12 operational
tables already introduced by M5–M16: players, events, event divisions, event
participants, division participants, participant payments, teams, team
members, matches, match dependencies, court queue entries, and division
placements. It composes the existing fixed aggregate protocols in dependency
order rather than adding an arbitrary-table protocol.

Profiles, roles, claims, Auth identities/sessions, and private idempotency
receipts are deliberately not mirrored as application data. Web remains
online-first and never creates Drift or an Android outbox coordinator.

## Apply, pull, and recovery

Android mutations retain the accepted atomic record-plus-outbox transactions.
The organizer synchronization coordinator processes bounded slices in this
order: players; event setup; participation/payment; teams; tournament
structures/results/placements; court queue. Existing per-stream checkpoints
remain the durable cursor and advance only with their local reconciliation
transaction. Cloud timestamps, versions, tombstones, stable operation UUIDs,
payload identity, authorization, and optimistic concurrency remain
authoritative. Realtime notifications remain debounced refetch hints.

Retryable failures stay queued. Authorization failures are visibly blocked and
pending work is not discarded on sign-out or role loss. Interrupted claims,
replay after cloud acceptance, and repeated pull pages retain the recovery
rules established in M5 and the bounded aggregate milestones.

## Simultaneous organizers and conflicts

OPEN-009 is resolved. Version 1 permits multiple organizers without a lock or
lease. The first cloud transaction carrying valid expected versions succeeds;
a later stale command becomes an explicit conflict. A conflict blocks the
affected aggregate, while unrelated operations continue.

The organizer synchronization screen provides two deliberate actions:

- **Use cloud version** archives the local intent in a private local audit,
  cancels the stale outbox command, and pulls authoritative state.
- **Reapply local change** archives the stale command, assigns a new operation
  UUID, updates its expected cloud version, and submits it through the same
  domain and server validation. It may conflict again.

Neither action performs last-write-wins or field merging. Match results and
corrections continue to obey score, lifecycle, audit, downstream-play, and
event-completion rules. The UI uses human-readable aggregate labels and never
shows raw payloads, provider exceptions, emails, Auth IDs, or credentials.

SQLite schema v11 adds only `sync_resolution_audit`. It keeps the cancelled or
reapplied local and cloud payload evidence and replacement operation ID. No
hosted schema migration is required because the existing fixed RPCs already
enforce authorization, idempotency, payload hashes, optimistic versions, and
aggregate invariants.

## Platform behavior

- Android owns SQLite, offline commands, pending/conflict presentation,
  restart recovery, and the dependency-ordered coordinator.
- Web calls the accepted online repositories/RPCs and waits for cloud
  acceptance. It never initializes SQLite and has no offline mutations.
- Guest/member sessions cannot operate synchronization or read private payment
  state. Uploads start only after a live organizer-role snapshot.

## Validation and walkthrough

Automated coverage includes coordinator ordering/coalescing, conflict isolation,
resolution audit, replacement operation identity/version, retry-now backoff
override, schema migration, and all earlier regression suites. The final run
passed 364 Flutter tests, static analysis, Web production compilation, and
Android debug APK compilation. Linked migration history and dry run were clean;
linked lint reported no errors, only pre-existing M13/M14 PL/pgSQL warnings.

The user confirmed Android and Web walkthrough categories A–F on 2026-09-07:
representative offline work, restart, reconnect, cross-device convergence,
both conflict actions, authorization loss, duplicate prevention, responsive
presentation, direct refresh/routes, and Web's no-SQLite boundary. A synthetic
M17 queue required one organizer-authorized reconciliation during the Android
walkthrough; no schema or production-data change was made.

Local pgTAP is optional when Docker's Linux engine is unavailable. Hosted smoke
checks use only existing fixed protocols and synthetic rollback fixtures. It
was skipped in this run because Docker's Linux engine was unavailable.

## Known limitations and M18 boundary

M17 intentionally provides no automatic merge, organizer lease, background
push delivery, or Web offline store. M18 owns history and derived statistics;
no M18 calculation or UI is included here.

Future maintainers should begin with:

- `lib/src/application/sync/operational_sync.dart`
- `lib/src/infrastructure/sync/drift_operational_sync_store.dart`
- `lib/src/infrastructure/sync/operational_sync_providers.dart`
- `lib/src/presentation/sync/operational_sync_page.dart`
- `docs/SYNC.md`
