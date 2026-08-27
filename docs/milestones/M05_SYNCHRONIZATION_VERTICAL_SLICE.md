# M05 — Synchronization Vertical Slice

## Goal and selected entity

Milestone 5 proves one production-shaped Android local-to-cloud-to-local
synchronization flow without implementing later features. Permanent players are
the sole synchronized entity because their permanent client-generated UUIDs,
small record shape, existing M2/M3/M4 representation, public separation from
Auth, and existing Realtime membership exercise the protocol with few
relational dependencies.

This milestone does not claim that events, participants, payments, teams,
matches, queues, placements, profiles, or roles synchronize.

## End-to-end flow

1. Android validates a `PermanentPlayer` mutation.
2. `DriftSyncingPlayerRepository` writes the player and a stable outbox
   operation in one SQLite transaction.
3. Schema version 2 preserves that pending operation across process loss.
4. The foreground coordinator recovers stale claims and claims the oldest
   eligible bounded batch in `(created_at, operation_id)` order.
5. `SupabasePlayerSyncGateway` sends the fixed operation to the hosted player
   apply function through the existing Supabase client.
6. PostgreSQL checks organizer permission, validates the allowlisted payload,
   applies the player mutation, and records its result atomically.
7. Identical operation-ID replay returns the recorded result. Reuse with
   different content fails safely.
8. The gateway pulls authoritative players in `(updated_at, id)` order,
   including tombstones for authorized organizers.
9. SQLite reconciles a page and advances its checkpoint in one transaction.
10. Version/pending-intent mismatches become preserved conflicts.
11. Player Realtime notifications are debounced into pull requests; their row
    payload is never written directly.

## Local schema version 2

The tested v1→v2 migration leaves all twelve M4 operational tables unchanged
and adds:

- `sync_outbox_operations`: operation/entity UUIDs, fixed `player` entity type,
  `upsert`/`tombstone` kind, base version, deterministic JSON, UTC creation and
  eligibility times, attempt count, claim status/time, and short redacted
  failure fields.
- `sync_pull_checkpoints`: the durable player `(updated_at, player_id)` pull
  cursor and local update time.
- `sync_conflicts`: operation and entity IDs, expected version, local proposal,
  optional authoritative remote record/version, detection time, and resolution
  status.

Synchronization metadata is separate from operational rows. M5 adds no dirty,
device, replication, Auth, or account-link columns to `players` or any other
business table.

Committed generated artifacts are:

- `lib/src/infrastructure/persistence/local/app_database.g.dart`
- `drift_schemas/drift_schema_v1.json`
- `drift_schemas/drift_schema_v2.json`
- `test/generated_migrations/schema.dart` and generated version helpers

The accepted legacy M4 `app_database_v1.json` snapshot remains unchanged.

## Atomic local mutation and operation ordering

The existing M2 `PlayerRepository` contract is unchanged. Android composes a
synchronizing adapter that enforces version 0 for a create and exactly one
version increment for an update/tombstone. The player and outbox insert share a
transaction; a failed outbox insert rolls the player mutation back.

Claims are bounded and deterministic. A claim records `inFlight` plus UTC claim
time. Claims older than 15 minutes return to pending after interruption.
Authorization blocks retain the operation and defer it for five minutes.
Retryable failures use bounded exponential backoff (5–300 seconds) plus an
injectable sub-second jitter. Permanent failures remain observable; queues are
never destructively cleared.

## Hosted idempotency and security protocol

The existing Tokyo project (`ap-northeast-1`) received three M5 migrations:

- `20260828120000_player_sync_vertical_slice.sql`
- `20260828120500_assert_player_sync_security.sql`
- `20260828121000_assert_player_sync_protocol.sql`

`private.player_sync_operation_receipts` is unavailable to Data API client
roles. `public.apply_player_sync_operation` is `SECURITY DEFINER` with an empty
`search_path`, but it immediately checks the accepted M3
`private.is_organizer()` permission. This explicit check is necessary because
the narrowly scoped function performs the player mutation and private receipt
insert atomically. Only `authenticated` can execute it; anonymous and public
execution are revoked. It accepts no table name, SQL, arbitrary columns, or
provider key.

The function accepts one fixed player payload, checks operation kind,
timestamps, tombstone consistency, entity identity, and exact version
progression. An identical receipt replay returns the stored accepted/conflict
result. Different content under the same operation UUID raises a safe invalid
argument error. A stale base version returns the current authoritative player
as a conflict and performs no mutation.

`public.pull_player_sync_changes` applies the same organizer check and returns a
bounded tombstone-aware page ordered by `(updated_at, id)`. The existing M3
public read policy remains unchanged. No service-role key is required or used
by Flutter.

## Pull reconciliation and conflicts

Equal remote versions are no-ops. Clearly newer remote players replace the
local row only when no incompatible local operation is pending. Accepted
records write through a non-queueing infrastructure path, preventing echo.
The checkpoint commits with the page.

When an upload has a stale base version or a pull meets incompatible pending
intent, the original operation is marked conflicted and both proposals are
retained. Automatic retry stops. M5 deliberately chooses neither local nor
remote and provides no resolution UI. The exact simultaneous-organizer policy
remains `OPEN-009` despite its historical “before M5” resolve-by note; this
slice needs detection and preservation, not a product-level resolution rule.

## Realtime, platform, and authentication boundaries

Supabase already publishes `players`. Android subscribes only when both its real
Drift database and configured Supabase client exist. A burst becomes one
authoritative pull hint. Disposal closes channel, stream, timer, coordinator,
and database ownership through Riverpod.

Web still opens no SQLite, constructs no Android sync store/coordinator, and
makes no offline guarantee. No unsupported native platform gained persistence.

M7 still owns registration, sign-in UI, role management, and player claiming.
M5 consumes an already-existing Supabase session only. Without a valid session,
uploads remain pending and pull reports authorization-blocked without a
service-role workaround. The ordinary test suite injects fake authorized
gateways.

## Dependencies and tools

No dependency was added or changed. The resolved M4/M3 packages remain:

- `drift 2.34.3`
- `drift_flutter 0.3.1`
- `path_provider 2.1.6`
- `drift_dev 2.34.5`
- `build_runner 2.16.0`
- `supabase_flutter 2.17.2`

Hosted work used the existing official Supabase CLI `2.115.0`. The CLI reported
`2.116.0` available, but the installed tool was not mutated during M5.

## Generation and validation commands

```powershell
flutter pub get
dart run build_runner build
dart run drift_dev schema dump lib/src/infrastructure/persistence/local/app_database.dart drift_schemas
dart run drift_dev schema generate drift_schemas test/generated_migrations
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Hosted migration procedure:

```powershell
supabase projects list --output json
supabase migration list --linked
supabase db push --linked --dry-run --skip-vault
supabase db push --linked --skip-vault
supabase migration list --linked
supabase db lint --linked --fail-on error
```

The hosted migrations and catalog/protocol assertions passed. Publishable-key
anonymous smoke checks allowed public player reads and denied private reads plus
apply/pull. Docker Desktop's engine was unavailable, so the retained pgTAP file
was not run locally and is not claimed as passing. No remote GitHub Actions run
is claimed because this branch was not pushed.

The acceptance run used Flutter `3.47.1` stable and Dart `3.13.1`. Dependency
resolution, formatting, static analysis, all 85 Flutter tests, the Web
production build, and Android debug APK build passed. Repeated code generation,
schema export, and migration-helper generation produced stable SHA-256 hashes.
The Web output is `build/web`; the APK is
`build/app/outputs/flutter-apk/app-debug.apk`. The Web optional Cupertino-font
diagnostic and Android SDK XML-version warning match earlier accepted baseline
warnings and did not affect either artifact.

## Optional manual Android procedure

After M7 supplies a safe organizer session and a test/dev mutation harness:

1. Install a configured development APK on a physical Android device.
2. Disconnect the network, make a test player mutation, and verify it is local
   and queued through diagnostics rather than a production feature screen.
3. Close/reopen and confirm the operation remains pending.
4. Restore connectivity and explicitly request foreground synchronization.
5. Verify Supabase applied it once, safe replay does not duplicate it, and a
   Realtime notification requests an authoritative pull.

This authenticated-device procedure was not executed in M5 because implementing
authentication or a player-management screen would implement M7/M8 early.

## Known limitations and deferred work

- Only players synchronize; the remaining operational tables wait for their
  feature milestones and M17 hardening.
- There is no Android background service/job scheduler or uncontrolled loop.
  Triggers are foreground startup, explicit request, and Realtime hints; a
  future lifecycle/connectivity integration may call the same explicit method.
- M5 has no conflict-resolution UI or approved automatic policy.
- No M7 authentication UX, organizer administration, or player claiming exists.
- No production screen exposes pending/conflicted counts or creates a player.
- Authenticated physical-device upload/restore remains deferred as described.
- All twelve product decisions remain open. M5 does not choose authentication,
  claiming, skill, scoring, correction, tie-breaker, bracket reset, division,
  payment, simultaneous-organizer, hosting, or team-size rules.

Future Me should study `sync_models.dart`, `sync_contracts.dart`,
`player_sync_coordinator.dart`, `drift_syncing_player_repository.dart`,
`drift_player_sync_store.dart`, `supabase_player_sync_gateway.dart`, the Drift
v2 migration, the three hosted migrations, and their deterministic tests first.

There is no authentication UI, role management, player claiming, full-table
synchronization, tournament algorithm, feature UI, deployment, secret,
service-role client, or real community data in Milestone 5.
