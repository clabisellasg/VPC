# Android Synchronization Design

## Current status

**Player vertical slice implemented in Milestone 5; full synchronization is not
implemented.** Permanent players were selected because their stable UUID
identity and limited relational dependencies exercise create, update,
tombstone, pull, conflict, and Realtime behavior without pulling later feature
entities into M5.

Milestone 3 supplies only the hosted business-record schema, optimistic version
fields, tombstones, RLS, and Realtime publication. It creates no outbox,
operation receipt, checkpoint, failed-operation, or conflict table and no
synchronization coordinator. Realtime remains a refetch signal; its publication
configuration is not synchronization implementation.

Milestone 4 supplied Android SQLite schema version 1 and local player, event,
and match repository adapters. Its twelve operational tables intentionally have
no sync-state, dirty, outbox, inbox, retry, cursor, device, conflict, or
replication field/table. Local transactions in M4 prove atomic business writes.
M5 advances that database through a tested v1→v2 migration, adds separate
outbox/checkpoint/conflict tables, and replaces only the Android player adapter
with an atomic save-and-queue adapter. Event and match adapters remain M4-only.

The hosted player protocol uses a private receipt table plus fixed
`apply_player_sync_operation` and `pull_player_sync_changes` functions. It is
not a generic replication endpoint. Extending it to the remaining operational
tables is explicitly future work.

## Local-first writes and outbox

Important Android organizer changes write to SQLite first. In one local
transaction, the application:

1. Validates the action against the locally available state and permissions.
2. Applies the local business-record change with its expected/new version.
3. Appends an outbox operation describing the synchronization intent.
4. Commits both changes or neither.

The UI can then use committed local state while offline. A crash cannot leave a
business change committed without its synchronization intent.

Each new shared record and each outbox operation uses a client-generated UUID.
The M5 player operation stores entity type/ID, operation kind, base version,
deterministic JSON payload, UTC creation/eligibility timestamps, attempts,
claim status, and short redacted failure information. It stores no credential,
Auth token, raw exception, or service-role key.

## Push, idempotency, and ordering

When connectivity and a valid authenticated session are available, the sync
coordinator sends pending operations to secure cloud operations. The cloud
records or recognizes the unique operation ID so a retry returns the prior
outcome instead of applying the mutation twice. This covers ambiguous failures
where the server may have committed but the client did not receive a response.

Operations with causal dependencies are submitted in their local logical order.
An independent operation may eventually be processed separately, but
parallelism must not violate event lifecycle, match progression, or queue
dependencies. Permanent rejection does not cause dependent operations to be
silently applied out of context.

Optimistic versions express the state the client edited. The server verifies
the expected version and returns the accepted new version or a structured
conflict. Server timestamps and accepted versions are reconciled into SQLite.

## Transactional cloud operations

Critical actions—especially lifecycle changes, finalized match results,
elimination progression, placements, and court-queue transitions—must execute
as authorized, transactional, idempotent database operations. Their related
updates either all commit or none commit. RLS and database functions enforce
cloud authority; client-side checks are not sufficient security.

## Pull reconciliation and checkpoints

The coordinator incrementally pulls changes accepted after a durable local
checkpoint. It applies a received batch and advances its checkpoint in a local
transaction so an interruption can safely replay the batch. Pull includes
tombstones and enough version/timestamp information to reconcile active and
removed records. The player checkpoint is the last applied
`(updated_at, player_id)` tuple. The page and checkpoint commit together.
Equal versions are idempotent, and a clearly newer remote player replaces local
state only when no incompatible local operation is pending. Pulled records
bypass the queueing repository and are not echoed as new mutations.

Supabase remains the shared convergence point. Android reconciles accepted
cloud state into SQLite, including its own server-normalized changes and
changes from Web/PWA or other organizers.

## Conflict and failure categories

At minimum, synchronization distinguishes:

- **Version conflict:** the cloud record changed after the local expected
  version.
- **Lifecycle conflict:** an action is invalid in the cloud event/match state.
- **Dependency conflict:** a prerequisite operation or match result is absent,
  rejected, or superseded.
- **Authorization/session conflict:** the actor lacks permission, the role
  changed, or authentication is unavailable/expired.
- **Deletion/tombstone conflict:** one side changed a record the other side
  removed from active use.
- **Validation conflict:** cloud-enforced business rules reject the operation.
- **Transient failure:** connectivity, timeout, or service failure permits a
  safe idempotent retry.
- **Permanent failure:** the operation cannot succeed without correction or
  intervention.

Failures and conflicts retain the operation, reason, and relevant local/remote
versions for investigation. The exact simultaneous-organizer policy is an open
decision. **Silent last-write-wins is prohibited for critical operations.**

For the M5 player slice, a stale base version or incompatible remote pull marks
the operation `conflicted` and creates an unresolved conflict row with both
representations. Retry stops for that mutation. M5 provides no automatic
resolution and no conflict UI, preserving `OPEN-009`.

## Realtime behavior

Supabase Realtime may notify an online client that relevant shared data changed.
The notification triggers a repository refetch or checkpointed synchronization
pull. Realtime payloads are not treated as authoritative records, are not a
durable queue, and do not replace idempotent push/pull reconciliation.

## Authentication and offline limitations

Offline Android can continue important organizer work only within a previously
established local session and locally available authorization context, subject
to a later explicit security/session policy. It cannot perform online login,
refresh an expired credential, prove a new role, approve a player claim, or
guarantee that cloud permissions have not changed while disconnected.

Queued operations are re-authorized by the cloud when sent. An offline local
success is therefore pending shared acceptance; the UI must distinguish local,
pending, synced, failed, and conflicted states where material. Authentication
methods and the exact simultaneous-organizer conflict/control policy remain
open decisions in [DECISIONS.md](DECISIONS.md).

## Milestone 5 runtime boundary

M5 subscribes only to `public.players` when both the Android database and
Supabase client exist. Bursts are debounced and invoke the same authoritative
pull. Realtime payloads are never written directly. Subscription and timer
disposal follows the Riverpod-owned runtime, while Web receives no SQLite
coordinator.

M5 does not implement authentication. With no current Supabase session, upload
and tombstone-aware pull report an authorization block, retain queued work, and
defer the next eligible attempt. Production uploads never use service-role
access. Fake authorized gateways prove coordinator behavior until M7 provides
an approved organizer sign-in path.

## Milestone 6 public cache boundary

M6 performs an anonymous, read-only full snapshot of active events and
divisions. On Android only, the snapshot is reconciled into the existing Drift
tables for last-known guest display. This path deliberately bypasses the M5
player queueing repository and creates no outbox operation, receipt, pull
checkpoint, or conflict row. It is not an expansion of the organizer upload
protocol and does not synchronize any event mutation.

Because production organizer event editing does not exist before M9, this cache
is safe for the M6 slice. Reconciliation rejects a newer local record instead
of silently overwriting it. Before organizer event writes are introduced, the
event synchronization protocol must define pending-intent detection and shared
conflict handling. Web remains online-only.

Opening the guest shell does not start player upload/pull. The M5 coordinator
and Realtime implementation remain intact but await an authenticated lifecycle
trigger in a later milestone.

## Milestone 7 authenticated synchronization gate

M7 supplies that lifecycle trigger without expanding the player-only protocol.
Supabase restores the account session, then the private account snapshot reads
the effective role from `user_roles`. Only a live `organizer` result starts the
existing Android M5 runtime. Guest, ordinary member, unavailable authorization,
and sign-out states invalidate and dispose it. Authorization rejection still
leaves outbox operations pending; no operation is discarded.

Profiles, roles, and player-claim requests are online-only M7 data. They are not
written to SQLite, placed in the operational outbox, or treated as offline
authority. A temporarily persisted Auth session may be presented offline, but
claim mutations and role confirmation require the cloud. PostgreSQL rechecks
organizer permission for every M5 apply/pull RPC regardless of Flutter state.
## M8 player-directory use of the M5 slice

M8 reuses the player-only M5 synchronization slice without expanding its
entity scope. Android organizer creation commits the player and outbox
operation atomically. Public anonymous refresh is read-only: it creates no
outbox record, never infers tombstones from partial results, and does not
overwrite pending, failed, blocked, or conflicted local proposals. A confirmed
organizer session remains necessary for authoritative tombstone pull and
upload. Conflicts are displayed honestly and remain unresolved under OPEN-009.

Web never creates SQLite/outbox infrastructure and applies organizer creation
online through the existing idempotent cloud operation.
