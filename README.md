# Volta Paddle Club

Volta Paddle Club is the Community Pickleball Management System: a cost-free
application for running casual and formal pickleball events in a local,
single-court community. It will eventually manage reusable community players,
participation, check-in, payment status, temporary teams, approved tournament
formats, the court queue, history, and statistics.

**Current status:** Milestone 5 — Synchronization Vertical Slice
(`COMPLETED`). The accepted M0–M4 baseline remains intact. M5 synchronizes
permanent players only; it does not imply full-table synchronization.

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
flutter run -d chrome
```

The compile-time environment defaults to `development`. Select an explicit
supported value with `--dart-define`:

```powershell
flutter run -d chrome --dart-define=APP_ENV=test
flutter build web --dart-define=APP_ENV=production
```

Supported values are `development`, `test`, and `production`; any other value
is rejected during application startup.

Supabase is optional for ordinary tests and builds. For a configured online
run, supply both client values from outside the repository:

```powershell
flutter run -d chrome `
  "--dart-define=SUPABASE_URL=$env:VPC_SUPABASE_URL" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$env:VPC_SUPABASE_PUBLISHABLE_KEY"
```

Providing only one value is rejected. Do not commit `.env` files or use a
service-role/secret key in Flutter.

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
not deployments or releases. The M5 coordinator requires both Android local
persistence and configured Supabase; without an authenticated organizer
session, queued uploads remain pending. Authentication UI remains M7 work.
