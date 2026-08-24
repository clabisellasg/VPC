# Volta Paddle Club

Volta Paddle Club is the Community Pickleball Management System: a cost-free
application for running casual and formal pickleball events in a local,
single-court community. It will eventually manage reusable community players,
participation, check-in, payment status, temporary teams, approved tournament
formats, the court queue, history, and statistics.

**Current status:** Milestone 1 — Flutter Project Bootstrap (`COMPLETED`). The
repository contains a minimal Android/Web bootstrap only; no tournament,
persistence, backend, synchronization, or authentication feature is implemented.

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

## Quality and builds

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

The Web output is written to `build/web`. The Android debug APK is written to
`build/app/outputs/flutter-apk/app-debug.apk`. These are local build artifacts,
not deployments or releases. Milestone 2 must not begin without explicit
authorization.
