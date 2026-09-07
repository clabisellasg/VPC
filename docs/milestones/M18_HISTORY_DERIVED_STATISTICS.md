# M18 — Tournament History and Statistics

## Scope

M18 derives public player history from current operational records. It does not
store editable career counters, rankings, payment data, account identity, or
private synchronization metadata. The authoritative inputs are active
completed matches, active team memberships, checked-in event participation,
and active division placements.

## Definitions

Matches, wins, losses, points for/against, and differential use the current
completed match result only. A corrected result replaces its prior value;
revision/audit rows and byes never count. A zero-match player has a `0%` win
rate. Event appearances are distinct completed/archived checked-in events;
division appearances are distinct divisions with an active team appearance.
Champion and runner-up counts use active positions 1 and 2 respectively.

Partners are unordered pairs of permanent player IDs within a completed active
team. Their matches, wins, losses, and rate use the same current-match rules.

## Platform boundaries

Android derives the read model from its synchronized Drift operational rows and
does not create a statistics outbox or duplicated totals. Web uses the fixed
public `read_public_player_history` function and never initializes SQLite. The
function exposes only public player/event/division/team/match/placement labels;
it does not expose payments, profiles, roles, claims, Auth IDs, or receipt data.

## Validation and manual acceptance

The fixed public function was applied as migration `20260907180000`; linked
migration history agrees and database lint adds no M18 error. Focused history
and profile tests, analysis, Android packaging, and the regression suite were
exercised before manual testing. The user confirmed Android and Web categories
A–E on 2026-09-08, including online totals, zero history, cached offline
reading, cross-platform comparison, privacy, responsive text, navigation, and
USB-independent restart.

## Known limitations and M19 boundary

History is intentionally bounded to its first public page in the M18 UI. M18
adds no global ranking, opponent head-to-head analysis, achievement system, or
editable historical correction UI. M19 owns deployment and iPhone/PWA parity.

Future maintainers should begin with:

- `lib/src/application/history/player_history_models.dart`
- `lib/src/application/history/player_history_calculator.dart`
- `lib/src/infrastructure/history/drift_player_history_reader.dart`
- `lib/src/infrastructure/history/supabase_player_history_reader.dart`
