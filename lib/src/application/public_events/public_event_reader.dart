import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'public_event_models.dart';

/// Provider-neutral, read-only access used by the public guest experience.
abstract interface class PublicEventReader {
  Future<RepositoryResult<PublicEventCatalog?>> readCachedCatalog();

  Future<RepositoryResult<PublicEventCatalog>> refreshCatalog();

  Future<RepositoryResult<PublicEventItem>> getEvent(EventId id);
}

/// Remote side of the public reader. Implementations may only read public data.
abstract interface class PublicEventRemoteSource {
  Future<RepositoryResult<PublicEventCatalog>> fetchCatalog();
}

/// Android-only cache port. It deliberately has no guest-facing write API.
abstract interface class PublicEventCache {
  Future<RepositoryResult<PublicEventCatalog?>> readCatalog();

  Future<RepositoryResult<PublicEventCatalog>> reconcile(
    PublicEventCatalog authoritativeCatalog,
  );
}
