import 'dart:convert';

import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';
import '../common/repository_result.dart';
import '../events/event_division.dart';
import '../teams/temporary_team.dart';
import '../matches/validated_score.dart';

/// Input includes membership metadata because tombstones cannot be inferred
/// from the permanent PlayerId references in TemporaryTeam.
final class TournamentTeam {
  TournamentTeam({
    required this.team,
    required Map<PlayerId, RecordMetadata> members,
  }) : members = Map.unmodifiable(members);
  final TemporaryTeam team;
  final Map<PlayerId, RecordMetadata> members;
}

final class TournamentGenerationRequest {
  TournamentGenerationRequest({
    required this.eventId,
    required this.division,
    required Iterable<TournamentTeam> teams,
    Iterable<TeamId>? organizerOrder,
  }) : teams = List.unmodifiable(teams),
       organizerOrder = organizerOrder == null
           ? null
           : List.unmodifiable(organizerOrder);
  final EventId eventId;
  final EventDivision division;
  final List<TournamentTeam> teams;

  /// If supplied, this must be a complete, unique permutation of team IDs.
  final List<TeamId>? organizerOrder;
  List<TournamentTeam> get canonicalTeams {
    final order = organizerOrder;
    if (order != null &&
        (order.length != teams.length ||
            order.toSet().length != order.length ||
            !order.toSet().containsAll(teams.map((t) => t.team.id)))) {
      throw const TournamentGenerationFailure(
        code: 'invalid_order',
        message: 'Organizer order must include every team exactly once.',
      );
    }
    final result = teams.toList();
    result.sort(
      (a, b) => order == null
          ? a.team.id.value.compareTo(b.team.id.value)
          : order.indexOf(a.team.id).compareTo(order.indexOf(b.team.id)),
    );
    return List.unmodifiable(result);
  }
}

final class PlannedMatchKey {
  PlannedMatchKey(this.value) {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_./-]*$').hasMatch(value)) {
      throw const TournamentGenerationFailure(
        code: 'invalid_key',
        message:
            'Planned match keys must be nonempty stable structural labels.',
      );
    }
  }
  final String value;
  @override
  bool operator ==(Object other) =>
      other is PlannedMatchKey && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

sealed class PlannedParticipantSource {
  const PlannedParticipantSource();
  Map<String, Object> toJson();
}

final class DirectTeamSource extends PlannedParticipantSource {
  const DirectTeamSource(this.teamId);
  final TeamId teamId;
  @override
  Map<String, Object> toJson() => {'teamId': teamId.value};
}

final class MatchOutcomeSource extends PlannedParticipantSource {
  const MatchOutcomeSource(this.matchKey, this.outcome);
  final PlannedMatchKey matchKey;
  final MatchDependencySource outcome;
  @override
  Map<String, Object> toJson() => {
    'matchKey': matchKey.value,
    'outcome': outcome.name,
  };
}

final class PlannedMatch {
  const PlannedMatch({
    required this.key,
    required this.eventId,
    required this.divisionId,
    required this.sideOne,
    required this.sideTwo,
    this.round = 1,
    this.section = 'main',
    this.status = MatchStatus.scheduled,
    this.finalScore,
    this.winner,
  });
  final PlannedMatchKey key;
  final EventId eventId;
  final DivisionId divisionId;
  final PlannedParticipantSource sideOne;
  final PlannedParticipantSource sideTwo;
  final int round;
  final String section;
  final MatchStatus status;
  final ValidatedScore? finalScore;
  final TeamId? winner;
  Map<String, Object?> toJson() => {
    'key': key.value,
    'eventId': eventId.value,
    'divisionId': divisionId.value,
    'sideOne': sideOne.toJson(),
    'sideTwo': sideTwo.toJson(),
    'round': round,
    'section': section,
    'status': status.name,
    'score': finalScore == null
        ? null
        : [finalScore!.sideOne, finalScore!.sideTwo],
    'winner': winner?.value,
  };
}

final class TournamentPlan {
  TournamentPlan({
    required this.eventId,
    required this.divisionId,
    required this.format,
    required Iterable<PlannedMatch> matches,
    Map<String, String> metadata = const {},
  }) : matches = List.unmodifiable(matches),
       metadata = Map.unmodifiable(metadata);
  final EventId eventId;
  final DivisionId divisionId;
  final TournamentFormat format;

  /// Explicit list order is authoritative. Metadata is serialized by sorted key.
  final List<PlannedMatch> matches;
  final Map<String, String> metadata;
  String get canonicalJson {
    final keys = metadata.keys.toList()..sort();
    return jsonEncode({
      'eventId': eventId.value,
      'divisionId': divisionId.value,
      'format': format.name,
      'matches': matches.map((m) => m.toJson()).toList(),
      'metadata': {for (final key in keys) key: metadata[key]},
    });
  }

  @override
  bool operator ==(Object other) =>
      other is TournamentPlan && canonicalJson == other.canonicalJson;
  @override
  int get hashCode => canonicalJson.hashCode;
}

abstract interface class TournamentGenerator {
  RepositoryResult<TournamentPlan> generate(
    TournamentGenerationRequest request,
  );
}

/// Deliberately no production format strategy in M12.
final class UnimplementedTournamentGenerator implements TournamentGenerator {
  const UnimplementedTournamentGenerator();
  @override
  RepositoryResult<TournamentPlan> generate(
    TournamentGenerationRequest request,
  ) => const RepositoryFailure(
    TournamentGenerationFailure(
      code: 'unimplemented_format',
      message: 'Tournament generation is implemented in M13–M15.',
    ),
  );
}
