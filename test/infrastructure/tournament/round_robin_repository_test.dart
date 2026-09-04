import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/tournament/round_robin_service.dart';
import 'package:vpc/src/application/tournament/single_elimination_service.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/matches/validated_score.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/tournament/drift_round_robin_repository.dart';

import '../persistence/local/persistence_test_support.dart';

String rrId(int n) =>
    '14000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final class TestRoundRobinIds implements BracketIds, BracketClock {
  int next = 500;
  @override
  MatchId matchId() => MatchId(rrId(next++));
  @override
  SyncOperationId operationId() => SyncOperationId(rrId(next++));
  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 4);
}

Future<void> seedRoundRobinTeams(AppDatabase db, int count) async {
  await db.into(db.events).insert(eventCompanion(status: 'registration'));
  await db
      .into(db.eventDivisions)
      .insert(
        divisionCompanion().copyWith(
          tournamentFormat: const Value('singleRoundRobin'),
        ),
      );
  for (var index = 0; index < count; index++) {
    final team = rrId(100 + index);
    await db.into(db.teams).insert(teamCompanion(id: team));
    for (var member = 0; member < 2; member++) {
      final player = rrId(index * 2 + member + 1),
          participant = rrId(200 + index * 2 + member),
          assignment = rrId(300 + index * 2 + member);
      await db
          .into(db.players)
          .insert(
            playerCompanion(
              id: player,
              displayName: 'VPC M14 Sample ${index * 2 + member}',
            ),
          );
      await db
          .into(db.eventParticipants)
          .insert(
            EventParticipantsCompanion.insert(
              id: participant,
              eventId: eventOneId,
              playerId: player,
              checkInStatus: 'checkedIn',
              createdAt: createdAt,
              updatedAt: updatedAt,
              version: 0,
            ),
          );
      await db
          .into(db.divisionParticipants)
          .insert(
            DivisionParticipantsCompanion.insert(
              id: assignment,
              divisionId: divisionOneId,
              eventParticipantId: participant,
              createdAt: createdAt,
              updatedAt: updatedAt,
              version: 0,
            ),
          );
      await db
          .into(db.teamMembers)
          .insert(teamMemberCompanion(teamId: team, playerId: player));
    }
  }
}

void main() {
  late AppDatabase db;
  late DriftRoundRobinRepository repository;
  late RoundRobinService service;
  Future<RoundRobinContext> load() async => (await repository.load(
    EventId(eventOneId),
    DivisionId(divisionOneId),
  )).when(success: (value) => value, failure: (failure) => throw failure);

  setUp(() async {
    db = AppDatabase.inMemory();
    repository = DriftRoundRobinRepository(db);
    final ids = TestRoundRobinIds();
    service = RoundRobinService(repository: repository, ids: ids, clock: ids);
    await seedRoundRobinTeams(db, 3);
  });
  tearDown(() => db.close());

  test('preview is read-only and confirmed generation is atomic', () async {
    final context = await load();
    expect(
      service.preview(context, AuthorizationState.guest),
      isA<RepositoryFailure>(),
    );
    final preview = service.preview(context, AuthorizationState.organizer);
    expect(preview.isSuccess, isTrue);
    expect(await db.select(db.matches).get(), isEmpty);
    final result = await service.generate(
      context,
      AuthorizationState.organizer,
      seedOrder: context.teams.map((team) => team.team.id).toList(),
      confirmed: true,
    );
    expect(result.isSuccess, isTrue);
    expect(await db.select(db.matches).get(), hasLength(3));
    expect(await db.select(db.matchDependencies).get(), isEmpty);
    expect(await db.select(db.roundRobinOutbox).get(), hasLength(1));
  });

  test('outbox failure rolls back all generated schedule records', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_rr_outbox BEFORE INSERT ON round_robin_outbox "
      "BEGIN SELECT RAISE(ABORT,'test failure'); END",
    );
    final context = await load();
    final result = await service.generate(
      context,
      AuthorizationState.organizer,
      seedOrder: context.teams.map((team) => team.team.id).toList(),
      confirmed: true,
    );
    expect(result, isA<RepositoryFailure>());
    expect(await db.select(db.matches).get(), isEmpty);
    expect(await db.select(db.roundRobinSnapshots).get(), isEmpty);
  });

  test('results derive placements and correction preserves audit', () async {
    var context = await load();
    await service.generate(
      context,
      AuthorizationState.organizer,
      seedOrder: context.teams.map((team) => team.team.id).toList(),
      confirmed: true,
    );
    await db.customStatement("UPDATE events SET status='inProgress'");
    context = await load();
    for (final planned in context.tournament!.plan.matches) {
      await service.change(
        await load(),
        AuthorizationState.organizer,
        action: RoundRobinAction.start,
        key: planned.key,
      );
      final result = await service.change(
        await load(),
        AuthorizationState.organizer,
        action: RoundRobinAction.result,
        key: planned.key,
        score: ValidatedScore(11, 5),
      );
      expect(result.isSuccess, isTrue);
    }
    context = await load();
    expect(context.tournament!.complete, isTrue);
    expect(
      (await db.select(db.divisionPlacements).get()).where(
        (row) => row.deletedAt == null,
      ),
      hasLength(3),
    );
    final corrected = await service.change(
      context,
      AuthorizationState.organizer,
      action: RoundRobinAction.correct,
      key: context.tournament!.plan.matches.first.key,
      score: ValidatedScore(5, 11),
      reason: 'VPC M14 deterministic correction',
    );
    expect(corrected.isSuccess, isTrue);
    expect(await db.select(db.matchResultRevisions).get(), hasLength(1));
    expect(
      (await db.select(db.divisionPlacements).get()).where(
        (row) => row.deletedAt != null,
      ),
      hasLength(3),
    );
  });
}
