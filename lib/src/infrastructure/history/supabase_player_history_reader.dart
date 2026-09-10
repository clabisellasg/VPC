import 'dart:collection';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/history/player_history_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../common/public_supabase_request.dart';
import '../../core/supabase/public_supabase_rest_client.dart';

abstract interface class PublicPlayerHistoryGateway {
  Future<Object?> read(PlayerId playerId);
}

final class SupabasePublicPlayerHistoryGateway
    implements PublicPlayerHistoryGateway {
  const SupabasePublicPlayerHistoryGateway(this.client);

  final SupabaseClient client;

  @override
  Future<Object?> read(PlayerId playerId) => runPublicSupabaseRequest(
    () => client.rpc<Object?>(
      'read_public_player_history',
      params: {'p_player_id': playerId.value},
    ),
  );
}

final class HttpPublicPlayerHistoryGateway
    implements PublicPlayerHistoryGateway {
  const HttpPublicPlayerHistoryGateway(this.client);

  final PublicSupabaseRestClient client;

  @override
  Future<Object?> read(PlayerId playerId) => runPublicSupabaseRequest(
    () => client.rpc('read_public_player_history', {
      'p_player_id': playerId.value,
    }),
  );
}

final class SupabasePlayerHistoryReader implements PlayerHistoryReader {
  const SupabasePlayerHistoryReader(this.gateway);

  final PublicPlayerHistoryGateway gateway;

  @override
  Future<RepositoryResult<PlayerHistorySnapshot>> read(
    PlayerId playerId,
  ) async {
    try {
      final value = await gateway.read(playerId);
      if (value == null) {
        return RepositoryFailure(
          NotFoundFailure(entity: 'Player', identifier: playerId.value),
        );
      }
      return RepositorySuccess(
        _snapshot(Map<String, Object?>.from(value as Map)),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error) {
      if (error is Error) rethrow;
      return RepositoryFailure(safePublicReadFailure(error, 'Player history'));
    }
  }

  PlayerHistorySnapshot _snapshot(Map<String, Object?> value) {
    final summary = Map<String, Object?>.from(value['summary'] as Map);
    final matches = _rows(value['matches']).map(_match).toList();
    final events = _rows(value['events']).map(_event).toList();
    final partners = _rows(value['partners']).map(_partner).toList();
    return PlayerHistorySnapshot(
      summary: PlayerCareerSummary(
        matchesPlayed: _int(summary, 'matches_played'),
        wins: _int(summary, 'wins'),
        losses: _int(summary, 'losses'),
        eventAppearances: _int(summary, 'event_appearances'),
        divisionAppearances: _int(summary, 'division_appearances'),
        championships: _int(summary, 'championships'),
        runnerUpFinishes: _int(summary, 'runner_up_finishes'),
        pointsFor: _int(summary, 'points_for'),
        pointsAgainst: _int(summary, 'points_against'),
      ),
      matches: PlayerHistoryPage(
        entries: matches.take(playerHistoryPageSize),
        hasMore: matches.length > playerHistoryPageSize,
      ),
      events: PlayerHistoryPage(
        entries: events.take(playerHistoryPageSize),
        hasMore: events.length > playerHistoryPageSize,
      ),
      partners: partners,
    );
  }

  List<Map<String, Object?>> _rows(Object? value) {
    if (value is! List) {
      throw const ValidationFailure(
        field: 'history',
        message: 'History rows are invalid.',
      );
    }
    return value.map((row) => Map<String, Object?>.from(row as Map)).toList();
  }

  PlayerMatchHistoryEntry _match(Map<String, Object?> row) =>
      PlayerMatchHistoryEntry(
        matchId: MatchId(_string(row, 'match_id')),
        eventId: EventId(_string(row, 'event_id')),
        eventName: _string(row, 'event_name'),
        divisionId: DivisionId(_string(row, 'division_id')),
        divisionName: _string(row, 'division_name'),
        format: _format(row['format']),
        completedAt: _time(row, 'completed_at'),
        teamName: _string(row, 'team_name'),
        opponentName: _string(row, 'opponent_name'),
        pointsFor: _int(row, 'points_for'),
        pointsAgainst: _int(row, 'points_against'),
        won: row['won'] == true,
        roundNumber: row['round_number'] as int?,
      );
  PlayerCompletedEventEntry _event(Map<String, Object?> row) =>
      PlayerCompletedEventEntry(
        eventId: EventId(_string(row, 'event_id')),
        eventName: _string(row, 'event_name'),
        completedAt: _time(row, 'completed_at'),
        divisionNames: UnmodifiableListView(const <String>[]),
      );
  PlayerPartnerSummary _partner(Map<String, Object?> row) =>
      PlayerPartnerSummary(
        partnerId: PlayerId(_string(row, 'player_id')),
        partnerName: _string(row, 'display_name'),
        matchesPlayed: _int(row, 'matches_played'),
        wins: _int(row, 'wins'),
        losses: _int(row, 'losses'),
      );
  String _string(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is String && value.isNotEmpty) return value;
    throw ValidationFailure(field: key, message: 'History $key is invalid.');
  }

  int _int(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is int) return value;
    throw ValidationFailure(field: key, message: 'History $key is invalid.');
  }

  DateTime _time(Map<String, Object?> row, String key) =>
      DateTime.parse(_string(row, key)).toUtc();
  TournamentFormat? _format(Object? value) => switch (value) {
    null => null,
    'singleElimination' => TournamentFormat.singleElimination,
    'doubleElimination' => TournamentFormat.doubleElimination,
    'singleRoundRobin' => TournamentFormat.singleRoundRobin,
    'doubleRoundRobin' => TournamentFormat.doubleRoundRobin,
    _ => throw const ValidationFailure(
      field: 'format',
      message: 'History format is invalid.',
    ),
  };
}
