import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/history/player_history_calculator.dart';
import 'package:vpc/src/application/history/player_history_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';

void main() {
  final player = PlayerId('11111111-1111-4111-8111-111111111111');
  PlayerMatchHistoryEntry match({required bool won, required String id}) =>
      PlayerMatchHistoryEntry(
        matchId: MatchId(id),
        eventId: EventId('22222222-2222-4222-8222-222222222222'),
        eventName: 'VPC Test',
        divisionId: DivisionId('33333333-3333-4333-8333-333333333333'),
        divisionName: 'Open',
        format: TournamentFormat.singleRoundRobin,
        completedAt: DateTime.utc(2026, 9, 7),
        teamName: 'A / B',
        opponentName: 'C / D',
        pointsFor: won ? 11 : 9,
        pointsAgainst: won ? 8 : 11,
        won: won,
        roundNumber: 1,
      );
  test('zero history is a deterministic valid summary', () {
    final result = const PlayerHistoryCalculator().summary(
      matches: const [],
      eventAppearances: 0,
      divisionAppearances: 0,
      championships: 0,
      runnerUpFinishes: 0,
    );
    expect(result.matchesPlayed, 0);
    expect(result.winRate, 0);
    expect(result.pointDifferential, 0);
  });
  test('calculates current wins losses and points without counters', () {
    final result = const PlayerHistoryCalculator().summary(
      matches: [
        match(won: true, id: '44444444-4444-4444-8444-444444444444'),
        match(won: false, id: '55555555-5555-4555-8555-555555555555'),
      ],
      eventAppearances: 1,
      divisionAppearances: 1,
      championships: 0,
      runnerUpFinishes: 0,
    );
    expect((result.matchesPlayed, result.wins, result.losses), (2, 1, 1));
    expect(
      (result.pointsFor, result.pointsAgainst, result.pointDifferential),
      (20, 19, 1),
    );
    expect(result.winRate, 50);
  });
  test('partner pair is unordered from the player perspective', () {
    final data = match(won: true, id: '66666666-6666-4666-8666-666666666666');
    final partners = const PlayerHistoryCalculator().partners(
      playerId: player,
      matches: [data],
      partnersByMatch: {
        data.matchId: [
          PlayerPartnerFact(
            PlayerId('77777777-7777-4777-8777-777777777777'),
            'Partner',
          ),
          PlayerPartnerFact(player, 'Self'),
        ],
      },
    );
    expect(partners.single.partnerName, 'Partner');
    expect((partners.single.matchesPlayed, partners.single.wins), (1, 1));
  });
}
