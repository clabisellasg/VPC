# Volta Paddle Club

Volta Paddle Club is the Community Pickleball Management System: a cost-free
application for running casual and formal pickleball events in a local,
single-court community. It will eventually manage reusable community players,
participation, check-in, payment status, temporary teams, approved tournament
formats, the court queue, history, and statistics.

**Current status:** Milestone 14 — Single and Double Round Robin (`COMPLETED`).
M0–M14 are completed; M15–M21 remain NOT STARTED.

## Version 1 technology stack

- Flutter and Dart with a shared presentation layer.
- Android Flutter-generated APK as the primary platform.
- SQLite for offline-first Android persistence.
- Supabase for the cloud backend, including Authentication, PostgreSQL,
  Realtime where appropriate, database functions, and row-level security.
- Flutter Web/PWA for online-first iPhone access through Safari.
- Git and GitHub using free-tier infrastructure only.

The Version 1 scope and technology stack are feature-frozen. Changes require an
explicitly approved decision recorded in
[DECISIONS.md](docs/DECISIONS.md); implementation must not silently expand the
scope, replace the stack, or begin a later milestone.

## Project roles

- **ChatGPT Web:** project planner and software architect; it defines and
  approves requirements and architecture.
- **Codex:** repository implementation AI; it implements only the active,
  approved milestone and validates its work.

## Documentation

- [Project overview](docs/PROJECT_OVERVIEW.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Conceptual database model](docs/DATABASE.md)
- [Milestone roadmap](docs/MILESTONES.md)
- [Decisions](docs/DECISIONS.md)
- [Testing strategy](docs/TESTING.md)
- [Synchronization design](docs/SYNC.md)
- [Operations outline](docs/OPERATIONS.md)
- [Milestone 1 implementation record](docs/milestones/M01_FLUTTER_BOOTSTRAP.md)
- [Milestone 2 implementation record](docs/milestones/M02_DOMAIN_PERSISTENCE_CONTRACTS.md)
- [Milestone 3 implementation record](docs/milestones/M03_SUPABASE_CLOUD_FOUNDATION.md)
- [Milestone 4 implementation record](docs/milestones/M04_ANDROID_SQLITE_PERSISTENCE.md)
- [Milestone 5 implementation record](docs/milestones/M05_SYNCHRONIZATION_VERTICAL_SLICE.md)
- [Milestone 6 implementation record](docs/milestones/M06_PUBLIC_APPLICATION_GUEST_READING.md)
- [Milestone 7 implementation record](docs/milestones/M07_ACCOUNTS_ROLES_PLAYER_CLAIMING.md)
- [Milestone 8 implementation record](docs/milestones/M08_PERMANENT_COMMUNITY_PLAYER_DIRECTORY.md)
- [Milestone 9 implementation record](docs/milestones/M09_EVENT_DIVISION_SETUP.md)
- [Milestone 10 implementation record](docs/milestones/M10_EVENT_PARTICIPATION.md)
- [Milestone 11 implementation record](docs/milestones/M11_TEAM_FORMATION.md)
- [Milestone 12 implementation record](docs/milestones/M12_TOURNAMENT_ENGINE_FOUNDATION.md)
- [Milestone 13 implementation record](docs/milestones/M13_SINGLE_ELIMINATION.md)
- [Milestone 14 implementation record](docs/milestones/M14_ROUND_ROBIN.md)

## Development setup

The validated baseline uses Flutter `3.47.1` stable and Dart `3.13.1`. Android
development requires Android SDK Platform and Build Tools `36.0.0`, Android NDK
`28.2.13676358`, and Java 17. Web development requires a supported browser such
as Chrome.

Resolve the locked dependencies:

```powershell
flutter pub get
```

Run on a connected Android device or emulator:

```powershell
flutter devices
flutter run -d <device-id>
```

Run on Chrome:

```powershell
flutter run -d chrome --web-port 8080
```

The fixed development port keeps the local URL stable at
`http://localhost:8080` instead of allocating a different port per session.

The compile-time environment defaults to `development`. Select an explicit
supported value with `--dart-define`:

```powershell
flutter run -d chrome --web-port 8080 --dart-define=APP_ENV=test
flutter build web --dart-define=APP_ENV=production
```

Supported values are `development`, `test`, and `production`; any other value
is rejected during application startup.

Supabase is optional for ordinary tests and builds. For a configured online
run, supply both client values from outside the repository:

```powershell
flutter run -d chrome --web-port 8080 `
  "--dart-define=SUPABASE_URL=$env:VPC_SUPABASE_URL" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$env:VPC_SUPABASE_PUBLISHABLE_KEY"
```

Providing only one value is rejected. Do not commit `.env` files or use a
service-role/secret key in Flutter.

Configured builds open the public guest shell without sign-in. Web reads
events and divisions directly from Supabase. Android shows its last-known
SQLite cache when available, then refreshes from the same anonymous public
endpoint. An unconfigured build remains usable and explains why online public
events cannot load.

The Account destination supports email/password registration and sign-in when
Supabase is configured. Hosted email confirmation redirects to
`/account/confirm` on Web or the narrowly scoped Android URI
`com.voltapaddleclub.vpc://auth-callback/account/confirm`. Public events remain
available while signed out. Password recovery and additional Auth providers
are not implemented in M7.

## Quality and builds

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Run only the pure-domain Milestone 2 suites with:

```powershell
flutter test test/domain
```

Regenerate and verify the Android SQLite schema and migration-test artifacts
with:

```powershell
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/src/infrastructure/persistence/local/app_database.dart drift_schemas
dart run drift_dev schema generate drift_schemas test/generated_migrations
flutter test test/infrastructure/persistence/local
```

The version-controlled cloud foundation is under `supabase/`. After personally
authenticating the official CLI, verify the target before any hosted migration:

```powershell
supabase projects list --output json
supabase migration list --linked
supabase db push --linked --dry-run --skip-vault
supabase db lint --linked
```

The Web output is written to `build/web`. The Android debug APK is written to
`build/app/outputs/flutter-apk/app-debug.apk`. These are local build artifacts,
not deployments or releases. Android participant changes commit with a durable
local outbox and may remain pending until a confirmed organizer session and
connectivity are available. Web organizer operations require an online,
configured Supabase client. Payment status is administrative Paid/Unpaid only.
