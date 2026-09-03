# M13 — Single Elimination

Status: COMPLETED. Automated/hosted validation and user-performed Android/Web
walkthroughs passed. M14 remains NOT STARTED.
Baseline: `768f7b8b1ef376a07bcc023e0a318a8eccd068d3`.
Branch: `milestone/m13-single-elimination`.

## Rules and boundaries

The pure generator uses M12 canonical TeamId ordering or explicit organizer
seed order. Recursive placement expands each seed x into x, 2S+1-x until the
smallest power-of-two bracket contains all teams. Adjacent positions pair.
Unoccupied seeds are visual BYEs; the sole team advances without a played
match, score or statistical win. Only N-1 real matches are persisted. Planned
keys are deterministic (`se/rN/mN`); confirmation assigns persistence UUIDs.
Preview writes nothing. Draft regeneration requires Registration with no
started/scored match and explicit confirmation, retaining previous tombstones.

Stored states remain scheduled → queued (Ready) → inProgress → completed.
Starting a ready match is explicit. M12 final-score validation derives the
winner; only the winner advances. Final placements are champion and runner-up.
OPEN-004 is resolved by V1-078 in [decisions](../DECISIONS.md): corrections have
immutable revisions, a required reason, optimistic versions and an unstarted
downstream boundary. No rewind/override exists.

The bracket renders round columns, positioned matchup cards and painted
connectors, with horizontal scrolling on phones. BYE/TBD, seed, state, score,
winner and final placements are displayed. Public reads require no account.
Only organizers receive mutation actions. M14 round robin, M15 double
elimination and M16 queue/scheduling remain unimplemented.

## Persistence and platform paths

Android Drift schema 7 adds single_elimination_snapshots,
single_elimination_outbox, single_elimination_checkpoints and
match_result_revisions. Existing matches/dependencies/placements are reused.
The real v6→v7 migration preserves earlier records. Generation, result,
progression, audit and outbox writes share a transaction. Pending work is not
cloud success. Pull imports authoritative rows without enqueueing mutations;
protected pending work prevents checkpoint advancement. No automatic conflict
resolution is authorized.

Web uses the initialized Supabase client and fixed RPC commands online; it
does not open SQLite. The public context excludes account/payment information;
audit revisions are organizer-only. Direct client writes to match records are
revoked in favor of validated organizer commands. Realtime is a debounced
public bracket refresh hint, never authoritative row input.

## Hosted repair record

- Already applied and preserved: `20260904130000_m13_single_elimination.sql`.
- Unapplied assertions renamed without content changes from
  `20260904130500_assert_m13_single_elimination.sql` to
  `20260904131500_assert_m13_single_elimination.sql`.
- Repair: `20260904131000_repair_m13_correction_dependency.sql` replaces only
  apply_single_elimination_operation. The PL/pgSQL record is dependency_row;
  recursive and loop SQL use md rather than the colliding dep alias. Safe
  search_path, authority, versions, audit, transactions and grants are retained.
- Additional regression: `20260904132000_assert_m13_correction_regression.sql`.

Dry runs and application passed. Local/remote histories agree through 132000.
The original schema was not rewritten. The repair's first attempt accidentally
included an existing function declaration and failed transactionally; its
unapplied contents were narrowed to the intended replacement before successful
application. No applied migration was edited.

Hosted rollback-only synthetic assertions passed: 2–8-team generation,
pre-downstream correction and corrected winner advancement, rejection after
downstream start/completion, audit preservation/immutability, corrected final
placements, unauthorized/stale rejection, identical replay and changed-payload
rejection. No test fixtures or receipts remain from these transactions.
Linked lint passed its error threshold, reporting a text-to-jsonb initialization
warning and an unused/shadowed integer loop variable; no security rules were
weakened. These are not claimed as warning-free lint.

## Validation and acceptance

Flutter dependencies were resolved without upgrades. Drift generation, schema
dump and migration-helper generation ran. Focused engine/persistence/migration
tests passed (34 including existing migration/schema regressions), plus two
responsive bracket tests. The final full suite passed all 275 tests; formatting and
static analysis passed. Repeated generation/export completed with unchanged
hashes for the generated database, v7 snapshot and migration helpers.
Web production build and Android debug APK passed at build/web and
build/app/outputs/flutter-apk/app-debug.apk. Anonymous hosted public
reads and private-table/mutation denial passed. Relative links, credential scan,
git diff --check and git diff --cached --check passed. No dependency upgrade.
Build warnings: missing optional Cupertino font and older Android SDK XML
parser. Neither blocked its build. Docker is installed but its Linux daemon is
unavailable, so local pgTAP did not run. No remote CI run is claimed.

Commands follow the existing [testing guide](../TESTING.md): flutter pub get;
dart run build_runner build; dart run drift_dev schema dump
lib/src/infrastructure/persistence/local/app_database.dart drift_schemas;
dart run drift_dev schema generate drift_schemas test/generated_migrations;
dart format --output=none --set-exit-if-changed .; flutter analyze; flutter test;
flutter build web; flutter build apk --debug.

Mandatory Android and Web walkthroughs were confirmed passed by the user.
During the walkthrough, the user verified the two-team Final
preview. A disappearing preview notice was traced to successful background
refresh clearing transient messages. The notice now derives from preview state
and remains above the bracket. A focused widget regression passed for manual
and periodic refresh with zero persistence writes; final full validation was
rerun after walkthrough fixes.

The user also requested a bounded add-participant picker correction during the
walkthrough: active event participants are hidden by permanent PlayerId, not
display name. Registered entries do not break directory page continuation;
roster-read failures expose no unverified candidates. Existing registration
duplicate checks and server constraints remain unchanged. Two focused picker
tests cover filtering/search/page continuation and fail-closed roster reads.

Further user-confirmed checks: two-team generation, final result and reversed
final correction with champion/runner-up swap, Web reconciliation and guest
read-only display; three-team top-seed bye/reordering, Android offline generation
surviving restart, reconnect reconciliation, winner advancement, and correction
replacing the finalist before downstream play.

The downstream-start rejection walkthrough exposed a score-dialog lifecycle
crash: parent-owned text controllers were disposed before the dialog exit
animation unmounted its fields. The dialog now owns and disposes its controllers
with its route. A focused widget regression covers immediate rejection, animated
exit, reopening and cancellation. That test and all 15 Single Elimination domain
tests pass together (16 tests). The correction policy is unchanged; physical
retesting subsequently confirmed rejection after downstream start without a crash.

Subsequent user confirmations cover downstream-start correction rejection after
the dialog fix, offline final result/pending persistence across restart and
reconciliation to Web, and four- and five-team previews. The eight-team preview
rendered correctly on Android and Web, but Web lacked a discoverable horizontal
control. The bracket now has an explicit top scrollbar and Earlier/Later rounds
buttons when it exceeds the viewport; phone swipe scrolling is retained. Three
focused tests pass for navigation/disposal and narrow/wide large-text rendering.
Manual Web scrollbar and Earlier/Later controls were subsequently confirmed passed.

The user's final categorized confirmation covers Web organizer confirmation,
draft regeneration and its post-start lock, results/correction and online-only
failure behavior; member mutation denial; direct reload and browser/system-back
navigation; larger text, keyboard controls, no visible/console errors, and
Android reopening without USB. Earlier confirmations cover 2/3/4/5/8-team
previews, byes, final placements, allowed/blocked corrections, Android offline
generation and result persistence/restart/reconnect, and matching Web results.
These are user-performed manual results, not automated browser assertions.

Seed-list reordering is a device-local draft until generation/regeneration is
confirmed. Refreshing another device does not copy an unconfirmed ordering list.
The confirmed bracket persists its seed order and synchronizes; the user
explicitly confirmed the generated bracket was correct across devices.

Final validation: pub get, 220-file formatting verification, analyze, all 275
tests, Web production build, Android debug APK, build_runner, Drift dump and
migration helper generation passed. SHA256 comparison confirmed all existing
generated sources/snapshots unchanged after regeneration. Linked migration
history agrees, dry-run reports no pending migrations, and linked lint passes
the error threshold with the three warnings already recorded above. Anonymous
public reads/private-data isolation and command denial were rechecked without
creating records. Hosted authenticated correction/security assertions are the
successful rollback-only migration runs described above; user-confirmed manual
organizer/member tests supplement those runs. Local pgTAP remains skipped because
Docker's Linux engine pipe is unavailable. No remote CI run is claimed.

Documentation-link and credential-pattern scans passed. Package manifests and
lockfile are unchanged; Android ID remains com.voltapaddleclub.vpc, Android/Web
are the only application platforms, and Web's provider boundary returns no
local database. Generated build/cache outputs and personal data are excluded.

## Files to study first

- lib/src/domain/tournament/single_elimination_generator.dart
- lib/src/domain/tournament/single_elimination_bracket.dart
- lib/src/application/tournament/single_elimination_service.dart
- lib/src/infrastructure/tournament/
- lib/src/presentation/tournament/
- supabase/migrations/20260904131000_repair_m13_correction_dependency.sql
- test/domain/tournament/single_elimination_test.dart
- test/infrastructure/tournament/bracket_repository_test.dart

No dependencies were added. No release, push, merge, M14+ implementation or
real community fixture creation is authorized by this record.
