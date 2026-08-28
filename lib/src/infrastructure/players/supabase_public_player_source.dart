import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/players/player_directory_models.dart';
import '../../application/players/player_directory_reader.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';

abstract interface class PublicPlayerRowsGateway {
  Future<List<Map<String, Object?>>> search(PlayerDirectoryQuery query);

  Future<Map<String, Object?>?> getById(PlayerId id);
}

final class SupabasePublicPlayerRowsGateway implements PublicPlayerRowsGateway {
  const SupabasePublicPlayerRowsGateway(this.client);

  final SupabaseClient client;

  static const selectedColumns =
      'id,display_name,created_at,updated_at,version,deleted_at';

  @override
  Future<List<Map<String, Object?>>> search(PlayerDirectoryQuery query) async {
    final response = await client.rpc<List<dynamic>>(
      'search_public_players',
      params: <String, Object?>{
        'p_query': query.searchText,
        'p_after_name': query.after?.normalizedName,
        'p_after_id': query.after?.id.value,
        'p_limit': query.limit,
      },
    );
    return response
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> getById(PlayerId id) async {
    final rows = await client
        .from('players')
        .select(selectedColumns)
        .eq('id', id.value)
        .isFilter('deleted_at', null)
        .limit(1);
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.single);
  }
}

final class SupabasePublicPlayerSource implements PlayerDirectoryRemoteSource {
  const SupabasePublicPlayerSource(this.gateway);

  final PublicPlayerRowsGateway gateway;

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> fetchPage(
    PlayerDirectoryQuery query,
  ) async {
    try {
      final rows = await gateway.search(query);
      var hasMore = false;
      final entries = <PlayerDirectoryEntry>[];
      for (final row in rows) {
        final profile = publicPlayerFromRow(row);
        final normalized = _requiredString(row, 'normalized_name');
        if (normalized != normalizePlayerName(profile.displayName)) {
          throw const ValidationFailure(
            field: 'normalized_name',
            message: 'Public player ordering data is invalid.',
          );
        }
        final rowHasMore = row['has_more'];
        if (rowHasMore is! bool) {
          throw const ValidationFailure(
            field: 'has_more',
            message: 'Public player pagination data is invalid.',
          );
        }
        hasMore = rowHasMore;
        entries.add(PlayerDirectoryEntry(profile: profile));
      }
      return RepositorySuccess(
        PlayerDirectoryPage(
          entries: entries,
          hasMore: hasMore,
          origin: PlayerDirectoryOrigin.remote,
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      return const RepositoryFailure(
        UnknownRepositoryFailure(
          message: 'Public player data could not be loaded safely.',
        ),
      );
    }
  }

  @override
  Future<RepositoryResult<PlayerDirectoryEntry>> fetchById(PlayerId id) async {
    try {
      final row = await gateway.getById(id);
      if (row == null) {
        return RepositoryFailure(
          NotFoundFailure(entity: 'Player', identifier: id.value),
        );
      }
      return RepositorySuccess(
        PlayerDirectoryEntry(profile: publicPlayerFromRow(row)),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      return const RepositoryFailure(
        UnknownRepositoryFailure(
          message: 'The public player profile could not be loaded safely.',
        ),
      );
    }
  }
}

PublicPlayerProfile publicPlayerFromRow(Map<String, Object?> row) {
  final deletedAt = _optionalTimestamp(row, 'deleted_at');
  return PublicPlayerProfile(
    id: PlayerId(_requiredString(row, 'id')),
    displayName: _requiredString(row, 'display_name'),
    metadata: RecordMetadata(
      createdAt: _requiredTimestamp(row, 'created_at'),
      updatedAt: _requiredTimestamp(row, 'updated_at'),
      recordVersion: _requiredInt(row, 'version'),
      deletedAt: deletedAt,
    ),
  );
}

String _requiredString(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is String) {
    return value;
  }
  throw ValidationFailure(field: field, message: 'Public $field must be text.');
}

int _requiredInt(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is int) {
    return value;
  }
  throw ValidationFailure(
    field: field,
    message: 'Public $field must be an integer.',
  );
}

DateTime _requiredTimestamp(Map<String, Object?> row, String field) {
  final value = _optionalTimestamp(row, field);
  if (value != null) {
    return value;
  }
  throw ValidationFailure(
    field: field,
    message: 'Public $field must be a valid timestamp.',
  );
}

DateTime? _optionalTimestamp(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw ValidationFailure(
      field: field,
      message: 'Public $field must be a timestamp.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
    throw ValidationFailure(
      field: field,
      message: 'Public $field must include a UTC offset.',
    );
  }
  return parsed.toUtc();
}
