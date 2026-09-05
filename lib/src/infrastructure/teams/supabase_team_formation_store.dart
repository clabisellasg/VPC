import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/teams/team_formation_contracts.dart';
import '../../application/teams/team_formation_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/player_skill.dart';
import 'team_pull_models.dart';

final class SupabaseTeamFormationStore
    implements TeamFormationStore, TeamPullSource {
  const SupabaseTeamFormationStore(this.client);
  final SupabaseClient client;

  @override
  Future<List<TeamPullAggregate>> pullTeams(TeamPullCursor? after) async {
    final rows = await client.rpc<List<dynamic>>(
      'pull_team_formation_changes',
      params: {
        'p_after_updated_at': after?.updatedAt.toIso8601String(),
        'p_after_division_id': after?.divisionId.value,
        'p_limit': 50,
      },
    );
    return rows
        .map(
          (row) =>
              TeamPullAggregate.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<RepositoryResult<TeamFormationSnapshot>> load(
    EventId eventId,
    DivisionId divisionId,
  ) async {
    try {
      final response = await client.rpc<Map<String, dynamic>>(
        'get_team_formation_snapshot',
        params: {
          'p_event_id': eventId.value,
          'p_division_id': divisionId.value,
        },
      );
      return RepositorySuccess(_snapshot(response));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } on PostgrestException catch (error) {
      return RepositoryFailure(
        error.code == '42501'
            ? const UnauthorizedFailure(
                message: 'A confirmed organizer account is required.',
              )
            : const PersistenceUnavailableFailure(
                message: 'Team formation could not be loaded safely.',
              ),
      );
    }
  }

  @override
  Future<RepositoryResult<TeamFormationSnapshot>> replace({
    required TeamFormationSnapshot current,
    required TeamFormationPreview preview,
    required SyncOperationId operationId,
  }) async {
    final payload = <String, Object?>{
      'event_id': current.eventId.value,
      'division_id': current.divisionId.value,
      'teams': preview.teams
          .map(
            (team) => {
              'id': team.id.value,
              'method': team.method.name,
              'player_ids': team.players
                  .map((player) => player.playerId.value)
                  .toList(),
            },
          )
          .toList(),
      'base_teams': {
        for (final entry in preview.baseTeamVersions.entries)
          entry.key.value: entry.value,
      },
    };
    try {
      final response = await client.rpc<Map<String, dynamic>>(
        'apply_team_formation_operation',
        params: {
          'p_operation_id': operationId.value,
          'p_event_id': current.eventId.value,
          'p_division_id': current.divisionId.value,
          'p_payload': payload,
        },
      );
      final snapshot = response['snapshot'];
      if (snapshot is! Map) throw const FormatException();
      return RepositorySuccess(_snapshot(Map<String, dynamic>.from(snapshot)));
    } on PostgrestException catch (error) {
      return RepositoryFailure(
        error.code == '42501'
            ? const UnauthorizedFailure(
                message: 'Organizer permission is required.',
              )
            : error.code == '23514' ||
                  error.code == '23505' ||
                  error.code == '40001'
            ? const ConflictFailure(
                message: 'Team formation changed or is no longer eligible.',
              )
            : const PersistenceUnavailableFailure(
                message: 'Team formation could not be saved safely.',
              ),
      );
    } catch (error) {
      if (error is Error) rethrow;
      return const RepositoryFailure(
        ValidationFailure(
          field: 'remoteTeamFormation',
          message: 'Cloud team data is invalid.',
        ),
      );
    }
  }

  TeamFormationSnapshot _snapshot(Map<String, dynamic> json) {
    final eligible = (json['eligible_players'] as List).map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      return EligibleTeamPlayer(
        playerId: PlayerId(row['player_id'] as String),
        displayName: row['display_name'] as String,
        skill: row['skill_level'] == null
            ? null
            : PlayerSkill((row['skill_level'] as num).toInt()),
        paid: row['paid'] as bool,
      );
    }).toList();
    final byId = {for (final player in eligible) player.playerId.value: player};
    final teams = (json['teams'] as List).map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      final players = (row['player_ids'] as List)
          .map((id) => byId[id as String])
          .whereType<EligibleTeamPlayer>()
          .toList();
      if (players.length != (row['player_ids'] as List).length) {
        throw const ValidationFailure(
          field: 'teamEligibility',
          message:
              'An existing team includes a player who is no longer checked in '
              'or assigned to this division. Review the participant roster '
              'and restore eligibility before managing these pairs.',
        );
      }
      return TeamDraft(
        id: TeamId(row['id'] as String),
        players: players,
        method: TeamFormationMethod.values.byName(row['method'] as String),
        recordVersion: (row['version'] as num).toInt(),
      );
    }).toList();
    return TeamFormationSnapshot(
      eventId: EventId(json['event_id'] as String),
      divisionId: DivisionId(json['division_id'] as String),
      eventStatus: EventStatus.values.byName(json['event_status'] as String),
      eligiblePlayers: eligible,
      teams: teams,
    );
  }
}
