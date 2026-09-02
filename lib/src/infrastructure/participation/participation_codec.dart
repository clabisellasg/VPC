import 'dart:convert';

import '../../application/participation/participation_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/events/division_participant.dart';
import '../../domain/events/event_participant.dart';
import '../../domain/events/participant_payment.dart';

String encodeParticipation(ParticipationRecord record) =>
    jsonEncode(participationToJson(record));

Map<String, Object?> participationToJson(ParticipationRecord record) => {
  'participant': _participantToJson(record.participant),
  'divisions': record.divisions.map(_divisionToJson).toList(),
  'payment': _paymentToJson(record.payment),
  'player_display_name': record.playerDisplayName,
};

ParticipationRecord decodeParticipation(Object? value) {
  final object = value is String ? jsonDecode(value) : value;
  if (object is! Map) {
    throw const ValidationFailure(
      field: 'participation',
      message: 'Participation payload must be an object.',
    );
  }
  final map = Map<String, Object?>.from(object);
  final participant = map['participant'];
  final payment = map['payment'];
  final divisions = map['divisions'];
  final name = map['player_display_name'];
  if (participant is! Map ||
      payment is! Map ||
      divisions is! List ||
      name is! String) {
    throw const ValidationFailure(
      field: 'participation',
      message: 'Participation payload fields are invalid.',
    );
  }
  return ParticipationRecord(
    participant: _participantFromJson(Map<String, Object?>.from(participant)),
    payment: _paymentFromJson(Map<String, Object?>.from(payment)),
    playerDisplayName: name,
    divisions: divisions.map((value) {
      if (value is! Map) {
        throw const ValidationFailure(
          field: 'divisions',
          message: 'Division assignment must be an object.',
        );
      }
      return _divisionFromJson(Map<String, Object?>.from(value));
    }),
  );
}

Map<String, Object?> _participantToJson(EventParticipant value) => {
  'id': value.id.value,
  'event_id': value.eventId.value,
  'player_id': value.playerId.value,
  'check_in_status': value.checkInStatus.name,
  ..._metadataToJson(value.metadata),
};

Map<String, Object?> _divisionToJson(DivisionParticipant value) => {
  'id': value.id.value,
  'division_id': value.divisionId.value,
  'event_participant_id': value.eventParticipantId.value,
  ..._metadataToJson(value.metadata),
};

Map<String, Object?> _paymentToJson(ParticipantPayment value) => {
  'id': value.id.value,
  'event_participant_id': value.eventParticipantId.value,
  'division_id': value.divisionId?.value,
  'status': value.status.name,
  ..._metadataToJson(value.metadata),
};

EventParticipant _participantFromJson(Map<String, Object?> map) =>
    EventParticipant(
      id: EventParticipantId(_string(map, 'id')),
      eventId: EventId(_string(map, 'event_id')),
      playerId: PlayerId(_string(map, 'player_id')),
      checkInStatus: _enum(
        CheckInStatus.values,
        _string(map, 'check_in_status'),
        'check_in_status',
      ),
      metadata: _metadata(map),
    );

DivisionParticipant _divisionFromJson(Map<String, Object?> map) =>
    DivisionParticipant(
      id: DivisionParticipantId(_string(map, 'id')),
      divisionId: DivisionId(_string(map, 'division_id')),
      eventParticipantId: EventParticipantId(
        _string(map, 'event_participant_id'),
      ),
      metadata: _metadata(map),
    );

ParticipantPayment _paymentFromJson(Map<String, Object?> map) =>
    ParticipantPayment(
      id: ParticipantPaymentId(_string(map, 'id')),
      eventParticipantId: EventParticipantId(
        _string(map, 'event_participant_id'),
      ),
      divisionId: map['division_id'] == null
          ? null
          : DivisionId(_string(map, 'division_id')),
      status: _enum(PaymentStatus.values, _string(map, 'status'), 'status'),
      metadata: _metadata(map),
    );

Map<String, Object?> _metadataToJson(RecordMetadata value) => {
  'created_at': value.createdAt.toIso8601String(),
  'updated_at': value.updatedAt.toIso8601String(),
  'version': value.recordVersion,
  'deleted_at': value.deletedAt?.toIso8601String(),
};

RecordMetadata _metadata(Map<String, Object?> map) => RecordMetadata(
  createdAt: DateTime.parse(_string(map, 'created_at')).toUtc(),
  updatedAt: DateTime.parse(_string(map, 'updated_at')).toUtc(),
  recordVersion: _integer(map, 'version'),
  deletedAt: map['deleted_at'] == null
      ? null
      : DateTime.parse(_string(map, 'deleted_at')).toUtc(),
);

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String && value.isNotEmpty) return value;
  throw ValidationFailure(field: key, message: '$key is invalid.');
}

int _integer(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is int) return value;
  throw ValidationFailure(field: key, message: '$key is invalid.');
}

T _enum<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw ValidationFailure(field: field, message: '$field is unsupported.');
}
