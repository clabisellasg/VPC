import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/tournament/single_elimination_service.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/matches/validated_score.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/tournament/drift_bracket_repository.dart';

import '../persistence/local/persistence_test_support.dart';

String id(int n) => '13000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final class TestBracketIds implements BracketIds, BracketClock {
  int next = 500;
  @override
  MatchId matchId() => MatchId(id(next++));
  @override
  SyncOperationId operationId() => SyncOperationId(id(next++));
  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 4);
}

Future<void> seedBracketTeams(AppDatabase db, int count) async {
  await db.into(db.events).insert(eventCompanion(status: 'registration'));
  await db.into(db.eventDivisions).insert(divisionCompanion());
  for (var i = 0; i < count; i++) {
    final team = id(100 + i);
    await db.into(db.teams).insert(teamCompanion(id: team));
    for (var j = 0; j < 2; j++) {
      final player = id(i * 2 + j + 1),
          participant = id(200 + i * 2 + j),
          assignment = id(300 + i * 2 + j);
      await db
          .into(db.players)
          .insert(
            playerCompanion(
              id: player,
              displayName: 'VPC M13 Sample ${i * 2 + j}',
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
  late DriftBracketRepository repository;
  late SingleEliminationService service;
  Future<BracketContext> load() async => (await repository.load(
    EventId(eventOneId),
    DivisionId(divisionOneId),
  )).when(success: (v) => v, failure: (f) => throw f);
  setUp(() async {
    db = AppDatabase.inMemory();
    repository = DriftBracketRepository(db);
    final ids = TestBracketIds();
    service = SingleEliminationService(
      repository: repository,
      ids: ids,
      clock: ids,
    );
    await seedBracketTeams(db, 3);
  });
  tearDown(() => db.close());
  test('preview writes nothing; generation and outbox are atomic', () async {
    final context = await load(),
        order = (await load()).teams.map((t) => t.team.id).toList();
    expect(
      service.preview(context, AuthorizationState.guest),
      isA<RepositoryFailure>(),
    );
    expect(
      service.preview(context, AuthorizationState.member),
      isA<RepositoryFailure>(),
    );
    expect(
      service.preview(context, AuthorizationState.organizer).isSuccess,
      isTrue,
    );
    expect(await db.select(db.matches).get(), isEmpty);
    final result = await service.generate(
      context,
      AuthorizationState.organizer,
      seedOrder: order,
      confirmed: true,
    );
    final generated = result.when(success: (v) => v, failure: (f) => throw f);
    expect(generated.disposition, BracketDisposition.pending);
    expect(await db.select(db.matches).get(), hasLength(2));
    expect(await db.select(db.matchDependencies).get(), hasLength(1));
    expect(await db.select(db.singleEliminationOutbox).get(), hasLength(1));
  });
  test('outbox failure rolls back the complete generation', () async {
    await db.customStatement(
      "CREATE TRIGGER test_outbox_failure BEFORE INSERT ON single_elimination_outbox BEGIN SELECT RAISE(ABORT,'test failure'); END",
    );
    final context = await load();
    expect(
      await service.generate(
        context,
        AuthorizationState.organizer,
        seedOrder: context.teams.map((t) => t.team.id).toList(),
        confirmed: true,
      ),
      isA<RepositoryFailure>(),
    );
    expect(await db.select(db.matches).get(), isEmpty);
    expect(await db.select(db.matchDependencies).get(), isEmpty);
    expect(await db.select(db.singleEliminationSnapshots).get(), isEmpty);
  });
  test(
    'local final progression, placement correction and immutable audit',
    () async {
      var context = await load();
      await service.generate(
        context,
        AuthorizationState.organizer,
        seedOrder: context.teams.map((t) => t.team.id).toList(),
        confirmed: true,
      );
      await db.customStatement("UPDATE events SET status='inProgress'");
      context = await load();
      for (final key in context.bracket!.plan.matches.map((m) => m.key)) {
        var result = await service.change(
          await load(),
          AuthorizationState.organizer,
          action: BracketAction.start,
          key: key,
        );
        expect(result.isSuccess, isTrue);
        result = await service.change(
          await load(),
          AuthorizationState.organizer,
          action: BracketAction.result,
          key: key,
          score: ValidatedScore(11, 2),
        );
        result.when(success: (v) => v, failure: (f) => throw f);
      }
      context = await load();
      expect(context.bracket!.champion, isNotNull);
      final last = context.bracket!.plan.matches.last.key;
      final corrected = await service.change(
        context,
        AuthorizationState.organizer,
        action: BracketAction.correct,
        key: last,
        score: ValidatedScore(8, 11),
        reason: 'VPC M13 synthetic correction',
      );
      corrected.when(success: (v) => v, failure: (f) => throw f);
      expect(await db.select(db.matchResultRevisions).get(), hasLength(1));
      final placements = await db.select(db.divisionPlacements).get();
      expect(placements.where((p) => p.deletedAt == null), hasLength(2));
      expect(placements.where((p) => p.deletedAt != null), hasLength(2));
      await expectLater(
        db.customStatement('DELETE FROM match_result_revisions'),
        throwsA(anything),
      );
    },
  );
}
