import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/public_events/public_event_models.dart';
import 'package:vpc/src/application/public_events/public_event_reader.dart';
import 'package:vpc/src/application/public_events/public_event_readers.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';

import 'public_event_fixtures.dart';

void main() {
  test('online reader has no local cache and finds a public event', () async {
    final reader = OnlinePublicEventReader(_Remote(publicCatalog()));

    final cached = await reader.readCachedCatalog();
    cached.when(
      success: expectAsync1((catalog) => expect(catalog, isNull)),
      failure: (_) => fail('Cache lookup should succeed.'),
    );
    final result = await reader.getEvent(EventId(currentEventId));
    expect(result.isSuccess, isTrue);
  });

  test(
    'Android reader retains cached data when remote refresh fails',
    () async {
      final cachedCatalog = publicCatalog(
        origin: PublicCatalogOrigin.androidCache,
      );
      final reader = AndroidCachedPublicEventReader(
        cache: _Cache(cachedCatalog),
        remote: const _FailingRemote(),
      );

      final cached = await reader.readCachedCatalog();
      cached.when(
        success: (catalog) => expect(catalog?.events, isNotEmpty),
        failure: (failure) => fail(failure.message),
      );
      expect((await reader.refreshCatalog()).isSuccess, isFalse);
    },
  );

  test('unconfigured reader returns a typed safe failure', () async {
    final result = await const UnconfiguredPublicEventReader().refreshCatalog();

    result.when(
      success: (_) => fail('Expected unconfigured failure.'),
      failure: (failure) {
        expect(failure, isA<PersistenceUnavailableFailure>());
        expect(failure.message, isNot(contains('key')));
      },
    );
  });
}

final class _Remote implements PublicEventRemoteSource {
  const _Remote(this.catalog);

  final PublicEventCatalog catalog;

  @override
  Future<RepositoryResult<PublicEventCatalog>> fetchCatalog() async =>
      RepositorySuccess(catalog);
}

final class _FailingRemote implements PublicEventRemoteSource {
  const _FailingRemote();

  @override
  Future<RepositoryResult<PublicEventCatalog>> fetchCatalog() async =>
      const RepositoryFailure(
        UnknownRepositoryFailure(message: 'Safe remote failure.'),
      );
}

final class _Cache implements PublicEventCache {
  const _Cache(this.catalog);

  final PublicEventCatalog catalog;

  @override
  Future<RepositoryResult<PublicEventCatalog?>> readCatalog() async =>
      RepositorySuccess(catalog);

  @override
  Future<RepositoryResult<PublicEventCatalog>> reconcile(
    PublicEventCatalog authoritativeCatalog,
  ) async => RepositorySuccess(authoritativeCatalog);
}
