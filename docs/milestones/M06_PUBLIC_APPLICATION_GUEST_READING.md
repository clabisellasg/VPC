# M06 — Public Application and Guest Reading

## Goal and scope

Milestone 6 replaces the bootstrap-only screen with the first public Volta
Paddle Club experience. A guest can enter without authentication, navigate to
public events, browse current/upcoming/completed groups, open a stable event
detail route, view public divisions, and refresh. The data scope is only
`events` and `event_divisions`.

M6 does not add authentication, roles, player claiming, organizer writes,
participants, payments, scores, tournament logic, or full operational
synchronization. Those boundaries remain M7 and later work.

## Navigation and UI states

GoRouter owns three public locations:

- `/`: restrained guest home.
- `/events`: grouped public event catalog.
- `/events/:eventId`: public details identified by the existing UUID.

The shared shell uses a bottom navigation bar on narrow phones and a navigation
rail on wider browsers. System/browser back behavior stays within GoRouter;
unknown routes and missing event IDs fail visibly. Cards have semantic button
labels, touch targets come from Material components, layouts use constrained
responsive widths, and text follows the platform text scaler.

The presentation distinguishes initial loading, content, no events, refresh in
progress, safe recoverable failure, unconfigured Supabase, Android cached data,
and missing event. Errors never display raw provider exceptions, configuration
values, URLs, or keys.

## Public grouping and ordering

Existing M2 lifecycle status is authoritative:

- `upcoming` → Upcoming.
- `registration` and `inProgress` → Current.
- `completed` and `archived` → Completed.

Upcoming/current rows order by UTC scheduled date ascending, completed rows by
date descending, and UUID breaks ties deterministically. Divisions order by
case-insensitive name then UUID. Tombstoned events and divisions are excluded.
Widgets do not call `DateTime.now`; timestamps are validated and normalized to
UTC, while adapter/cache refresh time uses an injectable clock.

## Read boundaries and platform behavior

`PublicEventReader` is a framework- and provider-neutral application port. It
supports an optional cached catalog, authoritative refresh, and typed event
lookup. `PublicEventCatalog` contains immutable event/division projections and
their origin. Expected failures use the existing M2 repository result and
domain failure types.

`SupabasePublicEventSource` uses the already initialized nullable client and
anonymous publishable-key access. Its gateway requests only active `events` and
`event_divisions`, validates every public field outside widgets, orders rows
deterministically, and maps provider failures to safe messages. It never reads
payments, profiles, roles, Auth identities, or synchronization receipts and
never performs a service-role operation.

Web composes the online reader. Provider tests prove this path does not request
the local database factory. An unconfigured Web build remains valid but shows
the explicit configuration state.

Android composes `DriftPublicEventCache` over the existing M4 tables. It shows
active saved data first, then fetches a complete remote snapshot and reconciles
events/divisions in one local transaction. Reconciliation preserves UUIDs,
money, UTC metadata, versions, lifecycle values, and relationships. It advances
missed lifecycle states through adjacent transitions, marks active cached rows
absent from the complete snapshot with local tombstones, and rejects a newer
local version/timestamp. It creates no outbox operation and does not use or
expand the M5 player upload protocol.

The guest shell no longer watches the M5 sync runtime at startup, so opening
events cannot upload pending organizer operations. M5 infrastructure remains
unchanged and awaits an authenticated lifecycle trigger.

M6 uses explicit refresh and pull-to-refresh. Event/division Realtime is not
subscribed in this milestone; future use must remain a debounced authoritative
refetch hint.

## Synthetic hosted records

`20260828150000_m06_public_demo_seed.sql` is an explicitly named, idempotent
data migration with three fictional events and four fictional divisions:

- `61000000-0000-4000-8000-000000000001`: current sample session.
- `61000000-0000-4000-8000-000000000002`: upcoming sample open.
- `61000000-0000-4000-8000-000000000003`: completed sample round robin.
- Division IDs use the corresponding deterministic `62000000-...` prefix.

Names include `VPC Demo` or `Sample`; timestamps are coherent UTC reference
dates around 2026-08-28, but grouping depends on lifecycle status so the UI does
not silently reclassify them later. The rows contain no player, account,
payment, contact, credential, profile, or role data.

Never edit an applied migration to remove fixtures. Add and review a later data
migration that first deletes the four exact `62000000-...` division IDs and
then the three exact `61000000-...` event IDs. That narrow removal must not
match names or touch unrelated records.

## Configuration and run commands

No dependency changed. The relevant locked versions remain Flutter Riverpod
`3.4.2`, GoRouter `17.5.0`, Supabase Flutter `2.17.2`, Drift `2.34.3`, and Drift
Flutter `0.3.1`.

Supply only the publishable client pair from the local environment:

```powershell
flutter run -d chrome `
  "--dart-define=SUPABASE_URL=$env:VPC_SUPABASE_URL" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$env:VPC_SUPABASE_PUBLISHABLE_KEY"

flutter run -d <android-device-id> `
  "--dart-define=SUPABASE_URL=$env:VPC_SUPABASE_URL" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$env:VPC_SUPABASE_PUBLISHABLE_KEY"
```

Do not use a service-role/secret key, commit an `.env` file, or paste client
values into documentation or logs.

## Tests and validation

Deterministic tests cover lifecycle grouping and ordering, tombstone exclusion,
immutable divisions, Supabase mapping and malformed fields, provider redaction,
Android cache display/reconciliation/fallback, no-outbox pulls, local-version
protection, unconfigured behavior, guest routing, details, all UI states,
refresh coalescing, stale-controller disposal, narrow/wide layouts, semantics,
provider overrides, and Web SQLite exclusion. Ordinary tests use fakes and
in-memory Drift with no network or credentials.

The retained pgTAP file `public_guest_read_test.sql` asserts the fixture rows,
anonymous reads, and anonymous event/division write denial. The full M6
acceptance commands and hosted smoke outcomes are recorded in
[TESTING.md](../TESTING.md).

The implementation run passed dependency resolution, formatting, analysis,
all 116 Flutter tests, the Web production build, and Android debug APK build.
The linked Tokyo project received the one M6 data migration; migration history
agrees, database lint found no error, anonymous public reads returned the seven
exact fixtures, writes were denied, and private tables remained hidden. Docker
was not running, so pgTAP was retained but not executed locally.

## Manual Android procedure

1. Run a configured build on a physical Android phone.
2. Verify the guest shell opens with no sign-in and all three groups appear.
3. Open a demo event, inspect its divisions, then use system back.
4. Pull to refresh; close/reopen; disconnect USB and reopen again.
5. Increase system font size and inspect a narrow layout for clipping.
6. After one online load, disable Wi-Fi/mobile data, reopen, and confirm saved
   rows appear with the cached/offline message.
7. Restore connectivity and confirm refresh clears the cached indication.

This procedure was completed on a physical `23021RAAEG` running Android 14
(API 34). The configured app installed and launched without sign-in; all three
fixture groups, details, divisions, Back, refresh, reopen, narrow-screen and
increased-font behavior passed. After an online refresh, the app reopened with
saved events and an honest cached/offline indication while Wi-Fi and mobile
data were disabled. Connectivity restoration refreshed successfully, and the
installed app reopened after USB disconnection.

## Manual Web procedure

1. Run the configured Chrome build and enter without sign-in.
2. Verify groups, detail routes, explicit refresh, and narrow/wide layouts.
3. Use browser back/forward and refresh a supported route.
4. Simulate a network failure and verify the recoverable state.
5. Confirm the Web provider never constructs SQLite.

This procedure must not be marked passed unless it is actually performed.

The configured in-app browser walkthrough passed guest entry, event groups,
details/divisions, explicit refresh, direct-route reload, browser back/forward,
narrow/wide layouts, and console inspection. Browser-level network interruption
was unavailable, so the recoverable network state is verified by deterministic
widget tests but not claimed as a completed manual browser check.

## Known limitations and deferred work

- The public projection has only fields supported by M2/M3: name, lifecycle,
  one scheduled UTC time, event type, court label, optional fee, and divisions.
  There is no fabricated description, date range, or division status.
- M6 has explicit refresh but no event/division Realtime subscription.
- Android cache reconciliation is safe before organizer event editing exists;
  event pending-intent/conflict integration must precede later organizer writes.
- There is no Web offline data store or PWA data synchronization.
- M7 still owns accounts, roles, and player claiming. All twelve recorded
  product decisions remain open.
- No organizer workflow, participant/payment UI, tournament engine, scoring,
  standings, deployment, or release work is present.

Future Me should study `public_event_models.dart`, `public_event_reader.dart`,
`public_event_readers.dart`, `supabase_public_event_source.dart`,
`drift_public_event_cache.dart`, `public_event_providers.dart`,
`public_events_controller.dart`, `app_router.dart`, the M6 seed migration, and
their tests first.
