import 'dart:convert';

import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';
import '../matches/match.dart';
import '../matches/validated_score.dart';
import 'round_robin_generator.dart';
import 'round_robin_standings.dart';
import 'single_elimination_bracket.dart' show ResultRevision;
import 'tournament_contracts.dart';

final class RoundRobinTournament {
  RoundRobinTournament({
    required this.plan,
    required Map<PlannedMatchKey, Match> matches,
    required this.metadata,
    Iterable<ResultRevision> revisions = const [],
  }) : matches = Map.unmodifiable(matches),
       revisions = List.unmodifiable(revisions) {
    if (!isRoundRobin(plan.format) ||
        plan.matches.length != this.matches.length ||
        plan.matches.any((m) => !this.matches.containsKey(m.key)) ||
        this.matches.values.map((m) => m.id).toSet().length !=
            this.matches.length ||
        this.matches.values.any((m) => m.divisionId != plan.divisionId)) {
      throw const TournamentGenerationFailure(
        code: 'invalid_schedule',
        message: 'The active round-robin schedule is inconsistent.',
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
  bool get complete =>
      matches.isNotEmpty &&
      matches.values.every(
        (m) => m.status == MatchStatus.completed || m.metadata.isDeleted,
      );
  List<TeamId> get seedOrder {
    final encoded = plan.metadata['seedOrder'];
    if (encoded == null) {
      throw const TournamentGenerationFailure(
        code: 'invalid_schedule',
        message: 'Seed order is unavailable.',
      );
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const TournamentGenerationFailure(
        code: 'invalid_schedule',
        message: 'Seed order could not be validated.',
      );
    }
    return List.unmodifiable(decoded.map((value) => TeamId(value as String)));
  }

  List<RoundRobinStanding> get standings => calculateRoundRobinStandings(
    plan: plan,
    seedOrder: seedOrder,
    matches: matches.values,
  );

  RoundRobinTournament start(
    PlannedMatchKey key,
    EventStatus eventStatus,
    int expected,
    DateTime now,
  ) {
    _check(eventStatus, expected);
    final current = _match(key);
    return _replace(
      key,
      current.transitionTo(
        MatchStatus.inProgress,
        metadata: _next(current.metadata, now),
      ),
      now,
    );
  }

  RoundRobinTournament result({
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
    final correcting = current.status == MatchStatus.completed,
        reason = correctionReason?.trim();
    if (current.status != MatchStatus.inProgress && !correcting) {
      throw const TournamentGenerationFailure(
        code: 'match_not_started',
        message: 'Start the ready match before recording a result.',
      );
    }
    if (correcting && (reason == null || reason.isEmpty)) {
      throw const ValidationFailure(
        field: 'reason',
        message: 'A non-empty correction reason is required.',
      );
    }
    final winner = score.sideOneWins
        ? current.sideOneTeamId!
        : current.sideTwoTeamId!;
    final updated = Match(
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
    return RoundRobinTournament(
      plan: plan,
      matches: {...matches, key: updated},
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

  RoundRobinTournament _replace(PlannedMatchKey key, Match row, DateTime now) =>
      RoundRobinTournament(
        plan: plan,
        matches: {...matches, key: row},
        metadata: _next(metadata, now),
        revisions: revisions,
      );
  Match _match(PlannedMatchKey key) =>
      matches[key] ??
      (throw const TournamentGenerationFailure(
        code: 'missing_match',
        message: 'The match is not part of this schedule.',
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
        message: 'The schedule changed. Refresh before trying again.',
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
