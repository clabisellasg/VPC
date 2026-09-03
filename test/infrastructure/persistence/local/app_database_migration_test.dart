import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';

import '../../../generated_migrations/schema.dart';

void main() {
  test('v6 to v7 preserves M12 records and adds bracket durability', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(6);
    schema.rawDatabase.execute('''
INSERT INTO players(id,display_name,skill_level,created_at,updated_at,version)
VALUES('13000000-0000-4000-8000-000000000001','VPC M13 Migration Sample',4,
'2026-09-03T00:00:00.000Z','2026-09-03T00:00:00.000Z',9);
''');
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    final player = await db.select(db.players).getSingle();
    expect(player.version, 9);
    expect(player.skillLevel, 4);
    expect(player.id, '13000000-0000-4000-8000-000000000001');
    expect(await db.select(db.singleEliminationSnapshots).get(), isEmpty);
    expect(await db.select(db.singleEliminationOutbox).get(), isEmpty);
    expect(await db.select(db.singleEliminationCheckpoints).get(), isEmpty);
    expect(await db.select(db.matchResultRevisions).get(), isEmpty);
    await db.close();
    schema.close();
  });
  test(
    'v5 to v6 preserves nullable formats and replaces format-lock triggers',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(5);
      schema.rawDatabase.execute('''
INSERT INTO events (id,name,scheduled_at,event_type,status,court_label,created_at,updated_at,version)
VALUES ('12000000-0000-4000-8000-000000000001','VPC M12 Migration','2026-09-03T00:00:00.000Z','formal','registration','Sample Court','2026-09-03T00:00:00.000Z','2026-09-03T00:00:00.000Z',7);
INSERT INTO event_divisions (id,event_id,name,tournament_format,created_at,updated_at,version)
VALUES ('12000000-0000-4000-8000-000000000002','12000000-0000-4000-8000-000000000001','Open',NULL,'2026-09-03T00:00:00.000Z','2026-09-03T00:00:00.000Z',8);
''');
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 6);
      final row = await db.select(db.eventDivisions).getSingle();
      expect(row.tournamentFormat, isNull);
      expect(row.version, 8);
      await db.customStatement(
        "UPDATE event_divisions SET tournament_format='singleElimination'",
      );
      expect(
        (await db.select(db.eventDivisions).getSingle()).tournamentFormat,
        'singleElimination',
      );
      await expectLater(
        db.customStatement("UPDATE event_divisions SET name='Locked change'"),
        throwsA(isA<Exception>()),
      );
      await db.close();
      schema.close();
    },
  );
  test(
    'v1 to v2 migration preserves player data and adds sync tables',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(1);
      schema.rawDatabase.execute('''
      INSERT INTO players (
        id, display_name, created_at, updated_at, version, deleted_at
      ) VALUES (
        '10000000-0000-4000-8000-000000000001',
        'Existing Player',
        '2026-08-20T00:00:00.000Z',
        '2026-08-20T00:00:00.000Z',
        0,
        NULL
      )
    ''');

      final database = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(database, 2);

      final player = await database.select(database.players).getSingle();
      expect(player.displayName, 'Existing Player');
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'sync_%' ORDER BY name",
          )
          .get();
      expect(tables.map((row) => row.read<String>('name')), [
        'sync_conflicts',
        'sync_outbox_operations',
        'sync_pull_checkpoints',
      ]);

      await database.close();
      schema.close();
    },
  );

  test('v2 to v3 preserves configured formats and permits null', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(2);
    schema.rawDatabase.execute('''
      INSERT INTO events (
        id,name,scheduled_at,event_type,status,court_label,
        created_at,updated_at,version,deleted_at
      ) VALUES (
        '20000000-0000-4000-8000-000000000001','Existing Event',
        '2026-09-01T00:00:00.000Z','formal','upcoming','Community Court',
        '2026-09-01T00:00:00.000Z','2026-09-01T00:00:00.000Z',0,NULL
      );
      INSERT INTO event_divisions (
        id,event_id,name,tournament_format,created_at,updated_at,version,deleted_at
      ) VALUES (
        '20000000-0000-4000-8000-000000000002',
        '20000000-0000-4000-8000-000000000001','Open','singleElimination',
        '2026-09-01T00:00:00.000Z','2026-09-01T00:00:00.000Z',0,NULL
      );
    ''');

    final database = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(database, 3);
    final preserved = await database
        .select(database.eventDivisions)
        .getSingle();
    expect(preserved.tournamentFormat, 'singleElimination');
    await database
        .into(database.eventDivisions)
        .insert(
          EventDivisionsCompanion.insert(
            id: '20000000-0000-4000-8000-000000000003',
            eventId: '20000000-0000-4000-8000-000000000001',
            name: 'Mixed',
            tournamentFormat: const Value(null),
            createdAt: DateTime.utc(2026, 9),
            updatedAt: DateTime.utc(2026, 9),
            version: 0,
          ),
        );
    expect(
      (await database.select(database.eventDivisions).get())
          .last
          .tournamentFormat,
      isNull,
    );
    await database.close();
    schema.close();
  });

  test(
    'v3 to v4 preserves participation and adds bounded sync tables',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(3);
      schema.rawDatabase.execute('''
      INSERT INTO players (
        id,display_name,created_at,updated_at,version,deleted_at
      ) VALUES (
        '30000000-0000-4000-8000-000000000001','Existing Player',
        '2026-09-01T00:00:00.000Z','2026-09-01T00:00:00.000Z',0,NULL
      );
      INSERT INTO events (
        id,name,scheduled_at,event_type,status,court_label,
        created_at,updated_at,version,deleted_at
      ) VALUES (
        '30000000-0000-4000-8000-000000000002','Existing Event',
        '2026-09-02T00:00:00.000Z','formal','registration','Community Court',
        '2026-09-01T00:00:00.000Z','2026-09-01T00:00:00.000Z',1,NULL
      );
      INSERT INTO event_participants (
        id,event_id,player_id,check_in_status,created_at,updated_at,version,deleted_at
      ) VALUES (
        '30000000-0000-4000-8000-000000000003',
        '30000000-0000-4000-8000-000000000002',
        '30000000-0000-4000-8000-000000000001','notPresent',
        '2026-09-01T00:00:00.000Z','2026-09-01T00:00:00.000Z',0,NULL
      );
    ''');

      final database = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(database, 4);
      expect(
        await database.select(database.eventParticipants).get(),
        hasLength(1),
      );
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'participation_%' ORDER BY name",
          )
          .get();
      expect(tables.map((row) => row.read<String>('name')), [
        'participation_conflicts',
        'participation_outbox_operations',
        'participation_pull_checkpoints',
      ]);
      await database.close();
      schema.close();
    },
  );

  test(
    'v4 to v5 preserves players and adds nullable skill and team sync',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(4);
      schema.rawDatabase.execute('''
      INSERT INTO players (id,display_name,created_at,updated_at,version,deleted_at)
      VALUES ('40000000-0000-4000-8000-000000000001','Existing Unrated Player',
      '2026-09-01T00:00:00.000Z','2026-09-01T00:00:00.000Z',0,NULL)
    ''');
      final database = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(database, 5);
      final player = await database.select(database.players).getSingle();
      expect(player.skillLevel, isNull);
      await (database.update(database.players)
            ..where((row) => row.id.equals(player.id)))
          .write(const PlayersCompanion(skillLevel: Value(5)));
      expect(
        (await database.select(database.players).getSingle()).skillLevel,
        5,
      );
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'team_formation_%' ORDER BY name",
          )
          .get();
      expect(tables.map((row) => row.read<String>('name')), [
        'team_formation_conflicts',
        'team_formation_outbox_operations',
        'team_formation_pull_checkpoints',
      ]);
      await database.close();
      schema.close();
    },
  );
}
