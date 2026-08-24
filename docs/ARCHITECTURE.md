# Architecture Baseline

## Scope

This document defines the conceptual Version 1 architecture. It deliberately
does not select unapproved Flutter packages or prescribe an exact source-folder
layout. Implementation begins in later milestones.

## Layers and responsibilities

### Shared Flutter presentation layer

Provides Android and Web/PWA screens, navigation, user interaction, and state
presentation. It invokes application use cases and does not contain tournament,
persistence, authorization, or synchronization rules.

### Application/use-case layer

Coordinates user actions, permissions, domain policies, repository calls, and
transaction boundaries. It exposes workflows suitable for both platforms while
selecting platform-appropriate persistence paths through abstractions.

### Pure Dart domain layer

Defines business concepts, validated state transitions, identities, and rules
without depending on Flutter, SQLite, Supabase, or the network.

### Pure Dart tournament engine

Deterministically generates and progresses only Single Elimination, Double
Elimination, Single Round Robin, and Double Round Robin. It remains separately
testable with fixtures and invariants and does not perform UI, storage, or
network work.

### Repository boundary

Defines storage-neutral contracts used by application use cases. Local and
remote implementations translate between persistence representations and
domain concepts without leaking infrastructure details into the domain.

### Android SQLite local data source

Stores the Android working set and is the immediate source of truth for
important offline-capable organizer operations. A local mutation and its
outbox operation are committed atomically in the same SQLite transaction.

### Android synchronization coordinator

Observes connectivity and session capability, submits pending outbox operations
in order, reconciles remote changes using checkpoints, records failures and
conflicts, and refreshes local state. It operates behind the synchronization
boundary rather than inside presentation or domain logic.

### Supabase remote data source

Supabase is the shared convergence point for Android and Web/PWA data.
PostgreSQL stores shared records; Supabase Authentication establishes identity;
row-level security (RLS) enforces access; database functions provide critical
transactional and idempotent cloud operations; and Realtime announces relevant
changes.

### Flutter Web/PWA online path

The iPhone Safari Web/PWA uses the online Supabase repository path. Version 1
does not promise native iPhone offline mutation. An authenticated organizer can
perform authorized management operations while online.

## Conceptual flow

```mermaid
flowchart LR
    UI[Shared Flutter UI] --> APP[Application / use cases]
    APP --> DOMAIN[Pure Dart domain]
    APP --> ENGINE[Pure Dart tournament engine]
    APP --> REPO[Repository boundary]
    REPO -->|Android: local first| SQL[SQLite]
    SQL -->|atomic mutation + outbox| SYNC[Sync coordinator]
    SYNC <-->|idempotent push + checkpointed pull| SB[Supabase]
    REPO -->|Web/PWA: online| SB
    SB --- AUTH[Auth + RLS]
    SB --- PG[PostgreSQL + functions]
    SB -. Realtime change/refetch signal .-> REPO
```

## Source-of-truth distinctions

- On offline-first Android, SQLite is the operational source for the current
  local view and pending changes.
- Supabase PostgreSQL is the shared convergence point and authoritative shared
  cloud state across Android and Web/PWA clients.
- The outbox is the durable source of pending Android synchronization intent;
  it is not the shared business record.
- Realtime is only a change/refetch signal. Repositories refetch durable data;
  Realtime payloads are not the source of truth.
- Finalized match records are the source of truth for match-derived statistics
  where practical. Derived totals must be reproducible from those records.
- Supabase Authentication is the source of authenticated cloud identity, while
  application roles and permissions determine organizer authority.

## Architectural invariants

1. Domain and tournament-engine code remains pure Dart and infrastructure-free.
2. Players are permanent reusable records; teams are temporary and scoped to an
   event/division.
3. Player participation never requires an account, and a later approved claim
   links rather than replaces a player record.
4. Guests cannot modify data; organizers authenticate and must have explicit
   permission.
5. Important Android organizer mutations succeed locally without network access
   and create an outbox operation in the same transaction.
6. Every synchronized mutation has a client-generated UUID operation ID and is
   safe to retry idempotently.
7. Critical cloud operations are transactional, authorize the actor, validate
   expected versions, and avoid partial bracket or queue progression.
8. Critical conflicts are surfaced for explicit handling; silent
   last-write-wins is prohibited.
9. Completed history is preserved. Removal, when needed, uses an auditable
   tombstone rather than destructive loss of shared history.
10. Realtime never bypasses repository validation or synchronization rules.
11. Only the four approved tournament formats enter the Version 1 engine.
12. Infrastructure choices and usage must remain within free tiers.

Detailed synchronization semantics are recorded in [SYNC.md](SYNC.md), and the
conceptual entities are recorded in [DATABASE.md](DATABASE.md).
