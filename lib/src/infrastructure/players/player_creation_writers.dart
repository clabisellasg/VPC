import '../../application/players/player_directory_models.dart';
import '../../application/players/player_directory_reader.dart';
import '../../application/sync/sync_contracts.dart';
import '../../application/sync/sync_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/player_repository.dart';

final class AndroidPlayerCreationWriter implements PlayerCreationWriter {
  const AndroidPlayerCreationWriter({
    required this.repository,
    required this.coordinator,
  });

  final PlayerRepository repository;
  final SyncCoordinator? coordinator;

  @override
  Future<RepositoryResult<CreatedPlayer>> create(
    PublicPlayerProfile player,
  ) async {
    final saved = await repository.save(player.toPlayer());
    if (saved case RepositoryFailure(:final failure)) {
      return RepositoryFailure(failure);
    }
    final sync = coordinator;
    if (sync == null) {
      return RepositorySuccess(
        CreatedPlayer(
          profile: player,
          disposition: PlayerCreationDisposition.pending,
        ),
      );
    }
    final report = await sync.synchronize();
    if (report.status == SyncRunStatus.completed && report.uploaded > 0) {
      final authoritative = await repository.getById(player.id);
      if (authoritative case RepositorySuccess(:final value)) {
        return RepositorySuccess(
          CreatedPlayer(
            profile: PublicPlayerProfile.fromPlayer(value),
            disposition: PlayerCreationDisposition.synchronized,
          ),
        );
      }
    }
    return RepositorySuccess(
      CreatedPlayer(
        profile: player,
        disposition: PlayerCreationDisposition.pending,
      ),
    );
  }
}

final class WebPlayerCreationWriter implements PlayerCreationWriter {
  const WebPlayerCreationWriter({
    required this.remote,
    required this.idFactory,
    required this.clock,
  });

  final SyncRemoteGateway remote;
  final SyncIdFactory idFactory;
  final SyncClock clock;

  @override
  Future<RepositoryResult<CreatedPlayer>> create(
    PublicPlayerProfile player,
  ) async {
    final now = clock.nowUtc();
    final operation = SyncOperation(
      id: idFactory.operationId(),
      entityType: SyncEntityType.player,
      entityId: player.id,
      kind: SyncOperationKind.upsert,
      payload: PlayerSyncPayload.fromPlayer(player.toPlayer()),
      createdAt: now,
      attemptCount: 0,
      nextEligibleAt: now,
      status: SyncOperationStatus.pending,
    );
    final result = await remote.applyPlayerOperation(operation);
    return switch (result) {
      RemoteApplyAccepted(:final player) => RepositorySuccess(
        CreatedPlayer(
          profile: PublicPlayerProfile.fromPlayer(player),
          disposition: PlayerCreationDisposition.synchronized,
        ),
      ),
      RemoteApplyConflict() => const RepositoryFailure(
        ConflictFailure(
          message:
              'The player could not be created because cloud data changed.',
        ),
      ),
      RemoteApplyFailure(kind: SyncFailureKind.authorizationBlocked) =>
        const RepositoryFailure(
          UnauthorizedFailure(
            message: 'A confirmed organizer session is required.',
          ),
        ),
      RemoteApplyFailure(:final safeMessage) => RepositoryFailure(
        PersistenceUnavailableFailure(message: safeMessage),
      ),
    };
  }
}

final class UnavailablePlayerCreationWriter implements PlayerCreationWriter {
  const UnavailablePlayerCreationWriter();

  @override
  Future<RepositoryResult<CreatedPlayer>> create(
    PublicPlayerProfile player,
  ) async => const RepositoryFailure(
    PersistenceUnavailableFailure(
      message: 'Player creation is not configured for this build.',
    ),
  );
}
