# M14 — Single and Double Round Robin

Status: COMPLETED. Automated and hosted validation passed, and the user
confirmed mandatory Android and Web walkthrough categories A–F. M15 remains
NOT STARTED.
Baseline: `977c0c9af151cd19f1c3930536febc7a38ab500a`.
Branch: `milestone/m14-round-robin`.

## Schedule and standings rules

The pure Dart circle method uses explicit organizer order or stable TeamId
order. Single Round Robin produces N(N−1)/2 matches across N−1 even-team or N
odd-team rounds. Double Round Robin repeats that deterministic first leg,
reverses displayed sides, and produces N(N−1) matches. Odd inputs use an
internal BYE only: no Match, win, loss, score, or point is created; the resting
team is shown for that round. All playable matches begin Ready and have no
winner/loser dependencies.

Standings derive played, wins, losses, points for/against, and differential
only from active completed Match records. V1-079 resolves OPEN-005 in this
order: wins; mini-table wins among the remaining tied group; mini-table point
differential among the still-tied group; overall differential; points scored;
original seed. Both meetings count in Double Round Robin. The same inputs
always produce the same schedule and ranking.

The M12 one-game-to-11, win-by-two, no-cap rule remains authoritative. An In
Progress organizer may correct a completed result with a non-empty reason;
the previous row is immutable audit history and standings/placements recompute
atomically. There is no winner advancement. Completing every expected match
creates a placement for every team; player statistics remain derived future
work.

## Persistence, security, and platforms

Drift schema 8 adds `round_robin_snapshots`, `round_robin_outbox`, and
`round_robin_checkpoints`; the v7-to-v8 migration preserves existing data.
Matches, revisions, and placements are reused. Preview is memory-only.
Confirmed generation/regeneration and Android outbox persistence are atomic;
regeneration is limited to Registration before a start/result. Pending and
conflicted work is not reported as synchronized or overwritten by pull.

Migration `20260904180000_m14_round_robin.sql` adds the public aggregate root,
private receipts, public context, organizer apply/pull RPCs, RLS, grants, and a
Realtime refresh-hint publication. `20260904180500_assert_m14_round_robin.sql`
uses rollback-only synthetic rows. Guests may read schedules; guest/member
writes are denied; only the fixed organizer command mutates records. No payment
or Auth data is returned. Web uses the initialized publishable-key client
online and never initializes SQLite.

Follow-up migrations `20260904181000_fix_round_robin_odd_team_match_keys.sql`
and `20260904181500_assert_round_robin_odd_team_match_keys.sql` repair and
assert playable-match numbering for odd-team rounds whose first physical pair
is the internal BYE. Existing applied migrations were not rewritten.

## UI, validation, and limitations

Public and organizer pages provide Schedule and Standings sections, ordered
rounds, Leg 1/Leg 2, rests, states, scores, tie-break explanations, seed-order
review, preview/confirmation, and organizer-only result/correction actions.
Routes support direct event/division identity. Narrow layouts scroll; wide Web
uses a standings table. No elimination bracket is rendered for these formats.
When every active scheduled match has completed, the standings view explicitly
labels the first two derived placements Champion and Runner-up while the event
may still be In Progress. Team-formation regressions also preserve accumulated
manual preview pairs, allow an individual preview pair to be undone or the
whole unconfirmed preview reset, support multi-participant registration, and
provide drag-based seed ordering.
Local Web walkthroughs use the fixed `http://localhost:8080` origin so repeated
test sessions do not allocate incrementing temporary ports.

Run Flutter dependency resolution, generation/schema freshness checks,
formatting, analysis, tests, Web/APK builds, linked migration history/lint,
documentation/secret scans, and Git checks. Manual Android and Web validation
must cover odd/even Single schedules, Double legs, standings/tie-breaks,
placements, correction, regeneration lock, permissions, offline Android
restart/reconnect, Web online-only behavior, accessibility, and guest reads.

Docker is installed but its Linux engine is unavailable, so local pgTAP could
not run; hosted rollback assertions remain authoritative database test coverage.
The user confirmed Android and Web categories A–F, including odd/even Single
Round Robin, Double Round Robin, BYEs, score correction, derived standings and
placements, offline Android persistence/reconnect, Web online-only failure
behavior, permissions, responsiveness, and guest reads.
The final optional repeat of Drift's schema-dump command stalled in its Windows
build-hook launcher. The already-exported v8 snapshot, repeated build-runner and
migration-helper generation, and passing fresh/v7→v8 database tests provide the
checked-in schema evidence.
M15 Double Elimination and M16 court scheduling/queue are explicitly absent.

Files to study first:

- `lib/src/domain/tournament/round_robin_generator.dart`
- `lib/src/domain/tournament/round_robin_standings.dart`
- `lib/src/application/tournament/round_robin_service.dart`
- `lib/src/infrastructure/tournament/round_robin_codec.dart`
- `lib/src/presentation/tournament/round_robin_page.dart`
- `supabase/migrations/20260904180000_m14_round_robin.sql`
