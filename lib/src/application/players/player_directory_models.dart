import 'dart:collection';

import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/players/permanent_player.dart';

const playerDirectoryPageSize = 50;

String preparePlayerDisplayName(String value) {
  final prepared = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (prepared.isEmpty) {
    throw const ValidationFailure(
      field: 'displayName',
      message: 'Player display name cannot be blank.',
    );
  }
  return prepared;
}

String normalizePlayerName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

final class PlayerDirectoryCursor {
  PlayerDirectoryCursor({required String normalizedName, required this.id})
    : normalizedName = normalizePlayerName(normalizedName) {
    if (this.normalizedName.isEmpty) {
      throw const ValidationFailure(
        field: 'cursor',
        message: 'A player cursor requires a normalized name.',
      );
    }
  }

  final String normalizedName;
  final PlayerId id;
}

final class PlayerDirectoryQuery {
  factory PlayerDirectoryQuery({
    String searchText = '',
    PlayerDirectoryCursor? after,
    int limit = playerDirectoryPageSize,
  }) {
    if (limit <= 0 || limit > playerDirectoryPageSize) {
      throw const ValidationFailure(
        field: 'limit',
        message:
            'Player directory pages must contain between 1 and 50 records.',
      );
    }
    return PlayerDirectoryQuery._(
      searchText: normalizePlayerName(searchText),
      after: after,
      limit: limit,
    );
  }

  const PlayerDirectoryQuery._({
    required this.searchText,
    required this.after,
    required this.limit,
  });

  final String searchText;
  final PlayerDirectoryCursor? after;
  final int limit;

  PlayerDirectoryQuery next(PlayerDirectoryCursor cursor) =>
      PlayerDirectoryQuery(searchText: searchText, after: cursor, limit: limit);
}

final class PublicPlayerProfile {
  factory PublicPlayerProfile({
    required PlayerId id,
    required String displayName,
    required RecordMetadata metadata,
  }) {
    if (metadata.isDeleted) {
      throw const ValidationFailure(
        field: 'deletedAt',
        message: 'A public player profile must be active.',
      );
    }
    return PublicPlayerProfile._(
      id: id,
      displayName: preparePlayerDisplayName(displayName),
      metadata: metadata,
    );
  }

  factory PublicPlayerProfile.fromPlayer(PermanentPlayer player) {
    if (player.accountId != null) {
      throw const ValidationFailure(
        field: 'accountId',
        message: 'Public player profiles cannot contain account identity.',
      );
    }
    return PublicPlayerProfile(
      id: player.id,
      displayName: player.displayName,
      metadata: player.metadata,
    );
  }

  const PublicPlayerProfile._({
    required this.id,
    required this.displayName,
    required this.metadata,
  });

  final PlayerId id;
  final String displayName;
  final RecordMetadata metadata;

  PermanentPlayer toPlayer() =>
      PermanentPlayer(id: id, displayName: displayName, metadata: metadata);
}

enum PlayerSyncPresentation {
  synchronized,
  pending,
  authorizationBlocked,
  failed,
  conflicted,
}

enum PlayerDirectoryOrigin { remote, androidLocal }

final class PlayerDirectoryEntry {
  const PlayerDirectoryEntry({
    required this.profile,
    this.syncState = PlayerSyncPresentation.synchronized,
  });

  final PublicPlayerProfile profile;
  final PlayerSyncPresentation syncState;
}

final class PlayerDirectoryPage {
  PlayerDirectoryPage({
    required Iterable<PlayerDirectoryEntry> entries,
    required this.hasMore,
    required this.origin,
  }) : entries = UnmodifiableListView(entries) {
    if (this.entries.length > playerDirectoryPageSize) {
      throw const ValidationFailure(
        field: 'entries',
        message: 'A player directory page cannot exceed 50 records.',
      );
    }
  }

  final UnmodifiableListView<PlayerDirectoryEntry> entries;
  final bool hasMore;
  final PlayerDirectoryOrigin origin;

  PlayerDirectoryCursor? get nextCursor {
    if (!hasMore || entries.isEmpty) {
      return null;
    }
    final last = entries.last.profile;
    return PlayerDirectoryCursor(normalizedName: last.displayName, id: last.id);
  }
}

enum PlayerCreationDisposition { pending, synchronized }

final class CreatedPlayer {
  const CreatedPlayer({required this.profile, required this.disposition});

  final PublicPlayerProfile profile;
  final PlayerCreationDisposition disposition;
}

sealed class PlayerCreationResult {
  const PlayerCreationResult();
}

final class PlayerCreated extends PlayerCreationResult {
  const PlayerCreated(this.value);

  final CreatedPlayer value;
}

final class PlayerDuplicateWarning extends PlayerCreationResult {
  PlayerDuplicateWarning(Iterable<PublicPlayerProfile> candidates)
    : candidates = UnmodifiableListView(candidates);

  final UnmodifiableListView<PublicPlayerProfile> candidates;
}

final class PlayerCreationFailed extends PlayerCreationResult {
  const PlayerCreationFailed(this.failure);

  final DomainFailure failure;
}
