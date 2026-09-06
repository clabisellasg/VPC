import 'dart:convert';

import '../../application/court/court_queue_service.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/court/court_queue_entry.dart';
import '../../domain/matches/match.dart';

Map<String, Object?> courtCommandJson(CourtQueueCommand command) => {
  'operation_id': command.operationId.value,
  'event_id': command.eventId.value,
  'action': command.action,
  'created_at': command.createdAt.toIso8601String(),
  'match_id': command.matchId?.value,
  'expected_match_version': command.expectedMatchVersion,
  'entry_ids': {
    for (final entry in command.entryIds.entries)
      entry.key.value: entry.value.value,
  },
};

CourtQueueCommand decodeCourtCommand(Object? value) {
  final map = _object(value);
  final ids = _object(map['entry_ids']);
  return CourtQueueCommand(
    operationId: SyncOperationId(_text(map, 'operation_id')),
    eventId: EventId(_text(map, 'event_id')),
    action: _text(map, 'action'),
    createdAt: _time(map, 'created_at'),
    matchId: map['match_id'] == null ? null : MatchId(_text(map, 'match_id')),
    expectedMatchVersion: _integer(map, 'expected_match_version'),
    entryIds: ids.map(
      (key, value) =>
          MapEntry(MatchId(key), CourtQueueEntryId(value as String)),
    ),
  );
}

CourtQueueSnapshot decodeCourtSnapshot(Object? value) {
  try {
    final map = _object(value);
    final eventId = EventId(_text(map, 'event_id'));
    CourtMatchView view(Object? value) {
      final row = _object(value);
      return CourtMatchView(
        eventId: eventId,
        match: _match(row),
        format: _enum(TournamentFormat.values, _text(row, 'tournament_format')),
        divisionName: _text(row, 'division_name'),
        sideOneLabel: _text(row, 'side_one_label'),
        sideTwoLabel: _text(row, 'side_two_label'),
        bracketSection: row['bracket_section'] as String?,
      );
    }

    QueuedCourtMatch queued(Object? value) {
      final row = _object(value), match = view(row['match']);
      return QueuedCourtMatch(
        entry: CourtQueueEntry(
          id: CourtQueueEntryId(_text(row, 'id')),
          eventId: eventId,
          divisionId: DivisionId(_text(row, 'division_id')),
          matchId: match.match.id,
          queuePosition: _integer(row, 'queue_position'),
          metadata: _metadata(row),
        ),
        match: match,
      );
    }

    return CourtQueueSnapshot(
      eventId: eventId,
      eventName: _text(map, 'event_name'),
      current: map['current'] == null ? null : view(map['current']),
      currentEntry: map['current_entry'] == null
          ? null
          : queued(map['current_entry']).entry,
      queue: _list(map, 'queue').map(queued),
      unqueuedReady: _list(map, 'unqueued_ready').map(view).toList(),
      completedHistory: _list(map, 'completed_history').map(view),
      hasIneligibleEntries: map['has_ineligible_entries'] == true,
      disposition: _enum(
        CourtQueueDisposition.values,
        (map['disposition'] as String?) ?? 'synchronized',
      ),
    );
  } on DomainFailure {
    rethrow;
  } on Object {
    throw const ValidationFailure(
      field: 'courtQueueData',
      message: 'Court queue data could not be validated safely.',
    );
  }
}

String encodeCourtCommand(CourtQueueCommand command) =>
    jsonEncode(courtCommandJson(command));

Match _match(Map<String, Object?> row) => Match(
  id: MatchId(_text(row, 'id')),
  divisionId: DivisionId(_text(row, 'division_id')),
  status: _enum(MatchStatus.values, _text(row, 'status')),
  metadata: _metadata(row),
  sideOneTeamId: row['side_one_team_id'] == null
      ? null
      : TeamId(_text(row, 'side_one_team_id')),
  sideTwoTeamId: row['side_two_team_id'] == null
      ? null
      : TeamId(_text(row, 'side_two_team_id')),
  sideOneScore: row['side_one_score'] as int?,
  sideTwoScore: row['side_two_score'] as int?,
  winnerTeamId: row['winner_team_id'] == null
      ? null
      : TeamId(_text(row, 'winner_team_id')),
  roundNumber: row['round_number'] as int?,
  sequenceNumber: row['sequence_number'] as int?,
);

RecordMetadata _metadata(Map<String, Object?> row) => RecordMetadata(
  createdAt: _time(row, 'created_at'),
  updatedAt: _time(row, 'updated_at'),
  recordVersion: _integer(row, 'version'),
  deletedAt: row['deleted_at'] == null ? null : _time(row, 'deleted_at'),
);

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException();
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List) throw const FormatException();
  return value;
}

String _text(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw const FormatException();
  return value;
}

int _integer(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw const FormatException();
  return value;
}

DateTime _time(Map<String, Object?> map, String key) {
  final raw = _text(map, key), parsed = DateTime.tryParse(raw);
  if (parsed == null || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(raw)) {
    throw const FormatException();
  }
  return parsed.toUtc();
}

T _enum<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw const FormatException();
}
