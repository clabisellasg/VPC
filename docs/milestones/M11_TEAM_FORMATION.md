# M11 — Team Formation

## Goal and scope

M11 implements organizer-only manual, random, and simple balanced formation of
temporary two-player teams for one event division. It resolves OPEN-002 and
OPEN-012. It does not implement tournament formats, seeding, brackets, matches,
scores, standings, or scheduling; those remain M12+.

## Community skill

The permanent scale stores nullable integer `skill_level`: 1 Beginner, 2
Developing, 3 Intermediate, 4 Advanced, and 5 Competitive. Null means Unrated,
not Intermediate. Organizers may assign, change, or clear it; public profiles
may show its label. It is an approximate community-organizing aid, not DUPR or
an official competitive rating. Existing players remain Unrated.

## Formation rules

A player is eligible only when the permanent player, event registration, and
division assignment are active and the participant is checked in. Payment does
not exclude eligibility. A complete team has exactly two players; an odd player
remains Unassigned without an incomplete team record.

- Manual formation pairs two eligible unassigned players.
- Random formation uses injected randomness, shuffles once, then pairs in
  sequence. A fixed seed and ordered input are repeatable.
- Balanced formation requires every eligible player to be rated, sorts by skill
  descending then PlayerId, and pairs strongest remaining with weakest
  remaining. Team strength is the sum; spread is maximum minus minimum complete
  team strength. This is a transparent heuristic, not AI or a guarantee.

Every generated result is a non-persistent preview until explicit confirmation.
Clearing/replacement is an aggregate operation and team changes are locked
outside REGISTRATION.

Confirmed pairs may be returned to Unassigned during Registration. This first
previews the replacement; confirmation releases both players for manual pairing.
Random and balanced previews reconsider all eligible players, including existing
pairs. A replacement tombstones superseded draft identities rather than deleting
history. The Unassigned preview supports any number of players, not just one.

## Persistence, synchronization, and platforms

Drift schema version 5 adds nullable constrained player skill plus bounded team
outbox/checkpoint/conflict tables. Android commits team replacement, members,
tombstones, and the outbox operation atomically; offline confirmation is
Pending and survives restart. The fixed cloud RPC verifies organizer authority,
eligibility, lifecycle, aggregate shape, and idempotency before applying the
replacement. Web previews in memory, calls Supabase online, waits for acceptance,
and never opens SQLite. Player skill uses the existing player sync protocol.

Opening an Android division displays local data first, then performs durable
checkpointed team pull. The existing singleton checkpoint covers all team/division
aggregates. Strict `(updated_at, division_id)` cursors prevent equal-time rows
from being skipped. Teams, members, tombstones, and the page cursor commit
atomically; failed mapping/reconciliation or protected local work cannot advance
the cursor. Remote metadata is preserved exactly in UTC with microsecond
precision. Pull never uses device time or creates outbox operations. Realtime
requests this same pull, and Web remains independent of Drift/checkpoints.

Relevant files:

- `lib/src/application/teams/` — provider-neutral formation models and service.
- `lib/src/infrastructure/teams/` — Drift/Supabase adapters and bounded upload.
- `lib/src/domain/players/player_skill.dart` — accepted skill value object.
- `lib/src/presentation/teams/` — organizer preview and confirmation screen.
- `supabase/migrations/20260902120000_m11_team_formation.sql` — cloud boundary.

## Validation and manual testing

Run generation/schema export, formatting, analysis, all tests, Web and Android
builds, linked migration history/lint, and hosted anonymous/member/organizer
security/idempotency checks. Then perform the required physical Android and Web
walkthroughs from the planner specification using synthetic records only.

The user confirmed the Web walkthrough and subsequently the complete physical
Android walkthrough. During manual verification, Web-to-Android snapshot loading
and confirmed-team release controls were corrected. The user then confirmed
release/re-pair behavior worked and completed the Android walkthrough.

Final local validation: `flutter pub get`, formatting verification, analysis,
all 201 Flutter tests, `flutter build web`, and `flutter build apk --debug`
passed. Artifacts are `build/web` and
`build/app/outputs/flutter-apk/app-debug.apk`; neither is committed. No dependency
versions were changed. The Web build reports an optional Cupertino font-family
warning, and Android reports an SDK XML-version compatibility warning; both
builds succeed.

Supabase CLI 2.115.0 reports matching local/hosted migration histories through
`20260903120000` and no linked schema lint errors. All three M11 migrations were
applied to the existing Tokyo project. Anonymous public player/event reads
return 200; profile/role reads and the fixed-signature team mutation RPC return
401. Organizer/member behavior was exercised in the user-confirmed walkthroughs.
Local pgTAP was not run because the Docker Desktop Linux daemon is unavailable.
No remote GitHub Actions run is claimed.

The two final-inspection gaps were corrected by the authoritative pull mapper,
`team_formation_puller.dart`, atomic Drift page reconciliation, and migration
`20260903120000_m11_authoritative_team_pull.sql`. Nine focused regressions prove
timestamp precision, null/tombstone preservation, idempotence, actual SQLite
close/reopen, cursor tie-breaking, pending/conflicted protection, and rollback
including a forced checkpoint-write failure. Hosted read-only assertions compare
every pulled metadata field to stored cloud records and paginate one aggregate
at a time. No real records or roles are changed by those assertions.

Status: **COMPLETED**. The final validation run passed all 201 tests, formatting,
analysis, Web and Android debug builds. `build_runner build`, Drift schema dump
and migration-helper generation were rerun; generated hashes remained unchanged.
Linked migration history and database lint, hosted assertions/privacy smoke
checks, documentation links, credential scans, and Git whitespace checks passed.
The existing passed manual walkthroughs are retained; these corrections change
no visible UI. M12–M21 remain NOT STARTED.

Deliberate scope limitations: no automatic skill calculation,
partner-history optimization, conflict resolution, substitutes, incomplete
teams, or tournament-engine behavior.
