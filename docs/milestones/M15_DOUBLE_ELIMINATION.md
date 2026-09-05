# M15 — Double Elimination

Status: COMPLETED. Automated and hosted validation passed, and the user
confirmed the mandatory physical Android and Web walkthroughs.
Baseline: `04ba0e0699776625bf774d68bef7d047366e205c`.
Branch: `milestone/m15-double-elimination`.

## Rules and bracket model

M15 implements only `DOUBLE_ELIMINATION`. Generation uses M12 canonical team
ordering, M13 recursive seed placement, deterministic planned keys, and staged
loser routing. Winners advance through the Winners bracket; each played loser
drops into the correct Losers round, and a second actual loss eliminates the
team. Non-power-of-two inputs advance BYEs without fake teams, played matches,
scores, wins, or losses. Preview is memory-only and protected progress prevents
regeneration.

V1-080 resolves OPEN-006 with a grand-final reset. Grand Final 1 ends the
tournament when the undefeated Winners finalist wins. A win by the
once-defeated Losers finalist activates deterministic Grand Final 2, which then
decides champion and runner-up. The reset is visible as “if necessary” but no
fake played reset Match is persisted when it is unnecessary. Expected played
match totals are `2N - 2` without reset and `2N - 1` with reset.

M12 score validation remains one game to 11, win by two, no cap. Result entry
derives winner/loser and unlocks only fully resolved matches. M13 correction
rules remain authoritative: an In Progress organizer supplies a reason, prior
results become immutable revisions, and every affected downstream match must
remain unstarted. Corrections traverse winner and loser routes, recompute reset
state and placements atomically, and never rewind played downstream matches.

## Persistence, security, and synchronization

Drift schema 9 adds double-elimination snapshot, outbox, and checkpoint tables
through a v8-to-v9 migration while reusing matches, dependencies, placements,
and result revisions. Android mutations and outbox intent commit atomically,
survive restart, reconcile authoritatively, and preserve conflicts. Web uses
the same application contract through online Supabase RPCs and never opens
SQLite.

Hosted migrations are append-only:

- `20260905150000_m15_double_elimination.sql` adds the aggregate schema and
  fixed functions.
- `20260905150600_repair_m15_version_guard.sql` through
  `20260905150900_repair_m15_version_diagnostics.sql` safely replace version
  validation without rewriting the applied schema migration.
- `20260905151000_assert_m15_double_elimination.sql` runs rollback-only
  authorization, idempotency, progression, reset, placement, correction, and
  audit assertions.
- `20260905151500_preserve_m15_reset_match_identity.sql` preserves the
  deterministic reset-match ID in cloud context responses and legacy queued
  Android payload reconciliation.

The correction failure was traced without weakening security. The final helper
selects stored versions explicitly and reports the conflicting expected/stored
values. Public reads contain tournament/team information only. Anonymous and
ordinary-member writes are denied; the fixed command verifies organizer role,
format, lifecycle, scope, scores, source slots, optimistic versions, reset
state, and replay identity. Functions use a fixed safe search path and expose
no arbitrary table control. No service-role key is used by Flutter.

## User experience and platform boundary

Organizer and public routes render separate Winners, Losers, and Grand Finals
areas with team labels, state, scores, BYEs/TBD slots, reset-final explanation,
and champion/runner-up. Wide and narrow layouts support horizontal bracket
scrolling. Organizers may reorder preview seeds, confirm generation, start
Ready matches, submit scores, and request permitted corrections. Guests and
members remain read-only.

Android supports deterministic offline preview, confirmed persistence, result
entry, restart, pending status, and later idempotent convergence. Web requires
online cloud acceptance and never initializes local persistence. Realtime is a
debounced refetch hint, not tournament authority.

## Validation and known limitations

The hosted schema and follow-up repair/assertion migrations applied to the
linked project. Local/remote history agrees through `20260905151500`; linked
lint reports no errors. The assertion transaction rolls back its deterministic
fixtures. Docker's Linux engine is unavailable, so local pgTAP cannot run and
the hosted rollback assertions provide database coverage.

Formatting and static analysis are clean, all 329 Flutter tests pass, and both
the Web production build and Android debug APK build succeed. Repeated Drift
helper generation and build-runner generation produce unchanged v9 artifacts.
Anonymous hosted reads return 200 for the bracket projection; profile, role,
payment, and mutation requests return 401. Mandatory physical Android/Web
walkthroughs passed, including both grand-final outcomes, reset activation,
BYEs, winner/loser progression, correction rules, offline restart and
reconnect, guest read-only access, responsive scrolling, and cross-device
convergence. The direct Drift schema dump repeated the known Windows
build-hook stall; the committed v9 snapshot stayed unchanged and its migration
tests passed. M15 provides no Double Round Robin changes, court assignment,
queue, scheduling optimization, or M16+ functionality. M16 owns the one-court
Now Playing and Up Next workflow.

Files to study first:

- `lib/src/domain/tournament/double_elimination_generator.dart`
- `lib/src/domain/tournament/double_elimination_bracket.dart`
- `lib/src/application/tournament/double_elimination_service.dart`
- `lib/src/infrastructure/tournament/drift_double_elimination_repository.dart`
- `lib/src/infrastructure/tournament/double_elimination_synchronizer.dart`
- `lib/src/presentation/tournament/double_elimination_page.dart`
- `supabase/migrations/20260905150000_m15_double_elimination.sql`
