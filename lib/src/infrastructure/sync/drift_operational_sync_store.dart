import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/sync/operational_sync.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/drift_mapping.dart';
import 'player_sync_codec.dart';

final class DriftOperationalSyncStore implements OperationalSyncStore {
  DriftOperationalSyncStore(this.database);
  final AppDatabase database;

  static const _sources = <_Source>[
    _Source(
      'sync_outbox_operations',
      'players',
      'entity_id',
      'failure_message',
      'sync_conflicts',
    ),
    _Source(
      'event_setup_outbox_operations',
      'events',
      'event_id',
      'failure_message',
      'event_setup_conflicts',
    ),
    _Source(
      'participation_outbox_operations',
      'participation',
      'event_participant_id',
      'failure_message',
      'participation_conflicts',
    ),
    _Source(
      'team_formation_outbox_operations',
      'teams',
      'division_id',
      'failure_message',
      'team_formation_conflicts',
    ),
    _Source(
      'single_elimination_outbox',
      'singleElimination',
      'division_id',
      'failure',
      null,
    ),
    _Source('round_robin_outbox', 'roundRobin', 'division_id', 'failure', null),
    _Source(
      'double_elimination_outbox',
      'doubleElimination',
      'division_id',
      'failure',
      null,
    ),
    _Source('court_queue_outbox', 'courtQueue', 'event_id', 'failure', null),
  ];

  @override
  Future<OperationalSyncSnapshot> snapshot() async {
    final items = <OperationalSyncItem>[];
    for (final source in _sources) {
      final rows = await database
          .customSelect(
            "SELECT id,${source.aggregateColumn} aggregate_id,status,created_at,${source.failureColumn} failure FROM ${source.table} WHERE status<>'accepted' ORDER BY created_at,id",
          )
          .get();
      for (final row in rows) {
        final data = row.data;
        final aggregate = data['aggregate_id'] as String;
        items.add(
          OperationalSyncItem(
            operationId: data['id'] as String,
            stream: OperationalSyncStream.values.byName(source.stream),
            aggregateId: aggregate,
            label: await _label(source, aggregate),
            state: _state(data['status'] as String),
            createdAt: _date(data['created_at']),
            message: _safeMessage(data['failure'] as String?),
          ),
        );
      }
    }
    items.sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      return time == 0 ? a.operationId.compareTo(b.operationId) : time;
    });
    return OperationalSyncSnapshot(
      items: items,
      lastSuccessfulSync: await _lastCheckpoint(),
    );
  }

  @override
  Future<void> retryFailures() async {
    await database.transaction(() async {
      // "Retry now" must bypass a retryable player's scheduled backoff after
      // connectivity returns. Retryable player operations remain pending (not
      // failed), so the generic failed-row reset below does not cover them.
      final now = DateTime.now().toUtc().toIso8601String();
      await database.customStatement(
        '''
UPDATE sync_outbox_operations
SET next_eligible_at=?,failure_code=NULL,failure_message=NULL,claimed_at=NULL
WHERE status='pending' AND failure_code='retryable'
''',
        [now],
      );
      // A reapplication is a new write against the current cloud version.
      // Repair replacement payloads produced by an interrupted/older client
      // before making them eligible again.
      await database.customStatement('''
UPDATE sync_outbox_operations
SET payload_json=json_set(payload_json,'\$.version',base_version+1)
WHERE status='failed' AND base_version IS NOT NULL AND EXISTS(
  SELECT 1 FROM sync_resolution_audit a
  WHERE a.replacement_operation_id=sync_outbox_operations.id
    AND a.stream='players' AND a.resolution_action='reapplyLocal')
''');
      for (final source in _sources) {
        await database.customStatement(
          "UPDATE ${source.table} SET status='pending',${source.failureColumn}=NULL WHERE status='failed'",
        );
      }
    });
  }

  @override
  Future<void> useCloudVersion(String operationId) async {
    final found = await _find(operationId);
    if (found == null || found.status != 'conflicted') {
      throw StateError(
        'The conflict is no longer available. Refresh and try again.',
      );
    }
    await database.transaction(() async {
      await _audit(found, 'useCloud', null);
      await _applyRemoteEvidence(found);
      await _rewindCheckpoint(found);
      await _removeConflict(found);
    });
  }

  @override
  Future<void> stageLocalReapplication(
    String operationId,
    String replacementOperationId,
  ) async {
    final found = await _find(operationId);
    if (found == null || found.status != 'conflicted') {
      throw StateError(
        'The conflict is no longer available. Refresh and try again.',
      );
    }
    await database.transaction(() async {
      await _audit(found, 'reapplyLocal', replacementOperationId);
      await _applyRemoteEvidence(found);
      await _rewindCheckpoint(found);
      await _removeConflict(found);
    });
  }

  @override
  Future<void> enqueueStagedReapplication(
    String operationId,
    String replacementOperationId,
  ) async {
    final audit = await database
        .customSelect(
          "SELECT * FROM sync_resolution_audit WHERE operation_id=? AND resolution_action='reapplyLocal' AND replacement_operation_id=?",
          variables: [
            Variable<String>(operationId),
            Variable<String>(replacementOperationId),
          ],
        )
        .getSingleOrNull();
    if (audit == null) {
      throw StateError('The reapplication evidence is unavailable.');
    }
    final source = _sources.singleWhere(
      (item) => item.stream == audit.read<String>('stream'),
    );
    final aggregateId = audit.read<String>('aggregate_id');
    final payload = Map<String, Object?>.from(
      jsonDecode(audit.read<String>('local_payload_json')) as Map,
    );
    payload['operation_id'] = replacementOperationId;
    final version = await _currentVersion(source, aggregateId);
    if (payload.containsKey('expected_version')) {
      payload['expected_version'] = version;
    }
    if (source.stream == 'players' && version != null) {
      payload['version'] = version + 1;
    }
    final found = _Found(source, {
      'id': operationId,
      source.aggregateColumn: aggregateId,
      'payload_json': audit.read<String>('local_payload_json'),
      'status': 'conflicted',
      if (source.stream == 'players') 'entity_type': 'player',
      if (source.stream == 'players')
        'operation_kind': payload['deleted_at'] == null
            ? 'upsert'
            : 'tombstone',
      if (source.stream == 'teams')
        'event_id': await _eventIdForDivision(aggregateId),
    }, audit.readNullable<String>('remote_payload_json'));
    await _insertReplacement(
      found,
      replacementOperationId,
      jsonEncode(payload),
      version,
    );
  }

  @override
  Future<void> recordSuccessfulSync(DateTime atUtc) async {
    // The per-stream committed pull checkpoints are the durable success record.
    // Do not maintain a second cursor that could disagree after a crash.
  }

  Future<_Found?> _find(String id) async {
    for (final source in _sources) {
      final rows = await database
          .customSelect(
            'SELECT * FROM ${source.table} WHERE id=? LIMIT 1',
            variables: [Variable<String>(id)],
          )
          .get();
      if (rows.isEmpty) continue;
      final data = rows.single.data;
      String? remote;
      if (source.conflictTable != null) {
        final conflict = await database
            .customSelect(
              'SELECT remote_payload_json FROM ${source.conflictTable} WHERE operation_id=? AND status=\'unresolved\'',
              variables: [Variable<String>(id)],
            )
            .get();
        remote = conflict.isEmpty
            ? null
            : conflict.single.data['remote_payload_json'] as String?;
      } else if (data.containsKey('remote_json')) {
        remote = data['remote_json'] as String?;
      }
      return _Found(source, data, remote);
    }
    return null;
  }

  Future<void> _audit(_Found found, String action, String? replacement) async {
    await database.customStatement(
      'INSERT INTO sync_resolution_audit(operation_id,replacement_operation_id,stream,aggregate_id,resolution_action,local_payload_json,remote_payload_json,resolved_at) VALUES(?,?,?,?,?,?,?,?)',
      [
        found.id,
        replacement,
        found.source.stream,
        found.aggregateId,
        action,
        found.payload,
        found.remotePayload,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> _removeConflict(_Found found) async {
    if (found.source.conflictTable != null) {
      await database.customStatement(
        'DELETE FROM ${found.source.conflictTable} WHERE operation_id=?',
        [found.id],
      );
    }
    await database.customStatement(
      'DELETE FROM ${found.source.table} WHERE id=?',
      [found.id],
    );
  }

  Future<void> _applyRemoteEvidence(_Found found) async {
    final remote = found.remotePayload;
    if (remote == null || found.source.stream != 'players') return;
    final player = decodePlayerPayload(remote).toPlayer();
    await database
        .into(database.players)
        .insertOnConflictUpdate(playerToCompanion(player));
  }

  Future<void> _rewindCheckpoint(_Found found) async {
    final (table, where, arguments) = switch (found.source.stream) {
      'players' => (
        'sync_pull_checkpoints',
        'entity_type=?',
        <Object?>['player'],
      ),
      'events' => ('event_setup_pull_checkpoints', '1=1', <Object?>[]),
      'participation' => ('participation_pull_checkpoints', '1=1', <Object?>[]),
      'teams' => ('team_formation_pull_checkpoints', '1=1', <Object?>[]),
      'singleElimination' => (
        'single_elimination_checkpoints',
        'scope=?',
        <Object?>[found.aggregateId],
      ),
      'roundRobin' => (
        'round_robin_checkpoints',
        'scope=?',
        <Object?>[found.aggregateId],
      ),
      'doubleElimination' => (
        'double_elimination_checkpoints',
        'scope=?',
        <Object?>[found.aggregateId],
      ),
      'courtQueue' => (
        'court_queue_checkpoints',
        'scope=?',
        <Object?>[found.aggregateId],
      ),
      _ => throw StateError('Unsupported synchronization stream.'),
    };
    await database.customStatement(
      'DELETE FROM $table WHERE $where',
      arguments,
    );
  }

  Future<void> _insertReplacement(
    _Found found,
    String id,
    String payload,
    int? remoteVersion,
  ) async {
    final s = found.source;
    if (s.stream == 'players') {
      await database.customStatement(
        'INSERT INTO ${s.table}(id,entity_type,entity_id,operation_kind,base_version,payload_json,created_at,attempt_count,next_eligible_at,status) VALUES(?,?,?,?,?,?,?,0,?,\'pending\')',
        [
          id,
          found.data['entity_type'],
          found.aggregateId,
          found.data['operation_kind'],
          remoteVersion,
          payload,
          DateTime.now().toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      return;
    }
    if (s.stream == 'events' || s.stream == 'participation') {
      await database.customStatement(
        'INSERT INTO ${s.table}(id,${s.aggregateColumn},base_version,payload_json,created_at,status) VALUES(?,?,?,?,?,\'pending\')',
        [
          id,
          found.aggregateId,
          remoteVersion,
          payload,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      return;
    }
    if (s.stream == 'teams') {
      await database.customStatement(
        'INSERT INTO ${s.table}(id,event_id,division_id,payload_json,created_at,status) VALUES(?,?,?,?,?,\'pending\')',
        [
          id,
          found.data['event_id'],
          found.aggregateId,
          payload,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      return;
    }
    await database.customStatement(
      'INSERT INTO ${s.table}(id,${s.aggregateColumn},payload_json,status,created_at) VALUES(?,?,?,\'pending\',?)',
      [
        id,
        found.aggregateId,
        payload,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<int?> _currentVersion(_Source source, String aggregateId) async {
    final table = switch (source.stream) {
      'players' => 'players',
      'events' || 'courtQueue' => 'events',
      'participation' => 'event_participants',
      _ => null,
    };
    if (table != null) {
      final rows = await database
          .customSelect(
            'SELECT version FROM $table WHERE id=?',
            variables: [Variable<String>(aggregateId)],
          )
          .get();
      return rows.isEmpty ? null : rows.single.read<int>('version');
    }
    if (source.stream == 'teams') return null;
    final snapshot = switch (source.stream) {
      'singleElimination' => ['single_elimination_snapshots', 'bracket_json'],
      'roundRobin' => ['round_robin_snapshots', 'tournament_json'],
      'doubleElimination' => ['double_elimination_snapshots', 'bracket_json'],
      _ => throw StateError('Unsupported synchronization stream.'),
    };
    final rows = await database
        .customSelect(
          'SELECT ${snapshot[1]} payload FROM ${snapshot[0]} WHERE division_id=?',
          variables: [Variable<String>(aggregateId)],
        )
        .get();
    return rows.isEmpty
        ? null
        : _rootVersion(rows.single.read<String>('payload'));
  }

  Future<String> _eventIdForDivision(String divisionId) async =>
      (await database
              .customSelect(
                'SELECT event_id FROM event_divisions WHERE id=?',
                variables: [Variable<String>(divisionId)],
              )
              .getSingle())
          .read<String>('event_id');

  Future<String> _label(_Source source, String id) async {
    final query = switch (source.stream) {
      'players' => [
        'SELECT display_name label FROM players WHERE id=?',
        'Player',
      ],
      'events' ||
      'courtQueue' => ['SELECT name label FROM events WHERE id=?', 'Event'],
      'participation' => [
        "SELECT p.display_name label FROM event_participants ep JOIN players p ON p.id=ep.player_id WHERE ep.id=?",
        'Participant',
      ],
      _ => [
        "SELECT e.name || ' — ' || d.name label FROM event_divisions d JOIN events e ON e.id=d.event_id WHERE d.id=?",
        'Tournament division',
      ],
    };
    final rows = await database
        .customSelect(query[0], variables: [Variable<String>(id)])
        .get();
    return rows.isEmpty
        ? query[1]
        : (rows.single.data['label'] as String? ?? query[1]);
  }

  Future<DateTime?> _lastCheckpoint() async {
    final rows = await database.customSelect('''
SELECT max(stamp) stamp FROM (
 SELECT updated_at stamp FROM sync_pull_checkpoints UNION ALL
 SELECT updated_at FROM event_setup_pull_checkpoints UNION ALL
 SELECT updated_at FROM participation_pull_checkpoints UNION ALL
 SELECT updated_at FROM team_formation_pull_checkpoints UNION ALL
 SELECT updated_at FROM single_elimination_checkpoints UNION ALL
 SELECT updated_at FROM round_robin_checkpoints UNION ALL
 SELECT updated_at FROM double_elimination_checkpoints UNION ALL
 SELECT updated_at FROM court_queue_checkpoints)
''').get();
    final value = rows.single.data['stamp'];
    return value == null ? null : _date(value);
  }
}

OperationalSyncState _state(String value) => switch (value) {
  'inFlight' => OperationalSyncState.uploading,
  'blocked' => OperationalSyncState.authorizationBlocked,
  'failed' => OperationalSyncState.failed,
  'conflicted' => OperationalSyncState.conflicted,
  _ => OperationalSyncState.pending,
};

DateTime _date(Object? value) =>
    value is DateTime ? value.toUtc() : DateTime.parse(value as String).toUtc();
String? _safeMessage(String? value) => value == null
    ? null
    : (value.length <= 180 ? value : '${value.substring(0, 177)}...');

int? _rootVersion(String? raw) {
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map && decoded['version'] is int
        ? decoded['version'] as int
        : null;
  } on FormatException {
    return null;
  }
}

final class _Source {
  const _Source(
    this.table,
    this.stream,
    this.aggregateColumn,
    this.failureColumn,
    this.conflictTable,
  );
  final String table, stream, aggregateColumn, failureColumn;
  final String? conflictTable;
}

final class _Found {
  const _Found(this.source, this.data, this.remotePayload);
  final _Source source;
  final Map<String, Object?> data;
  final String? remotePayload;
  String get id => data['id'] as String;
  String get aggregateId => data[source.aggregateColumn] as String;
  String get payload => data['payload_json'] as String;
  String get status => data['status'] as String;
}
