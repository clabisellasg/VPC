import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/court/court_queue_service.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/infrastructure/court/drift_court_queue_repository.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';

import '../persistence/local/persistence_test_support.dart';

String id(int value) =>
    '16100000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

Future<void> seed(
  AppDatabase db, {
  int offset = 0,
  String eventStatus = 'inProgress',
}) async {
  await db
      .into(db.events)
      .insert(eventCompanion(id: id(1 + offset), status: eventStatus));
  await db
      .into(db.eventDivisions)
      .insert(
        divisionCompanion(
          id: id(2 + offset),
          eventId: id(1 + offset),
          format: 'singleElimination',
        ),
      );
  await db
      .into(db.teams)
      .insert(
        TeamsCompanion.insert(
          id: id(3 + offset),
          divisionId: id(2 + offset),
          formationMethod: 'manual',
          displayLabel: const Value('Team One'),
          createdAt: createdAt,
          updatedAt: updatedAt,
          version: 0,
        ),
      );
  await db
      .into(db.teams)
      .insert(
        TeamsCompanion.insert(
          id: id(4 + offset),
          divisionId: id(2 + offset),
          formationMethod: 'manual',
          displayLabel: const Value('Team Two'),
          createdAt: createdAt,
          updatedAt: updatedAt,
          version: 0,
        ),
      );
  await db
      .into(db.matches)
      .insert(
        MatchesCompanion.insert(
          id: id(5 + offset),
          divisionId: id(2 + offset),
          sideOneTeamId: Value(id(3 + offset)),
          sideTwoTeamId: Value(id(4 + offset)),
          status: 'queued',
          roundNumber: const Value(1),
          sequenceNumber: const Value(1),
          createdAt: createdAt,
          updatedAt: updatedAt,
          version: 0,
        ),
      );
}

CourtQueueCommand reconcileCommand() => CourtQueueCommand(
  operationId: SyncOperationId(id(20)),
  eventId: EventId(id(1)),
  action: 'reconcile',
  createdAt: DateTime.utc(2026, 9, 6),
  expectedMatchVersion: -1,
  entryIds: {MatchId(id(5)): CourtQueueEntryId(id(10))},
);

void main() {
  late AppDatabase db;
  late DriftCourtQueueRepository repository;
  setUp(() async {
    db = AppDatabase.inMemory();
    repository = DriftCourtQueueRepository(db);
    await seed(db);
  });
  tearDown(() => db.close());

  test(
    'reconciliation inserts a READY match once with atomic outbox',
    () async {
      expect(
        (await repository.reconcile(reconcileCommand())).isSuccess,
        isTrue,
      );
      expect(await db.select(db.courtQueueEntries).get(), hasLength(1));
      expect(await db.select(db.courtQueueOutbox).get(), hasLength(1));
      expect(
        (await repository.reconcile(reconcileCommand())).isSuccess,
        isTrue,
      );
      expect(await db.select(db.courtQueueEntries).get(), hasLength(1));
    },
  );

  test(
    'authoritative replacement uses an ISO timestamp not before creation',
    () async {
      expect(
        (await repository.reconcile(reconcileCommand())).isSuccess,
        isTrue,
      );
      final beforeCreation = DateTime.utc(2026, 8, 25, 23, 59, 59);

      await repository.tombstoneEntriesForAuthoritativeReplace(
        EventId(id(1)),
        beforeCreation,
      );

      final entry = await db.select(db.courtQueueEntries).getSingle();
      expect(entry.deletedAt, entry.createdAt);
      expect(entry.updatedAt, entry.createdAt);
    },
  );

  test(
    'unlabeled teams use their player names instead of internal IDs',
    () async {
      await db.customStatement('DROP TRIGGER team_members_eligibility_guard');
      await db.customStatement(
        'DROP TRIGGER team_members_unique_division_guard',
      );
      for (final entry in <(int, String)>[
        (30, 'Ada'),
        (31, 'Bea'),
        (32, 'Cora'),
        (33, 'Dina'),
      ]) {
        await db
            .into(db.players)
            .insert(playerCompanion(id: id(entry.$1), displayName: entry.$2));
      }
      await db.customStatement(
        'UPDATE teams SET display_label=NULL WHERE id IN (?,?)',
        [id(3), id(4)],
      );
      for (final membership in <(int, int)>[
        (3, 30),
        (3, 31),
        (4, 32),
        (4, 33),
      ]) {
        await db
            .into(db.teamMembers)
            .insert(
              teamMemberCompanion(
                teamId: id(membership.$1),
                playerId: id(membership.$2),
              ),
            );
      }

      final snapshot = (await repository.load(EventId(id(1))))
          .when(success: (value) => value, failure: (failure) => throw failure);
      expect(snapshot.unqueuedReady.single.sideOneLabel, 'Ada / Bea');
      expect(snapshot.unqueuedReady.single.sideTwoLabel, 'Cora / Dina');
    },
  );

  test('queue positions follow round before match position', () async {
    for (final values in <(int, int, int)>[(6, 2, 1), (7, 1, 2)]) {
      await db
          .into(db.matches)
          .insert(
            MatchesCompanion.insert(
              id: id(values.$1),
              divisionId: id(2),
              sideOneTeamId: Value(id(3)),
              sideTwoTeamId: Value(id(4)),
              status: 'queued',
              roundNumber: Value(values.$2),
              sequenceNumber: Value(values.$3),
              createdAt: createdAt,
              updatedAt: updatedAt,
              version: 0,
            ),
          );
    }
    final result = await repository.reconcile(
      CourtQueueCommand(
        operationId: SyncOperationId(id(24)),
        eventId: EventId(id(1)),
        action: 'reconcile',
        createdAt: DateTime.utc(2026, 9, 6),
        expectedMatchVersion: -1,
        entryIds: {
          MatchId(id(5)): CourtQueueEntryId(id(10)),
          MatchId(id(6)): CourtQueueEntryId(id(11)),
          MatchId(id(7)): CourtQueueEntryId(id(12)),
        },
      ),
    );
    final snapshot = result.when(
      success: (value) => value,
      failure: (failure) => throw failure,
    );
    expect(
      snapshot.queue
          .map(
            (entry) => (
              entry.match.match.roundNumber,
              entry.match.match.sequenceNumber,
            ),
          )
          .toList(),
      [(1, 1), (1, 2), (2, 1)],
    );
  });

  test('outbox failure rolls back queue insertion completely', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_queue_outbox BEFORE INSERT ON court_queue_outbox BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
    );
    expect((await repository.reconcile(reconcileCommand())).isSuccess, isFalse);
    expect(await db.select(db.courtQueueEntries).get(), isEmpty);
  });

  test(
    'start is explicit, atomic and rejects a second current match',
    () async {
      await repository.reconcile(reconcileCommand());
      await db.customStatement(
        'INSERT INTO single_elimination_snapshots(division_id,bracket_json) VALUES(?,?)',
        [
          id(2),
          jsonEncode({
            'matches': [
              {
                'id': id(5),
                'status': 'queued',
                'updated_at': updatedAt.toIso8601String(),
                'version': 0,
              },
            ],
          }),
        ],
      );
      final start = CourtQueueCommand(
        operationId: SyncOperationId(id(21)),
        eventId: EventId(id(1)),
        action: 'start',
        createdAt: DateTime.utc(2026, 9, 6, 1),
        matchId: MatchId(id(5)),
        expectedMatchVersion: 0,
      );
      expect((await repository.start(start)).isSuccess, isTrue);
      final snapshot = (await repository.load(EventId(id(1))))
          .when(success: (value) => value, failure: (failure) => throw failure);
      expect(snapshot.current?.match.id, MatchId(id(5)));
      expect(snapshot.currentEntry?.matchId, MatchId(id(5)));
      final stored = await db.select(db.singleEliminationSnapshots).getSingle();
      final tournament = jsonDecode(stored.bracketJson) as Map<String, dynamic>;
      final storedMatch = (tournament['matches'] as List).single as Map;
      expect(storedMatch['status'], 'inProgress');
      expect(storedMatch['version'], 1);
      expect(
        (await db.select(db.courtQueueEntries).get()).single.deletedAt,
        equals(null),
      );
      expect(
        (await repository.start(
          CourtQueueCommand(
            operationId: SyncOperationId(id(22)),
            eventId: EventId(id(1)),
            action: 'start',
            createdAt: DateTime.utc(2026, 9, 6, 2),
            matchId: MatchId(id(5)),
            expectedMatchVersion: 1,
          ),
        )).isSuccess,
        isFalse,
      );
    },
  );

  test('completed and tombstoned queue entries are reconciled out', () async {
    await repository.reconcile(reconcileCommand());
    await db.importBracketHistory(
      () => db.customStatement(
        "UPDATE matches SET status='completed',side_one_score=11,side_two_score=5,winner_team_id=?,updated_at=?,version=1 WHERE id=?",
        [id(3), DateTime.utc(2026, 9, 6, 1).toIso8601String(), id(5)],
      ),
    );
    final next = CourtQueueCommand(
      operationId: SyncOperationId(id(23)),
      eventId: EventId(id(1)),
      action: 'reconcile',
      createdAt: DateTime.utc(2026, 9, 6, 2),
      expectedMatchVersion: -1,
    );
    expect((await repository.reconcile(next)).isSuccess, isTrue);
    final rows = await db.select(db.courtQueueEntries).get();
    expect(rows.single.deletedAt, isA<DateTime>());
    final snapshot = (await repository.load(EventId(id(1))))
        .when(success: (value) => value, failure: (failure) => throw failure);
    expect(snapshot.completedHistory.single.match.id, MatchId(id(5)));
  });

  test('Registration matches cannot enter the active court queue', () async {
    await seed(db, offset: 100, eventStatus: 'registration');
    final result = await repository.reconcile(
      CourtQueueCommand(
        operationId: SyncOperationId(id(120)),
        eventId: EventId(id(101)),
        action: 'reconcile',
        createdAt: DateTime.utc(2026, 9, 6, 3),
        expectedMatchVersion: -1,
        entryIds: {MatchId(id(105)): CourtQueueEntryId(id(110))},
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(
      await (db.select(
        db.courtQueueEntries,
      )..where((row) => row.eventId.equals(id(101)))).get(),
      isEmpty,
    );
  });
}
