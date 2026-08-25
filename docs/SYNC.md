# Android Synchronization Design

## Current status

**Designed only; not implemented through Milestone 3.** This document defines
the required conceptual behavior without choosing SQLite packages, outbox/sync
schemas, endpoint shapes, or an exact conflict-resolution policy.

Milestone 3 supplies only the hosted business-record schema, optimistic version
fields, tombstones, RLS, and Realtime publication. It creates no outbox,
operation receipt, checkpoint, failed-operation, or conflict table and no
synchronization coordinator. Realtime remains a refetch signal; its publication
configuration is not synchronization implementation.

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
An operation includes enough identity, ordering, actor/session, expected-version,
and payload information to validate and replay it. Exact representations are
deferred to the persistence milestones.

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
removed records. Checkpoints may be scoped, but their exact shape is deferred.

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
