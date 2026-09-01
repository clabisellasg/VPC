# M09 — Event and Division Lifecycle

## Goal and status

M9 implements casual/formal event setup, quick casual creation, configurable
division names, and the approved forward-only lifecycle. The milestone is
**COMPLETED** after automated, hosted, Android-phone, and Web acceptance passed
on 2026-09-01.

## Implemented behavior

- Organizer routes `/organizer/events`, `/organizer/events/new`, and
  `/organizer/events/:eventId/setup` provide a dashboard, quick casual setup,
  formal setup, UPCOMING editing, and confirmed lifecycle advancement.
- Quick casual setup creates an UPCOMING event plus one Open division. Formal
  setup requires one or more unique, whitespace-normalized division names.
- Existing M2 event fields are used: name, UTC scheduled time, event type,
  lifecycle status, and `courtLabel` as venue. No unsupported description or
  end-time column was invented.
- Structural setup is editable only while UPCOMING. Every transition advances
  exactly one state and ARCHIVED is terminal; there is no hard deletion or
  cancellation behavior.

## Nullable tournament format decision

`EventDivision.format`, PostgreSQL `event_divisions.tournament_format`, and the
Drift column are nullable until M12. Null means **not configured yet**, not that
the division needs no format. It avoids recording an organizer choice that was
never made. Existing non-null values remain valid and are preserved without a
backfill, fake enum, or default.

Every M9-created quick-casual or formal division stores null. UPCOMING may
advance to REGISTRATION, but REGISTRATION cannot advance to IN PROGRESS while
any active division is unconfigured. M12 owns format selection and must require
it before tournament generation.

## Persistence and synchronization

Android Drift schema version 3 migrates `tournament_format` to nullable while
preserving configured values. It adds bounded event-setup outbox, checkpoint,
and conflict tables. Event plus divisions plus operation commit atomically;
failed outbox insertion rolls everything back. Pending work survives restart
and is not overwritten by public refresh. Conflicts are retained unresolved.
Local acceptance returns immediately while synchronization runs in the
background; organizer cards report pending, blocked, and conflicted states.
The checkpoint singleton is written explicitly so repeated reconciliation is
safe on SQLite.

The cloud migration adds a fixed organizer-guarded aggregate RPC, private
idempotency receipts, checkpointed event/division pull, and normalized active
division uniqueness. Payloads are allowlisted, versions optimistic, changed
operation-ID reuse rejected, and RLS remains authoritative.

Web uses the cloud boundary online and never initializes SQLite or reports
success before cloud acceptance. M6 public event reading remains available.
Successful organizer mutations refresh the established public-event reader.

## Important files

- `lib/src/application/events/`: setup models, contracts, and use cases.
- `lib/src/infrastructure/events/`: Drift store, cloud gateway, codec, platform
  writers/synchronizer, UUID/clock primitives, and providers.
- `lib/src/presentation/events/`: dashboard, forms, and lifecycle feedback.
- `supabase/migrations/20260829120000_m09_event_division_setup.sql`.
- `drift_schemas/drift_schema_v3.json` and generated migration helpers.

## Validation and manual procedures

Final acceptance ran formatting, static analysis, Flutter tests, Web/APK
builds, repeated Drift generation/export, linked migration/lint checks, hosted
security smoke checks, documentation/secret scans, and Git whitespace checks.

Android: verify guest events, member denial, organizer casual/formal creation,
division validation, online/offline pending behavior, restart/reconnect exactly
once, public division refresh, adjacent lifecycle, the format-required guard,
setup locking, preservation, conflict honesty, text scaling, and USB-free reopen.

Web: verify guest reads, member denial, organizer online creation, validation,
lifecycle/format guard, public refresh/direct routes, browser navigation,
responsive layout, no SQLite, and no console errors. Use synthetic `VPC M9`
records only.

The Web walkthrough passed guest and organizer navigation, casual/formal
creation, duplicate division validation, public refresh, the null-format
lifecycle guard, direct-route/browser navigation, responsive layouts, and a
clean console. The physical Android walkthrough passed local-first online and
offline creation, immediate pending status, restart persistence, reconnect
reconciliation, lifecycle guard, responsive text, gesture back navigation, and
USB-free reopen. No safe production conflict-injection or M9 format-selection
path exists; those behaviors remain covered by deterministic tests rather than
mutating accepted fixtures.

## Known limitations and M10 boundary

M9 does not select tournament formats, resolve conflicts, or define
cancellation. It adds no participants, check-in, payment status, teams,
matches, brackets, scores, standings, queues, placements, or statistics. M10
owns participation, check-in, and Paid/Unpaid tracking. `OPEN-002` and
`OPEN-009` remain open.
