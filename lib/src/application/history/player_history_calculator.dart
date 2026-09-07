import '../history/player_history_models.dart';
import '../../domain/common/entity_id.dart';

/// Pure aggregation for current, already-filtered completed-match facts.
/// Adapters exclude tombstones and obsolete revisions before calling this.
final class PlayerHistoryCalculator {
  const PlayerHistoryCalculator();

  PlayerCareerSummary summary({
    required Iterable<PlayerMatchHistoryEntry> matches,
    required int eventAppearances,
    required int divisionAppearances,
    required int championships,
    required int runnerUpFinishes,
  }) {
    var wins = 0;
    var pointsFor = 0;
    var pointsAgainst = 0;
    var count = 0;
    for (final match in matches) {
      count++;
      if (match.won) wins++;
      pointsFor += match.pointsFor;
      pointsAgainst += match.pointsAgainst;
    }
    return PlayerCareerSummary(
      matchesPlayed: count,
      wins: wins,
      losses: count - wins,
      eventAppearances: eventAppearances,
      divisionAppearances: divisionAppearances,
      championships: championships,
      runnerUpFinishes: runnerUpFinishes,
      pointsFor: pointsFor,
      pointsAgainst: pointsAgainst,
    );
  }

  List<PlayerPartnerSummary> partners({
    required PlayerId playerId,
    required Iterable<PlayerMatchHistoryEntry> matches,
    required Map<MatchId, Iterable<PlayerPartnerFact>> partnersByMatch,
  }) {
    final totals = <PlayerId, _PartnerTotal>{};
    for (final match in matches) {
      for (final partner
          in partnersByMatch[match.matchId] ?? const <PlayerPartnerFact>[]) {
        if (partner.id == playerId) continue;
        final total = totals.putIfAbsent(
          partner.id,
          () => _PartnerTotal(partner.name),
        );
        total.matches++;
        if (match.won) total.wins++;
      }
    }
    final result =
        totals.entries
            .map(
              (entry) => PlayerPartnerSummary(
                partnerId: entry.key,
                partnerName: entry.value.name,
                matchesPlayed: entry.value.matches,
                wins: entry.value.wins,
                losses: entry.value.matches - entry.value.wins,
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.partnerName.toLowerCase().compareTo(
              b.partnerName.toLowerCase(),
            ),
          );
    return result;
  }
}

final class _PartnerTotal {
  _PartnerTotal(this.name);
  final String name;
  int matches = 0;
  int wins = 0;
}

final class PlayerPartnerFact {
  const PlayerPartnerFact(this.id, this.name);
  final PlayerId id;
  final String name;
}
