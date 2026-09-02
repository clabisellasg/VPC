import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/teams/team_formation_contracts.dart';
import '../../application/teams/team_formation_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/player_skill.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/drift_mapping.dart';
import 'team_pull_models.dart';

final class DriftTeamFormationStore implements TeamFormationStore {
  const DriftTeamFormationStore(this.database);
  final AppDatabase database;

  @override
  Future<RepositoryResult<TeamFormationSnapshot>> load(
    EventId eventId,
    DivisionId divisionId,
  ) async {
    try {
      final event = await (database.select(
        database.events,
      )..where((row) => row.id.equals(eventId.value))).getSingleOrNull();
      final division =
          await (database.select(database.eventDivisions)..where(
                (row) =>
                    row.id.equals(divisionId.value) &
                    row.eventId.equals(eventId.value) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (event == null || division == null) {
        return RepositoryFailure(
          NotFoundFailure(
            entity: 'Event division',
            identifier: divisionId.value,
          ),
        );
      }
      final participants =
          await (database.select(database.eventParticipants)..where(
                (row) =>
                    row.eventId.equals(eventId.value) &
                    row.checkInStatus.equals('checkedIn') &
                    row.deletedAt.isNull(),
              ))
              .get();
      final eligible = <EligibleTeamPlayer>[];
      for (final participant in participants) {
        final assignment =
            await (database.select(database.divisionParticipants)..where(
                  (row) =>
                      row.eventParticipantId.equals(participant.id) &
                      row.divisionId.equals(divisionId.value) &
                      row.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (assignment == null) continue;
        final player =
            await (database.select(database.players)..where(
                  (row) =>
                      row.id.equals(participant.playerId) &
                      row.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (player == null) continue;
        final payment =
            await (database.select(database.participantPayments)..where(
                  (row) =>
                      row.eventParticipantId.equals(participant.id) &
                      row.divisionId.isNull() &
                      row.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        eligible.add(
          EligibleTeamPlayer(
            playerId: PlayerId(player.id),
            displayName: player.displayName,
            skill: player.skillLevel == null
                ? null
                : PlayerSkill(player.skillLevel!),
            paid: payment?.status == 'paid',
          ),
        );
      }
      eligible.sort((a, b) => a.playerId.value.compareTo(b.playerId.value));
      final rows =
          await (database.select(database.teams)
                ..where(
                  (row) =>
                      row.divisionId.equals(divisionId.value) &
                      row.deletedAt.isNull(),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.id)]))
              .get();
      final teams = <TeamDraft>[];
      for (final row in rows) {
        final members =
            await (database.select(database.teamMembers)
                  ..where(
                    (member) =>
                        member.teamId.equals(row.id) &
                        member.deletedAt.isNull(),
                  )
                  ..orderBy([(member) => OrderingTerm.asc(member.playerId)]))
                .get();
        final players = members
            .map(
              (member) => eligible
                  .where((value) => value.playerId.value == member.playerId)
                  .firstOrNull,
            )
            .whereType<EligibleTeamPlayer>()
            .toList();
        if (players.length != 2) {
          throw const ValidationFailure(
            field: 'teamMembers',
            message: 'Stored complete team must contain two eligible players.',
          );
        }
        teams.add(
          TeamDraft(
            id: TeamId(row.id),
            players: players,
            method: enumValue(
              TeamFormationMethod.values,
              row.formationMethod,
              field: 'formationMethod',
            ),
            recordVersion: row.version,
          ),
        );
      }
      final conflict =
          await (database.select(database.teamFormationConflicts)
                ..where(
                  (row) =>
                      row.divisionId.equals(divisionId.value) &
                      row.status.equals('unresolved'),
                )
                ..limit(1))
              .getSingleOrNull();
      final pending =
          await (database.select(database.teamFormationOutboxOperations)
                ..where((row) => row.divisionId.equals(divisionId.value))
                ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      return RepositorySuccess(
        TeamFormationSnapshot(
          eventId: eventId,
          divisionId: divisionId,
          eventStatus: enumValue(
            EventStatus.values,
            event.status,
            field: 'eventStatus',
          ),
          eligiblePlayers: eligible,
          teams: teams,
          disposition: conflict != null
              ? TeamMutationDisposition.conflicted
              : pending != null
              ? TeamMutationDisposition.pending
              : TeamMutationDisposition.synchronized,
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  @override
  Future<RepositoryResult<TeamFormationSnapshot>> replace({
    required TeamFormationSnapshot current,
    required TeamFormationPreview preview,
    required SyncOperationId operationId,
  }) async {
    try {
      return await database.transaction(() async {
        final event = await (database.select(
          database.events,
        )..where((row) => row.id.equals(current.eventId.value))).getSingle();
        if (event.status != 'registration') {
          return const RepositoryFailure<TeamFormationSnapshot>(
            InvalidStateTransitionFailure(
              entity: 'Team formation',
              from: 'locked',
              to: 'replace',
            ),
          );
        }
        final now = DateTime.now().toUtc();
        final oldTeams =
            await (database.select(database.teams)..where(
                  (row) =>
                      row.divisionId.equals(current.divisionId.value) &
                      row.deletedAt.isNull(),
                ))
                .get();
        final actualVersions = {
          for (final team in oldTeams) TeamId(team.id): team.version,
        };
        if (actualVersions.length != preview.baseTeamVersions.length ||
            actualVersions.entries.any(
              (entry) => preview.baseTeamVersions[entry.key] != entry.value,
            )) {
          return const RepositoryFailure<TeamFormationSnapshot>(
            ConflictFailure(
              message: 'Team formation changed. Refresh before replacing it.',
            ),
          );
        }
        for (final team in oldTeams) {
          await (database.update(database.teamMembers)..where(
                (row) => row.teamId.equals(team.id) & row.deletedAt.isNull(),
              ))
              .write(
                TeamMembersCompanion(
                  deletedAt: Value(now),
                  updatedAt: Value(now),
                  version: Value(team.version + 1),
                ),
              );
          await (database.update(
            database.teams,
          )..where((row) => row.id.equals(team.id))).write(
            TeamsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              version: Value(team.version + 1),
            ),
          );
        }
        for (final draft in preview.teams) {
          await database
              .into(database.teams)
              .insert(
                TeamsCompanion.insert(
                  id: draft.id.value,
                  divisionId: current.divisionId.value,
                  formationMethod: draft.method.name,
                  createdAt: now,
                  updatedAt: now,
                  version: 0,
                ),
              );
          for (final player in draft.players) {
            await database
                .into(database.teamMembers)
                .insert(
                  TeamMembersCompanion.insert(
                    teamId: draft.id.value,
                    playerId: player.playerId.value,
                    createdAt: now,
                    updatedAt: now,
                    version: 0,
                  ),
                );
          }
        }
        final payload = jsonEncode({
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
        });
        await database
            .into(database.teamFormationOutboxOperations)
            .insert(
              TeamFormationOutboxOperationsCompanion.insert(
                id: operationId.value,
                eventId: current.eventId.value,
                divisionId: current.divisionId.value,
                payloadJson: payload,
                createdAt: now,
                status: 'pending',
              ),
            );
        final loaded = await load(current.eventId, current.divisionId);
        return loaded;
      });
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  Future<List<LocalTeamFormationOutboxRow>> pendingOperations() =>
      (database.select(database.teamFormationOutboxOperations)
            ..where((row) => row.status.equals('pending'))
            ..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.id),
            ]))
          .get();

  Future<TeamFormationPreview> decodePending(
    LocalTeamFormationOutboxRow operation,
    TeamFormationSnapshot authoritative,
  ) async {
    final payload = jsonDecode(operation.payloadJson) as Map<String, dynamic>;
    final byId = {
      for (final player in authoritative.eligiblePlayers)
        player.playerId.value: player,
    };
    final teams = (payload['teams'] as List).map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      return TeamDraft(
        id: TeamId(row['id'] as String),
        players: (row['player_ids'] as List)
            .map((id) => byId[id as String])
            .whereType<EligibleTeamPlayer>(),
        method: TeamFormationMethod.values.byName(row['method'] as String),
      );
    }).toList();
    final base = Map<String, dynamic>.from(
      payload['base_teams'] as Map? ?? const {},
    );
    final assigned = teams
        .expand((team) => team.players)
        .map((player) => player.playerId)
        .toSet();
    return TeamFormationPreview(
      teams: teams,
      unassigned: authoritative.eligiblePlayers.where(
        (player) => !assigned.contains(player.playerId),
      ),
      unrated: const [],
      method: teams.isEmpty ? TeamFormationMethod.manual : teams.first.method,
      baseTeamVersions: {
        for (final entry in base.entries)
          TeamId(entry.key): (entry.value as num).toInt(),
      },
    );
  }

  Future<void> acceptOperation(String id) => (database.delete(
    database.teamFormationOutboxOperations,
  )..where((row) => row.id.equals(id))).go();

  Future<void> markOperation(String id, String status, String message) =>
      (database.update(
        database.teamFormationOutboxOperations,
      )..where((row) => row.id.equals(id))).write(
        TeamFormationOutboxOperationsCompanion(
          status: Value(status),
          failureMessage: Value(message),
        ),
      );

  Future<TeamPullCursor?> readPullCheckpoint() async {
    final row = await database
        .select(database.teamFormationPullCheckpoints)
        .getSingleOrNull();
    return row == null
        ? null
        : TeamPullCursor(
            row.cursorUpdatedAt.toUtc(),
            DivisionId(row.cursorDivisionId),
          );
  }

  /// Applies a complete page and cursor together. A protected division blocks
  /// the page rather than skipping its changes and advancing beyond them.
  Future<bool> reconcilePullPage(
    List<TeamPullAggregate> page,
  ) => database.transaction(() async {
    if (page.isEmpty) return true;
    final previous = await readPullCheckpoint();
    // Identical or older pages are already durably applied.
    if (previous != null && page.last.cursor.compareTo(previous) <= 0) {
      return true;
    }
    TeamPullCursor? ordered;
    for (final aggregate in page) {
      if (ordered != null && aggregate.cursor.compareTo(ordered) <= 0) {
        throw const ValidationFailure(
          field: 'teamPull',
          message: 'Team pull order is invalid.',
        );
      }
      ordered = aggregate.cursor;
    }
    final changes = page
        .where(
          (value) => previous == null || value.cursor.compareTo(previous) > 0,
        )
        .toList();
    for (final aggregate in changes) {
      final pending =
          await (database.select(database.teamFormationOutboxOperations)
                ..where(
                  (row) =>
                      row.divisionId.equals(aggregate.cursor.divisionId.value),
                )
                ..limit(1))
              .getSingleOrNull();
      final conflict =
          await (database.select(database.teamFormationConflicts)
                ..where(
                  (row) =>
                      row.divisionId.equals(aggregate.cursor.divisionId.value) &
                      row.status.equals('unresolved'),
                )
                ..limit(1))
              .getSingleOrNull();
      if (pending != null || conflict != null) return false;
      final division =
          await (database.select(database.eventDivisions)..where(
                (row) =>
                    row.id.equals(aggregate.cursor.divisionId.value) &
                    row.eventId.equals(aggregate.eventId.value),
              ))
              .getSingleOrNull();
      if (division == null) {
        throw const ValidationFailure(
          field: 'teamPull',
          message: 'Pull event/division prerequisites first.',
        );
      }
    }
    // Local formation guards apply to organizer commands, not historical
    // server-authoritative imports. Restore them within this same SQLite
    // transaction; foreign keys and table CHECK constraints stay enabled.
    final guards = await database
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND name IN ('team_members_eligibility_guard', 'team_members_unique_division_guard')",
        )
        .get();
    for (final guard in guards) {
      await database.customStatement(
        'DROP TRIGGER "${guard.read<String>('name')}"',
      );
    }
    try {
      for (final aggregate in changes) {
        for (final team in aggregate.teams) {
          final metadata = team.metadata;
          final row = LocalTeamRow(
            id: team.id.value,
            divisionId: aggregate.cursor.divisionId.value,
            formationMethod: team.method.name,
            displayLabel: team.label,
            createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt,
            deletedAt: metadata.deletedAt,
            version: metadata.recordVersion,
          );
          final existing = await (database.select(
            database.teams,
          )..where((t) => t.id.equals(row.id))).getSingleOrNull();
          if (existing != row) {
            await database.into(database.teams).insertOnConflictUpdate(row);
          }
        }
        for (final member in aggregate.members) {
          final metadata = member.metadata;
          final row = LocalTeamMemberRow(
            teamId: member.teamId.value,
            playerId: member.playerId.value,
            createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt,
            deletedAt: metadata.deletedAt,
            version: metadata.recordVersion,
          );
          final existing =
              await (database.select(database.teamMembers)..where(
                    (m) =>
                        m.teamId.equals(row.teamId) &
                        m.playerId.equals(row.playerId),
                  ))
                  .getSingleOrNull();
          if (existing != row) {
            await database
                .into(database.teamMembers)
                .insertOnConflictUpdate(row);
          }
        }
        final duplicates = await database
            .customSelect(
              'SELECT tm.player_id FROM team_members tm JOIN teams t ON t.id = tm.team_id '
              'WHERE t.division_id = ? AND t.deleted_at IS NULL AND tm.deleted_at IS NULL '
              'GROUP BY tm.player_id HAVING count(*) > 1',
              variables: [
                Variable.withString(aggregate.cursor.divisionId.value),
              ],
            )
            .get();
        if (duplicates.isNotEmpty) {
          throw const ValidationFailure(
            field: 'teamPull',
            message: 'Cloud team membership is inconsistent.',
          );
        }
      }
      final cursor = page.last.cursor;
      await database
          .into(database.teamFormationPullCheckpoints)
          .insertOnConflictUpdate(
            TeamFormationPullCheckpointsCompanion.insert(
              singleton: const Value(1),
              cursorUpdatedAt: cursor.updatedAt,
              cursorDivisionId: cursor.divisionId.value,
              updatedAt: cursor.updatedAt,
            ),
          );
    } finally {
      for (final guard in guards) {
        await database.customStatement(guard.read<String>('sql'));
      }
    }
    return true;
  });
}
