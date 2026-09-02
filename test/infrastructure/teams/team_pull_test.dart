import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/teams/drift_team_formation_store.dart';
import 'package:vpc/src/infrastructure/teams/team_formation_puller.dart';
import 'package:vpc/src/infrastructure/teams/team_pull_models.dart';

import '../persistence/local/persistence_test_support.dart';

const cloudCreated = '2020-01-02T03:04:05.123456+08:00';
const cloudUpdated = '2020-02-03T04:05:06.654321Z';
const cloudDeleted = '2020-02-03T04:05:06.654321Z';

Map<String, dynamic> fixture({bool deleted = false, String? playerId}) => {
  'division_id': divisionOneId,
  'updated_at': cloudUpdated,
  'snapshot': {
    'event_id': eventOneId,
    'teams': [
      {
        'id': teamOneId,
        'division_id': divisionOneId,
        'formation_method': 'manual',
        'display_label': null,
        'created_at': cloudCreated,
        'updated_at': cloudUpdated,
        'deleted_at': deleted ? cloudDeleted : null,
        'version': 7,
      },
    ],
    'members': [
      for (final id in [playerOneId, playerId ?? playerTwoId])
        {
          'team_id': teamOneId,
          'player_id': id,
          'created_at': cloudCreated,
          'updated_at': cloudUpdated,
          'deleted_at': deleted ? cloudDeleted : null,
          'version': 9,
        },
    ],
  },
};

void main() {
  late AppDatabase db;
  late DriftTeamFormationStore local;
  var fixtureClosed = false;
  setUp(() async {
    fixtureClosed = false;
    db = AppDatabase.inMemory();
    local = DriftTeamFormationStore(db);
    await insertEventGraph(db);
    await db
        .into(db.players)
        .insert(
          playerCompanion(
            id: playerTwoId,
            displayName: 'Sample Two',
            version: 0,
          ),
        );
  });
  tearDown(() async {
    if (!fixtureClosed) await db.close();
  });

  test('closing and reopening SQLite preserves the pull checkpoint', () async {
    await db.close();
    fixtureClosed = true;
    final directory = await Directory.systemTemp.createTemp('vpc-team-pull-');
    final file = File('${directory.path}/test.sqlite');
    var persisted = AppDatabase(NativeDatabase(file));
    try {
      await insertEventGraph(persisted);
      await persisted
          .into(persisted.players)
          .insert(
            playerCompanion(
              id: playerTwoId,
              displayName: 'Sample Two',
              version: 0,
            ),
          );
      final first = TeamPullAggregate.fromJson(fixture());
      await DriftTeamFormationStore(persisted).reconcilePullPage([first]);
      await persisted.close();
      persisted = AppDatabase(NativeDatabase(file));
      final source = _Source([]);
      await TeamFormationPuller(
        local: DriftTeamFormationStore(persisted),
        remote: source,
      ).pull();
      expect(source.requested.single!.compareTo(first.cursor), 0);
      expect(await persisted.select(persisted.teamMembers).get(), hasLength(2));
    } finally {
      await persisted.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'empty checkpoint then cloud metadata and cursor commit exactly once',
    () async {
      expect(await local.readPullCheckpoint(), isNull);
      final record = TeamPullAggregate.fromJson(fixture());
      expect(await local.reconcilePullPage([record]), isTrue);
      final team = await db.select(db.teams).getSingle();
      final members = await db.select(db.teamMembers).get();
      for (final row in members) {
        expect(row.createdAt.toUtc(), DateTime.parse(cloudCreated).toUtc());
        expect(row.updatedAt.toUtc(), DateTime.parse(cloudUpdated));
        expect(row.deletedAt, isNull);
        expect(row.version, 9);
      }
      expect(team.createdAt.toUtc(), DateTime.parse(cloudCreated).toUtc());
      expect(team.updatedAt.toUtc(), DateTime.parse(cloudUpdated));
      expect(team.deletedAt, isNull);
      expect(team.version, 7);
      final before = await db
          .customSelect('SELECT total_changes() AS n')
          .getSingle();
      await local.reconcilePullPage([record]);
      final after = await db
          .customSelect('SELECT total_changes() AS n')
          .getSingle();
      expect(after.read<int>('n'), before.read<int>('n'));
      expect((await local.readPullCheckpoint())!.compareTo(record.cursor), 0);
      expect(await db.select(db.teamFormationOutboxOperations).get(), isEmpty);
    },
  );

  test('historical team/member tombstones retain exact microseconds', () async {
    await local.reconcilePullPage([
      TeamPullAggregate.fromJson(fixture(deleted: true)),
    ]);
    final team = await db.select(db.teams).getSingle();
    expect(team.deletedAt!.toUtc(), DateTime.parse(cloudDeleted));
    for (final member in await db.select(db.teamMembers).get()) {
      expect(member.deletedAt!.toUtc(), DateTime.parse(cloudDeleted));
    }
  });

  test('constraint failure rolls back teams, members and checkpoint and restores guards', () async {
    final invalid = TeamPullAggregate.fromJson(
      fixture(playerId: '00000000-0000-4000-8000-000000000099'),
    );
    await expectLater(local.reconcilePullPage([invalid]), throwsA(anything));
    expect(await local.readPullCheckpoint(), isNull);
    expect(await db.select(db.teams).get(), isEmpty);
    expect(await db.select(db.teamMembers).get(), isEmpty);
    final guards = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'team_members_%guard'",
        )
        .get();
    expect(guards, hasLength(2));
  });

  test(
    'checkpoint write failure rolls back updated authoritative rows',
    () async {
      final initial = TeamPullAggregate.fromJson(fixture());
      await local.reconcilePullPage([initial]);
      final originalTeam = await db.select(db.teams).getSingle();
      final originalMembers = await db.select(db.teamMembers).get();
      final nextJson = fixture();
      const later = '2021-02-03T04:05:06.654321Z';
      nextJson['updated_at'] = later;
      for (final row in [
        ...(nextJson['snapshot'] as Map)['teams'] as List,
        ...(nextJson['snapshot'] as Map)['members'] as List,
      ]) {
        (row as Map)['updated_at'] = later;
        row['version'] = 10;
      }
      await db.customStatement(
        "CREATE TRIGGER reject_test_checkpoint BEFORE UPDATE ON team_formation_pull_checkpoints BEGIN SELECT RAISE(ABORT, 'test checkpoint failure'); END",
      );
      await expectLater(
        local.reconcilePullPage([TeamPullAggregate.fromJson(nextJson)]),
        throwsA(anything),
      );
      expect(await db.select(db.teams).getSingle(), originalTeam);
      expect(await db.select(db.teamMembers).get(), originalMembers);
      expect((await local.readPullCheckpoint())!.compareTo(initial.cursor), 0);
    },
  );

  test('mapping failure cannot advance checkpoint', () async {
    final bad = fixture();
    (bad['snapshot'] as Map)['members'] = [
      {'team_id': 'invalid'},
    ];
    expect(
      () => TeamPullAggregate.fromJson(bad),
      throwsA(isA<ValidationFailure>()),
    );
    expect(await local.readPullCheckpoint(), isNull);
  });

  for (final status in ['pending', 'conflicted']) {
    test(
      '$status local work protects records and does not skip cursor',
      () async {
        await db
            .into(db.teamFormationOutboxOperations)
            .insert(
              TeamFormationOutboxOperationsCompanion.insert(
                id: '00000000-0000-4000-8000-000000000098',
                eventId: eventOneId,
                divisionId: divisionOneId,
                payloadJson: '{}',
                createdAt: DateTime.utc(2030),
                status: status,
              ),
            );
        expect(
          await local.reconcilePullPage([
            TeamPullAggregate.fromJson(fixture()),
          ]),
          isFalse,
        );
        expect(await local.readPullCheckpoint(), isNull);
        expect(await db.select(db.teams).get(), isEmpty);
        expect(
          await db.select(db.teamFormationOutboxOperations).get(),
          hasLength(1),
        );
      },
    );
  }

  test('new puller resumes persisted cursor; equal-time division tie-break is retained', () async {
    final first = TeamPullAggregate.fromJson(fixture());
    final source = _Source([first]);
    await TeamFormationPuller(local: local, remote: source).pull();
    expect(source.requested.single, isNull);
    // Recreate store/puller, as on application restart; no in-memory cursor.
    final restartedSource = _Source([]);
    await TeamFormationPuller(
      local: DriftTeamFormationStore(db),
      remote: restartedSource,
    ).pull();
    expect(restartedSource.requested.single!.compareTo(first.cursor), 0);
    final otherDivision = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
    await db
        .into(db.eventDivisions)
        .insert(
          EventDivisionsCompanion.insert(
            id: otherDivision,
            eventId: eventOneId,
            name: 'Sample other',
            createdAt: createdAt,
            updatedAt: updatedAt,
            version: 0,
          ),
        );
    final next = TeamPullAggregate.fromJson({
      'division_id': otherDivision,
      'updated_at': cloudUpdated,
      'snapshot': {'event_id': eventOneId, 'teams': [], 'members': []},
    });
    final nextSource = _Source([next]);
    await TeamFormationPuller(local: local, remote: nextSource).pull();
    expect(nextSource.requested.single!.compareTo(first.cursor), 0);
    expect((await local.readPullCheckpoint())!.compareTo(next.cursor), 0);
  });
}

final class _Source implements TeamPullSource {
  _Source(this.page);
  final List<TeamPullAggregate> page;
  final requested = <TeamPullCursor?>[];
  @override
  Future<List<TeamPullAggregate>> pullTeams(TeamPullCursor? after) async {
    requested.add(after);
    return page;
  }
}
