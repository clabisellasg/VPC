import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/persistence/local/drift_mapping.dart';

import 'persistence_test_support.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'fresh schema creates operational and bounded sync tables at version 6',
    () async {
      final rows = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' AND name <> 'drift_schema' ORDER BY name",
          )
          .get();

      expect(database.schemaVersion, 6);
      expect(rows.map((row) => row.read<String>('name')).toSet(), {
        'court_queue_entries',
        'division_participants',
        'division_placements',
        'event_divisions',
        'event_participants',
        'events',
        'match_dependencies',
        'matches',
        'participant_payments',
        'players',
        'team_members',
        'teams',
        'sync_conflicts',
        'sync_outbox_operations',
        'sync_pull_checkpoints',
        'event_setup_outbox_operations',
        'event_setup_pull_checkpoints',
        'event_setup_conflicts',
        'participation_outbox_operations',
        'participation_pull_checkpoints',
        'participation_conflicts',
        'team_formation_outbox_operations',
        'team_formation_pull_checkpoints',
        'team_formation_conflicts',
      });
    },
  );

  test('foreign keys are enabled and reject missing parents', () async {
    final pragma = await database
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    expect(pragma.read<int>('foreign_keys'), 1);

    await expectLater(
      database.into(database.eventDivisions).insert(divisionCompanion()),
      throwsA(anything),
    );
  });

  test(
    'null formats block in-progress and structural edits lock after upcoming',
    () async {
      await database.into(database.events).insert(eventCompanion());
      await database
          .into(database.eventDivisions)
          .insert(
            divisionCompanion().copyWith(tournamentFormat: const Value(null)),
          );
      await (database.update(database.events)
            ..where((row) => row.id.equals(eventOneId)))
          .write(const EventsCompanion(status: Value('registration')));
      await expectLater(
        (database.update(database.events)
              ..where((row) => row.id.equals(eventOneId)))
            .write(const EventsCompanion(status: Value('inProgress'))),
        throwsA(anything),
      );
      await expectLater(
        (database.update(database.eventDivisions)
              ..where((row) => row.id.equals(divisionOneId)))
            .write(const EventDivisionsCompanion(name: Value('Renamed'))),
        throwsA(anything),
      );
    },
  );

  test(
    'approved enum names map exactly and schema guards are installed',
    () async {
      for (final value in EventType.values) {
        expect(
          enumValue(EventType.values, value.name, field: 'eventType'),
          value,
        );
      }
      for (final value in EventStatus.values) {
        expect(
          enumValue(EventStatus.values, value.name, field: 'eventStatus'),
          value,
        );
      }
      for (final value in TournamentFormat.values) {
        expect(
          enumValue(TournamentFormat.values, value.name, field: 'format'),
          value,
        );
      }
      for (final value in CheckInStatus.values) {
        expect(
          enumValue(CheckInStatus.values, value.name, field: 'checkIn'),
          value,
        );
      }
      for (final value in PaymentStatus.values) {
        expect(
          enumValue(PaymentStatus.values, value.name, field: 'payment'),
          value,
        );
      }
      for (final value in TeamFormationMethod.values) {
        expect(
          enumValue(TeamFormationMethod.values, value.name, field: 'formation'),
          value,
        );
      }
      for (final value in MatchStatus.values) {
        expect(
          enumValue(MatchStatus.values, value.name, field: 'matchStatus'),
          value,
        );
      }
      for (final value in MatchDependencySource.values) {
        expect(
          enumValue(MatchDependencySource.values, value.name, field: 'source'),
          value,
        );
      }
      for (final value in MatchDestinationSlot.values) {
        expect(
          enumValue(MatchDestinationSlot.values, value.name, field: 'slot'),
          value,
        );
      }

      final triggers = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
          .get();
      expect(triggers, hasLength(21));
      expect(
        triggers.map((row) => row.read<String>('name')),
        containsAll([
          'matches_final_score_insert_guard',
          'matches_final_score_update_guard',
          'matches_completed_result_lock',
        ]),
      );
    },
  );

  test(
    'active uniqueness constraints reject duplicate participation',
    () async {
      await insertEventGraph(database);
      await database
          .into(database.eventParticipants)
          .insert(
            EventParticipantsCompanion.insert(
              id: participantOneId,
              eventId: eventOneId,
              playerId: playerOneId,
              checkInStatus: 'checkedIn',
              createdAt: createdAt,
              updatedAt: updatedAt,
              version: 0,
            ),
          );

      await expectLater(
        database
            .into(database.eventParticipants)
            .insert(
              EventParticipantsCompanion.insert(
                id: participantTwoId,
                eventId: eventOneId,
                playerId: playerOneId,
                checkInStatus: 'notPresent',
                createdAt: createdAt,
                updatedAt: updatedAt,
                version: 0,
              ),
            ),
        throwsA(anything),
      );
    },
  );

  test('UUID, money, UTC, enums, version, and tombstone round-trip', () async {
    final deletedAt = DateTime.utc(2026, 8, 26, 3, 4, 5, 678, 901);
    await database
        .into(database.events)
        .insert(eventCompanion(version: 7, deletedAt: deletedAt));

    final row = await database.select(database.events).getSingle();
    expect(row.id, eventOneId);
    expect(row.entryFeeMinorUnits, 25000);
    expect(row.entryFeeCurrency, 'PHP');
    expect(row.eventType, 'formal');
    expect(row.status, 'upcoming');
    expect(row.version, 7);
    expect(row.createdAt, createdAt);
    expect(row.updatedAt, updatedAt);
    expect(row.deletedAt, deletedAt);
    expect(row.createdAt.isUtc, isTrue);
    expect(row.createdAt.microsecond, createdAt.microsecond);
  });

  test('successful multi-table transaction commits every record', () async {
    await insertEventGraph(database);
    await database
        .into(database.players)
        .insert(playerCompanion(id: playerTwoId, displayName: 'Second Player'));
    await (database.update(database.events)
          ..where((row) => row.id.equals(eventOneId)))
        .write(const EventsCompanion(status: Value('registration')));
    for (final entry in [
      (participantOneId, playerOneId),
      (participantTwoId, playerTwoId),
    ]) {
      await database
          .into(database.eventParticipants)
          .insert(
            EventParticipantsCompanion.insert(
              id: entry.$1,
              eventId: eventOneId,
              playerId: entry.$2,
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
              id: '00000000-0000-4000-8000-0000000000${entry.$1 == participantOneId ? '61' : '62'}',
              divisionId: divisionOneId,
              eventParticipantId: entry.$1,
              createdAt: createdAt,
              updatedAt: updatedAt,
              version: 0,
            ),
          );
    }
    await database.insertTeamWithMembers(teamCompanion(), [
      teamMemberCompanion(),
      teamMemberCompanion(playerId: playerTwoId),
    ]);

    expect(await database.select(database.teams).get(), hasLength(1));
    expect(await database.select(database.teamMembers).get(), hasLength(2));
  });

  test('failed multi-table transaction rolls back every record', () async {
    await insertEventGraph(database);

    await expectLater(
      database.insertTeamWithMembers(teamCompanion(), [
        teamMemberCompanion(),
        teamMemberCompanion(),
      ]),
      throwsA(anything),
    );

    expect(await database.select(database.teams).get(), isEmpty);
    expect(await database.select(database.teamMembers).get(), isEmpty);
  });

  test('invalid stored UUID is rejected by the domain mapper', () {
    final row = LocalPlayerRow(
      createdAt: createdAt,
      updatedAt: updatedAt,
      version: 0,
      id: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
      displayName: 'Invalid Row',
    );

    expect(() => playerFromRow(row), throwsA(isA<ValidationFailure>()));
  });

  test('close reliably prevents later database access', () async {
    await database.customSelect('SELECT 1').get();
    await database.close();

    await expectLater(
      database.customSelect('SELECT 1').get(),
      throwsA(anything),
    );
  });
}
