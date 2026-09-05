import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';
import '../matches/match.dart';
import '../matches/validated_score.dart';
import 'double_elimination_generator.dart';
import 'single_elimination_bracket.dart' show ResultRevision;
import 'tournament_contracts.dart';

final class DoubleEliminationBracket {
  DoubleEliminationBracket({
    required this.plan,
    required this.reservedResetMatchId,
    required Map<PlannedMatchKey, Match> matches,
    required this.metadata,
    Iterable<ResultRevision> revisions = const [],
  }) : matches = Map.unmodifiable(matches),
       revisions = List.unmodifiable(revisions) {
    final reset = DoubleEliminationGenerator.resetKey;
    if (plan.format != TournamentFormat.doubleElimination ||
        plan.matches
            .where((m) => m.key != reset)
            .any((m) => !this.matches.containsKey(m.key)) ||
        this.matches.keys.any(
          (key) => !plan.matches.any((m) => m.key == key),
        ) ||
        this.matches.values.map((m) => m.id).toSet().length !=
            this.matches.length ||
        this.matches.values.any(
          (m) => m.divisionId != plan.divisionId || m.metadata.isDeleted,
        ) ||
        (this.matches[reset] != null &&
            this.matches[reset]!.id != reservedResetMatchId)) {
      throw const TournamentGenerationFailure(
        code: 'invalid_double_elimination',
        message: 'The active Double Elimination structure is inconsistent.',
      );
    }
  }

  final TournamentPlan plan;
  final MatchId reservedResetMatchId;
  final Map<PlannedMatchKey, Match> matches;
  final RecordMetadata metadata;
  final List<ResultRevision> revisions;

  bool get mayRegenerate => matches.values.every(
    (m) =>
        (m.status == MatchStatus.scheduled || m.status == MatchStatus.queued) &&
        m.sideOneScore == null &&
        m.sideTwoScore == null,
  );
  Match get grandFinalOne =>
      matches[DoubleEliminationGenerator.grandFinalOneKey]!;
  Match? get grandFinalTwo => matches[DoubleEliminationGenerator.resetKey];
  bool get resetRequired =>
      grandFinalOne.status == MatchStatus.completed &&
      grandFinalOne.winnerTeamId == grandFinalOne.sideTwoTeamId;
  bool get decided =>
      grandFinalTwo?.status == MatchStatus.completed ||
      (grandFinalOne.status == MatchStatus.completed && !resetRequired);
  Match? get decidingFinal => !decided
      ? null
      : (grandFinalTwo?.status == MatchStatus.completed
            ? grandFinalTwo
            : grandFinalOne);
  TeamId? get champion => decidingFinal?.winnerTeamId;
  TeamId? get runnerUp {
    final finalMatch = decidingFinal, winner = champion;
    if (finalMatch == null || winner == null) return null;
    return winner == finalMatch.sideOneTeamId
        ? finalMatch.sideTwoTeamId
        : finalMatch.sideOneTeamId;
  }

  DoubleEliminationBracket withReservedResetMatchId(MatchId value) {
    final current = grandFinalTwo;
    final rows = <PlannedMatchKey, Match>{...matches};
    if (current != null && current.id != value) {
      rows[DoubleEliminationGenerator.resetKey] = Match(
        id: value,
        divisionId: current.divisionId,
        status: current.status,
        metadata: current.metadata,
        sideOneTeamId: current.sideOneTeamId,
        sideTwoTeamId: current.sideTwoTeamId,
        sideOneScore: current.sideOneScore,
        sideTwoScore: current.sideTwoScore,
        winnerTeamId: current.winnerTeamId,
        roundNumber: current.roundNumber,
        sequenceNumber: current.sequenceNumber,
      );
    }
    return DoubleEliminationBracket(
      plan: plan,
      reservedResetMatchId: value,
      matches: rows,
      metadata: metadata,
      revisions: revisions,
    );
  }

  DoubleEliminationBracket start(
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
    return _copy(
      rows: {
        ...matches,
        key: current.transitionTo(
          MatchStatus.inProgress,
          metadata: _next(current.metadata, now),
        ),
      },
      now: now,
    );
  }

  DoubleEliminationBracket result({
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
    if (correcting && current.winnerTeamId != winner) {
      _ensureDownstreamUnstarted(key);
    }
    var rows = <PlannedMatchKey, Match>{
      ...matches,
      key: Match(
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
      ),
    };
    rows = _reconcile(rows, now);
    return DoubleEliminationBracket(
      plan: plan,
      reservedResetMatchId: reservedResetMatchId,
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

  void _ensureDownstreamUnstarted(PlannedMatchKey changed) {
    final affected = <PlannedMatchKey>{changed};
    for (final planned in plan.matches) {
      if ([planned.sideOne, planned.sideTwo]
          .whereType<MatchOutcomeSource>()
          .any((source) => affected.contains(source.matchKey))) {
        affected.add(planned.key);
        final downstream = matches[planned.key];
        if (downstream != null &&
            (downstream.status == MatchStatus.inProgress ||
                downstream.status == MatchStatus.completed ||
                downstream.sideOneScore != null ||
                downstream.sideTwoScore != null)) {
          throw const TournamentGenerationFailure(
            code: 'downstream_started',
            message: 'The result cannot be corrected because an affected downstream match has started.',
          );
        }
      }
    }
  }

  Map<PlannedMatchKey, Match> _reconcile(
    Map<PlannedMatchKey, Match> rows,
    DateTime now,
  ) {
    TeamId? outcome(MatchOutcomeSource source) {
      final match = rows[source.matchKey];
      if (match?.status != MatchStatus.completed) return null;
      if (source.outcome == MatchDependencySource.winner) {
        return match!.winnerTeamId;
      }
      return match!.winnerTeamId == match.sideOneTeamId
          ? match.sideTwoTeamId
          : match.sideOneTeamId;
    }

    for (final planned in plan.matches) {
      final isReset = planned.key == DoubleEliminationGenerator.resetKey;
      final gf1 = rows[DoubleEliminationGenerator.grandFinalOneKey];
      final activateReset =
          gf1?.status == MatchStatus.completed &&
          gf1!.winnerTeamId == gf1.sideTwoTeamId;
      if (isReset && !activateReset) {
        rows.remove(planned.key);
        continue;
      }
      TeamId? resolve(PlannedParticipantSource source) => switch (source) {
        DirectTeamSource(:final teamId) => teamId,
        MatchOutcomeSource() => outcome(source),
      };
      final one = resolve(planned.sideOne), two = resolve(planned.sideTwo);
      var row = rows[planned.key];
      if (row == null) {
        if (!isReset) {
          throw const ValidationFailure(
            field: 'resetMatchId',
            message:
                'The conditional reset requires its stable match identity.',
          );
        }
        row = Match(
          id: reservedResetMatchId,
          divisionId: plan.divisionId,
          status: MatchStatus.scheduled,
          metadata: RecordMetadata(
            createdAt: now,
            updatedAt: now,
            recordVersion: 0,
          ),
          roundNumber: planned.round,
          sequenceNumber: plan.matches.indexOf(planned) + 1,
        );
      }
      if (row.status == MatchStatus.inProgress ||
          row.status == MatchStatus.completed) {
        if (row.sideOneTeamId != one || row.sideTwoTeamId != two) {
          throw const TournamentGenerationFailure(
            code: 'downstream_started',
            message: 'Played match participants cannot be changed.',
          );
        }
        continue;
      }
      rows[planned.key] = Match(
        id: row.id,
        divisionId: row.divisionId,
        status: one != null && two != null
            ? MatchStatus.queued
            : MatchStatus.scheduled,
        metadata: row.sideOneTeamId == one && row.sideTwoTeamId == two
            ? row.metadata
            : _next(row.metadata, now),
        sideOneTeamId: one,
        sideTwoTeamId: two,
        roundNumber: row.roundNumber,
        sequenceNumber: row.sequenceNumber,
      );
    }
    return rows;
  }

  DoubleEliminationBracket _copy({
    required Map<PlannedMatchKey, Match> rows,
    required DateTime now,
  }) => DoubleEliminationBracket(
    plan: plan,
    reservedResetMatchId: reservedResetMatchId,
    matches: rows,
    metadata: _next(metadata, now),
    revisions: revisions,
  );
  Match _match(PlannedMatchKey key) =>
      matches[key] ??
      (throw const TournamentGenerationFailure(
        code: 'missing_match',
        message: 'The match is not active in this bracket.',
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
        message: 'The bracket changed. Refresh before trying again.',
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
