# Operations Outline

## Status and use

Tournament, release, recovery, and deployment procedures in this document are
still **PRELIMINARY / FUTURE**. Milestone 3 validates the initial hosted
Supabase migration/security foundation, Milestone 4 validates the local
schema/repository foundation, Milestone 5 validates a player-only
synchronization engine and hosted protocol, and Milestone 6 adds a synthetic
public-read fixture workflow. These do not validate a tournament runbook,
release APK, PWA deployment, backup/restore, full-table sync, or pilot.

## M6 synthetic public fixtures — REVIEWABLE DATA WORKFLOW

- `20260828150000_m06_public_demo_seed.sql` is visibly a data migration, not a
  schema change. It inserts only three `VPC Demo` events and four `Sample`
  divisions with deterministic `61000000-...`/`62000000-...` UUIDs.
- Verify the linked project and dry run before applying it. After application,
  confirm exactly those IDs and anonymous RLS behavior; never use a
  service-role key for client smoke checks.
- The M6 validation applied this migration to the existing linked Tokyo `vpc`
  project and confirmed all seven exact rows. No other hosted row was modified.
- To retire the fixtures, create a new reviewed data migration. Delete the four
  exact division IDs first and then the three exact event IDs. Never edit the
  applied seed migration, delete by display-name pattern, or touch unrelated
  community data.
- The reference dates are around 2026-08-28. Lifecycle status controls public
  grouping, so the fixtures remain explicit examples rather than pretending to
  be live community schedules.
- Physical Android and manual browser procedures are recorded in
  [M06_PUBLIC_APPLICATION_GUEST_READING.md](milestones/M06_PUBLIC_APPLICATION_GUEST_READING.md)
  and their M6 execution evidence is recorded in
  [TESTING.md](TESTING.md).

## Supabase migration maintenance — M3 VALIDATED FOUNDATION

- Use the official Supabase CLI and authenticate interactively with
  `supabase login`; never paste or commit the access token.
- Link only the existing `vpc` project and confirm `ap-northeast-1` (Tokyo) in
  `supabase projects list --output json` before mutation.
- Review committed migrations, then run `supabase migration list --linked` and
  `supabase db push --linked --dry-run --skip-vault` before a real push.
- Apply with `supabase db push --linked --skip-vault`, reconcile migration
  history, and run `supabase db lint --linked`.
- Use only the publishable key for client smoke checks. Never use the
  service-role/secret key in Flutter or client validation.
- The M3 pgTAP suite requires a functioning Docker-backed runner. Retain it even
  when Docker is unavailable; do not report it as passed without execution.
- No production seed data or automatic organizer assignment is part of the
  migration workflow. Organizer-role administration remains a privileged
  future runbook.

## Android local schema maintenance — M4/M5 VALIDATED FOUNDATION

- The production file is `vpc.sqlite` beneath Android's application-support
  directory. Do not copy it into the repository or treat a debug database as a
  backup format.
- Regenerate Drift sources, export into `drift_schemas/`, and regenerate
  `test/generated_migrations/` after an approved schema edit. Review every
  artifact and require stable hashes across a second pass before committing.
- Local schema v1 is the M4 baseline and v2 is the M5 synchronization slice.
  The v1→v2 migration is validated against the committed v1 snapshot and
  preserves M4 operational data. Every later increment needs equivalent tests.
- Foreign keys must remain enabled. Preserve restrictive history, tombstones,
  versions, UUID identities, and UTC precision during future migrations.
- Web and non-Android native platforms must not open this database. No SQLite
  Web assets or native desktop/iOS database setup is part of Version 1.
- Closing the Riverpod owner closes the database connection/background isolate.
  M5 adds player pending/conflict storage, but no procedure claims full-table
  synchronization, backup, restore, or user-facing recovery is implemented.

## Pre-tournament readiness — PRELIMINARY / FUTURE

- Confirm the event, divisions, format, participants, approved rule decisions,
  organizer access, and one-court queue are correctly configured.
- Confirm all intended participants exist once in the permanent player
  directory and that checked-in eligibility is understood.
- Review Paid/Unpaid counts without treating them as processed payments.
- Confirm devices, charging, venue connectivity expectations, and an identified
  lead organizer.
- Rehearse result entry, correction policy, queue progression, and escalation
  steps using the release candidate.

## Supabase free-project activity check — PRELIMINARY / FUTURE

- Before a tournament, verify the free Supabase project is active and reachable
  from the expected network.
- Verify Authentication, database access, RLS-protected public/organizer paths,
  database functions, and Realtime signals using safe health checks.
- Review free-tier usage and limits without enabling paid infrastructure.
- Record the check time and responsible organizer. Future validated steps must
  account for any free-project inactivity or pause behavior then in effect.

## Android offline readiness — PRELIMINARY / FUTURE

- Install the approved APK and verify its version and migration status.
- Authenticate and complete any required preloading while online.
- Confirm the active event and required player/tournament data are present in
  SQLite.
- Enter airplane mode and exercise the approved important organizer operations
  without changing production tournament data.
- Confirm the UI exposes local/pending state and does not imply cloud acceptance.

## Pending-sync verification — PRELIMINARY / FUTURE

M5 provides testable storage contracts for player pending/failed/conflicted
operations but no production inspection screen. Until later operations UI is
approved, do not clear or edit the outbox manually.

- Before play, reduce pending operations to zero on each organizer Android
  device while online.
- During and after play, inspect pending, retrying, failed, and conflicted counts.
- Do not archive or decommission the final working device until critical
  operations are confirmed in Supabase and refetched by another client.
- Preserve operation IDs and diagnostic evidence for unresolved items; avoid
  destructive queue clearing.

## Conflict handling — PRELIMINARY / FUTURE

M5 preserves player conflicts with local and remote evidence but intentionally
does not resolve them. `OPEN-009` remains open; the steps below are still a
future operational outline, not an approved resolution policy.

- Stop progression that depends on a critical conflict, especially match
  results, bracket paths, placements, and court-queue state.
- Compare the retained local operation and versions with authoritative cloud
  state, identify the organizers involved, and follow the approved conflict and
  correction policies.
- Record the selected resolution and verify downstream matches, standings,
  placements, history, and statistics after reconciliation.
- Never use silent last-write-wins for a critical operation. Exact controls
  remain open and must be approved by the synchronization milestone.

## Manual backup and restore — PRELIMINARY / FUTURE

- Define supported exports/backups for Supabase PostgreSQL and any necessary
  device-local recovery data using free-tier capabilities.
- Protect personal and authentication-related data during storage and transfer.
- Label backups with environment, version, timestamp, and integrity evidence.
- Test restore into an isolated environment before relying on the procedure.
- Verify identities, history, match dependencies, placements, and operation
  metadata after restore. No backup or restore method is validated yet.

## APK distribution — PRELIMINARY / FUTURE

Milestone 1 can produce `build/app/outputs/flutter-apk/app-debug.apk` for local
development validation. That debug artifact is not signed or approved for
community distribution and is not a release.

- Produce the Android Flutter-generated APK from a documented, reproducible,
  release-tagged source revision.
- Record signing ownership, artifact checksum, version, supported upgrade path,
  and trusted community distribution channel.
- Test clean install and upgrade on representative Android devices.
- Do not describe a debug or otherwise unverified APK as a release.

## Account and organizer operations — M7 PRELIMINARY

Supabase **Authentication → URL Configuration** must allow exactly the
configured deployment callback plus these development callbacks:

- `com.voltapaddleclub.vpc://auth-callback/account/confirm`
- `http://localhost:7357/account/confirm`
- `http://127.0.0.1:7357/account/confirm`

Hosted email confirmation remains enabled. Never disable it to bypass a test,
and never place a password, token, private key, or personal email in source,
documentation, shell history, screenshots, or issue text.

The first organizer is assigned only after the Auth account exists, through a
trusted Supabase SQL Editor or equivalent database-administration session. The
operator substitutes the intended Auth UUID privately:

```sql
insert into public.user_roles (user_id, role)
values ('<AUTH_USER_UUID>'::uuid, 'organizer')
on conflict (user_id, role) do update
set deleted_at = null, updated_at = now(), version = public.user_roles.version + 1;
```

Revoke the permission without deleting its audit row:

```sql
update public.user_roles
set deleted_at = now(), updated_at = now(), version = version + 1
where user_id = '<AUTH_USER_UUID>'::uuid
  and role = 'organizer'
  and deleted_at is null;
```

There is intentionally no Flutter role-management or self-promotion endpoint.
After assignment or revocation, sign in normally and refresh the account page
to verify the authoritative role. Do not use a service-role key in Flutter.

The hosted public fixtures are:

- `73000000-0000-4000-8000-000000000001` — `M7 Synthetic Claim Player`
- `73000000-0000-4000-8000-000000000002` —
  `M7 Android Synthetic Claim Player`

They supported the separate Web and physical-Android claim walkthroughs.
Remove either only through a reviewed later data migration after clearing its
exact test claim history and private profile link; do not delete by display-name
pattern, unrelated permanent players, or intended organizer accounts.

## PWA deployment — PRELIMINARY / FUTURE

- Select the free static hosting provider through an approved decision before
  M19 implementation.
- Document reproducible production build and deployment steps, environment
  configuration, HTTPS/domain behavior, cache/update behavior, rollback, and
  iPhone Safari installation/use.
- Verify public access and authenticated online organizer workflows against
  production RLS. Version 1 does not promise native iPhone offline support.
- Monitor free-tier constraints and do not enable paid services implicitly.

## Pilot tournament — PRELIMINARY / FUTURE

- First conduct an end-to-end simulated tournament with representative formats,
  connectivity loss, restart, duplicate retry, conflicts, and recovery.
- Run a real community pilot only after M20 acceptance and with a fallback way
  to preserve play and results.
- Capture operator feedback, timings, accessibility issues, device/network
  behavior, data integrity, unresolved sync, and release-blocking defects.
- Fix and revalidate release blockers before Version 1 release; retain the pilot
  record as acceptance evidence for M21.
## M8 player-directory manual acceptance (preliminary)

## Android phone

Use a configured build and only clearly synthetic `VPC M8 Test` names. As a
guest, open Players, search an existing fixture, open its profile, and verify
no private/Auth fields. Sign in as organizer, verify normalized-name duplicate
warning and reuse path, then deliberately acknowledge creation of a distinct
same-name test player. Confirm online synchronization. Create another
synthetic player offline; verify pending display across close/reopen, restore
connectivity, and confirm exactly one cloud row after reconciliation. If a safe
conflict fixture is available, verify it is visible and not auto-resolved.
Increase text size, sign out and retain guest access, then disconnect USB and
reopen the installed app.

## Web

Verify guest list/search/profile, direct-route reload, browser back/forward,
narrow/wide layouts, member write denial, organizer online creation, duplicate
warning plus deliberate acknowledgement, authoritative cloud success, no
SQLite initialization, no private fields, and no console errors.

These procedures passed on 2026-08-29 on the configured Web build and a
physical Android 14 phone. The Android offline fixture synchronized to exactly
one cloud row after reconnect. The conditional conflict injection step was not
run because M8 intentionally provides no safe conflict-control UI. Synthetic
validation rows are documented in the M8 record; remove them only by exact ID
through a reviewed administrative workflow, never by broad name matching.

## M9 event setup acceptance — VALIDATED 2026-09-01

Use only synthetic `VPC M9` events. Android validation covers guest reads,
member denial, organizer casual/formal setup, division validation, online sync,
offline pending persistence/restart, reconnect exactly once, public details,
sequential lifecycle, setup lock, format-required guard, preserved conflicts,
text scaling, and USB-free reopen. Web covers the corresponding online flow,
direct routes, browser navigation, responsive layouts, no SQLite, and no console
errors. Never describe local pending state as cloud acceptance.

The mandatory Web and physical-Android walkthroughs passed. Android validation
also confirmed immediate local pending feedback, persistence across restart,
reconnect reconciliation, and gesture-back navigation. Conflict injection and
post-registration lifecycle checks remain deterministic-test-only because M9
has no safe production conflict fixture or tournament-format selector.
