# M08 — Permanent Community Player Directory

## Goal and status

M8 establishes the reusable public player directory, conservative duplicate
warning, basic permanent-player profile, and organizer creation flow. The
milestone is **COMPLETED**: automated, hosted, physical Android-phone, and Web
walkthrough acceptance passed on 2026-08-29.

## Implemented scope

- Guest routes `/players` and `/players/:playerId` list, search, page, and show
  active permanent community players without requiring an account.
- `/organizer/players/new` is presentation-guarded by the currently confirmed
  organizer role. PostgreSQL remains the final authorization boundary.
- The basic public profile contains only permanent `PlayerId` internally,
  display name, and active/missing state. It contains no Auth identity, claim,
  email, role, skill, biography, contact, image, or statistics.
- Search trims surrounding whitespace, collapses internal whitespace, compares
  case-insensitively, performs display-name substring matching, orders by
  normalized name and `PlayerId`, and uses explicit pages of at most 50 rows.
- Exact normalized-name matches produce a duplicate warning. Reusing an
  existing identity preserves history; creating a different person with the
  same name requires deliberate acknowledgement and never merges records.
- UUID and UTC clock generation are injected outside widgets.

## Platform and synchronization behavior

Android reads active players from Drift immediately, then refreshes public
rows when configured. Remote public reads do not create outbox work and do not
overwrite a player with pending, failed, authorization-blocked, or conflicted
local work. Organizer creation uses the existing M5 repository transaction, so
the player and outbox operation commit atomically. A confirmed organizer
session may run the existing idempotent M5 upload/pull coordinator; pending
operations survive restart and conflict records remain visible but unresolved.

Anonymous reads do not reveal tombstones, so a guest-only Android cache may
temporarily retain an older player until an authenticated organizer pull
provides the tombstone. Absence from a partial public result is never treated
as deletion.

Web uses Supabase online and never initializes Drift. Organizer creation uses
the existing fixed M5 cloud apply operation and reports success only after the
cloud returns the authoritative player. Web has no offline creation.

Player Realtime remains the M5 debounced refresh-hint mechanism when the
organizer synchronization runtime is active. Payloads are not trusted as
domain records; Web public browsing uses explicit refresh in M8.

## Cloud query

Migration `20260829090000_m08_public_player_directory.sql` adds only a fixed,
bounded `search_public_players` RPC and a partial normalized-name index. The
function is `SECURITY INVOKER`, has an empty `search_path`, is limited to 50
rows, explicitly returns public player columns, and remains subject to player
RLS. No player columns, policies, Auth links, skill fields, or statistics were
added.

## Important files

- `lib/src/application/players/`: query/page models, read ports, and creation
  use case.
- `lib/src/infrastructure/players/`: Supabase reader, Drift cache, platform
  writers, injected UUID/clock, and Riverpod composition.
- `lib/src/presentation/players/`: directory, profile, creation flow, and
  overrideable controllers.
- `supabase/migrations/20260829090000_m08_public_player_directory.sql`:
  bounded public search.
- `supabase/tests/database/permanent_player_directory_test.sql`: catalog and
  privilege assertions.

## Validation and tests

Run:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
supabase migration list --linked
supabase db lint --linked --fail-on error
```

Focused tests cover normalization, paging, duplicate acknowledgement,
injected identity/time, safe row mapping, tombstone exclusion, cached reads,
non-outbox remote reconciliation, pending-write preservation, Web's no-SQLite
boundary, guest routes, missing profiles, authorization presentation, and
responsive layouts. Ordinary tests use fakes or in-memory Drift and make no
network calls.

The linked hosted migrations were applied on 2026-08-29. Local and remote
history agree, linked database lint reports no errors, the public search RPC
and M6 event reads return HTTP 200 anonymously, and anonymous player writes
plus profile/role/claim reads are denied. Docker was unavailable, so the
committed pgTAP file was not run locally. The Flutter suite currently contains
159 passing tests. Web and Android debug production builds pass. Authenticated
member denial and organizer creation were confirmed through the walkthroughs.

## Mandatory manual acceptance

The Android and Web procedures are maintained in `docs/OPERATIONS.md`. Both
were completed on 2026-08-29. Web verified guest list/search/profile, direct
reload, history navigation, responsive layouts, member denial, organizer
duplicate acknowledgement/creation, no SQLite, no private public fields, and
no console errors. The physical Android phone verified guest access, profile
privacy, organizer duplicate handling, online and offline creation, pending
survival across restart, reconnect upload, text scaling, guest access after
sign-out, and reopening after USB disconnection. No safe manual conflict
injection control exists, so that conditional step was skipped; deterministic
tests cover visible, unresolved conflict state.

The intentionally synthetic manual rows use M7 fixture-derived names and
`VPC M8 Android Offline Test 20260829`. The unique offline fixture had zero
cloud rows before the walkthrough and exactly one version-zero cloud row after
reconciliation, proving a single idempotent upload. Remove or replace these
only by exact UUID through a reviewed administrative workflow; never delete by
broad display-name matching.

## Known limitations and deferred work

- General rename/edit/tombstone UI is not specified in M8.
- Guest caches may retain a row until organizer-authorized tombstone pull.
- Conflict resolution is deliberately absent; OPEN-009 remains open.
- No skill scale exists; OPEN-002 remains open until before M11.
- No fuzzy/phonetic match or automatic merge exists.
- No event participation, event/division lifecycle, or M9 feature is present.
- Player history/statistics remain future work derived from real records.

M8 introduces no account claiming, Auth data in players, event functionality,
skill fields, stored statistics, automatic merge, or M9+ implementation.
