import 'dart:collection';

import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/common/domain_enums.dart';

const playerHistoryPageSize = 20;

final class PlayerCareerSummary {
  const PlayerCareerSummary({
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.eventAppearances,
    required this.divisionAppearances,
    required this.championships,
    required this.runnerUpFinishes,
    required this.pointsFor,
    required this.pointsAgainst,
  });

  const PlayerCareerSummary.zero()
    : matchesPlayed = 0,
      wins = 0,
      losses = 0,
      eventAppearances = 0,
      divisionAppearances = 0,
      championships = 0,
      runnerUpFinishes = 0,
      pointsFor = 0,
      pointsAgainst = 0;

  final int matchesPlayed;
  final int wins;
  final int losses;
  final int eventAppearances;
  final int divisionAppearances;
  final int championships;
  final int runnerUpFinishes;
  final int pointsFor;
  final int pointsAgainst;

  int get pointDifferential => pointsFor - pointsAgainst;
  double get winRate => matchesPlayed == 0 ? 0 : wins / matchesPlayed * 100;
}

final class PlayerPartnerSummary {
  const PlayerPartnerSummary({
    required this.partnerId,
    required this.partnerName,
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
  });

  final PlayerId partnerId;
  final String partnerName;
  final int matchesPlayed;
  final int wins;
  final int losses;
  double get winRate => matchesPlayed == 0 ? 0 : wins / matchesPlayed * 100;
}

final class PlayerMatchHistoryEntry {
  const PlayerMatchHistoryEntry({
    required this.matchId,
    required this.eventId,
    required this.eventName,
    required this.divisionId,
    required this.divisionName,
    required this.format,
    required this.completedAt,
    required this.teamName,
    required this.opponentName,
    required this.pointsFor,
    required this.pointsAgainst,
    required this.won,
    required this.roundNumber,
  });

  final MatchId matchId;
  final EventId eventId;
  final String eventName;
  final DivisionId divisionId;
  final String divisionName;
  final TournamentFormat? format;
  final DateTime completedAt;
  final String teamName;
  final String opponentName;
  final int pointsFor;
  final int pointsAgainst;
  final bool won;
  final int? roundNumber;
}

final class PlayerCompletedEventEntry {
  const PlayerCompletedEventEntry({
    required this.eventId,
    required this.eventName,
    required this.completedAt,
    required this.divisionNames,
  });

  final EventId eventId;
  final String eventName;
  final DateTime completedAt;
  final UnmodifiableListView<String> divisionNames;
}

final class PlayerHistoryPage<T> {
  PlayerHistoryPage({required Iterable<T> entries, required this.hasMore})
    : entries = UnmodifiableListView(entries) {
    if (this.entries.length > playerHistoryPageSize) {
      throw const ValidationFailure(
        field: 'entries',
        message: 'History pages cannot contain more than 20 records.',
      );
    }
  }
  final UnmodifiableListView<T> entries;
  final bool hasMore;
}

final class PlayerHistorySnapshot {
  PlayerHistorySnapshot({
    required this.summary,
    required this.matches,
    required this.events,
    required Iterable<PlayerPartnerSummary> partners,
    this.hasPendingSync = false,
    this.hasConflict = false,
  }) : partners = UnmodifiableListView(partners);

  final PlayerCareerSummary summary;
  final PlayerHistoryPage<PlayerMatchHistoryEntry> matches;
  final PlayerHistoryPage<PlayerCompletedEventEntry> events;
  final UnmodifiableListView<PlayerPartnerSummary> partners;
  final bool hasPendingSync;
  final bool hasConflict;
}

abstract interface class PlayerHistoryReader {
  Future<RepositoryResult<PlayerHistorySnapshot>> read(PlayerId playerId);
}
