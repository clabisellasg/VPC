# M03 — Supabase Cloud Foundation

## Goal and scope

Milestone 3 establishes the shared Supabase/PostgreSQL/Auth/Realtime security
foundation for Volta Paddle Club. It adds the initial hosted schema, restrictive
grants and row-level security, a normalized organizer permission, Realtime
publication membership, and an optional Flutter client initialization boundary.

It does not implement sign-in, player claiming, application repositories,
SQLite, synchronization, tournament algorithms, or feature UI.

## Hosted project and tooling

- Existing project: `vpc`; it was linked rather than recreated or migrated.
- Accepted region: Northeast Asia (Tokyo), Supabase region code
  `ap-northeast-1`.
- Hosted PostgreSQL observed during preflight: major version 17.
- Supabase CLI: official stable standalone binary `2.115.0`.
- The CLI archive was obtained from the official `supabase/cli` GitHub release
  and its published SHA-256 checksum was verified before use.

The non-secret project reference may be supplied to the official link command.
Authentication remains interactive and local:

```powershell
supabase login
supabase link --project-ref <project-ref>
supabase projects list --output json
```

Never put an access token, database password, secret key, or service-role key
in a command committed to the repository. The CLI stores its own authenticated
session outside the repository.

## Version-controlled migrations

- `20260825111647_initial_cloud_foundation.sql` creates the schema, constraints,
  indexes, scope/transition guards, RLS policies, grants, organizer helper, and
  idempotent Realtime publication entries.
- `20260825113131_assert_cloud_foundation_security.sql` creates no application
  object. It fails atomically unless the hosted catalog has all required tables,
  RLS, policy count, public/private grants, no client DELETE grants, a safe
  organizer helper, no auth ID in `players`, and all Realtime entries.

The safe hosted workflow is:

```powershell
supabase migration list --linked
supabase db push --linked --dry-run --skip-vault
supabase db push --linked --skip-vault
supabase migration list --linked
supabase db lint --linked
```

Always verify `supabase projects list` identifies the expected linked project
and region before the non-dry-run push. M3 contains no seed or roles file and
does not update Vault.

## Schema summary

The migration creates these required `public` tables:

- Private identity/permission records: `user_profiles`, `user_roles`.
- Permanent community identity: `players`.
- Events and participation: `events`, `event_divisions`,
  `event_participants`, `division_participants`, `participant_payments`.
- Temporary competition records: `teams`, `team_members`.
- Tournament records: `matches`, `match_dependencies`,
  `court_queue_entries`, `division_placements`.

Application IDs are UUID primary keys with no database-side UUID default, so
future offline clients can supply them. Mutable records carry `created_at`,
`updated_at`, nonnegative `version`, and optional `deleted_at`. Timestamps use
PostgreSQL `timestamptz`. Historical relationships use restrictive foreign-key
deletion, and client roles receive no hard-delete grant.

Checks use the exact M2 enum strings and structural invariants. Event money uses
nonnegative integer minor units plus a three-letter currency code. The database
does not process money. Cross-record triggers reject inconsistent division,
event, team, dependency, queue, and placement scopes. Event and match status
changes accept only adjacent forward transitions.

No skill-rating column or scale, payment transaction/gateway field, player
claim table, outbox, sync checkpoint, conflict table, or derived player-stat
counter is introduced.

## Public/private and organizer security boundary

Anonymous and authenticated clients can select non-deleted rows from the 11
public community/tournament tables. Anonymous clients have no official-data
write grant. Authenticated clients receive insert/update grants for those
tables, but RLS permits the operations only when the caller has an active
`organizer` row.

`private.is_organizer()` is a `SECURITY DEFINER` function in the non-exposed
`private` schema. It uses an empty `search_path`, fully qualified references,
and minimal execution permission. Organizer is a normalized role attached to
an Auth user, not a separate account type. Registration does not create an
organizer row, and no client role can insert, update, or delete `user_roles`.

`participant_payments` is organizer-only. `user_profiles` is visible and
mutable only to the matching authenticated user. An authenticated user can read
only their own active `user_roles` row. The public `players` table contains no
Auth user ID; account/player linking remains deferred to the approved claim
milestone.

The service-role key must never be supplied to Flutter, embedded in an APK/Web
build, committed, logged, or used for client-level validation.

## Realtime

The migration idempotently adds the 11 public community/tournament tables to
the `supabase_realtime` publication. Profiles, roles, and payments are excluded.
M3 creates no Flutter subscription. Future clients must treat Realtime as a
change/refetch signal, not as authoritative record data.

## Flutter configuration

The only new direct runtime dependency is `supabase_flutter 2.17.2`.
`SupabaseConfiguration` reads:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Both are supplied with `--dart-define`. If both are absent, the app remains
valid and unconfigured for ordinary tests/builds. If exactly one is present,
startup throws a value-redacting `FormatException`. When both are present,
the official SDK initializes once and a nullable `SupabaseClient` is made
available at the Riverpod composition root. The bootstrap page does not consume
the provider and remains visually unchanged.

Values should be held outside the repository, for example in current-shell
environment variables:

```powershell
flutter run -d chrome `
  "--dart-define=SUPABASE_URL=$env:VPC_SUPABASE_URL" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$env:VPC_SUPABASE_PUBLISHABLE_KEY"
```

Do not create or commit an `.env` file. A publishable key is the only client key
allowed; never substitute the service-role or Supabase secret key.

## Tests and validation evidence

Focused Dart tests cover absent, complete, partial, and invalid configuration;
value-redacting errors; skipped initialization; and exactly-once initialization
through a test double. They perform no network call.

`supabase/tests/database/cloud_foundation_test.sql` is a 35-assertion pgTAP
suite covering tables, foreign keys, constraints, RLS, public/private access,
organizer authorization, profile/role privacy, payment privacy, Realtime, and
self-escalation denial. Docker is installed but its engine is not running. The
current CLI invokes a Docker-based test runner even with `--linked`, so the
pgTAP file could not be executed and is not reported as passing.

Hosted validation did complete through two complementary paths:

- The second migration executed catalog assertions against the hosted database.
- Publishable-key REST smoke checks returned `200` for every public table,
  `401` for payments/profiles/roles, and `401` for an anonymous player insert;
  no smoke-test row was created.

Remote `supabase db lint --linked` reported no schema errors. The dashboard
Security Advisor required a separate authenticated browser session that was not
available, so no dashboard-advisor result is claimed. Full authenticated
organizer end-to-end verification remains deferred until authentication flows
exist in M7.

The completed local acceptance run used Flutter `3.47.1` stable and Dart
`3.13.1`. Dependency resolution, formatting verification, static analysis, all
47 Flutter tests, the Web production build, and the Android debug APK build
passed. Outputs were produced at `build/web` and
`build/app/outputs/flutter-apk/app-debug.apk`; both remain ignored build
artifacts. The first Android attempt encountered host memory pressure in a JVM
daemon. After stale Kotlin daemons were stopped and the validation run was
limited to one in-process compiler worker, the required build passed. This was
not an Android-license failure, and the accepted project Gradle settings were
restored afterward.

## Known limitations and open decisions

- Authentication database integration exists, but no authentication method is
  enabled or selected by application code; `OPEN-011` remains open.
- No account-to-player claim workflow exists; `OPEN-001` remains open.
- Payment rows allow optional division scope without choosing `OPEN-008`.
- Division participation is structurally possible without deciding `OPEN-007`.
- Teams have no fixed-size constraint, preserving `OPEN-012`.
- Score values are only structurally nonnegative; `OPEN-003` remains open.
- No correction, tie-breaker, bracket-reset, skill-scale, simultaneous-editor,
  or hosting-provider decision is resolved. All 12 product decisions remain
  `OPEN`.

There is no SQLite implementation, outbox, synchronization logic, repository
adapter, sign-in UI, player/event screen, tournament generation, progression,
standings, deployment, production seed data, or service-role client usage in
Milestone 3.
