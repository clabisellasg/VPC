import 'package:drift/drift.dart';

import '../../../domain/common/domain_enums.dart';
import '../../../domain/common/domain_failure.dart';
import '../../../domain/common/entity_id.dart';
import '../../../domain/common/money.dart';
import '../../../domain/common/record_metadata.dart';
import '../../../domain/events/event.dart' as domain;
import '../../../domain/events/event_division.dart';
import '../../../domain/matches/match.dart' as domain;
import '../../../domain/players/permanent_player.dart';
import '../../../domain/players/player_skill.dart';
import 'app_database.dart';

RecordMetadata metadataFromValues({
  required DateTime createdAt,
  required DateTime updatedAt,
  required int version,
  required DateTime? deletedAt,
}) => RecordMetadata(
  createdAt: createdAt.toUtc(),
  updatedAt: updatedAt.toUtc(),
  recordVersion: version,
  deletedAt: deletedAt?.toUtc(),
);

PermanentPlayer playerFromRow(LocalPlayerRow row) => PermanentPlayer(
  id: PlayerId(row.id),
  displayName: row.displayName,
  accountId: null,
  skill: row.skillLevel == null ? null : PlayerSkill(row.skillLevel!),
  metadata: metadataFromValues(
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    version: row.version,
    deletedAt: row.deletedAt,
  ),
);

PlayersCompanion playerToCompanion(PermanentPlayer player) => PlayersCompanion(
  id: Value(player.id.value),
  displayName: Value(player.displayName),
  skillLevel: Value(player.skill?.value),
  createdAt: Value(player.metadata.createdAt),
  updatedAt: Value(player.metadata.updatedAt),
  version: Value(player.metadata.recordVersion),
  deletedAt: Value(player.metadata.deletedAt),
);

domain.Event eventFromRow(LocalEventRow row) {
  final fee = switch ((row.entryFeeMinorUnits, row.entryFeeCurrency)) {
    (final int units, final String currency) => Money(
      minorUnits: units,
      currencyCode: currency,
    ),
    (null, null) => null,
    _ => throw const ValidationFailure(
      field: 'entryFee',
      message: 'Stored entry-fee fields must both be present or absent.',
    ),
  };

  return domain.Event(
    id: EventId(row.id),
    name: row.name,
    scheduledAt: row.scheduledAt.toUtc(),
    type: enumValue(EventType.values, row.eventType, field: 'eventType'),
    status: enumValue(EventStatus.values, row.status, field: 'status'),
    entryFee: fee,
    courtLabel: row.courtLabel,
    metadata: metadataFromValues(
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      version: row.version,
      deletedAt: row.deletedAt,
    ),
  );
}

EventsCompanion eventToCompanion(domain.Event event) => EventsCompanion(
  id: Value(event.id.value),
  name: Value(event.name),
  scheduledAt: Value(event.scheduledAt),
  eventType: Value(event.type.name),
  status: Value(event.status.name),
  entryFeeMinorUnits: Value(event.entryFee?.minorUnits),
  entryFeeCurrency: Value(event.entryFee?.currencyCode),
  courtLabel: Value(event.courtLabel),
  createdAt: Value(event.metadata.createdAt),
  updatedAt: Value(event.metadata.updatedAt),
  version: Value(event.metadata.recordVersion),
  deletedAt: Value(event.metadata.deletedAt),
);

EventDivision eventDivisionFromRow(LocalEventDivisionRow row) => EventDivision(
  id: DivisionId(row.id),
  eventId: EventId(row.eventId),
  name: row.name,
  format: row.tournamentFormat == null
      ? null
      : enumValue(
          TournamentFormat.values,
          row.tournamentFormat!,
          field: 'tournamentFormat',
        ),
  metadata: metadataFromValues(
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    version: row.version,
    deletedAt: row.deletedAt,
  ),
);

EventDivisionsCompanion eventDivisionToCompanion(EventDivision division) =>
    EventDivisionsCompanion(
      id: Value(division.id.value),
      eventId: Value(division.eventId.value),
      name: Value(division.name),
      tournamentFormat: Value(division.format?.name),
      createdAt: Value(division.metadata.createdAt),
      updatedAt: Value(division.metadata.updatedAt),
      version: Value(division.metadata.recordVersion),
      deletedAt: Value(division.metadata.deletedAt),
    );

domain.Match matchFromRow(LocalMatchRow row) => domain.Match(
  id: MatchId(row.id),
  divisionId: DivisionId(row.divisionId),
  sideOneTeamId: row.sideOneTeamId == null ? null : TeamId(row.sideOneTeamId!),
  sideTwoTeamId: row.sideTwoTeamId == null ? null : TeamId(row.sideTwoTeamId!),
  status: enumValue(MatchStatus.values, row.status, field: 'status'),
  sideOneScore: row.sideOneScore,
  sideTwoScore: row.sideTwoScore,
  winnerTeamId: row.winnerTeamId == null ? null : TeamId(row.winnerTeamId!),
  roundNumber: row.roundNumber,
  sequenceNumber: row.sequenceNumber,
  metadata: metadataFromValues(
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    version: row.version,
    deletedAt: row.deletedAt,
  ),
);

MatchesCompanion matchToCompanion(domain.Match match) => MatchesCompanion(
  id: Value(match.id.value),
  divisionId: Value(match.divisionId.value),
  sideOneTeamId: Value(match.sideOneTeamId?.value),
  sideTwoTeamId: Value(match.sideTwoTeamId?.value),
  status: Value(match.status.name),
  sideOneScore: Value(match.sideOneScore),
  sideTwoScore: Value(match.sideTwoScore),
  winnerTeamId: Value(match.winnerTeamId?.value),
  roundNumber: Value(match.roundNumber),
  sequenceNumber: Value(match.sequenceNumber),
  createdAt: Value(match.metadata.createdAt),
  updatedAt: Value(match.metadata.updatedAt),
  version: Value(match.metadata.recordVersion),
  deletedAt: Value(match.metadata.deletedAt),
);

T enumValue<T extends Enum>(
  List<T> values,
  String storedValue, {
  required String field,
}) {
  for (final value in values) {
    if (value.name == storedValue) {
      return value;
    }
  }
  throw ValidationFailure(
    field: field,
    message: 'Stored value for $field is unsupported.',
  );
}
