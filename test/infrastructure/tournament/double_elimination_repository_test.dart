import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/tournament/double_elimination_service.dart';
import 'package:vpc/src/application/tournament/single_elimination_service.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/matches/validated_score.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/tournament/drift_double_elimination_repository.dart';
import 'package:vpc/src/infrastructure/tournament/double_elimination_codec.dart';

import '../persistence/local/persistence_test_support.dart';

String id(int n) => '15000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final class _Ids implements BracketIds, BracketClock {
  var next = 500;
  @override
  MatchId matchId() => MatchId(id(next++));
  @override
  SyncOperationId operationId() => SyncOperationId(id(next++));
  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 5);
}

Future<void> seed(AppDatabase db, int count) async {
  await db.into(db.events).insert(eventCompanion(status: 'registration'));
  await db
      .into(db.eventDivisions)
      .insert(divisionCompanion(format: 'doubleElimination'));
  for (var index = 0; index < count; index++) {
    final teamId = id(100 + index);
    await db.into(db.teams).insert(teamCompanion(id: teamId));
    for (var member = 0; member < 2; member++) {
      final playerId = id(index * 2 + member + 1);
      await db
          .into(db.players)
          .insert(
            playerCompanion(
              id: playerId,
              displayName: 'VPC M15 Sample ${index * 2 + member + 1}',
            ),
          );
      final participantId = id(200 + index * 2 + member);
      await db
          .into(db.eventParticipants)
          .insert(
            EventParticipantsCompanion.insert(
              id: participantId,
              eventId: eventOneId,
              playerId: playerId,
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
              id: id(300 + index * 2 + member),
              divisionId: divisionOneId,
              eventParticipantId: participantId,
              createdAt: createdAt,
              updatedAt: updatedAt,
              version: 0,
            ),
          );
      await db
          .into(db.teamMembers)
          .insert(teamMemberCompanion(teamId: teamId, playerId: playerId));
    }
  }
}

void main() {
  late AppDatabase database;
  late DriftDoubleEliminationRepository repository;
  late DoubleEliminationService service;
  setUp(() async {
    database = AppDatabase.inMemory();
    repository = DriftDoubleEliminationRepository(database);
    final ids = _Ids();
    service = DoubleEliminationService(
      repository: repository,
      ids: ids,
      clock: ids,
    );
    await seed(database, 3);
  });
  tearDown(() => database.close());

  Future<DoubleEliminationContext> load() async => (await repository.load(
    EventId(eventOneId),
    DivisionId(divisionOneId),
  )).when(success: (value) => value, failure: (failure) => throw failure);

  test('generation, snapshot and outbox commit atomically', () async {
    final context = await load();
    final result = await service.generate(
      context,
      AuthorizationState.organizer,
      seedOrder: context.teams.map((team) => team.team.id).toList(),
      confirmed: true,
    );
    expect(result.isSuccess, isTrue);
    expect(await database.select(database.matches).get(), hasLength(4));
    expect(
      await database.select(database.doubleEliminationSnapshots).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.doubleEliminationOutbox).get(),
      hasLength(1),
    );
  });

  test('outbox failure rolls back complete bracket generation', () async {
    await database.customStatement(
      "CREATE TRIGGER fail_m15_outbox BEFORE INSERT ON double_elimination_outbox BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
    );
    final context = await load();
    expect(
      await service.generate(
        context,
        AuthorizationState.organizer,
        seedOrder: context.teams.map((team) => team.team.id).toList(),
        confirmed: true,
      ),
      isA<RepositoryFailure>(),
    );
    expect(await database.select(database.matches).get(), isEmpty);
    expect(
      await database.select(database.doubleEliminationSnapshots).get(),
      isEmpty,
    );
  });

  test(
    'local progression activates reset and persists final placements',
    () async {
      var context = await load();
      await service.generate(
        context,
        AuthorizationState.organizer,
        seedOrder: context.teams.map((team) => team.team.id).toList(),
        confirmed: true,
      );
      final reservedResetId = (await load()).bracket!.reservedResetMatchId;
      await database.customStatement("UPDATE events SET status='inProgress'");
      while (true) {
        context = await load();
        if (context.bracket!.decided) break;
        final ready = context.bracket!.matches.entries
            .where((entry) => entry.value.status.name == 'queued')
            .first;
        await service.change(
          context,
          AuthorizationState.organizer,
          action: BracketAction.start,
          key: ready.key,
        );
        context = await load();
        final isGf1 = ready.key.value == 'de/finals/gf1';
        await service.change(
          context,
          AuthorizationState.organizer,
          action: BracketAction.result,
          key: ready.key,
          score: isGf1 ? ValidatedScore(5, 11) : ValidatedScore(11, 5),
        );
      }
      context = await load();
      expect(context.bracket!.grandFinalTwo, isNotNull);
      expect(context.bracket!.grandFinalTwo!.id, reservedResetId);
      expect(context.bracket!.champion, isNotNull);
      expect(
        (await database.select(database.divisionPlacements).get()).where(
          (row) => row.deletedAt == null,
        ),
        hasLength(2),
      );
    },
  );

  test('legacy queued reset payload reuses the generation identity', () async {
    var context = await load();
    await service.generate(
      context,
      AuthorizationState.organizer,
      seedOrder: context.teams.map((team) => team.team.id).toList(),
      confirmed: true,
    );
    context = await load();
    final reserved = context.bracket!.reservedResetMatchId.value;
    final raw = jsonDecode(
      (await repository.rows(
            r"SELECT payload_json FROM double_elimination_outbox WHERE json_extract(payload_json,'$.action')='generate'",
          )).single['payload_json']
          as String,
    ) as Map<String, Object?>;
    final proposed = Map<String, Object?>.from(raw['proposed'] as Map)
      ..remove('reset_match_id');
    raw['proposed'] = proposed;

    final normalized = normalizeDoubleBracketResetIdentity(
      raw['proposed'],
      reserved,
    );
    raw['proposed'] = normalized;
    final decoded = decodeDoubleCommand(raw);

    expect(decoded.proposed!.reservedResetMatchId.value, reserved);
    expect(
      decoded.proposed!.matches.values.map((match) => match.id.value),
      isNot(contains(id(999))),
    );
  });
}
