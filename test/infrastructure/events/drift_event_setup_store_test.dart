import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/events/event_setup_contracts.dart';
import 'package:vpc/src/application/events/event_setup_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_division.dart';
import 'package:vpc/src/infrastructure/events/drift_event_setup_store.dart';
import 'package:vpc/src/infrastructure/events/event_setup_writers.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';

void main() {
  late AppDatabase database;
  late DriftEventSetupStore store;
  setUp(() {
    database = AppDatabase.inMemory();
    store = DriftEventSetupStore(database);
  });
  tearDown(() => database.close());

  test(
    'event division and outbox commit atomically with null format',
    () async {
      final setup = _setup('92000000-0000-4000-8000-000000000001');
      final result = await store.save(
        setup,
        operationId: SyncOperationId('92000000-0000-4000-8000-000000000010'),
      );
      expect(result, isA<RepositorySuccess<EventSetupSaved>>());
      expect(
        (await database.select(database.eventDivisions).getSingle())
            .tournamentFormat,
        isNull,
      );
      expect(
        await database.select(database.eventSetupOutboxOperations).get(),
        hasLength(1),
      );
      expect(
        (await store.getSetup(
          setup.event.id,
        ) as RepositorySuccess<EventSetup>).value.divisions.single.format,
        isNull,
      );
    },
  );

  test('Android writer returns the local pending result immediately', () async {
    final writer = AndroidEventSetupWriter(
      store: store,
      idFactory: _FixedIds(),
    );
    final result = await writer.save(
      _setup('92000000-0000-4000-8000-000000000001'),
    );

    expect(
      (result as RepositorySuccess<EventSetupSaved>).value.disposition,
      EventMutationDisposition.pending,
    );
    expect(
      await database.select(database.eventSetupOutboxOperations).get(),
      hasLength(1),
    );
  });

  test('outbox failure rolls back the complete second aggregate', () async {
    const operation = '92000000-0000-4000-8000-000000000010';
    await store.save(
      _setup('92000000-0000-4000-8000-000000000001'),
      operationId: SyncOperationId(operation),
    );
    final result = await store.save(
      _setup('92000000-0000-4000-8000-000000000002'),
      operationId: SyncOperationId(operation),
    );
    expect(result, isA<RepositoryFailure<EventSetupSaved>>());
    expect(await database.select(database.events).get(), hasLength(1));
    expect(await database.select(database.eventDivisions).get(), hasLength(1));
  });

  test('authoritative reconciliation preserves pending local work', () async {
    final local = _setup('92000000-0000-4000-8000-000000000001');
    await store.save(
      local,
      operationId: SyncOperationId('92000000-0000-4000-8000-000000000010'),
    );
    final remote = _setup(
      '92000000-0000-4000-8000-000000000001',
      name: 'Remote Name',
    );
    expect(await store.reconcile([remote], DateTime.utc(2026, 9, 2)), 0);
    expect(
      (await store.getSetup(
        local.event.id,
      ) as RepositorySuccess<EventSetup>).value.event.name,
      'Local Event',
    );
  });

  test('repeated reconciliation updates the singleton checkpoint', () async {
    final remote = _setup('92000000-0000-4000-8000-000000000001');
    expect(await store.reconcile([remote], DateTime.utc(2026, 9, 2)), 1);
    expect(await store.reconcile([remote], DateTime.utc(2026, 9, 3)), 1);

    final checkpoints = await database
        .select(database.eventSetupPullCheckpoints)
        .get();
    expect(checkpoints, hasLength(1));
    expect(checkpoints.single.singleton, 1);
    expect(checkpoints.single.updatedAt, DateTime.utc(2026, 9, 3));
  });
}

final class _FixedIds implements EventSetupIdFactory {
  @override
  DivisionId divisionId() => DivisionId('92000000-0000-4000-8000-000000000012');

  @override
  EventId eventId() => EventId('92000000-0000-4000-8000-000000000011');

  @override
  SyncOperationId operationId() =>
      SyncOperationId('92000000-0000-4000-8000-000000000010');
}

EventSetup _setup(String id, {String name = 'Local Event'}) {
  final metadata = RecordMetadata(
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    recordVersion: 0,
  );
  final eventId = EventId(id);
  final divisionId = DivisionId(
    '${id.substring(0, id.length - 1)}${id.endsWith('1') ? 'a' : 'b'}',
  );
  return EventSetup(
    event: Event(
      id: eventId,
      name: name,
      scheduledAt: DateTime.utc(2026, 9, 10),
      type: EventType.casual,
      status: EventStatus.upcoming,
      courtLabel: 'Court',
      metadata: metadata,
    ),
    divisions: [
      EventDivision(
        id: divisionId,
        eventId: eventId,
        name: 'Open',
        format: null,
        metadata: metadata,
      ),
    ],
  );
}
