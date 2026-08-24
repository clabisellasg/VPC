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

## Open decisions

The “resolve by” milestone is the latest point at which an explicit accepted
decision is required before affected implementation proceeds.

| ID | Open question | Resolve by | Status |
| --- | --- | --- | --- |
| OPEN-001 | How is a claim to an existing player verified or approved? | Before M7 implementation | OPEN |
| OPEN-002 | What player skill scale is approved for balanced team generation? | Before M11 implementation | OPEN |
| OPEN-003 | What are the exact score validation rules? | Before M12 implementation | OPEN |
| OPEN-004 | How may a completed result be corrected after bracket progression? | Before M13 implementation | OPEN |
| OPEN-005 | What is the round-robin tie-breaker order? | Before M14 implementation | OPEN |
| OPEN-006 | Does double elimination use a grand-final bracket reset? | Before M15 implementation | OPEN |
| OPEN-007 | May one player join multiple divisions in the same event? | Before M10 implementation | OPEN |
| OPEN-008 | Is payment status event-wide, or may it differ by division? | Before M10 implementation | OPEN |
| OPEN-009 | What is the exact simultaneous-organizer conflict/control policy? | Before M5 implementation | OPEN |
| OPEN-010 | Which free static hosting provider will serve the Flutter Web/PWA? | Before M19 implementation | OPEN |
| OPEN-011 | Which authentication methods are enabled in Version 1? | Before M3 implementation | OPEN |
| OPEN-012 | Is Version 1 team size fixed at two or configurable? | Before M11 implementation | OPEN |

## Explicitly approved changes

No changes to the accepted Version 1 baseline have been approved. Future
entries must record a stable ID, approval date, approving authority, affected
requirements, and resulting documentation updates.

## Future-version suggestions

There are no approved or planned future-version suggestions in Milestone 0.
Ideas may be recorded here later only as non-committed suggestions. They must
not be described as Version 1 scope or implemented without separate approval.
