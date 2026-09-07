import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/sync/operational_sync.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/sync/drift_operational_sync_store.dart';

const playerId = '11000000-0000-4000-8000-000000000001';
const oldOperation = '12000000-0000-4000-8000-000000000001';
const newOperation = '12000000-0000-4000-8000-000000000002';
const conflictId = '13000000-0000-4000-8000-000000000001';

void main() {
  late AppDatabase database;
  late DriftOperationalSyncStore store;
  setUp(() async {
    database = AppDatabase.inMemory();
    store = DriftOperationalSyncStore(database);
    final stamp = DateTime.utc(2026, 9, 7).toIso8601String();
    await database.customStatement(
      'INSERT INTO players(id,display_name,skill_level,created_at,updated_at,version,deleted_at) VALUES(?,?,2,?,?,0,NULL)',
      [playerId, 'Local Name', stamp, stamp],
    );
    final payload = jsonEncode({
      'id': playerId,
      'display_name': 'Local Name',
      'created_at': stamp,
      'updated_at': stamp,
      'version': 0,
      'deleted_at': null,
      'skill_level': 2,
    });
    final remote = jsonEncode({
      'id': playerId,
      'display_name': 'Cloud Name',
      'created_at': stamp,
      'updated_at': stamp,
      'version': 2,
      'deleted_at': null,
      'skill_level': 4,
    });
    await database.customStatement(
      "INSERT INTO sync_outbox_operations(id,entity_type,entity_id,operation_kind,base_version,payload_json,created_at,attempt_count,next_eligible_at,status,claimed_at) VALUES(?,'player',?,'upsert',0,?,?,1,?,'conflicted',NULL)",
      [oldOperation, playerId, payload, stamp, stamp],
    );
    await database.customStatement(
      "INSERT INTO sync_conflicts(id,operation_id,entity_type,entity_id,expected_version,local_payload_json,remote_payload_json,remote_version,detected_at,status) VALUES(?,?,'player',?,0,?,?,2,?,'unresolved')",
      [conflictId, oldOperation, playerId, payload, remote, stamp],
    );
  });
  tearDown(() => database.close());

  test('snapshot is human-labelled and never exposes raw payload', () async {
    final snapshot = await store.snapshot();
    expect(snapshot.items.single.label, 'Local Name');
    expect(snapshot.items.single.state, OperationalSyncState.conflicted);
    expect(snapshot.items.single.message, isNull);
  });

  test('use cloud archives intent before cancelling stale operation', () async {
    await store.useCloudVersion(oldOperation);
    expect(
      (await database
          .customSelect('SELECT * FROM sync_outbox_operations')
          .get()),
      isEmpty,
    );
    final audit = await database
        .customSelect('SELECT * FROM sync_resolution_audit')
        .getSingle();
    expect(audit.read<String>('resolution_action'), 'useCloud');
    expect(audit.read<String>('local_payload_json'), contains('Local Name'));
    final player = await database
        .customSelect(
          'SELECT display_name,skill_level,version FROM players WHERE id=?',
          variables: [Variable<String>(playerId)],
        )
        .getSingle();
    expect(player.read<String>('display_name'), 'Cloud Name');
    expect(player.read<int>('skill_level'), 4);
    expect(player.read<int>('version'), 2);
  });

  test(
    'reapply creates a new operation ID with current remote version',
    () async {
      await store.stageLocalReapplication(oldOperation, newOperation);
      await database.customStatement(
        'UPDATE players SET version=2 WHERE id=?',
        [playerId],
      );
      await store.enqueueStagedReapplication(oldOperation, newOperation);
      final replacement = await database
          .customSelect('SELECT * FROM sync_outbox_operations')
          .getSingle();
      expect(replacement.read<String>('id'), newOperation);
      expect(replacement.read<int>('base_version'), 2);
      expect(replacement.read<String>('status'), 'pending');
      expect(
        jsonDecode(replacement.read<String>('payload_json'))['version'],
        3,
      );
      final audit = await database
          .customSelect('SELECT * FROM sync_resolution_audit')
          .getSingle();
      expect(audit.read<String>('replacement_operation_id'), newOperation);
    },
  );

  test('retry repairs a failed player reapplication version', () async {
    await store.stageLocalReapplication(oldOperation, newOperation);
    await database.customStatement('UPDATE players SET version=2 WHERE id=?', [
      playerId,
    ]);
    await store.enqueueStagedReapplication(oldOperation, newOperation);
    await database.customStatement(
      "UPDATE sync_outbox_operations SET status='failed',payload_json=json_set(payload_json,'\$.version',2) WHERE id=?",
      [newOperation],
    );

    await store.retryFailures();

    final replacement = await database
        .customSelect(
          'SELECT * FROM sync_outbox_operations WHERE id=?',
          variables: [Variable<String>(newOperation)],
        )
        .getSingle();
    expect(replacement.read<String>('status'), 'pending');
    expect(jsonDecode(replacement.read<String>('payload_json'))['version'], 3);
  });

  test('retry now bypasses a pending retryable player backoff', () async {
    final future = DateTime.utc(2026, 9, 8).toIso8601String();
    await database.customStatement(
      "UPDATE sync_outbox_operations SET status='pending',failure_code='retryable',failure_message='The cloud is temporarily unavailable.',next_eligible_at=? WHERE id=?",
      [future, oldOperation],
    );

    await store.retryFailures();

    final operation = await database
        .customSelect(
          'SELECT * FROM sync_outbox_operations WHERE id=?',
          variables: [Variable<String>(oldOperation)],
        )
        .getSingle();
    expect(operation.read<String>('status'), 'pending');
    expect(operation.readNullable<String>('failure_code'), isNull);
    expect(operation.readNullable<String>('failure_message'), isNull);
    expect(
      DateTime.parse(operation.read<String>('next_eligible_at'))
          .isBefore(DateTime.utc(2026, 9, 8)),
      isTrue,
    );
  });
}
