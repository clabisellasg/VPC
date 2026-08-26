# M04 — Android SQLite Persistence Foundation

## Goal and scope

Milestone 4 establishes the Android-only local persistence boundary for Volta
Paddle Club. Drift provides typed access to SQLite, twelve operational tables
mirror the M2/M3 records, and production adapters implement the existing
`PlayerRepository`, `EventRepository`, and `MatchRepository` ports.

This milestone contains no synchronization, outbox, network fallback, hosted
Supabase change, authentication flow, tournament algorithm, or feature UI.

## Dependencies

Resolved direct dependencies:

- `drift 2.34.3`
- `drift_flutter 0.3.1`
- `path_provider 2.1.6`
- `drift_dev 2.34.5` (development)
- `build_runner 2.16.0` (development)

Drift is the typed SQLite access layer; SQLite remains the local database. The
required current `drift_flutter` release resolves `sqlite3_flutter_libs`
transitively. It was not added as a direct dependency or selected as a separate
architecture decision.

## Platform and lifecycle boundary

On Android, the database is named `vpc.sqlite` and is placed beneath the
directory returned by `getApplicationSupportDirectory()`. `drift_flutter`
creates a background database isolate and shares it across application isolates.
Foreign keys are enabled both when the native connection is created and before
Drift opens the schema.

The Riverpod composition root creates and owns the Android database and closes
it when its provider is disposed. Repository providers expose Drift-backed M2
ports only when the database exists. Tests can use `AppDatabase.inMemory()` or
override the providers.

Web returns no local database and loads no SQLite/Wasm assets. Windows, Linux,
macOS, and iOS are also rejected as production local-database targets. Flutter
Web remains online-first through the future remote repository path.

## Version-one local schema

`AppDatabase.schemaVersion` is explicitly `1`. It contains:

- `players`
- `events`
- `event_divisions`
- `event_participants`
- `division_participants`
- `participant_payments`
- `teams`
- `team_members`
- `matches`
- `match_dependencies`
- `court_queue_entries`
- `division_placements`

`user_profiles` and `user_roles` are intentionally not mirrored locally.
There are no sync, dirty, outbox, inbox, retry, cursor, device, conflict, or
replication tables or columns.

The schema uses client-compatible text UUIDs, exact M2 enum names, integer
minor-unit money, nonnegative versions, UTC timestamps, tombstones, restrictive
foreign keys, checks, indexes, partial uniqueness, state-transition triggers,
and cross-scope triggers aligned with the M3 cloud schema. SQLite has no native
UUID type, so table IDs use 36-character text and every repository mapper
constructs the nominal M2 UUID type, which rejects malformed values.

Drift is configured to store timestamps as ISO-8601 text rather than its legacy
integer-seconds representation. Repository mappers normalize them to UTC. This
preserves sub-second precision and round-trips M2 metadata without loss.

The public M3 player row has no Auth user ID. Consequently, the local player
row also has no account-link column. A repository save containing a non-null
`AccountId` returns a typed validation failure instead of discarding it. The
future approved claim workflow must introduce a separate secure mapping.

## Repository adapters and transactions

- `DriftPlayerRepository` supports typed lookup, filtered observation, save,
  tombstone exclusion, and optimistic-version checks.
- `DriftEventRepository` supports typed lookup, status/type observation, save,
  optimistic versions, money mapping, and database lifecycle guards.
- `DriftMatchRepository` supports typed lookup, division observation, save,
  optimistic versions, and structural match-state mapping.

Adapters depend outward-to-inward on the M2 ports and return the existing
`RepositoryResult` and `DomainFailure` types. Expected SQLite constraint
failures become `ConflictFailure`; missing rows and version mismatches remain
typed. Unexpected errors are rethrown with their stack traces rather than
silently hidden.

Every save with an expected version is transactional. The database also
provides a restrained atomic team-plus-members write to establish and test a
multi-table transaction boundary. A failed member insert rolls back the team
and every earlier member insert.

## Generated code and schema evolution

Important generated/versioned artifacts:

- `lib/src/infrastructure/persistence/local/app_database.g.dart`
- `drift_schemas/app_database_v1.json`

Do not edit the generated Dart file or JSON snapshot manually. Regenerate with:

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/src/infrastructure/persistence/local/app_database.dart drift_schemas/app_database_v1.json
```

The installed `build_runner 2.16.0` reports that
`--delete-conflicting-outputs` is obsolete and ignores it safely. CI runs the
generator without that obsolete flag, re-exports the schema, and fails if
either committed artifact changes.

Schema version 1 has no invented historical migration. The version-one
snapshot is the baseline for later generated migration tests. An attempt to
open a later schema without an explicit upgrade path fails visibly.

## Testing

Run the persistence suites with:

```powershell
flutter test test/infrastructure/persistence/local
```

They use deterministic in-memory SQLite and cover schema creation, all tables,
foreign keys, uniqueness, enum mapping, UUID/money/UTC/version/tombstone round
trips, triggers, commit/rollback, all three repositories, typed failures,
invalid stored-data mapping, close behavior, and Web unavailability. They need
no emulator, network, Supabase credentials, or community data.

Full formatting, analysis, tests, generation freshness, Web production build,
and Android debug APK build form the milestone acceptance gate.

The completed local acceptance run passed dependency resolution, formatting of
63 Dart files, static analysis, all 65 Flutter tests (18 introduced by M4), the
Web production build, and the Android debug APK build. Outputs are
`build/web` and `build/app/outputs/flutter-apk/app-debug.apk`; both remain
ignored. A second generation/export pass wrote no generated Dart changes and
produced the same SHA-256 hashes for the Dart output and JSON snapshot.

The Web build repeated the accepted non-fatal optional Cupertino-icons font
diagnostic and successful Wasm dry run. On its first native SQLite build,
Gradle downloaded required CMake `3.22.1` using the machine's existing Android
SDK license state. The build then passed without adding a direct
`sqlite3_flutter_libs` dependency. No emulator-only check was required.

## Known limitations and future boundary

- The M2 ports expose only players, events, and matches, so the other nine
  tables currently have typed schema access but no domain repository port.
- No account claim or local authorization cache exists.
- No migration from a historical local schema exists because version 1 is the
  first local schema.
- SQLite timestamps are ISO-8601 text, while PostgreSQL uses `timestamptz`; the
  repository boundary normalizes both conceptually to M2 UTC `DateTime` values.
- All twelve product decisions remain open, including claim verification,
  payment scope, multiple divisions, scoring, team size, and conflict policy.

Future Me should study `app_database.dart`, `database_connection_native.dart`,
`local_persistence_providers.dart`, the three `drift_*_repository.dart` files,
the version-one JSON snapshot, and the persistence tests before changing the
local schema.

Milestone 5 must add synchronization deliberately. M4 creates no outbox or
operation ID, sends no local record to Supabase, and treats Realtime as unrelated
to local SQLite execution.
