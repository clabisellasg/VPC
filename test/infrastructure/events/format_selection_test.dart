import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/events/event_setup_contracts.dart';
import 'package:vpc/src/application/events/event_setup_models.dart';
import 'package:vpc/src/application/events/event_setup_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/infrastructure/events/drift_event_setup_store.dart';
import 'package:vpc/src/infrastructure/events/event_setup_writers.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';

import '../persistence/local/persistence_test_support.dart';

final class TestIds implements EventSetupIdFactory, EventSetupClock {
  var next = 100;
  @override
  EventId eventId() => EventId(eventOneId);
  @override
  DivisionId divisionId() => DivisionId(divisionOneId);
  @override
  SyncOperationId operationId() => SyncOperationId(
    '12000000-0000-4000-8000-${(next++).toString().padLeft(12, '0')}',
  );
  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 3, 1, 2, 3, 456, 789);
}

Future<void> seed(AppDatabase db) async {
  await insertEventGraph(db);
  await db.customStatement("UPDATE events SET status='registration'");
  await db.customStatement('UPDATE event_divisions SET tournament_format=NULL');
}

Future<EventSetup> load(DriftEventSetupStore store) async =>
    (await store.getSetup(
      EventId(eventOneId),
    ) as RepositorySuccess<EventSetup>).value;
EventSetupService service(DriftEventSetupStore store, TestIds ids) =>
    EventSetupService(
      writer: AndroidEventSetupWriter(store: store, idFactory: ids),
      idFactory: ids,
      clock: ids,
    );
Future<EventSetupMutationResult> select(
  EventSetupService useCase,
  EventSetup setup, {
  AuthorizationState role = AuthorizationState.organizer,
}) => useCase.selectFormat(
  current: setup,
  divisionId: DivisionId(divisionOneId),
  format: TournamentFormat.doubleRoundRobin,
  authorization: role,
);

final class FakeRemote implements EventSetupRemoteGateway {
  FakeRemote({this.reject = false});
  final bool reject;
  final received = <SyncOperationId>{};
  @override
  Future<EventSetupRemoteResult> apply(EventSetupOperation operation) async {
    if (reject) return const EventSetupRemoteConflict(null);
    final replayed = !received.add(operation.operationId);
    return EventSetupRemoteAccepted(setup: operation.setup, replayed: replayed);
  }

  @override
  Future<RepositoryResult<EventSetupPullPage>> pull({
    DateTime? afterUpdatedAt,
    EventId? afterId,
    int limit = 50,
  }) async =>
      const RepositorySuccess(EventSetupPullPage(setups: [], hasMore: false));
}

void main() {
  test('offline selection survives real close/reopen and reconnects once without matches', () async {
    final directory = await Directory.systemTemp.createTemp('vpc-m12-test-');
    final file = File('${directory.path}/test.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    final ids = TestIds();
    try {
      await seed(db);
      var store = DriftEventSetupStore(db);
      final result = await select(service(store, ids), await load(store));
      expect(
        (result as EventSetupSaved).disposition,
        EventMutationDisposition.pending,
      );
      expect(await db.select(db.matches).get(), isEmpty);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      store = DriftEventSetupStore(db);
      expect(
        (await load(store)).divisions.single.format,
        TournamentFormat.doubleRoundRobin,
      );
      expect(
        (await store.pendingOperations())
            .single
            .setup
            .divisions
            .single
            .metadata
            .updatedAt,
        ids.nowUtc(),
      );
      final remote = FakeRemote();
      final sync = EventSetupSynchronizer(
        store: store,
        remote: remote,
        idFactory: ids,
        clock: ids,
      );
      await sync.synchronize();
      await sync.synchronize();
      expect(remote.received, hasLength(1));
      expect(await store.pendingOperations(), isEmpty);
      expect(await db.select(db.matches).get(), isEmpty);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
  test('permission, conflict, atomic rollback and start guard', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    await seed(db);
    final store = DriftEventSetupStore(db);
    final ids = TestIds();
    final useCase = service(store, ids);
    for (final role in [
      AuthorizationState.guest,
      AuthorizationState.member,
      AuthorizationState.unavailable,
    ]) {
      final result = await select(useCase, await load(store), role: role);
      expect(
        (result as EventSetupMutationFailed).failure,
        isA<UnauthorizedFailure>(),
      );
    }
    await db.customStatement(
      "CREATE TRIGGER fail_outbox BEFORE INSERT ON event_setup_outbox_operations BEGIN SELECT RAISE(ABORT,'test failure'); END",
    );
    expect(
      await select(useCase, await load(store)),
      isA<EventSetupMutationFailed>(),
    );
    expect((await load(store)).divisions.single.format, isNull);
    expect(await store.pendingOperations(), isEmpty);
    await db.customStatement('DROP TRIGGER fail_outbox');
    expect(await select(useCase, await load(store)), isA<EventSetupSaved>());
    final blocked = await useCase.advance(await load(store));
    expect(
      (blocked as EventSetupMutationFailed).failure,
      isA<TournamentStructureRequiredFailure>(),
    );
    await EventSetupSynchronizer(
      store: store,
      remote: FakeRemote(reject: true),
      idFactory: ids,
      clock: ids,
    ).synchronize();
    expect(
      (await db.select(db.eventSetupOutboxOperations).getSingle()).status,
      'conflicted',
    );
    expect(await db.select(db.eventSetupConflicts).get(), hasLength(1));
    expect(
      (await load(store)).divisions.single.format,
      TournamentFormat.doubleRoundRobin,
    );
  });
  test(
    'Web path waits for authoritative acceptance and exposes typed denial',
    () async {
      // A fake gateway, no Drift database is constructed for Web.
      final ids = TestIds();
      final sourceDb = AppDatabase.inMemory();
      await seed(sourceDb);
      final setup = await load(DriftEventSetupStore(sourceDb));
      await sourceDb
          .close(); // Fixture loading only; adapter is platform-independent.
      final remote = FakeRemote();
      final writer = WebEventSetupWriter(remote: remote, idFactory: ids);
      final result =
          await EventSetupService(
            writer: writer,
            idFactory: ids,
            clock: ids,
          ).selectFormat(
            current: setup,
            divisionId: DivisionId(divisionOneId),
            format: TournamentFormat.singleRoundRobin,
            authorization: AuthorizationState.organizer,
          );
      expect(
        (result as EventSetupSaved).disposition,
        EventMutationDisposition.synchronized,
      );
      expect(remote.received, hasLength(1));
    },
  );
}
