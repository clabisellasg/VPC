import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/domain_validation.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';

/// Structural match state; it does not generate or progress a tournament.
final class Match {
  factory Match({
    required MatchId id,
    required DivisionId divisionId,
    required MatchStatus status,
    required RecordMetadata metadata,
    TeamId? sideOneTeamId,
    TeamId? sideTwoTeamId,
    int? sideOneScore,
    int? sideTwoScore,
    TeamId? winnerTeamId,
    int? roundNumber,
    int? sequenceNumber,
  }) {
    if (sideOneTeamId != null && sideOneTeamId == sideTwoTeamId) {
      throw const ValidationFailure(
        field: 'sideTwoTeamId',
        message: 'A team cannot occupy both sides of a match.',
      );
    }
    if (sideOneScore case final score?) {
      requireNonNegative(score, field: 'sideOneScore');
    }
    if (sideTwoScore case final score?) {
      requireNonNegative(score, field: 'sideTwoScore');
    }
    if (roundNumber case final value?) {
      requirePositive(value, field: 'roundNumber');
    }
    if (sequenceNumber case final value?) {
      requirePositive(value, field: 'sequenceNumber');
    }

    if (status == MatchStatus.completed) {
      if (sideOneTeamId == null || sideTwoTeamId == null) {
        throw const ValidationFailure(
          field: 'status',
          message: 'A completed match requires both sides.',
        );
      }
      if (sideOneScore == null || sideTwoScore == null) {
        throw const ValidationFailure(
          field: 'status',
          message: 'A completed match requires both structural scores.',
        );
      }
      if (winnerTeamId == null ||
          (winnerTeamId != sideOneTeamId && winnerTeamId != sideTwoTeamId)) {
        throw const ValidationFailure(
          field: 'winnerTeamId',
          message: 'A completed match winner must be one of its two sides.',
        );
      }
    } else if (winnerTeamId != null) {
      throw const ValidationFailure(
        field: 'winnerTeamId',
        message: 'Only a completed match can have a winner.',
      );
    }

    return Match._(
      id: id,
      divisionId: divisionId,
      sideOneTeamId: sideOneTeamId,
      sideTwoTeamId: sideTwoTeamId,
      status: status,
      sideOneScore: sideOneScore,
      sideTwoScore: sideTwoScore,
      winnerTeamId: winnerTeamId,
      roundNumber: roundNumber,
      sequenceNumber: sequenceNumber,
      metadata: metadata,
    );
  }

  const Match._({
    required this.id,
    required this.divisionId,
    required this.sideOneTeamId,
    required this.sideTwoTeamId,
    required this.status,
    required this.sideOneScore,
    required this.sideTwoScore,
    required this.winnerTeamId,
    required this.roundNumber,
    required this.sequenceNumber,
    required this.metadata,
  });

  final MatchId id;
  final DivisionId divisionId;
  final TeamId? sideOneTeamId;
  final TeamId? sideTwoTeamId;
  final MatchStatus status;
  final int? sideOneScore;
  final int? sideTwoScore;
  final TeamId? winnerTeamId;
  final int? roundNumber;
  final int? sequenceNumber;
  final RecordMetadata metadata;

  Match transitionTo(
    MatchStatus nextStatus, {
    required RecordMetadata metadata,
    int? sideOneScore,
    int? sideTwoScore,
    TeamId? winnerTeamId,
  }) {
    final expected = switch (status) {
      MatchStatus.scheduled => MatchStatus.queued,
      MatchStatus.queued => MatchStatus.inProgress,
      MatchStatus.inProgress => MatchStatus.completed,
      MatchStatus.completed => null,
    };
    if (nextStatus != expected) {
      throw InvalidStateTransitionFailure(
        entity: 'Match',
        from: status.name,
        to: nextStatus.name,
      );
    }

    return Match(
      id: id,
      divisionId: divisionId,
      sideOneTeamId: sideOneTeamId,
      sideTwoTeamId: sideTwoTeamId,
      status: nextStatus,
      sideOneScore: sideOneScore ?? this.sideOneScore,
      sideTwoScore: sideTwoScore ?? this.sideTwoScore,
      winnerTeamId: winnerTeamId ?? this.winnerTeamId,
      roundNumber: roundNumber,
      sequenceNumber: sequenceNumber,
      metadata: metadata,
    );
  }
}
