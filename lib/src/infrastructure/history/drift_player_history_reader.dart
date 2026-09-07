import 'dart:collection';

import 'package:drift/drift.dart';

import '../../application/history/player_history_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../persistence/local/app_database.dart';

/// Read-only Android derivation from local operational records. No aggregate
/// table, counter, outbox operation, or network request is involved.
final class DriftPlayerHistoryReader implements PlayerHistoryReader {
  const DriftPlayerHistoryReader(this.database);
  final AppDatabase database;

  @override
  Future<RepositoryResult<PlayerHistorySnapshot>> read(
    PlayerId playerId,
  ) async {
    try {
      final exists = await database
          .customSelect(
            'select id from players where id=? and deleted_at is null',
            variables: [Variable<String>(playerId.value)],
          )
          .get();
      if (exists.isEmpty) {
        return RepositoryFailure(
          NotFoundFailure(entity: 'Player', identifier: playerId.value),
        );
      }
      final rows = await database
          .customSelect(
            '''
select m.id match_id,e.id event_id,e.name event_name,d.id division_id,d.name division_name,d.tournament_format,
m.updated_at completed_at,m.round_number,m.side_one_team_id,m.side_two_team_id,m.side_one_score,m.side_two_score,m.winner_team_id,
case when m.side_one_team_id=tm.team_id then m.side_one_team_id else m.side_two_team_id end own_team_id
from matches m join team_members tm on tm.player_id=? and tm.team_id in(m.side_one_team_id,m.side_two_team_id) and tm.deleted_at is null
join teams t on t.id=tm.team_id and t.deleted_at is null join event_divisions d on d.id=m.division_id and d.deleted_at is null
join events e on e.id=d.event_id and e.deleted_at is null where m.status='completed' and m.deleted_at is null order by m.updated_at desc,m.id desc
''',
            variables: [Variable<String>(playerId.value)],
          )
          .get();
      final ids = <String>{
        for (final row in rows) ...<String>[
          row.read<String>('side_one_team_id'),
          row.read<String>('side_two_team_id'),
        ],
      };
      final memberRows = ids.isEmpty
          ? <QueryRow>[]
          : await database
                .customSelect(
                  'select tm.team_id,p.id,p.display_name from team_members tm join players p on p.id=tm.player_id and p.deleted_at is null where tm.deleted_at is null and tm.team_id in (${List.filled(ids.length, '?').join(',')})',
                  variables: ids.map((id) => Variable<String>(id)).toList(),
                )
                .get();
      final names = <String, List<_Name>>{};
      for (final row in memberRows) {
        names
            .putIfAbsent(row.read<String>('team_id'), () => [])
            .add(
              _Name(row.read<String>('id'), row.read<String>('display_name')),
            );
      }
      final matches = <PlayerMatchHistoryEntry>[];
      final partners = <String, _Partner>{};
      var wins = 0, forPoints = 0, against = 0;
      for (final row in rows) {
        final own = row.read<String>('own_team_id');
        final one = row.read<String>('side_one_team_id');
        final other = own == one ? row.read<String>('side_two_team_id') : one;
        final pf = own == one
            ? row.read<int>('side_one_score')
            : row.read<int>('side_two_score');
        final pa = own == one
            ? row.read<int>('side_two_score')
            : row.read<int>('side_one_score');
        final won = row.read<String>('winner_team_id') == own;
        matches.add(
          PlayerMatchHistoryEntry(
            matchId: MatchId(row.read<String>('match_id')),
            eventId: EventId(row.read<String>('event_id')),
            eventName: row.read<String>('event_name'),
            divisionId: DivisionId(row.read<String>('division_id')),
            divisionName: row.read<String>('division_name'),
            format: _format(row.readNullable<String>('tournament_format')),
            completedAt: row.read<DateTime>('completed_at').toUtc(),
            teamName: _label(names[own]),
            opponentName: _label(names[other]),
            pointsFor: pf,
            pointsAgainst: pa,
            won: won,
            roundNumber: row.readNullable<int>('round_number'),
          ),
        );
        if (won) wins++;
        forPoints += pf;
        against += pa;
        for (final partner in names[own] ?? const <_Name>[]) {
          if (partner.id == playerId.value) continue;
          final v = partners.putIfAbsent(
            partner.id,
            () => _Partner(partner.name),
          );
          v.matches++;
          if (won) v.wins++;
        }
      }
      final eventRows = await database
          .customSelect(
            "select distinct e.id,e.name,e.updated_at from event_participants ep join events e on e.id=ep.event_id and e.deleted_at is null where ep.player_id=? and ep.check_in_status='checkedIn' and ep.deleted_at is null and e.status in('completed','archived') order by e.updated_at desc,e.id desc",
            variables: [Variable<String>(playerId.value)],
          )
          .get();
      final placeRows = await database
          .customSelect(
            'select dp.position from division_placements dp join teams t on t.id=dp.team_id and t.deleted_at is null join team_members tm on tm.team_id=t.id and tm.player_id=? and tm.deleted_at is null where dp.deleted_at is null',
            variables: [Variable<String>(playerId.value)],
          )
          .get();
      final summary = PlayerCareerSummary(
        matchesPlayed: matches.length,
        wins: wins,
        losses: matches.length - wins,
        eventAppearances: eventRows.length,
        divisionAppearances: matches
            .map((m) => m.divisionId.value)
            .toSet()
            .length,
        championships: placeRows
            .where((r) => r.read<int>('position') == 1)
            .length,
        runnerUpFinishes: placeRows
            .where((r) => r.read<int>('position') == 2)
            .length,
        pointsFor: forPoints,
        pointsAgainst: against,
      );
      final partnerList =
          partners.entries
              .map(
                (e) => PlayerPartnerSummary(
                  partnerId: PlayerId(e.key),
                  partnerName: e.value.name,
                  matchesPlayed: e.value.matches,
                  wins: e.value.wins,
                  losses: e.value.matches - e.value.wins,
                ),
              )
              .toList()
            ..sort((a, b) => a.partnerName.compareTo(b.partnerName));
      final events = eventRows
          .map(
            (r) => PlayerCompletedEventEntry(
              eventId: EventId(r.read<String>('id')),
              eventName: r.read<String>('name'),
              completedAt: r.read<DateTime>('updated_at').toUtc(),
              divisionNames: UnmodifiableListView(const <String>[]),
            ),
          )
          .toList();
      final syncStates = await database.customSelect('''
select status from single_elimination_outbox where status<>'accepted'
union all select status from round_robin_outbox where status<>'accepted'
union all select status from double_elimination_outbox where status<>'accepted'
''').get();
      return RepositorySuccess(
        PlayerHistorySnapshot(
          summary: summary,
          matches: PlayerHistoryPage(
            entries: matches.take(playerHistoryPageSize),
            hasMore: matches.length > playerHistoryPageSize,
          ),
          events: PlayerHistoryPage(
            entries: events.take(playerHistoryPageSize),
            hasMore: events.length > playerHistoryPageSize,
          ),
          partners: partnerList,
          hasPendingSync: syncStates.isNotEmpty,
          hasConflict: syncStates.any(
            (row) => row.read<String>('status') == 'conflicted',
          ),
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error) {
      if (error is Error) rethrow;
      return const RepositoryFailure(
        UnknownRepositoryFailure(
          message: 'Cached player history could not be loaded safely.',
        ),
      );
    }
  }

  TournamentFormat? _format(String? v) => switch (v) {
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
  String _label(List<_Name>? values) => values == null || values.isEmpty
      ? 'Team'
      : (values..sort((a, b) => a.name.compareTo(b.name)))
            .map((v) => v.name)
            .join(' / ');
}

final class _Name {
  const _Name(this.id, this.name);
  final String id;
  final String name;
}

final class _Partner {
  _Partner(this.name);
  final String name;
  int matches = 0;
  int wins = 0;
}
