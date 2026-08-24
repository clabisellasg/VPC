# Community Pickleball Management System

The Community Pickleball Management System is a cost-free application for
running casual and formal pickleball events in a local, single-court community.
It will manage reusable community players, participation, check-in, payment
status, temporary teams, approved tournament formats, the court queue, history,
and statistics.

**Current status:** Milestone 0 — Project Governance and Architecture Baseline
(`IN PROGRESS`). No application has been bootstrapped or implemented.

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

Milestone 1 must not begin automatically. Setup and build commands will be
documented only after the Flutter project exists and those commands have been
validated.
