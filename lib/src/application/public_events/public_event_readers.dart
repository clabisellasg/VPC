import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'public_event_models.dart';
import 'public_event_reader.dart';

final class OnlinePublicEventReader implements PublicEventReader {
  const OnlinePublicEventReader(this.remote);

  final PublicEventRemoteSource remote;

  @override
  Future<RepositoryResult<PublicEventCatalog?>> readCachedCatalog() async =>
      const RepositorySuccess<PublicEventCatalog?>(null);

  @override
  Future<RepositoryResult<PublicEventCatalog>> refreshCatalog() =>
      remote.fetchCatalog();

  @override
  Future<RepositoryResult<PublicEventItem>> getEvent(EventId id) async {
    final result = await remote.fetchCatalog();
    return result.when(
      success: (catalog) {
        final item = catalog.eventById(id.value);
        return item == null
            ? RepositoryFailure<PublicEventItem>(
                NotFoundFailure(entity: 'Event', identifier: id.value),
              )
            : RepositorySuccess<PublicEventItem>(item);
      },
      failure: RepositoryFailure<PublicEventItem>.new,
    );
  }
}

final class AndroidCachedPublicEventReader implements PublicEventReader {
  const AndroidCachedPublicEventReader({
    required this.cache,
    required this.remote,
  });

  final PublicEventCache cache;
  final PublicEventRemoteSource? remote;

  @override
  Future<RepositoryResult<PublicEventCatalog?>> readCachedCatalog() =>
      cache.readCatalog();

  @override
  Future<RepositoryResult<PublicEventCatalog>> refreshCatalog() async {
    final source = remote;
    if (source == null) {
      return const RepositoryFailure<PublicEventCatalog>(
        PersistenceUnavailableFailure(
          message: 'Public cloud data is not configured for this build.',
        ),
      );
    }
    final remoteResult = await source.fetchCatalog();
    return remoteResult.when(
      success: cache.reconcile,
      failure: RepositoryFailure<PublicEventCatalog>.new,
    );
  }

  @override
  Future<RepositoryResult<PublicEventItem>> getEvent(EventId id) async {
    final cached = await cache.readCatalog();
    final cachedItem = cached.when(
      success: (catalog) => catalog?.eventById(id.value),
      failure: (_) => null,
    );
    if (cachedItem != null) {
      return RepositorySuccess<PublicEventItem>(cachedItem);
    }
    final refreshed = await refreshCatalog();
    return refreshed.when(
      success: (catalog) {
        final item = catalog.eventById(id.value);
        return item == null
            ? RepositoryFailure<PublicEventItem>(
                NotFoundFailure(entity: 'Event', identifier: id.value),
              )
            : RepositorySuccess<PublicEventItem>(item);
      },
      failure: RepositoryFailure<PublicEventItem>.new,
    );
  }
}

final class UnconfiguredPublicEventReader implements PublicEventReader {
  const UnconfiguredPublicEventReader();

  static const _failure = PersistenceUnavailableFailure(
    message: 'Public cloud data is not configured for this build.',
  );

  @override
  Future<RepositoryResult<PublicEventCatalog?>> readCachedCatalog() async =>
      const RepositorySuccess<PublicEventCatalog?>(null);

  @override
  Future<RepositoryResult<PublicEventCatalog>> refreshCatalog() async =>
      const RepositoryFailure<PublicEventCatalog>(_failure);

  @override
  Future<RepositoryResult<PublicEventItem>> getEvent(EventId id) async =>
      const RepositoryFailure<PublicEventItem>(_failure);
}
