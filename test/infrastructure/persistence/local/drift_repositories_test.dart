import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/money.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_repository.dart';
import 'package:vpc/src/domain/matches/match.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/domain/players/player_repository.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/persistence/local/drift_event_repository.dart';
import 'package:vpc/src/infrastructure/persistence/local/drift_match_repository.dart';
import 'package:vpc/src/infrastructure/persistence/local/drift_player_repository.dart';

import 'persistence_test_support.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() => database.close());

  test(
    'PlayerRepository saves, reads, observes, and excludes tombstones',
    () async {
      final repository = DriftPlayerRepository(database);
      final player = PermanentPlayer(
        id: PlayerId(playerOneId),
        displayName: 'Ada Player',
        metadata: metadata(version: 0),
      );

      expect((await repository.save(player)).isSuccess, isTrue);
      expect(
        success(await repository.getById(player.id)).displayName,
        'Ada Player',
      );
      expect(
        success(
          await repository
              .observe(PlayerSearchQuery(nameContains: 'ada'))
              .first,
        ),
        hasLength(1),
      );

      final deleted = PermanentPlayer(
        id: player.id,
        displayName: player.displayName,
        metadata: metadata(version: 1, deletedAt: deletedAt),
      );
      expect(
        (await repository.save(deleted, expectedVersion: 0)).isSuccess,
        isTrue,
      );
      expect(
        failure(await repository.getById(player.id)),
        isA<NotFoundFailure>(),
      );
    },
  );

  test('PlayerRepository returns typed missing and version failures', () async {
    final repository = DriftPlayerRepository(database);
    final player = PermanentPlayer(
      id: PlayerId(playerOneId),
      displayName: 'Ada Player',
      metadata: metadata(version: 0),
    );

    expect(
      failure(await repository.getById(player.id)),
      isA<NotFoundFailure>(),
    );
    expect(
      failure(await repository.save(player, expectedVersion: 0)),
      isA<NotFoundFailure>(),
    );
    await repository.save(player);
    expect(
      failure(await repository.save(player, expectedVersion: 9)),
      isA<ConflictFailure>(),
    );
  });

  test(
    'PlayerRepository refuses to discard an unimplemented account link',
    () async {
      final repository = DriftPlayerRepository(database);
      final player = PermanentPlayer(
        id: PlayerId(playerOneId),
        displayName: 'Claimed Player',
        accountId: AccountId('00000000-0000-4000-8000-000000000009'),
        metadata: metadata(version: 0),
      );

      expect(failure(await repository.save(player)), isA<ValidationFailure>());
      expect(await database.select(database.players).get(), isEmpty);
    },
  );

  test('EventRepository preserves domain values and query filters', () async {
    final repository = DriftEventRepository(database);
    final event = Event(
      id: EventId(eventOneId),
      name: 'Community Day',
      scheduledAt: DateTime.utc(2026, 9, 1, 8),
      type: EventType.formal,
      status: EventStatus.upcoming,
      entryFee: Money(minorUnits: 25000),
      courtLabel: 'Community Court',
      metadata: metadata(version: 0),
    );

    expect((await repository.save(event)).isSuccess, isTrue);
    final stored = success(await repository.getById(event.id));
    expect(stored.id, event.id);
    expect(stored.entryFee, Money(minorUnits: 25000));
    expect(stored.scheduledAt.isUtc, isTrue);
    expect(stored.metadata.createdAt.microsecond, createdAt.microsecond);
    expect(
      success(
        await repository
            .observe(
              EventQuery(
                statuses: {EventStatus.upcoming},
                type: EventType.formal,
              ),
            )
            .first,
      ),
      hasLength(1),
    );
  });

  test('EventRepository translates lifecycle constraint failures', () async {
    final repository = DriftEventRepository(database);
    final upcoming = Event(
      id: EventId(eventOneId),
      name: 'Community Day',
      scheduledAt: DateTime.utc(2026, 9, 1, 8),
      type: EventType.formal,
      status: EventStatus.upcoming,
      courtLabel: 'Community Court',
      metadata: metadata(version: 0),
    );
    await repository.save(upcoming);

    final skipped = Event(
      id: upcoming.id,
      name: upcoming.name,
      scheduledAt: upcoming.scheduledAt,
      type: upcoming.type,
      status: EventStatus.completed,
      courtLabel: upcoming.courtLabel,
      metadata: metadata(version: 1),
    );
    expect(
      failure(await repository.save(skipped, expectedVersion: 0)),
      isA<ConflictFailure>(),
    );
  });

  test('MatchRepository saves, observes, and returns typed failures', () async {
    await insertEventGraph(database);
    final repository = DriftMatchRepository(database);
    final match = Match(
      id: MatchId(matchOneId),
      divisionId: DivisionId(divisionOneId),
      status: MatchStatus.scheduled,
      roundNumber: 1,
      sequenceNumber: 1,
      metadata: metadata(version: 0),
    );

    expect((await repository.save(match)).isSuccess, isTrue);
    expect(
      success(await repository.getById(match.id)).status,
      MatchStatus.scheduled,
    );
    expect(
      success(await repository.observeForDivision(match.divisionId).first),
      hasLength(1),
    );
    expect(
      failure(await repository.save(match, expectedVersion: 5)),
      isA<ConflictFailure>(),
    );
    expect(
      failure(
        await repository.getById(
          MatchId('00000000-0000-4000-8000-000000000099'),
        ),
      ),
      isA<NotFoundFailure>(),
    );
  });
}

RecordMetadata metadata({required int version, DateTime? deletedAt}) =>
    RecordMetadata(
      createdAt: createdAt,
      updatedAt: updatedAt,
      recordVersion: version,
      deletedAt: deletedAt,
    );

final deletedAt = DateTime.utc(2026, 8, 26, 3, 4, 5, 678, 901);

T success<T>(RepositoryResult<T> result) => result.when(
  success: (value) => value,
  failure: (value) => throw TestFailure('Expected success, got $value'),
);

DomainFailure failure<T>(RepositoryResult<T> result) => result.when(
  success: (value) => throw TestFailure('Expected failure, got $value'),
  failure: (value) => value,
);
