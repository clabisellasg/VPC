import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/teams/team_formation_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/players/player_skill.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/teams/drift_team_formation_store.dart';

import '../persistence/local/persistence_test_support.dart';

void main() {
  late AppDatabase database;
  late DriftTeamFormationStore store;
  setUp(() async {
    database = AppDatabase.inMemory();
    store = DriftTeamFormationStore(database);
    await insertEventGraph(database);
    await database
        .into(database.players)
        .insert(
          playerCompanion(
            id: playerTwoId,
            displayName: 'Second',
            version: 0,
          ).copyWith(skillLevel: const Value(2)),
        );
    await (database.update(database.players)
          ..where((row) => row.id.equals(playerOneId)))
        .write(const PlayersCompanion(skillLevel: Value(5)));
    await (database.update(database.events)
          ..where((row) => row.id.equals(eventOneId)))
        .write(const EventsCompanion(status: Value('registration')));
    for (final item in [
      (participantOneId, playerOneId),
      (participantTwoId, playerTwoId),
    ]) {
      await database
          .into(database.eventParticipants)
          .insert(
            EventParticipantsCompanion.insert(
              id: item.$1,
              eventId: eventOneId,
              playerId: item.$2,
              checkInStatus: 'checkedIn',
              createdAt: createdAt,
              updatedAt: updatedAt,
              version: 0,
            ),
          );
      await database
          .into(database.divisionParticipants)
          .insert(
            DivisionParticipantsCompanion.insert(
              id: '00000000-0000-4000-8000-0000000000${item.$1 == participantOneId ? '71' : '72'}',
              divisionId: divisionOneId,
              eventParticipantId: item.$1,
              createdAt: createdAt,
              updatedAt: updatedAt,
              version: 0,
            ),
          );
    }
  });
  tearDown(() => database.close());
  test(
    'eligible players include checked-in division members and skill',
    () async {
      final result = await store.load(
        EventId(eventOneId),
        DivisionId(divisionOneId),
      );
      final snapshot =
          (result as RepositorySuccess<TeamFormationSnapshot>).value;
      expect(snapshot.eligiblePlayers, hasLength(2));
      expect(snapshot.eligiblePlayers.first.skill, PlayerSkill(5));
    },
  );
  test('replacement and outbox commit atomically with two members', () async {
    final snapshot = ((await store.load(
      EventId(eventOneId),
      DivisionId(divisionOneId),
    )) as RepositorySuccess<TeamFormationSnapshot>).value;
    final preview = TeamFormationPreview(
      teams: [
        TeamDraft(
          id: TeamId(teamOneId),
          players: snapshot.eligiblePlayers,
          method: TeamFormationMethod.balanced,
        ),
      ],
      unassigned: const [],
      unrated: const [],
      method: TeamFormationMethod.balanced,
    );
    final result = await store.replace(
      current: snapshot,
      preview: preview,
      operationId: SyncOperationId('00000000-0000-4000-8000-000000000080'),
    );
    expect(result, isA<RepositorySuccess<TeamFormationSnapshot>>());
    expect(await database.select(database.teams).get(), hasLength(1));
    expect(await database.select(database.teamMembers).get(), hasLength(2));
    expect(
      await database.select(database.teamFormationOutboxOperations).get(),
      hasLength(1),
    );
  });
}
