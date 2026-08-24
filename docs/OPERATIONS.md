# Operations Outline

## Status and use

All procedures in this document are **PRELIMINARY / FUTURE**. They are
operational acceptance targets for later milestones, not validated runbooks.
No application, backend, APK, PWA deployment, backup, restore, or pilot exists
in Milestone 0. Commands and provider-specific steps must be added only after
their implementation is selected and tested.

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

- Before play, reduce pending operations to zero on each organizer Android
  device while online.
- During and after play, inspect pending, retrying, failed, and conflicted counts.
- Do not archive or decommission the final working device until critical
  operations are confirmed in Supabase and refetched by another client.
- Preserve operation IDs and diagnostic evidence for unresolved items; avoid
  destructive queue clearing.

## Conflict handling — PRELIMINARY / FUTURE

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

- Produce the Android Flutter-generated APK from a documented, reproducible,
  release-tagged source revision.
- Record signing ownership, artifact checksum, version, supported upgrade path,
  and trusted community distribution channel.
- Test clean install and upgrade on representative Android devices.
- Do not describe an unverified APK as a release or publish it from Milestone 0.

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
