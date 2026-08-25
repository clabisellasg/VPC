import 'package:vpc/src/domain/common/record_metadata.dart';

const accountUuid = '00000000-0000-4000-8000-000000000001';
const playerOneUuid = '00000000-0000-4000-8000-000000000002';
const playerTwoUuid = '00000000-0000-4000-8000-000000000003';
const playerThreeUuid = '00000000-0000-4000-8000-000000000004';
const eventUuid = '00000000-0000-4000-8000-000000000005';
const divisionUuid = '00000000-0000-4000-8000-000000000006';
const eventParticipantUuid = '00000000-0000-4000-8000-000000000007';
const divisionParticipantUuid = '00000000-0000-4000-8000-000000000008';
const paymentUuid = '00000000-0000-4000-8000-000000000009';
const teamOneUuid = '00000000-0000-4000-8000-00000000000a';
const teamTwoUuid = '00000000-0000-4000-8000-00000000000b';
const matchOneUuid = '00000000-0000-4000-8000-00000000000c';
const matchTwoUuid = '00000000-0000-4000-8000-00000000000d';
const queueUuid = '00000000-0000-4000-8000-00000000000e';
const placementUuid = '00000000-0000-4000-8000-00000000000f';

RecordMetadata metadata({int version = 0, int minute = 0}) => RecordMetadata(
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1, 0, minute),
  recordVersion: version,
);
