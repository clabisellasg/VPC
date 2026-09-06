# M16 — One-Court Scheduling and Queue

Status: COMPLETED. Automated and hosted validation passed, and the mandatory
physical Android and Web walkthroughs were confirmed by the project owner.
Baseline: `2e03224b0f649956f6a95c6fe200aff7a704ad05`.
Branch: `milestone/m16-one-court-scheduling-queue`.

## Accepted one-court policy

One organizer operates one physical court for one event. Active, nondeleted,
unplayed matches enter the durable queue only when their existing tournament
state is `READY` (`queued` in storage), both teams are resolved, and the match
is not already Now Playing. BYEs and blocked, completed, deleted, or invalid
matches never enter. Reconciliation adds a newly ready match once, removes an
entry that becomes ineligible, and preserves the waiting position of every
still-eligible entry.

The recommended next match is deterministic:

1. Avoid either team from the immediately previous completed court match when
   another eligible match exists.
2. Prefer the oldest durable queue position.
3. For equal positions, prefer the match whose least-rested team has gone the
   most completed court matches without playing.
4. Resolve a remaining tie by event, division, match sequence, then MatchId.

A temporarily skipped match remains in place and cannot starve. If every match
repeats a team from the previous match, the remaining rules decide. Starting is
always an explicit organizer action. At most one match may be Now Playing;
completing it makes the court available but never starts another automatically.

## Architecture and lifecycle

Framework-independent queue contracts and the scheduling policy live under
`lib/src/application/court`. Widgets never call Drift or Supabase. The event
court route shows Now Playing, Up Next, the remaining queue, event/division and
format context, safe empty/error states, and organizer-only Start next match.
It opens the existing format-specific result flow rather than duplicating score
or progression rules. Guests and members have a read-only view.

Android Drift schema 10 adds only `court_queue_outbox` and
`court_queue_checkpoints`. Existing `court_queue_entries` remain the durable
queue record. Reconcile/start plus outbox insertion are one SQLite transaction;
pending work survives restart and never appears as synchronized. The bounded
synchronizer preserves protected intent and imports both the current entry and
waiting entries without creating another outbox operation.

Web uses the initialized Supabase client and never constructs SQLite. The fixed
public context function selects only event, division, match, team, and public
player display data. The fixed organizer command accepts only reconcile/start,
uses stable operation UUIDs, locks the event, checks match version and
eligibility, records a private receipt atomically, and replays identical input.
Changed operation reuse conflicts. A database trigger prevents a second active
Now Playing match across the event. Realtime notifications are debounced
refresh hints only.

The queue spans Single Elimination, Double Elimination, Single Round Robin, and
Double Round Robin without changing their generators or visualizations.
Tournament result completion/correction remains authoritative and queue refresh
reconciles newly unlocked or invalidated matches. Full synchronization
hardening remains M17.

## Validation and manual procedure

Automated validation covers eligibility, duplicate-free insertion, durable
order, repeat avoidance and fallback, rest distance, stable cross-format ties,
explicit authorization/start, one-current enforcement, atomic rollback,
idempotency, v9-to-v10 migration, remote validation, responsive semantics, and
existing regressions. Hosted checks must confirm public reads, anonymous/member
mutation denial, organizer reconcile/start, concurrent-start protection,
idempotent replay, stale versions, migration agreement, and lint.

For the physical Android walkthrough, use synthetic events only. Open an event
with ready matches across formats/divisions; confirm Now Playing and Up Next;
start and complete representative matches; confirm newly ready matches join;
close/reopen; enter a result offline; confirm pending state; reconnect and
confirm one authoritative result; verify guest/member read-only behavior,
larger text, and reopen after USB removal.

For Web, open the same queue at a narrow and wide size; verify direct-route
reload and browser navigation; start/complete representative matches online;
verify guest/member read-only behavior, refresh/retry, no SQLite initialization,
and no console errors.

The completed walkthrough covered guest/member read-only behavior, organizer
queue operation, explicit start, result completion, cross-format ordering,
restart persistence, Android-to-Web convergence, responsive layouts, and the
offline/pending boundary. Two final Android reconciliation defects were fixed:
historical result revisions are imported after their referenced matches on a
fresh cache, and authoritative queue replacement uses UTC ISO timestamps that
cannot precede each entry's creation time.

Known limits: Version 1 provides one court, no manual drag ordering, time slots,
duration estimates, booking, notifications, multiple-court scheduling, or
configurable fairness weights. OPEN-009 remains unresolved and conflicts are
preserved rather than automatically resolved.

Files to study first:

- `lib/src/application/court/court_queue_service.dart`
- `lib/src/infrastructure/court/drift_court_queue_repository.dart`
- `lib/src/infrastructure/court/court_queue_synchronizer.dart`
- `lib/src/infrastructure/court/supabase_court_queue_repository.dart`
- `lib/src/presentation/court/event_court_page.dart`
- `supabase/migrations/20260906120000_m16_one_court_queue.sql`
