import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'player_directory_models.dart';
import 'player_directory_reader.dart';

final class OnlinePlayerDirectoryReader implements PlayerDirectoryReader {
  const OnlinePlayerDirectoryReader(this.remote);

  final PlayerDirectoryRemoteSource remote;

  @override
  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id) =>
      remote.fetchById(id);

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  ) => remote.fetchPage(query);

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> refreshPage(
    PlayerDirectoryQuery query,
  ) => remote.fetchPage(query);
}

final class AndroidCachedPlayerDirectoryReader
    implements PlayerDirectoryReader {
  const AndroidCachedPlayerDirectoryReader({
    required this.cache,
    required this.remote,
  });

  final PlayerDirectoryCache cache;
  final PlayerDirectoryRemoteSource? remote;

  @override
  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id) async {
    final local = await cache.getById(id);
    if (local.isSuccess || remote == null) {
      return local;
    }
    final fetched = await remote!.fetchById(id);
    if (fetched case RepositorySuccess(:final value)) {
      final page = PlayerDirectoryPage(
        entries: [value],
        hasMore: false,
        origin: PlayerDirectoryOrigin.remote,
      );
      final reconciled = await cache.reconcile(page);
      if (reconciled is RepositoryFailure<void>) {
        return RepositoryFailure(reconciled.failure);
      }
      return cache.getById(id);
    }
    return fetched;
  }

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  ) => cache.readPage(query);

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> refreshPage(
    PlayerDirectoryQuery query,
  ) async {
    final source = remote;
    if (source == null) {
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'Public player refresh is not configured.',
        ),
      );
    }
    final fetched = await source.fetchPage(query);
    if (fetched case RepositoryFailure<PlayerDirectoryPage>()) {
      return fetched;
    }
    final remotePage =
        (fetched as RepositorySuccess<PlayerDirectoryPage>).value;
    final reconciled = await cache.reconcile(remotePage);
    if (reconciled case RepositoryFailure<void>(:final failure)) {
      return RepositoryFailure(failure);
    }
    return cache.readPage(query);
  }
}

final class UnconfiguredPlayerDirectoryReader implements PlayerDirectoryReader {
  const UnconfiguredPlayerDirectoryReader();

  static const _failure = PersistenceUnavailableFailure(
    message: 'Public player data is not configured.',
  );

  @override
  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id) async =>
      const RepositoryFailure(_failure);

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  ) async => const RepositoryFailure(_failure);

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> refreshPage(
    PlayerDirectoryQuery query,
  ) async => const RepositoryFailure(_failure);
}
