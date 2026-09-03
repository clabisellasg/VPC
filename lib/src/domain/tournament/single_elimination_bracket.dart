import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';
import '../matches/match.dart';
import '../matches/validated_score.dart';
import 'tournament_contracts.dart';

final class ResultRevision {
  const ResultRevision({
    required this.operationId,
    required this.previous,
    required this.reason,
    required this.recordedAt,
  });
  final SyncOperationId operationId;
  final Match previous;
  final String reason;
  final DateTime recordedAt;
}

/// Immutable playable state. Bye positions live in the plan metadata, not here.
final class SingleEliminationBracket {
  SingleEliminationBracket({
    required this.plan,
    required Map<PlannedMatchKey, Match> matches,
    required this.metadata,
    Iterable<ResultRevision> revisions = const [],
  }) : matches = Map.unmodifiable(matches),
       revisions = List.unmodifiable(revisions) {
    if (plan.format != TournamentFormat.singleElimination ||
        plan.matches.length != this.matches.length ||
        plan.matches.any((m) => !this.matches.containsKey(m.key)) ||
        this.matches.values.map((m) => m.id).toSet().length !=
            this.matches.length ||
        this.matches.values.any(
          (m) => m.divisionId != plan.divisionId || m.metadata.isDeleted,
        )) {
      throw const TournamentGenerationFailure(
        code: 'invalid_bracket',
        message: 'The active bracket is inconsistent.',
      );
    }
  }
  final TournamentPlan plan;
  final Map<PlannedMatchKey, Match> matches;
  final RecordMetadata metadata;
  final List<ResultRevision> revisions;

  bool get mayRegenerate => matches.values.every(
    (m) =>
        (m.status == MatchStatus.scheduled || m.status == MatchStatus.queued) &&
        m.sideOneScore == null &&
        m.sideTwoScore == null,
  );

  Match get finalMatch => matches[plan.matches.last.key]!;
  TeamId? get champion => finalMatch.winnerTeamId;
  TeamId? get runnerUp => champion == null
      ? null
      : (champion == finalMatch.sideOneTeamId
            ? finalMatch.sideTwoTeamId
            : finalMatch.sideOneTeamId);

  /// Starting is explicit; submitting a final score cannot skip ready/in-progress.
  SingleEliminationBracket start(
    PlannedMatchKey key,
    EventStatus eventStatus,
    int expectedVersion,
    DateTime now,
  ) {
    _check(eventStatus, expectedVersion);
    final current = _match(key);
    if (current.sideOneTeamId == null || current.sideTwoTeamId == null) {
      throw const TournamentGenerationFailure(
        code: 'unresolved_match',
        message: 'Both teams must be known before a match starts.',
      );
    }
    final updated = current.transitionTo(
      MatchStatus.inProgress,
      metadata: _next(current.metadata, now),
    );
    return SingleEliminationBracket(
      plan: plan,
      matches: {...matches, key: updated},
      metadata: _next(metadata, now),
      revisions: revisions,
    );
  }

  SingleEliminationBracket result({
    required PlannedMatchKey key,
    required ValidatedScore score,
    required EventStatus eventStatus,
    required int expectedVersion,
    required DateTime now,
    required SyncOperationId operationId,
    String? correctionReason,
  }) {
    _check(eventStatus, expectedVersion);
    final current = _match(key);
    final correcting = current.status == MatchStatus.completed;
    if (current.status != MatchStatus.inProgress && !correcting) {
      throw const TournamentGenerationFailure(
        code: 'match_not_started',
        message: 'Start the ready match before recording a result.',
      );
    }
    final reason = correctionReason?.trim();
    if (correcting && (reason == null || reason.isEmpty)) {
      throw const ValidationFailure(
        field: 'reason',
        message: 'A non-empty correction reason is required.',
      );
    }
    final winner = score.sideOneWins
        ? current.sideOneTeamId!
        : current.sideTwoTeamId!;
    final changedWinner = correcting && current.winnerTeamId != winner;
    if (changedWinner) {
      final affected = <PlannedMatchKey>{key};
      for (final planned in plan.matches) {
        if ([planned.sideOne, planned.sideTwo]
            .whereType<MatchOutcomeSource>()
            .any((s) => affected.contains(s.matchKey))) {
          affected.add(planned.key);
          final downstream = matches[planned.key]!;
          if (downstream.status == MatchStatus.inProgress ||
              downstream.status == MatchStatus.completed ||
              downstream.sideOneScore != null ||
              downstream.sideTwoScore != null) {
            throw const TournamentGenerationFailure(
              code: 'downstream_started',
              message: 'The result cannot be corrected because an affected downstream match has started.',
            );
          }
        }
      }
    }
    final rows = {...matches};
    rows[key] = Match(
      id: current.id,
      divisionId: current.divisionId,
      status: MatchStatus.completed,
      metadata: _next(current.metadata, now),
      sideOneTeamId: current.sideOneTeamId,
      sideTwoTeamId: current.sideTwoTeamId,
      sideOneScore: score.sideOne,
      sideTwoScore: score.sideTwo,
      winnerTeamId: winner,
      roundNumber: current.roundNumber,
      sequenceNumber: current.sequenceNumber,
    );
    for (final planned in plan.matches) {
      if (planned.key == key) continue;
      final row = rows[planned.key]!;
      TeamId? resolve(PlannedParticipantSource source) => switch (source) {
        DirectTeamSource(:final teamId) => teamId,
        MatchOutcomeSource(:final matchKey, :final outcome) =>
          outcome == MatchDependencySource.winner
              ? rows[matchKey]?.winnerTeamId
              : throw const TournamentGenerationFailure(
                  code: 'loser_dependency',
                  message: 'Single Elimination cannot advance a loser.',
                ),
      };
      final one = resolve(planned.sideOne);
      final two = resolve(planned.sideTwo);
      if (one == row.sideOneTeamId && two == row.sideTwoTeamId) continue;
      if (row.status == MatchStatus.inProgress ||
          row.status == MatchStatus.completed) {
        throw const TournamentGenerationFailure(
          code: 'downstream_started',
          message: 'Played match participants cannot be changed.',
        );
      }
      rows[planned.key] = Match(
        id: row.id,
        divisionId: row.divisionId,
        status: one != null && two != null
            ? MatchStatus.queued
            : MatchStatus.scheduled,
        metadata: _next(row.metadata, now),
        sideOneTeamId: one,
        sideTwoTeamId: two,
        roundNumber: row.roundNumber,
        sequenceNumber: row.sequenceNumber,
      );
    }
    return SingleEliminationBracket(
      plan: plan,
      matches: rows,
      metadata: _next(metadata, now),
      revisions: [
        ...revisions,
        if (correcting)
          ResultRevision(
            operationId: operationId,
            previous: current,
            reason: reason!,
            recordedAt: now,
          ),
      ],
    );
  }

  Match _match(PlannedMatchKey key) =>
      matches[key] ??
      (throw const TournamentGenerationFailure(
        code: 'missing_match',
        message: 'The match is not part of this bracket.',
      ));
  void _check(EventStatus status, int expected) {
    if (status != EventStatus.inProgress) {
      throw const TournamentGenerationFailure(
        code: 'event_not_in_progress',
        message: 'Results can change only while the event is In Progress.',
      );
    }
    if (expected != metadata.recordVersion) {
      throw const ConflictFailure(
        message: 'The bracket has changed. Refresh before trying again.',
      );
    }
  }

  static RecordMetadata _next(RecordMetadata old, DateTime now) =>
      RecordMetadata(
        createdAt: old.createdAt,
        updatedAt: now,
        recordVersion: old.recordVersion + 1,
      );
}
