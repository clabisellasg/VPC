import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';

/// Singleton checkpoint scope: all organizer-visible team/division aggregates.
final class TeamPullCursor implements Comparable<TeamPullCursor> {
  const TeamPullCursor(this.updatedAt, this.divisionId);
  final DateTime updatedAt;
  final DivisionId divisionId;
  @override
  int compareTo(TeamPullCursor other) {
    final time = updatedAt.compareTo(other.updatedAt);
    return time == 0
        ? divisionId.value.compareTo(other.divisionId.value)
        : time;
  }
}

final class PulledTeam {
  const PulledTeam(this.id, this.method, this.label, this.metadata);
  final TeamId id;
  final TeamFormationMethod method;
  final String? label;
  final RecordMetadata metadata;
}

final class PulledTeamMember {
  const PulledTeamMember(this.teamId, this.playerId, this.metadata);
  final TeamId teamId;
  final PlayerId playerId;
  final RecordMetadata metadata;
}

final class TeamPullAggregate {
  TeamPullAggregate({
    required this.cursor,
    required this.eventId,
    required Iterable<PulledTeam> teams,
    required Iterable<PulledTeamMember> members,
  }) : teams = List.unmodifiable(teams),
       members = List.unmodifiable(members);
  final TeamPullCursor cursor;
  final EventId eventId;
  final List<PulledTeam> teams;
  final List<PulledTeamMember> members;

  factory TeamPullAggregate.fromJson(Map<String, dynamic> row) {
    try {
      final division = DivisionId(row['division_id'] as String);
      final snapshot = Map<String, dynamic>.from(row['snapshot'] as Map);
      final cursor = TeamPullCursor(_time(row['updated_at']), division);
      final teams = (snapshot['teams'] as List).map((item) {
        final value = Map<String, dynamic>.from(item as Map);
        if (value['division_id'] != division.value) {
          throw const FormatException();
        }
        return PulledTeam(
          TeamId(value['id'] as String),
          TeamFormationMethod.values.byName(
            value['formation_method'] as String,
          ),
          value['display_label'] as String?,
          _metadata(value),
        );
      }).toList();
      final ids = teams.map((team) => team.id).toSet();
      if (ids.length != teams.length) throw const FormatException();
      final memberKeys = <String>{};
      final members = (snapshot['members'] as List).map((item) {
        final value = Map<String, dynamic>.from(item as Map);
        final member = PulledTeamMember(
          TeamId(value['team_id'] as String),
          PlayerId(value['player_id'] as String),
          _metadata(value),
        );
        if (!ids.contains(member.teamId) ||
            !memberKeys.add(
              '${member.teamId.value}/${member.playerId.value}',
            )) {
          throw const FormatException();
        }
        return member;
      }).toList();
      for (final metadata in [
        ...teams.map((team) => team.metadata),
        ...members.map((member) => member.metadata),
      ]) {
        if (metadata.updatedAt.isAfter(cursor.updatedAt)) {
          throw const FormatException();
        }
      }
      return TeamPullAggregate(
        cursor: cursor,
        eventId: EventId(snapshot['event_id'] as String),
        teams: teams,
        members: members,
      );
    } on DomainFailure {
      rethrow;
    } on TypeError {
      throw const ValidationFailure(
        field: 'teamPull',
        message: 'Cloud team metadata is invalid.',
      );
    } on FormatException {
      throw const ValidationFailure(
        field: 'teamPull',
        message: 'Cloud team metadata is invalid.',
      );
    } on ArgumentError {
      throw const ValidationFailure(
        field: 'teamPull',
        message: 'Cloud team metadata is invalid.',
      );
    }
  }
}

DateTime _time(Object? value) {
  if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException();
  }
  return DateTime.parse(value).toUtc();
}

RecordMetadata _metadata(Map<String, dynamic> value) => RecordMetadata(
  createdAt: _time(value['created_at']),
  updatedAt: _time(value['updated_at']),
  deletedAt: value['deleted_at'] == null ? null : _time(value['deleted_at']),
  recordVersion: value['version'] as int,
);

abstract interface class TeamPullSource {
  Future<List<TeamPullAggregate>> pullTeams(TeamPullCursor? after);
}
