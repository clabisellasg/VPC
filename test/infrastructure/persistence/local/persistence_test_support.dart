import 'package:drift/drift.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';

const playerOneId = '00000000-0000-4000-8000-000000000001';
const playerTwoId = '00000000-0000-4000-8000-000000000002';
const eventOneId = '00000000-0000-4000-8000-000000000010';
const divisionOneId = '00000000-0000-4000-8000-000000000020';
const participantOneId = '00000000-0000-4000-8000-000000000030';
const participantTwoId = '00000000-0000-4000-8000-000000000031';
const teamOneId = '00000000-0000-4000-8000-000000000040';
const matchOneId = '00000000-0000-4000-8000-000000000050';

final createdAt = DateTime.utc(2026, 8, 26, 1, 2, 3, 456, 789);
final updatedAt = DateTime.utc(2026, 8, 26, 2, 3, 4, 567, 890);

PlayersCompanion playerCompanion({
  String id = playerOneId,
  String displayName = 'Ada Player',
  int version = 0,
  DateTime? deletedAt,
}) => PlayersCompanion.insert(
  id: id,
  displayName: displayName,
  createdAt: createdAt,
  updatedAt: updatedAt,
  version: version,
  deletedAt: Value(deletedAt),
);

EventsCompanion eventCompanion({
  String id = eventOneId,
  String status = 'upcoming',
  int version = 0,
  int? feeMinorUnits = 25000,
  String? feeCurrency = 'PHP',
  DateTime? deletedAt,
}) => EventsCompanion.insert(
  id: id,
  name: 'Community Day',
  scheduledAt: DateTime.utc(2026, 9, 1, 8),
  eventType: 'formal',
  status: status,
  entryFeeMinorUnits: Value(feeMinorUnits),
  entryFeeCurrency: Value(feeCurrency),
  courtLabel: 'Community Court',
  createdAt: createdAt,
  updatedAt: updatedAt,
  version: version,
  deletedAt: Value(deletedAt),
);

EventDivisionsCompanion divisionCompanion({
  String id = divisionOneId,
  String eventId = eventOneId,
}) => EventDivisionsCompanion.insert(
  id: id,
  eventId: eventId,
  name: 'Open',
  tournamentFormat: const Value('singleElimination'),
  createdAt: createdAt,
  updatedAt: updatedAt,
  version: 0,
);

TeamsCompanion teamCompanion({String id = teamOneId}) => TeamsCompanion.insert(
  id: id,
  divisionId: divisionOneId,
  formationMethod: 'manual',
  displayLabel: const Value('Team One'),
  createdAt: createdAt,
  updatedAt: updatedAt,
  version: 0,
);

TeamMembersCompanion teamMemberCompanion({
  String teamId = teamOneId,
  String playerId = playerOneId,
}) => TeamMembersCompanion.insert(
  teamId: teamId,
  playerId: playerId,
  createdAt: createdAt,
  updatedAt: updatedAt,
  version: 0,
);

Future<void> insertEventGraph(AppDatabase database) async {
  await database.into(database.players).insert(playerCompanion());
  await database.into(database.events).insert(eventCompanion());
  await database.into(database.eventDivisions).insert(divisionCompanion());
}
