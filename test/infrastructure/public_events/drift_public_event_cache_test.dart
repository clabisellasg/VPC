import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/public_events/public_event_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/persistence/local/drift_mapping.dart';
import 'package:vpc/src/infrastructure/public_events/drift_public_event_cache.dart';

import '../../application/public_events/public_event_fixtures.dart';

void main() {
  late AppDatabase database;
  late DriftPublicEventCache cache;

  setUp(() {
    database = AppDatabase.inMemory();
    cache = DriftPublicEventCache(
      database,
      clock: () => DateTime.utc(2026, 8, 28, 5),
    );
  });

  tearDown(() => database.close());

  test('reads active local events and divisions as Android cache', () async {
    await database
        .into(database.events)
        .insert(eventToCompanion(publicEvent()));
    await database
        .into(database.eventDivisions)
        .insert(eventDivisionToCompanion(publicDivision()));

    final result = await cache.readCatalog();

    result.when(
      success: (catalog) {
        expect(catalog, isNotNull);
        expect(catalog!.origin, PublicCatalogOrigin.androidCache);
        expect(catalog.events.single.divisions, hasLength(1));
      },
      failure: (failure) => fail(failure.message),
    );
  });

  test(
    'reconciles remote records without creating player outbox work',
    () async {
      final result = await cache.reconcile(publicCatalog());

      result.when(
        success: (catalog) {
          expect(catalog.origin, PublicCatalogOrigin.remote);
          expect(catalog.events, hasLength(3));
        },
        failure: (failure) => fail(failure.message),
      );
      expect(
        await database.select(database.syncOutboxOperations).get(),
        isEmpty,
      );
    },
  );

  test('advances a stale cached lifecycle through adjacent states', () async {
    await database
        .into(database.events)
        .insert(
          eventToCompanion(
            publicEvent(
              status: EventStatus.upcoming,
              metadata: publicMetadata(),
            ),
          ),
        );
    final remote = publicCatalog(
      events: [
        PublicEventItem(
          event: publicEvent(
            status: EventStatus.completed,
            metadata: publicMetadata(version: 3),
          ),
        ),
      ],
    );

    final result = await cache.reconcile(remote);

    expect(result.isSuccess, isTrue);
    expect(
      (await database.select(database.events).getSingle()).status,
      EventStatus.completed.name,
    );
  });

  test(
    'marks records absent from authoritative full snapshot as tombstoned',
    () async {
      await cache.reconcile(publicCatalog());
      await cache.reconcile(
        PublicEventCatalog(
          events: const [],
          origin: PublicCatalogOrigin.remote,
          refreshedAt: DateTime.utc(2026, 8, 28, 6),
        ),
      );

      expect(
        (await database.select(database.events).get()).every(
          (row) => row.deletedAt != null,
        ),
        isTrue,
      );
      expect(
        (await database.select(database.eventDivisions).get()).every(
          (row) => row.deletedAt != null,
        ),
        isTrue,
      );
      final active = await cache.readCatalog();
      active.when(
        success: (catalog) => expect(catalog, isNull),
        failure: (failure) => fail(failure.message),
      );
    },
  );

  test(
    'preserves a newer local event instead of silently overwriting it',
    () async {
      await database
          .into(database.events)
          .insert(
            eventToCompanion(publicEvent(metadata: publicMetadata(version: 8))),
          );

      final result = await cache.reconcile(publicCatalog());

      result.when(
        success: (_) => fail('Expected conflict.'),
        failure: (failure) => expect(failure, isA<ConflictFailure>()),
      );
      expect((await database.select(database.events).getSingle()).version, 8);
    },
  );
}
