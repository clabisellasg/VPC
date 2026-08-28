# M07 — Accounts, Roles, and Player Claiming

## Goal and scope

Milestone 7 adds optional Supabase email/password accounts, private account
profiles, server-authoritative member/organizer presentation, and an auditable
request-and-organizer-approval link to an existing permanent player. M6 guest
events remain available without authentication. M7 adds no player editing,
organizer event administration, tournament engine, new synchronization slice,
or M8 functionality.

## Authentication and session behavior

Pure-Dart `AuthUser`, `AuthSessionState`, `AuthFailure`, and `AuthRepository`
contracts contain no Supabase type and expose no access or refresh token. The
production adapter uses the single initialized Supabase client for:

- email/password registration;
- hosted confirmation-required results;
- email/password sign-in and sign-out;
- persisted-session restoration and live Auth state changes;
- current-user refresh and redacted expected failures.

Supabase Flutter owns secure session persistence and PKCE callback processing;
the application does not manually persist or log tokens. Registration and
sign-in require connectivity. An unconfigured build remains valid for public
browsing and reports an honest Account state.

Hosted email confirmation is enabled. The project allow-list contains:

- Android: `com.voltapaddleclub.vpc://auth-callback/account/confirm`
- Local Web: `http://localhost:7357/account/confirm`
- Local Web loopback: `http://127.0.0.1:7357/account/confirm`

The Android manifest accepts only the application scheme, `auth-callback`
host, and `/account/confirm` path prefix. Web uses its current origin plus that
path. Unknown or expired callbacks show safe guidance and never display URL
fragments, codes, or tokens.

## Private profile and authorization

`user_profiles` now has an optional unique `player_id`. It is the private link
to the existing public `players` record. Account email stays in Supabase Auth;
public players contain no Auth user ID or email. No private profile, role, or
claim table is mirrored into Android SQLite.

An Auth-user trigger creates a minimum profile. A valid bounded
`display_name` from signup metadata may initialize the account-facing name;
invalid/missing metadata falls back to `Community member` and never grants a
role or player link. Members can update only their own display-name column and
cannot update `player_id`, metadata, tombstones, or roles.

The account snapshot maps authorization to guest, member, organizer, or
unavailable. Active `user_roles(role = 'organizer')` rows and PostgreSQL RLS/
functions remain authoritative. Flutter state controls presentation only.

## Trusted organizer bootstrap and revocation

M7 creates no organizer automatically and exposes no role-write endpoint.
After the intended Auth account exists, a trusted operator uses the linked
Supabase SQL Editor with the parameterized insert in
[OPERATIONS.md](../OPERATIONS.md). No real UUID or email belongs in a committed
migration. Revocation tombstones that exact role row through the documented
trusted SQL. The result is verified through a normal authenticated client.

## Claim lifecycle and atomic review

`PlayerClaimStatus` and PostgreSQL accept only `pending`, `approved`,
`rejected`, and `cancelled`. A member searches public unclaimed players,
requests one existing record with a client-generated UUID, reads their own
claim, and may cancel only while pending. Claims require connectivity and are
not placed in the M5 outbox.

An organizer can list pending claims with only claimant display name and public
player name. Approval is one transactional `SECURITY DEFINER` function with an
empty search path. It verifies current organizer authority, locks the request,
profile, and player, confirms pending state and both uniqueness conditions,
links `user_profiles.player_id`, records reviewer/time, and returns the
authoritative claim. Unique indexes provide a final concurrency guard.
Rejection records reviewer/time and an optional bounded reason without changing
the player or profile link. Client roles have no claim-table insert/update/
delete grant and cannot directly approve or link.

## Application routes and UI

M6 `/`, `/events`, and `/events/:eventId` routes remain public. M7 adds:

- `/account`
- `/account/sign-in`
- `/account/register`
- `/account/confirm`
- `/account/claim`
- `/organizer/claims`

The shared responsive shell adds Account as its only new destination. Protected
claim/review pages redirect signed-out users without flashing protected data.
Forms include validation, keyboard/autofill behavior, password visibility,
duplicate-submit protection, cleared password controllers, accessible labels,
safe errors, and confirmation guidance. There is no role-management, player-
editing, password-recovery, or tournament-administration screen.

## Android, Web, and M5 synchronization

Android keeps the M6 cached public-event behavior. A persisted valid Auth
session may restore while temporarily offline, but role and claim state reports
unavailable rather than claiming offline authority. Claim submission/review and
new sign-in require the network.

Web remains online-first and never initializes SQLite. Direct account routes
remain in GoRouter and use the same Supabase/Auth contracts.

M7 does not expand synchronization. After session restoration, a private cloud
snapshot confirms the current role. Only an organizer starts the existing M5
player runtime. Member, guest, unavailable, and sign-out states invalidate and
dispose it. PostgreSQL still authorizes every apply/pull call, and rejected
operations remain pending.

## Synthetic fixture

Two explicit data migrations provide separate deterministic manual fixtures:

- `20260828181000_m07_claim_test_fixture.sql` inserts
  `73000000-0000-4000-8000-000000000001`, named
  `M7 Synthetic Claim Player` for Web validation.
- `20260828181500_m07_android_claim_test_fixture.sql` inserts
  `73000000-0000-4000-8000-000000000002`, named
  `M7 Android Synthetic Claim Player` for physical-device validation.

They contain no contact, account, role, payment, or real community data.
Removal must be a later reviewed data migration after each fixture's exact
private links and claim history are safely cleared; never delete by display-name
pattern.

## Safe run and validation commands

Supply the publishable client pair only from private local environment values:

```powershell
flutter run -d chrome --web-port 7357 `
  "--dart-define=SUPABASE_URL=$env:VPC_SUPABASE_URL" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$env:VPC_SUPABASE_PUBLISHABLE_KEY"

flutter run -d <android-device-id> `
  "--dart-define=SUPABASE_URL=$env:VPC_SUPABASE_URL" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$env:VPC_SUPABASE_PUBLISHABLE_KEY"
```

Never use a service-role/secret key in Flutter. Automated checks are:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
npx --yes supabase@2.115.0 migration list --linked
npx --yes supabase@2.115.0 db lint --linked --fail-on error
git diff --check
```

The retained pgTAP suite contains 22 M7 assertions. Docker's executable exists
but its engine was unavailable, so local SQL tests were not run. Deployment
assertions and hosted smoke checks are recorded separately; neither is falsely
reported as a local pgTAP pass.

Final validation on 2026-08-28 produced these results:

- dependency resolution passed with the committed lock file unchanged;
- formatting verification and `flutter analyze` passed;
- all 132 Flutter tests passed;
- `flutter build web` produced `build/web`;
- `flutter build apk --debug` produced
  `build/app/outputs/flutter-apk/app-debug.apk`;
- linked migration history matched through `20260828181500`, the hosted
  dry-run was up to date, and database lint reported no schema errors;
- anonymous events/divisions reads returned `200`; profile, role, claim,
  official-write, and claim-RPC attempts returned `401`;
- both synthetic player IDs resolved to exactly one public row and exposed no
  Auth identifier or email field.

## Manual acceptance

The physical Android walkthrough passed on an Android 14 phone. It verified
guest access, registration,
confirmation callback, sign-in/restoration, private account and member state,
claim submission, organizer review, authoritative result/link, no duplicate
player, offline honesty, reconnect, and installed-app reopen without USB.

The Web walkthrough passed against the configured local Web build. It verified
the same guest/account/claim/review boundaries,
callback, refresh restoration, direct routes, browser history, responsive
layout, console cleanliness, and absence of SQLite.

## Known limitations and M8 boundary

- Email/password is the only enabled application flow. Google, Apple, phone,
  anonymous, magic-link, OTP, social providers, password recovery, MFA,
  account deletion, and identity linking are not implemented.
- Organizer assignment/revocation remains a trusted administrative operation.
- Profiles, roles, and claims require cloud access and have no offline queue.
- The claim workflow does not edit, create, merge, or deduplicate permanent
  players. Search, creation, duplicate warnings, and full player profiles are
  M8.
- No event/tournament organizer workflow, payment UI, or broader sync protocol
  is introduced.

Future Me should study `auth_models.dart`, `auth_repository.dart`,
`account_models.dart`, `player_claim_repository.dart`,
`supabase_auth_repository.dart`, `supabase_player_claim_repository.dart`,
`auth_controller.dart`, `account_controller.dart`, the account presentation
pages, `app_router.dart`, the four M7 migrations, and their tests first.
