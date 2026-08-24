# Milestone Roadmap

## Delivery rules

- Work on exactly one milestone at a time.
- Each milestone must meet its documented acceptance gate and have validation
  evidence before the next milestone is authorized.
- Codex may not implement future milestones early, even when doing so appears
  convenient for the active milestone.
- Milestone 1 must not begin automatically after Milestone 0. It requires an
  explicit instruction to begin.
- Use branches named `milestone/mXX-short-name`, for example
  `milestone/m00-governance-baseline`.
- Prefer focused commits named `type: concise milestone outcome`, for example
  `docs: establish milestone 0 project baseline`.
- Every meaningful milestone updates the relevant documentation, decisions,
  operations notes, and validation evidence so the repository remains an
  accurate project record.

The acceptance gate is: all milestone-specific requirements are complete, its
tests and validation checks pass or documented blockers are explicitly
accepted, documentation has been reconciled, and the planner/architect has
authorized proceeding.

## Roadmap

### M0 — Project Governance and Architecture Baseline

- **Purpose:** Establish documentation, architecture, decisions, scope,
  milestone rules, and Git workflow.
- **Dependencies:** None.
- **Status:** COMPLETED.

### M1 — Flutter Project Bootstrap

- **Purpose:** Create Android/web Flutter foundations, app shell, linting, test
  harness, and build verification.
- **Dependencies:** M0.
- **Status:** COMPLETED.

### M2 — Domain and Persistence Contracts

- **Purpose:** Define entities, IDs, state machines, repository contracts, and
  platform-independent boundaries.
- **Dependencies:** M1.
- **Status:** NOT STARTED.

### M3 — Supabase Database, Auth, and Security Foundation

- **Purpose:** Add migrations, cloud schema, Auth foundation, RLS, and database
  security tests.
- **Dependencies:** M2.
- **Status:** NOT STARTED.

### M4 — Android SQLite Foundation

- **Purpose:** Add local schema, migrations, repositories, outbox, and local
  transaction patterns.
- **Dependencies:** M2.
- **Status:** NOT STARTED.

### M5 — Synchronization Vertical Slice

- **Purpose:** Prove offline queueing, reconnect, idempotency, cloud application,
  pull reconciliation, conflicts, and Realtime refresh.
- **Dependencies:** M3 and M4.
- **Status:** NOT STARTED.

### M6 — Public Application and Guest Reading

- **Purpose:** Build shared navigation and public read-only
  current/upcoming/completed event experience.
- **Dependencies:** M3 and M5.
- **Status:** NOT STARTED.

### M7 — Accounts, Roles, and Player Claiming

- **Purpose:** Implement player accounts, organizer authorization, role-based
  controls, and approved claim workflow.
- **Dependencies:** M3 and M6.
- **Status:** NOT STARTED.

### M8 — Permanent Community Player Directory

- **Purpose:** Implement reusable players, search, creation, duplicate warnings,
  and basic profiles.
- **Dependencies:** M5 and M7.
- **Status:** NOT STARTED.

### M9 — Event and Division Lifecycle

- **Purpose:** Implement casual/formal event setup, divisions, quick casual
  setup, and lifecycle rules.
- **Dependencies:** M5, M7, and M8.
- **Status:** NOT STARTED.

### M10 — Participation, Check-In, and Payment Status

- **Purpose:** Add players to events, manage attendance, and track Paid/Unpaid
  status and totals.
- **Dependencies:** M9.
- **Status:** NOT STARTED.

### M11 — Team Formation

- **Purpose:** Implement manual, random, and simple balanced temporary team
  formation.
- **Dependencies:** M10.
- **Status:** NOT STARTED.

### M12 — Tournament Engine Foundation

- **Purpose:** Create tournament contracts, deterministic generation, match
  state rules, fixtures, and invariant testing.
- **Dependencies:** M2 and M11.
- **Status:** NOT STARTED.

### M13 — Single Elimination

- **Purpose:** Implement generation, byes, result progression, winner
  advancement, champion/runner-up, and visual bracket.
- **Dependencies:** M12.
- **Status:** NOT STARTED.

### M14 — Single and Double Round Robin

- **Purpose:** Implement schedules, scoring, standings, approved tie-breakers,
  and round-robin presentation.
- **Dependencies:** M12.
- **Status:** NOT STARTED.

### M15 — Double Elimination

- **Purpose:** Implement and thoroughly test winners bracket, losers bracket,
  final behavior, progression, and visual bracket.
- **Dependencies:** M12 and M13.
- **Status:** NOT STARTED.

### M16 — One-Court Scheduling and Queue

- **Purpose:** Implement Now Playing, Up Next, queue progression, and reasonable
  rest/fairness ordering across formats.
- **Dependencies:** M13, M14, and M15.
- **Status:** NOT STARTED.

### M17 — Complete Offline Tournament Operation and Sync Hardening

- **Purpose:** Verify every required Android organizer operation works offline
  and synchronizes safely.
- **Dependencies:** M8 through M16.
- **Status:** NOT STARTED.

### M18 — Tournament History and Statistics

- **Purpose:** Preserve and browse completed events and derive individual and
  partner statistics.
- **Dependencies:** M13 through M17.
- **Status:** NOT STARTED.

### M19 — iPhone Web/PWA Parity and Deployment

- **Purpose:** Verify guest, player, and online organizer functionality on
  iPhone Safari and deploy through a free static host.
- **Dependencies:** M6 through M18.
- **Status:** NOT STARTED.

### M20 — Release Hardening

- **Purpose:** Complete security, migration, accessibility, performance,
  recovery, documentation, and regression review.
- **Dependencies:** M17 through M19.
- **Status:** NOT STARTED.

### M21 — Community Rehearsal, Pilot Tournament, and V1 Release

- **Purpose:** Simulate a tournament, run a real community pilot, fix
  release-blocking defects, and release Version 1.
- **Dependencies:** M20.
- **Status:** NOT STARTED.
