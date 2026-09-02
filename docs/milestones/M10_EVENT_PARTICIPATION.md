# M10 — Participation, Check-In, and Payment Status

## Goal

Add organizer-managed registration of permanent players into events and
divisions, attendance correction, and private Paid/Unpaid tracking without
introducing payment processing, teams, or tournament operation.

## Implemented boundary

- Registration selects an existing permanent player, creates one event
  participant, one or more division assignments, an event-scoped Unpaid record,
  and one operation UUID.
- Normal structural mutation is limited to `registration`. During `inProgress`,
  check-in and payment corrections remain permitted. Completed and archived
  events are read-only. M9's format gate remains authoritative.
- Duplicate active event registrations, duplicate division assignments,
  cross-event divisions, inactive relationships, and stale versions fail
  explicitly. Removal uses tombstones and preserves history.
- No amount is stored by the accepted participant-payment model. Null is not
  fabricated as zero; M10 presents only Paid/Unpaid and processes no money.

## Platform behavior

Android uses Drift schema version 4. Participant, assignments, payment status,
and outbox operation commit in one transaction, appear immediately as pending,
survive restart, and reconcile only after cloud organizer authorization.
Pending, blocked, failed, and conflicted intent is retained; no automatic winner
policy was added.

Web initializes no SQLite. It calls the fixed organizer-authorized Supabase
aggregate command and reports success only after authoritative acceptance.
Guest/member presentation guards hide organizer controls, while PostgreSQL RLS
and server functions remain authoritative.

## Cloud and privacy

Migrations `20260901180000` and `20260901180500` add a private idempotency
receipt table, fixed aggregate apply/pull functions, and catalog security
assertions. Payments and receipts remain private. Public player rows contain no
Auth ID, email, role, or claim data. Identical operation replay is safe;
changed-content reuse and stale versions are rejected.

## Important files

- `lib/src/application/participation/`: provider-neutral models, ports, and use
  cases.
- `lib/src/infrastructure/participation/`: Drift store, codec, platform writers,
  bounded coordinator, Supabase gateway, and providers.
- `lib/src/presentation/participation/`: organizer roster and registration UI.
- `supabase/migrations/20260901180000_m10_event_participation.sql`: hosted
  aggregate protocol.
- `test/application/participation/` and
  `test/infrastructure/participation/`: deterministic coverage.

## Validation commands

```powershell
flutter pub get
dart run build_runner build
dart run drift_dev schema dump lib/src/infrastructure/persistence/local/app_database.dart drift_schemas
dart run drift_dev schema generate drift_schemas test/generated_migrations
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
supabase migration list --linked
supabase db lint --linked --fail-on error
```

## Manual validation

Android must verify guest regression, member denial, organizer registration,
multiple divisions, duplicate rejection, private payment display, check-in and
payment correction, online sync, offline pending/restart/reconnect, one cloud
aggregate, conflict visibility, lifecycle locks, text scaling, sign-out, and
USB-free reopen. Web must verify the corresponding online-only flow, routes,
browser navigation, responsive layouts, no SQLite, and no console errors.

Both mandatory walkthroughs passed on 2026-09-02 with synthetic records. Web
also verified reflected organizer URLs and direct-route refresh after enabling
GoRouter URL reflection for imperative navigation. Android verified offline
pending persistence across restart, idempotent reconnect, private payment
presentation, lifecycle locks, and visible conflict preservation.

## Validation result

- Formatting and static analysis passed.
- All 183 Flutter tests passed without live credentials or network access.
- `flutter build web` and `flutter build apk --debug` passed.
- Linked Supabase migration history agreed through both M10 migrations, and
  linked database lint reported no errors.
- Hosted anonymous public-read, private-table denial, and mutation-denial smoke
  checks passed. Organizer behavior was exercised in both mandatory configured
  walkthroughs.
- Local pgTAP was not executed because Docker Desktop's daemon was unavailable;
  the M10 SQL assertions remain version-controlled for a later local run.

## Known limitations and M11 boundary

- Conflict resolution remains deliberately absent under `OPEN-009`.
- M10 does not provide public/member self-registration.
- Realtime remains a refresh-hint architecture; no payload is treated as an
  authoritative record.
- Team formation, partners, balancing/skill, seeds, brackets, matches, and all
  tournament-engine behavior belong to M11+.
