import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/infrastructure/court/court_queue_codec.dart';

String id(int value) =>
    '16200000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

Map<String, Object?> matchRow({required String status}) => {
  'id': id(4),
  'division_id': id(2),
  'status': status,
  'side_one_team_id': id(5),
  'side_two_team_id': id(6),
  'side_one_score': null,
  'side_two_score': null,
  'winner_team_id': null,
  'round_number': 1,
  'sequence_number': 1,
  'created_at': '2026-09-06T00:00:00Z',
  'updated_at': '2026-09-06T00:00:00Z',
  'version': 1,
  'deleted_at': null,
  'tournament_format': 'singleElimination',
  'division_name': 'Open',
  'side_one_label': 'VPC Sample A',
  'side_two_label': 'VPC Sample B',
};

void main() {
  test('remote snapshot preserves the durable current queue entry', () {
    final current = matchRow(status: 'inProgress');
    final snapshot = decodeCourtSnapshot({
      'event_id': id(1),
      'event_name': 'VPC M16 Sample',
      'current': current,
      'current_entry': {
        'id': id(3),
        'event_id': id(1),
        'division_id': id(2),
        'match_id': id(4),
        'queue_position': 7,
        'created_at': '2026-09-06T00:00:00Z',
        'updated_at': '2026-09-06T00:00:00Z',
        'version': 1,
        'deleted_at': null,
        'match': current,
      },
      'queue': <Object?>[],
      'unqueued_ready': <Object?>[],
      'completed_history': <Object?>[],
      'has_ineligible_entries': true,
      'disposition': 'synchronized',
    });

    expect(snapshot.current?.match.id, MatchId(id(4)));
    expect(snapshot.currentEntry?.matchId, MatchId(id(4)));
    expect(snapshot.currentEntry?.queuePosition, 7);
    expect(snapshot.hasIneligibleEntries, isTrue);
  });

  test('invalid remote status is rejected explicitly', () {
    expect(
      () => decodeCourtSnapshot({
        'event_id': id(1),
        'event_name': 'VPC M16 Sample',
        'current': matchRow(status: 'invented'),
        'current_entry': null,
        'queue': <Object?>[],
        'unqueued_ready': <Object?>[],
        'completed_history': <Object?>[],
        'disposition': 'synchronized',
      }),
      throwsA(isA<DomainFailure>()),
    );
  });
}
