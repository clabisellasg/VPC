# Decision Register

Stable decision IDs are never reused. An `OPEN` entry is a question, not a
recommendation or accepted design. It moves to another section only after
explicit planner/architect approval, with the approval and date recorded.

## Accepted Version 1 decisions

| ID | Decision | Status |
| --- | --- | --- |
| V1-001 | Use Flutter and Dart for a shared Android and Web/PWA application. | ACCEPTED |
| V1-002 | Android Flutter-generated APK is primary, offline-first, and uses SQLite for important organizer operations. | ACCEPTED |
| V1-003 | Supabase provides the shared backend: Authentication, PostgreSQL, RLS, database functions, and Realtime where appropriate. | ACCEPTED |
| V1-004 | iPhone uses an online-first Flutter Web/PWA through Safari; authenticated organizers may manage tournaments while online. | ACCEPTED |
| V1-005 | Players are permanent reusable records; accounts are optional, and an approved later claim links to the existing record without losing history. | ACCEPTED |
| V1-006 | Teams are temporary and scoped to an event/division. | ACCEPTED |
| V1-007 | Organizer authority is an authenticated role/permission; guests have public read-only access. | ACCEPTED |
| V1-008 | Record only Paid/Unpaid status and totals; do not process payments. | ACCEPTED |
| V1-009 | Version 1 formats are Single Elimination, Double Elimination, Single Round Robin, and Double Round Robin only. | ACCEPTED |
| V1-010 | Team formation is manual, random, or simple balanced using approved skill information; it does not use AI. | ACCEPTED |
| V1-011 | Event lifecycle is `UPCOMING` → `REGISTRATION` → `IN PROGRESS` → `COMPLETED` → `ARCHIVED`. | ACCEPTED |
| V1-012 | Android local writes and their outbox operations are atomic; synchronization is idempotent and Supabase is the shared convergence point. | ACCEPTED |
| V1-013 | Realtime is a change/refetch signal, not the source of truth. | ACCEPTED |
| V1-014 | Completed event history is preserved, and finalized match records are the source for match-derived statistics where practical. | ACCEPTED |
| V1-015 | Individual statistics and temporary-partner statistics are separate. | ACCEPTED |
| V1-016 | Prominently support a one-court Now Playing and Up Next workflow. | ACCEPTED |
| V1-017 | Version 1 uses Git/GitHub and free-tier infrastructure only. | ACCEPTED |
| V1-018 | Version 1 excludes payment integrations, native iPhone distribution/offline support, AI features, communication/social features, complex rankings, badges, opponent head-to-head statistics, push notifications, and extra tournament formats. | ACCEPTED |
| V1-019 | The permanent display name is Volta Paddle Club. | ACCEPTED |
| V1-020 | The Flutter/Dart package name is `vpc`. | ACCEPTED |
| V1-021 | The Android namespace and application ID are `com.voltapaddleclub.vpc`. | ACCEPTED |
| V1-022 | Android and Web are the only generated Flutter platforms in Version 1; iPhone access uses Flutter Web/PWA. | ACCEPTED |
| V1-023 | Riverpod is the state-management and dependency-injection foundation; it does not replace the repository/outbox synchronization architecture. | ACCEPTED |
| V1-024 | GoRouter is the declarative routing foundation for Android and Web. | ACCEPTED |
| V1-025 | Runtime environment selection uses compile-time `--dart-define=APP_ENV=<value>`, supporting `development`, `test`, and `production` with `development` as the default. | ACCEPTED |
| V1-026 | The Milestone 1 SDK baseline is Flutter `3.47.1` stable with Dart `3.13.1`. | ACCEPTED |
| V1-027 | Domain entity identifiers are nominal types backed by validated lowercase canonical UUID strings; ID generation is outside Milestone 2. | ACCEPTED |
| V1-028 | Money is represented by nonnegative integer minor units and a three-letter ISO-style currency code, defaulting to PHP where needed; domain money never uses `double`. | ACCEPTED |
| V1-029 | Domain record timestamps are caller-supplied UTC values, record versions are nonnegative, and optional deletion is represented by a UTC tombstone. | ACCEPTED |
| V1-030 | Domain entities are immutable and expose no externally mutable entity collections. | ACCEPTED |
| V1-031 | The domain boundary is pure Dart and has no Flutter, routing, state-management, storage-provider, network, or platform dependency. | ACCEPTED |
| V1-032 | Repository interfaces are provider-neutral ports and expose typed domain records, queries, results, and failures rather than provider or platform types. | ACCEPTED |
| V1-033 | Derived player statistics are not stored as manually maintained counters; finalized match records remain their practical source of truth. | ACCEPTED |
| V1-034 | Use the existing Supabase `vpc` project in Northeast Asia (Tokyo), region code `ap-northeast-1`; do not recreate or migrate it for Version 1. | ACCEPTED |
| V1-035 | Supabase schema, grants, RLS, database helpers, and Realtime publication changes are managed by reviewed official-CLI migrations committed under `supabase/`. | ACCEPTED |
| V1-036 | Auth users, private profiles, and normalized role rows remain separate from guest-readable permanent player records; an active `organizer` role row grants organizer permission. | ACCEPTED |
| V1-037 | Flutter Supabase client configuration uses paired compile-time `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` values; both absent is valid and partial configuration is rejected. | ACCEPTED |
| V1-038 | Only public community/tournament tables enter the Realtime publication; profiles, roles, and payments remain excluded, and Realtime stays a refetch signal. | ACCEPTED |
| V1-039 | A Supabase service-role or secret key must never be embedded in Flutter, committed, logged, or used for client operations. | ACCEPTED |
| V1-040 | Drift is the typed Android SQLite access layer; the M4 baseline resolves `drift 2.34.3`, `drift_flutter 0.3.1`, `path_provider 2.1.6`, `drift_dev 2.34.5`, and `build_runner 2.16.0`. | ACCEPTED |
| V1-041 | Production local persistence exists only on Android, stores `vpc.sqlite` in the application-support directory, and runs through Drift's background shared isolate; Web and other native platforms do not open it. | ACCEPTED |
| V1-042 | Local schema version 1 uses ISO-8601 text for UTC timestamps to preserve sub-second precision and text UUID columns revalidated by M2 nominal ID constructors. | ACCEPTED |
| V1-043 | Drift generated Dart and the version-one JSON schema snapshot are committed and checked for freshness; no fictional pre-version-one migration is created. | ACCEPTED |
| V1-044 | Production Drift adapters implement the unchanged M2 player, event, and match ports, exclude tombstones from ordinary reads, use optimistic versions, and translate expected constraints into typed failures. | ACCEPTED |
| V1-045 | M5 proves synchronization with permanent players only; extension to the other operational records remains later work and must preserve entity dependencies. | ACCEPTED |
| V1-046 | Android local schema version 2 stores durable outbox operations, pull checkpoints, and conflicts in separate tables rather than adding dirty/sync columns to every domain table. | ACCEPTED |
| V1-047 | Player cloud mutations use a fixed, organizer-guarded PostgreSQL function with private operation receipts so identical operation-ID replays are idempotent and changed-payload reuse is rejected. | ACCEPTED |
| V1-048 | M5 detects and preserves version conflicts without choosing local-wins, remote-wins, or a product-level conflict-resolution policy. | ACCEPTED |
| V1-049 | Player Realtime notifications are debounced refresh hints that invoke an authoritative checkpointed pull; notification payloads are never written directly to SQLite. | ACCEPTED |
| V1-050 | M6 public event grouping follows lifecycle status: `upcoming` is upcoming, `registration`/`inProgress` are current, and `completed`/`archived` are completed; UTC dates are supporting display data. | ACCEPTED |
| V1-051 | Public guest widgets use a provider-neutral read port; Web reads anonymous Supabase data online, while Android may reconcile the same event/division projection into its existing Drift tables without creating outbox work. | ACCEPTED |
| V1-052 | M6 public refresh is explicit and authoritative; event/division Realtime subscriptions are deferred and any future subscription remains a refetch hint. | ACCEPTED |
| V1-053 | Deterministic `VPC Demo` event/division rows may reside in the hosted project as clearly labeled, removable, non-personal public fixtures for M6 device verification. | ACCEPTED |
| V1-054 | Version 1 initially uses Supabase email/password authentication; hosted email confirmation remains enabled, while password recovery and other providers are deferred. | ACCEPTED |
| V1-055 | Player claiming uses a request-and-organizer-approval workflow; approval atomically links the private account profile to one existing permanent player. | ACCEPTED |
| V1-056 | The account-to-player link is private `user_profiles.player_id`; public `players` rows contain no Auth user ID or email, and accounts never replace permanent players. | ACCEPTED |
| V1-057 | Organizer roles are normalized server-side permissions assigned or revoked only through trusted database administration; Flutter cannot assign roles and PostgreSQL RLS/RPC authorization remains authoritative. | ACCEPTED |
| V1-058 | M7 confirmation callbacks use `/account/confirm` on Web and `com.voltapaddleclub.vpc://auth-callback/account/confirm` on Android. | ACCEPTED |
| V1-059 | Only a currently authenticated account whose role is confirmed by the cloud as organizer starts the M5 player synchronization runtime; guest/member/sign-out states stop it. | ACCEPTED |

## Open decisions

The “resolve by” milestone is the latest point at which an explicit accepted
decision is required before affected implementation proceeds.

| ID | Open question | Resolve by | Status |
| --- | --- | --- | --- |
| OPEN-002 | What player skill scale is approved for balanced team generation? | Before M11 implementation | OPEN |
| OPEN-003 | What are the exact score validation rules? | Before M12 implementation | OPEN |
| OPEN-004 | How may a completed result be corrected after bracket progression? | Before M13 implementation | OPEN |
| OPEN-005 | What is the round-robin tie-breaker order? | Before M14 implementation | OPEN |
| OPEN-006 | Does double elimination use a grand-final bracket reset? | Before M15 implementation | OPEN |
| OPEN-007 | May one player join multiple divisions in the same event? | Before M10 implementation | OPEN |
| OPEN-008 | Is payment status event-wide, or may it differ by division? | Before M10 implementation | OPEN |
| OPEN-009 | What is the exact simultaneous-organizer conflict/control policy? | Before M5 implementation | OPEN |
| OPEN-010 | Which free static hosting provider will serve the Flutter Web/PWA? | Before M19 implementation | OPEN |
| OPEN-012 | Is Version 1 team size fixed at two or configurable? | Before M11 implementation | OPEN |

## Explicitly approved changes

| ID | Approval | Result | Status |
| --- | --- | --- | --- |
| OPEN-001 | M7 planner specification, 2026-08-28 | Resolved by V1-055: an authenticated member requests an existing player link and an organizer approves or rejects it. | RESOLVED |
| OPEN-011 | M7 planner specification, 2026-08-28 | Resolved by V1-054: initial V1 authentication is email/password with hosted confirmation preserved. Other providers remain deferred, not accepted. | RESOLVED |

## Future-version suggestions

There are no approved or planned future-version suggestions in Milestone 0.
Ideas may be recorded here later only as non-committed suggestions. They must
not be described as Version 1 scope or implemented without separate approval.
