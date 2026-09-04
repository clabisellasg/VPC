import 'package:drift/drift.dart';

import 'database_connection.dart';

part 'app_database.g.dart';

mixin RecordMetadataColumns on Table {
  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  IntColumn get version =>
      integer().customConstraint('NOT NULL CHECK (version >= 0)')();

  DateTimeColumn get deletedAt => dateTime().nullable()();
}

@DataClassName('LocalPlayerRow')
@TableIndex(name: 'players_display_name_idx', columns: {#displayName})
class Players extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get displayName =>
      text().customConstraint("NOT NULL CHECK (trim(display_name) <> '')")();

  IntColumn get skillLevel => integer()
      .customConstraint(
        'CHECK (skill_level IS NULL OR skill_level BETWEEN 1 AND 5)',
      )
      .nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalEventRow')
@TableIndex(
  name: 'events_status_scheduled_at_idx',
  columns: {#status, #scheduledAt},
)
class Events extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get name =>
      text().customConstraint("NOT NULL CHECK (trim(name) <> '')")();

  DateTimeColumn get scheduledAt => dateTime()();

  TextColumn get eventType => text().customConstraint(
    "NOT NULL CHECK (event_type IN ('casual', 'formal'))",
  )();

  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN "
    "('upcoming', 'registration', 'inProgress', 'completed', 'archived'))",
  )();

  IntColumn get entryFeeMinorUnits => integer().nullable()();

  TextColumn get entryFeeCurrency => text().nullable()();

  TextColumn get courtLabel =>
      text().customConstraint("NOT NULL CHECK (trim(court_label) <> '')")();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK ((entry_fee_minor_units IS NULL AND entry_fee_currency IS NULL) '
        'OR (entry_fee_minor_units >= 0 '
        "AND entry_fee_currency GLOB '[A-Z][A-Z][A-Z]'))",
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalEventDivisionRow')
@TableIndex(name: 'event_divisions_event_id_idx', columns: {#eventId})
@TableIndex.sql(
  'CREATE UNIQUE INDEX event_divisions_active_name_idx '
  'ON event_divisions (event_id, lower(name)) WHERE deleted_at IS NULL',
)
class EventDivisions extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();

  TextColumn get name =>
      text().customConstraint("NOT NULL CHECK (trim(name) <> '')")();

  TextColumn get tournamentFormat => text()
      .customConstraint(
        "CHECK (tournament_format IS NULL OR tournament_format IN ('singleElimination', "
        "'doubleElimination', 'singleRoundRobin', 'doubleRoundRobin'))",
      )
      .nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalEventParticipantRow')
@TableIndex(name: 'event_participants_player_id_idx', columns: {#playerId})
@TableIndex.sql(
  'CREATE UNIQUE INDEX event_participants_active_player_idx '
  'ON event_participants (event_id, player_id) WHERE deleted_at IS NULL',
)
class EventParticipants extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();

  TextColumn get playerId =>
      text().references(Players, #id, onDelete: KeyAction.restrict)();

  TextColumn get checkInStatus => text().customConstraint(
    "NOT NULL CHECK (check_in_status IN ('notPresent', 'checkedIn'))",
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalDivisionParticipantRow')
@TableIndex(
  name: 'division_participants_event_participant_idx',
  columns: {#eventParticipantId},
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX division_participants_active_entry_idx '
  'ON division_participants (division_id, event_participant_id) '
  'WHERE deleted_at IS NULL',
)
class DivisionParticipants extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();

  TextColumn get eventParticipantId =>
      text().references(EventParticipants, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalParticipantPaymentRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX participant_payments_active_event_scope_idx '
  'ON participant_payments (event_participant_id) '
  'WHERE division_id IS NULL AND deleted_at IS NULL',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX participant_payments_active_division_scope_idx '
  'ON participant_payments (event_participant_id, division_id) '
  'WHERE division_id IS NOT NULL AND deleted_at IS NULL',
)
class ParticipantPayments extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get eventParticipantId =>
      text().references(EventParticipants, #id, onDelete: KeyAction.restrict)();

  TextColumn get divisionId => text()
      .references(EventDivisions, #id, onDelete: KeyAction.restrict)
      .nullable()();

  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('unpaid', 'paid'))",
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalTeamRow')
@TableIndex(name: 'teams_division_id_idx', columns: {#divisionId})
class Teams extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();

  TextColumn get formationMethod => text().customConstraint(
    "NOT NULL CHECK (formation_method IN ('manual', 'random', 'balanced'))",
  )();

  TextColumn get displayLabel => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (display_label IS NULL OR trim(display_label) <> '')",
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalTeamMemberRow')
@TableIndex(name: 'team_members_player_id_idx', columns: {#playerId})
class TeamMembers extends Table with RecordMetadataColumns {
  TextColumn get teamId =>
      text().references(Teams, #id, onDelete: KeyAction.restrict)();

  TextColumn get playerId =>
      text().references(Players, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column<Object>> get primaryKey => {teamId, playerId};

  @override
  List<String> get customConstraints => [
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalMatchRow')
@TableIndex(
  name: 'matches_division_status_idx',
  columns: {#divisionId, #status, #sequenceNumber},
)
class Matches extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();

  @ReferenceName('matchesAsSideOne')
  TextColumn get sideOneTeamId =>
      text().references(Teams, #id, onDelete: KeyAction.restrict).nullable()();

  @ReferenceName('matchesAsSideTwo')
  TextColumn get sideTwoTeamId =>
      text().references(Teams, #id, onDelete: KeyAction.restrict).nullable()();

  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('scheduled', 'queued', 'inProgress', 'completed'))",
  )();

  IntColumn get sideOneScore => integer().nullable()();

  IntColumn get sideTwoScore => integer().nullable()();

  @ReferenceName('matchesAsWinner')
  TextColumn get winnerTeamId =>
      text().references(Teams, #id, onDelete: KeyAction.restrict).nullable()();

  IntColumn get roundNumber => integer().nullable()();

  IntColumn get sequenceNumber => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (side_one_team_id IS NULL OR side_two_team_id IS NULL '
        'OR side_one_team_id <> side_two_team_id)',
    'CHECK (side_one_score IS NULL OR side_one_score >= 0)',
    'CHECK (side_two_score IS NULL OR side_two_score >= 0)',
    'CHECK (round_number IS NULL OR round_number > 0)',
    'CHECK (sequence_number IS NULL OR sequence_number > 0)',
    "CHECK ((status = 'completed' AND side_one_team_id IS NOT NULL "
        'AND side_two_team_id IS NOT NULL AND side_one_score IS NOT NULL '
        'AND side_two_score IS NOT NULL AND winner_team_id IS NOT NULL '
        'AND winner_team_id IN (side_one_team_id, side_two_team_id)) '
        "OR (status <> 'completed' AND winner_team_id IS NULL))",
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalMatchDependencyRow')
@TableIndex(
  name: 'match_dependencies_destination_idx',
  columns: {#destinationMatchId},
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX match_dependencies_active_destination_slot_idx '
  'ON match_dependencies (destination_match_id, destination_slot) '
  'WHERE deleted_at IS NULL',
)
class MatchDependencies extends Table with RecordMetadataColumns {
  @ReferenceName('dependenciesAsSource')
  TextColumn get sourceMatchId =>
      text().references(Matches, #id, onDelete: KeyAction.restrict)();

  TextColumn get sourceOutcome => text().customConstraint(
    "NOT NULL CHECK (source_outcome IN ('winner', 'loser'))",
  )();

  @ReferenceName('dependenciesAsDestination')
  TextColumn get destinationMatchId =>
      text().references(Matches, #id, onDelete: KeyAction.restrict)();

  TextColumn get destinationSlot => text().customConstraint(
    "NOT NULL CHECK (destination_slot IN ('sideOne', 'sideTwo'))",
  )();

  @override
  Set<Column<Object>> get primaryKey => {
    sourceMatchId,
    sourceOutcome,
    destinationMatchId,
    destinationSlot,
  };

  @override
  List<String> get customConstraints => [
    'CHECK (source_match_id <> destination_match_id)',
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalCourtQueueEntryRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX court_queue_entries_active_position_idx '
  'ON court_queue_entries (event_id, queue_position) WHERE deleted_at IS NULL',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX court_queue_entries_active_match_idx '
  'ON court_queue_entries (match_id) WHERE deleted_at IS NULL',
)
class CourtQueueEntries extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();

  TextColumn get divisionId => text()
      .references(EventDivisions, #id, onDelete: KeyAction.restrict)
      .nullable()();

  TextColumn get matchId =>
      text().references(Matches, #id, onDelete: KeyAction.restrict)();

  IntColumn get queuePosition =>
      integer().customConstraint('NOT NULL CHECK (queue_position >= 0)')();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalDivisionPlacementRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX division_placements_active_position_idx '
  'ON division_placements (division_id, position) WHERE deleted_at IS NULL',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX division_placements_active_team_idx '
  'ON division_placements (division_id, team_id) WHERE deleted_at IS NULL',
)
class DivisionPlacements extends Table with RecordMetadataColumns {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();

  TextColumn get teamId =>
      text().references(Teams, #id, onDelete: KeyAction.restrict)();

  IntColumn get position =>
      integer().customConstraint('NOT NULL CHECK (position > 0)')();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (updated_at >= created_at)',
    'CHECK (deleted_at IS NULL OR deleted_at >= updated_at)',
  ];
}

@DataClassName('LocalSyncOutboxRow')
@TableIndex(
  name: 'sync_outbox_eligibility_idx',
  columns: {#status, #nextEligibleAt, #createdAt, #id},
)
@TableIndex(name: 'sync_outbox_entity_idx', columns: {#entityType, #entityId})
class SyncOutboxOperations extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get entityType =>
      text().customConstraint("NOT NULL CHECK (entity_type = 'player')")();

  TextColumn get entityId =>
      text().references(Players, #id, onDelete: KeyAction.restrict)();

  TextColumn get operationKind => text().customConstraint(
    "NOT NULL CHECK (operation_kind IN ('upsert', 'tombstone'))",
  )();

  IntColumn get baseVersion => integer().nullable()();

  TextColumn get payloadJson => text().customConstraint(
    "NOT NULL CHECK (json_valid(payload_json) AND json_type(payload_json) = 'object')",
  )();

  DateTimeColumn get createdAt => dateTime()();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get nextEligibleAt => dateTime()();

  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('pending', 'inFlight', 'conflicted', 'failed'))",
  )();

  DateTimeColumn get claimedAt => dateTime().nullable()();

  TextColumn get failureCode => text().nullable()();

  TextColumn get failureMessage => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (base_version IS NULL OR base_version >= 0)',
    'CHECK (attempt_count >= 0)',
    "CHECK ((status = 'inFlight' AND claimed_at IS NOT NULL) "
        "OR (status <> 'inFlight' AND claimed_at IS NULL))",
    'CHECK (failure_message IS NULL OR length(failure_message) <= 240)',
  ];
}

@DataClassName('LocalSyncCheckpointRow')
class SyncPullCheckpoints extends Table {
  TextColumn get entityType =>
      text().customConstraint("NOT NULL CHECK (entity_type = 'player')")();

  DateTimeColumn get cursorUpdatedAt => dateTime()();

  TextColumn get cursorEntityId =>
      text().references(Players, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {entityType};
}

@DataClassName('LocalSyncConflictRow')
@TableIndex(
  name: 'sync_conflicts_unresolved_idx',
  columns: {#status, #detectedAt},
)
@TableIndex(
  name: 'sync_conflicts_entity_idx',
  columns: {#entityType, #entityId},
)
class SyncConflicts extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get operationId => text()
      .references(SyncOutboxOperations, #id, onDelete: KeyAction.restrict)
      .unique()();

  TextColumn get entityType =>
      text().customConstraint("NOT NULL CHECK (entity_type = 'player')")();

  TextColumn get entityId =>
      text().references(Players, #id, onDelete: KeyAction.restrict)();

  IntColumn get expectedVersion => integer().nullable()();

  TextColumn get localPayloadJson => text().customConstraint(
    "NOT NULL CHECK (json_valid(local_payload_json) "
    "AND json_type(local_payload_json) = 'object')",
  )();

  TextColumn get remotePayloadJson => text().nullable()();

  IntColumn get remoteVersion => integer().nullable()();

  DateTimeColumn get detectedAt => dateTime()();

  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('unresolved', 'resolved'))",
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (expected_version IS NULL OR expected_version >= 0)',
    'CHECK (remote_version IS NULL OR remote_version >= 0)',
    'CHECK (remote_payload_json IS NULL OR '
        "(json_valid(remote_payload_json) AND json_type(remote_payload_json) = 'object'))",
  ];
}

@DataClassName('LocalEventSetupOutboxRow')
@TableIndex(
  name: 'event_setup_outbox_eligibility_idx',
  columns: {#status, #createdAt, #id},
)
class EventSetupOutboxOperations extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get payloadJson => text().customConstraint(
    "NOT NULL CHECK (json_valid(payload_json) AND json_type(payload_json) = 'object')",
  )();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('pending', 'blocked', 'conflicted', 'failed'))",
  )();
  TextColumn get failureMessage => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (base_version IS NULL OR base_version >= 0)',
    'CHECK (failure_message IS NULL OR length(failure_message) <= 240)',
  ];
}

@DataClassName('LocalEventSetupCheckpointRow')
class EventSetupPullCheckpoints extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1))();
  DateTimeColumn get cursorUpdatedAt => dateTime()();
  TextColumn get cursorEventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {singleton};

  @override
  List<String> get customConstraints => ['CHECK (singleton = 1)'];
}

@DataClassName('LocalEventSetupConflictRow')
@TableIndex(name: 'event_setup_conflicts_event_idx', columns: {#eventId})
class EventSetupConflicts extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get operationId => text()
      .references(EventSetupOutboxOperations, #id, onDelete: KeyAction.restrict)
      .unique()();
  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get localPayloadJson => text().customConstraint(
    "NOT NULL CHECK (json_valid(local_payload_json) AND json_type(local_payload_json) = 'object')",
  )();
  TextColumn get remotePayloadJson => text().nullable()();
  DateTimeColumn get detectedAt => dateTime()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('unresolved', 'resolved'))",
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalParticipationOutboxRow')
@TableIndex(
  name: 'participation_outbox_eligibility_idx',
  columns: {#status, #createdAt, #id},
)
class ParticipationOutboxOperations extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get eventParticipantId =>
      text().references(EventParticipants, #id, onDelete: KeyAction.restrict)();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get payloadJson => text().customConstraint(
    "NOT NULL CHECK (json_valid(payload_json) AND json_type(payload_json) = 'object')",
  )();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('pending', 'blocked', 'conflicted', 'failed'))",
  )();
  TextColumn get failureMessage => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (base_version IS NULL OR base_version >= 0)',
    'CHECK (failure_message IS NULL OR length(failure_message) <= 240)',
  ];
}

@DataClassName('LocalParticipationCheckpointRow')
class ParticipationPullCheckpoints extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1))();
  DateTimeColumn get cursorUpdatedAt => dateTime()();
  TextColumn get cursorParticipantId =>
      text().references(EventParticipants, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {singleton};

  @override
  List<String> get customConstraints => ['CHECK (singleton = 1)'];
}

@DataClassName('LocalParticipationConflictRow')
@TableIndex(
  name: 'participation_conflicts_participant_idx',
  columns: {#eventParticipantId},
)
class ParticipationConflicts extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get operationId => text()
      .references(
        ParticipationOutboxOperations,
        #id,
        onDelete: KeyAction.restrict,
      )
      .unique()();
  TextColumn get eventParticipantId =>
      text().references(EventParticipants, #id, onDelete: KeyAction.restrict)();
  TextColumn get localPayloadJson => text().customConstraint(
    "NOT NULL CHECK (json_valid(local_payload_json) AND json_type(local_payload_json) = 'object')",
  )();
  TextColumn get remotePayloadJson => text().nullable()();
  DateTimeColumn get detectedAt => dateTime()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('unresolved', 'resolved'))",
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalTeamFormationOutboxRow')
@TableIndex(
  name: 'team_formation_outbox_eligibility_idx',
  columns: {#status, #createdAt, #id},
)
class TeamFormationOutboxOperations extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();
  TextColumn get payloadJson => text().customConstraint(
    "NOT NULL CHECK (json_valid(payload_json) AND json_type(payload_json) = 'object')",
  )();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('pending', 'blocked', 'conflicted', 'failed'))",
  )();
  TextColumn get failureMessage => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalTeamFormationCheckpointRow')
class TeamFormationPullCheckpoints extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1))();
  DateTimeColumn get cursorUpdatedAt => dateTime()();
  TextColumn get cursorDivisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {singleton};
  @override
  List<String> get customConstraints => ['CHECK (singleton = 1)'];
}

@DataClassName('LocalTeamFormationConflictRow')
class TeamFormationConflicts extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get operationId => text()
      .references(
        TeamFormationOutboxOperations,
        #id,
        onDelete: KeyAction.restrict,
      )
      .unique()();
  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();
  TextColumn get localPayloadJson => text()();
  TextColumn get remotePayloadJson => text().nullable()();
  DateTimeColumn get detectedAt => dateTime()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('unresolved', 'resolved'))",
  )();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SingleEliminationSnapshots extends Table {
  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();
  TextColumn get bracketJson =>
      text().customConstraint('NOT NULL CHECK(json_valid(bracket_json))')();
  @override
  Set<Column<Object>> get primaryKey => {divisionId};
}

class SingleEliminationOutbox extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();
  TextColumn get payloadJson =>
      text().customConstraint('NOT NULL CHECK(json_valid(payload_json))')();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK(status IN ('pending','blocked','failed','conflicted','accepted'))",
  )();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get failure => text().nullable()();
  TextColumn get remoteJson => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SingleEliminationCheckpoints extends Table {
  TextColumn get scope => text()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get bracketId => text().withLength(min: 36, max: 36)();
  @override
  Set<Column<Object>> get primaryKey => {scope};
}

class RoundRobinSnapshots extends Table {
  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();
  TextColumn get tournamentJson =>
      text().customConstraint('NOT NULL CHECK(json_valid(tournament_json))')();
  @override
  Set<Column<Object>> get primaryKey => {divisionId};
}

class RoundRobinOutbox extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get divisionId =>
      text().references(EventDivisions, #id, onDelete: KeyAction.restrict)();
  TextColumn get payloadJson =>
      text().customConstraint('NOT NULL CHECK(json_valid(payload_json))')();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK(status IN ('pending','blocked','failed','conflicted','accepted'))",
  )();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get failure => text().nullable()();
  TextColumn get remoteJson => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RoundRobinCheckpoints extends Table {
  TextColumn get scope => text()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get tournamentId => text().withLength(min: 36, max: 36)();
  @override
  Set<Column<Object>> get primaryKey => {scope};
}

class MatchResultRevisions extends Table {
  TextColumn get operationId => text().withLength(min: 36, max: 36)();
  TextColumn get matchId =>
      text().references(Matches, #id, onDelete: KeyAction.restrict)();
  TextColumn get previousResult =>
      text().customConstraint('NOT NULL CHECK(json_valid(previous_result))')();
  TextColumn get reason =>
      text().customConstraint("NOT NULL CHECK(trim(reason)<>'')")();
  DateTimeColumn get recordedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

@DriftDatabase(
  tables: [
    Players,
    Events,
    EventDivisions,
    EventParticipants,
    DivisionParticipants,
    ParticipantPayments,
    Teams,
    TeamMembers,
    Matches,
    MatchDependencies,
    CourtQueueEntries,
    DivisionPlacements,
    SyncOutboxOperations,
    SyncPullCheckpoints,
    SyncConflicts,
    EventSetupOutboxOperations,
    EventSetupPullCheckpoints,
    EventSetupConflicts,
    ParticipationOutboxOperations,
    ParticipationPullCheckpoints,
    ParticipationConflicts,
    TeamFormationOutboxOperations,
    TeamFormationPullCheckpoints,
    TeamFormationConflicts,
    SingleEliminationSnapshots,
    SingleEliminationOutbox,
    SingleEliminationCheckpoints,
    RoundRobinSnapshots,
    RoundRobinOutbox,
    RoundRobinCheckpoints,
    MatchResultRevisions,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.forAndroid() : super(openAndroidDatabaseConnection());

  AppDatabase.inMemory() : super(openInMemoryDatabaseConnection());

  /// Only authoritative, validated match imports may have missed transitions or
  /// contain an already audited correction. Table checks and FKs remain active.
  Future<T> importBracketHistory<T>(Future<T> Function() action) =>
      transaction(() async {
        await customStatement('DROP TRIGGER matches_status_transition_guard');
        await customStatement('DROP TRIGGER matches_completed_result_lock');
        try {
          return await action();
        } finally {
          await customStatement(
            _scopeAndTransitionTriggers.firstWhere(
              (s) =>
                  s.contains('CREATE TRIGGER matches_status_transition_guard'),
            ),
          );
          await customStatement(
            _m13IntegrityTriggers.firstWhere(
              (s) => s.contains('CREATE TRIGGER matches_completed_result_lock'),
            ),
          );
        }
      });

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      for (final statement in _scopeAndTransitionTriggers) {
        await customStatement(statement);
      }
      for (final statement in _m13IntegrityTriggers) {
        await customStatement(statement);
      }
    },
    onUpgrade: (migrator, from, to) async {
      if (from == 1 && to >= 2) {
        await migrator.createTable(syncOutboxOperations);
        await migrator.createTable(syncPullCheckpoints);
        await migrator.createTable(syncConflicts);
        await migrator.createIndex(syncOutboxEligibilityIdx);
        await migrator.createIndex(syncOutboxEntityIdx);
        await migrator.createIndex(syncConflictsUnresolvedIdx);
        await migrator.createIndex(syncConflictsEntityIdx);
        if (to == 2) {
          return;
        }
      }
      if (from <= 2 && to >= 3) {
        await migrator.alterTable(TableMigration(eventDivisions));
        await migrator.createTable(eventSetupOutboxOperations);
        await migrator.createTable(eventSetupPullCheckpoints);
        await migrator.createTable(eventSetupConflicts);
        await migrator.createIndex(eventSetupOutboxEligibilityIdx);
        await migrator.createIndex(eventSetupConflictsEventIdx);
        for (final statement in _m09IntegrityTriggers) {
          await customStatement(statement);
        }
        if (to == 3) {
          return;
        }
      }
      if (from <= 3 && to >= 4) {
        await migrator.createTable(participationOutboxOperations);
        await migrator.createTable(participationPullCheckpoints);
        await migrator.createTable(participationConflicts);
        await migrator.createIndex(participationOutboxEligibilityIdx);
        await migrator.createIndex(participationConflictsParticipantIdx);
        if (to == 4) return;
      }
      if (from <= 4 && to >= 5) {
        await customStatement(
          'ALTER TABLE players ADD COLUMN skill_level INTEGER '
          'CHECK (skill_level IS NULL OR skill_level BETWEEN 1 AND 5)',
        );
        await migrator.createTable(teamFormationOutboxOperations);
        await migrator.createTable(teamFormationPullCheckpoints);
        await migrator.createTable(teamFormationConflicts);
        await migrator.createIndex(teamFormationOutboxEligibilityIdx);
        for (final statement in _m11IntegrityTriggers) {
          await customStatement(statement);
        }
        if (to == 5) return;
      }
      if (from <= 5 && to >= 6) {
        await customStatement(
          'DROP TRIGGER IF EXISTS event_divisions_setup_lock_guard',
        );
        for (final statement in _m12IntegrityTriggers) {
          await customStatement(statement);
        }
        if (to == 6) return;
      }
      if (from <= 6 && to >= 7) {
        await migrator.createTable(singleEliminationSnapshots);
        await migrator.createTable(singleEliminationOutbox);
        await migrator.createTable(singleEliminationCheckpoints);
        await migrator.createTable(matchResultRevisions);
        for (final statement in _m13IntegrityTriggers) {
          await customStatement(statement);
        }
        if (to == 7) return;
      }
      if (from <= 7 && to == 8) {
        await migrator.createTable(roundRobinSnapshots);
        await migrator.createTable(roundRobinOutbox);
        await migrator.createTable(roundRobinCheckpoints);
        return;
      }
      throw StateError(
        'No local schema upgrade path exists from $from to $to.',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> insertTeamWithMembers(
    TeamsCompanion team,
    Iterable<TeamMembersCompanion> members,
  ) => transaction(() async {
    await into(teams).insert(team);
    for (final member in members) {
      await into(teamMembers).insert(member);
    }
  });
}

final _scopeAndTransitionTriggers = <String>[
  '''
CREATE TRIGGER events_status_transition_guard
BEFORE UPDATE OF status ON events
WHEN NEW.status <> OLD.status AND NOT (
  (OLD.status = 'upcoming' AND NEW.status = 'registration') OR
  (OLD.status = 'registration' AND NEW.status = 'inProgress') OR
  (OLD.status = 'inProgress' AND NEW.status = 'completed') OR
  (OLD.status = 'completed' AND NEW.status = 'archived')
)
BEGIN
  SELECT RAISE(ABORT, 'invalid event status transition');
END
''',
  '''
CREATE TRIGGER matches_status_transition_guard
BEFORE UPDATE OF status ON matches
WHEN NEW.status <> OLD.status AND NOT (
  (OLD.status = 'scheduled' AND NEW.status = 'queued') OR
  (OLD.status = 'queued' AND NEW.status = 'inProgress') OR
  (OLD.status = 'inProgress' AND NEW.status = 'completed')
)
BEGIN
  SELECT RAISE(ABORT, 'invalid match status transition');
END
''',
  '''
CREATE TRIGGER division_participants_scope_guard
BEFORE INSERT ON division_participants
WHEN (SELECT event_id FROM event_divisions WHERE id = NEW.division_id) <>
     (SELECT event_id FROM event_participants WHERE id = NEW.event_participant_id)
BEGIN
  SELECT RAISE(ABORT, 'division participant event mismatch');
END
''',
  '''
CREATE TRIGGER division_participants_scope_update_guard
BEFORE UPDATE OF division_id, event_participant_id ON division_participants
WHEN (SELECT event_id FROM event_divisions WHERE id = NEW.division_id) <>
     (SELECT event_id FROM event_participants WHERE id = NEW.event_participant_id)
BEGIN
  SELECT RAISE(ABORT, 'division participant event mismatch');
END
''',
  '''
CREATE TRIGGER participant_payments_scope_guard
BEFORE INSERT ON participant_payments
WHEN NEW.division_id IS NOT NULL AND
     (SELECT event_id FROM event_divisions WHERE id = NEW.division_id) <>
     (SELECT event_id FROM event_participants WHERE id = NEW.event_participant_id)
BEGIN
  SELECT RAISE(ABORT, 'payment division event mismatch');
END
''',
  '''
CREATE TRIGGER participant_payments_scope_update_guard
BEFORE UPDATE OF division_id, event_participant_id ON participant_payments
WHEN NEW.division_id IS NOT NULL AND
     (SELECT event_id FROM event_divisions WHERE id = NEW.division_id) <>
     (SELECT event_id FROM event_participants WHERE id = NEW.event_participant_id)
BEGIN
  SELECT RAISE(ABORT, 'payment division event mismatch');
END
''',
  '''
CREATE TRIGGER matches_team_scope_guard
BEFORE INSERT ON matches
WHEN (NEW.side_one_team_id IS NOT NULL AND
      (SELECT division_id FROM teams WHERE id = NEW.side_one_team_id) <> NEW.division_id)
  OR (NEW.side_two_team_id IS NOT NULL AND
      (SELECT division_id FROM teams WHERE id = NEW.side_two_team_id) <> NEW.division_id)
  OR (NEW.winner_team_id IS NOT NULL AND
      (SELECT division_id FROM teams WHERE id = NEW.winner_team_id) <> NEW.division_id)
BEGIN
  SELECT RAISE(ABORT, 'match team division mismatch');
END
''',
  '''
CREATE TRIGGER matches_team_scope_update_guard
BEFORE UPDATE OF division_id, side_one_team_id, side_two_team_id, winner_team_id
ON matches
WHEN (NEW.side_one_team_id IS NOT NULL AND
      (SELECT division_id FROM teams WHERE id = NEW.side_one_team_id) <> NEW.division_id)
  OR (NEW.side_two_team_id IS NOT NULL AND
      (SELECT division_id FROM teams WHERE id = NEW.side_two_team_id) <> NEW.division_id)
  OR (NEW.winner_team_id IS NOT NULL AND
      (SELECT division_id FROM teams WHERE id = NEW.winner_team_id) <> NEW.division_id)
BEGIN
  SELECT RAISE(ABORT, 'match team division mismatch');
END
''',
  '''
CREATE TRIGGER match_dependencies_scope_guard
BEFORE INSERT ON match_dependencies
WHEN (SELECT division_id FROM matches WHERE id = NEW.source_match_id) <>
     (SELECT division_id FROM matches WHERE id = NEW.destination_match_id)
BEGIN
  SELECT RAISE(ABORT, 'match dependency division mismatch');
END
''',
  '''
CREATE TRIGGER match_dependencies_scope_update_guard
BEFORE UPDATE OF source_match_id, destination_match_id ON match_dependencies
WHEN (SELECT division_id FROM matches WHERE id = NEW.source_match_id) <>
     (SELECT division_id FROM matches WHERE id = NEW.destination_match_id)
BEGIN
  SELECT RAISE(ABORT, 'match dependency division mismatch');
END
''',
  '''
CREATE TRIGGER court_queue_entries_scope_guard
BEFORE INSERT ON court_queue_entries
WHEN (SELECT event_id FROM event_divisions
      WHERE id = (SELECT division_id FROM matches WHERE id = NEW.match_id)) <> NEW.event_id
  OR (NEW.division_id IS NOT NULL AND
      NEW.division_id <> (SELECT division_id FROM matches WHERE id = NEW.match_id))
BEGIN
  SELECT RAISE(ABORT, 'court queue scope mismatch');
END
''',
  '''
CREATE TRIGGER court_queue_entries_scope_update_guard
BEFORE UPDATE OF event_id, division_id, match_id ON court_queue_entries
WHEN (SELECT event_id FROM event_divisions
      WHERE id = (SELECT division_id FROM matches WHERE id = NEW.match_id)) <> NEW.event_id
  OR (NEW.division_id IS NOT NULL AND
      NEW.division_id <> (SELECT division_id FROM matches WHERE id = NEW.match_id))
BEGIN
  SELECT RAISE(ABORT, 'court queue scope mismatch');
END
''',
  '''
CREATE TRIGGER division_placements_scope_guard
BEFORE INSERT ON division_placements
WHEN (SELECT division_id FROM teams WHERE id = NEW.team_id) <> NEW.division_id
BEGIN
  SELECT RAISE(ABORT, 'placement team division mismatch');
END
''',
  '''
CREATE TRIGGER division_placements_scope_update_guard
BEFORE UPDATE OF division_id, team_id ON division_placements
WHEN (SELECT division_id FROM teams WHERE id = NEW.team_id) <> NEW.division_id
BEGIN
  SELECT RAISE(ABORT, 'placement team division mismatch');
END
''',
  ..._m09IntegrityTriggers,
  ..._m11IntegrityTriggers,
  'DROP TRIGGER event_divisions_setup_lock_guard',
  ..._m12IntegrityTriggers,
];

final _m12IntegrityTriggers = <String>[
  '''
CREATE TRIGGER event_divisions_setup_lock_guard
BEFORE UPDATE OF name, tournament_format, deleted_at ON event_divisions
WHEN ((NEW.name IS NOT OLD.name OR NEW.deleted_at IS NOT OLD.deleted_at)
  AND (SELECT status FROM events WHERE id=OLD.event_id) <> 'upcoming'
  AND (SELECT deleted_at FROM events WHERE id=OLD.event_id) IS NULL)
 OR (NEW.tournament_format IS NOT OLD.tournament_format AND
   ((SELECT status FROM events WHERE id=OLD.event_id) <> 'registration'
    OR OLD.deleted_at IS NOT NULL
    OR EXISTS(SELECT 1 FROM matches WHERE division_id=OLD.id)))
BEGIN
  SELECT RAISE(ABORT, 'division setup or tournament format is locked');
END
''',
  for (final action in ['INSERT', 'UPDATE'])
    '''
CREATE TRIGGER matches_final_score_${action.toLowerCase()}_guard
BEFORE $action ON matches
WHEN NEW.status='completed' AND NOT (
  ((max(NEW.side_one_score,NEW.side_two_score)=11 AND min(NEW.side_one_score,NEW.side_two_score) BETWEEN 0 AND 9)
    OR (min(NEW.side_one_score,NEW.side_two_score)>=10 AND abs(NEW.side_one_score-NEW.side_two_score)=2))
  AND NEW.winner_team_id=CASE WHEN NEW.side_one_score>NEW.side_two_score THEN NEW.side_one_team_id ELSE NEW.side_two_team_id END)
BEGIN
  SELECT RAISE(ABORT, 'invalid final score or derived winner');
END
''',
  '''
CREATE TRIGGER matches_completed_result_lock
BEFORE UPDATE ON matches
WHEN OLD.status='completed' AND (NEW.side_one_score IS NOT OLD.side_one_score
 OR NEW.side_two_score IS NOT OLD.side_two_score OR NEW.winner_team_id IS NOT OLD.winner_team_id
 OR NEW.side_one_team_id IS NOT OLD.side_one_team_id OR NEW.side_two_team_id IS NOT OLD.side_two_team_id)
BEGIN
  SELECT RAISE(ABORT, 'completed result correction is not approved');
END
''',
];

const _m13IntegrityTriggers = <String>[
  'DROP TRIGGER IF EXISTS matches_completed_result_lock',
  r'''CREATE TRIGGER matches_completed_result_lock BEFORE UPDATE ON matches
WHEN OLD.status='completed' AND (NEW.side_one_score IS NOT OLD.side_one_score
 OR NEW.side_two_score IS NOT OLD.side_two_score OR NEW.winner_team_id IS NOT OLD.winner_team_id
 OR NEW.side_one_team_id IS NOT OLD.side_one_team_id OR NEW.side_two_team_id IS NOT OLD.side_two_team_id)
 AND (NEW.side_one_team_id IS NOT OLD.side_one_team_id OR NEW.side_two_team_id IS NOT OLD.side_two_team_id
 OR NOT EXISTS(SELECT 1 FROM match_result_revisions r WHERE r.match_id=OLD.id
   AND json_extract(r.previous_result,'$.version')=OLD.version
   AND json_extract(r.previous_result,'$.side_one_score')=OLD.side_one_score
   AND json_extract(r.previous_result,'$.side_two_score')=OLD.side_two_score))
BEGIN SELECT RAISE(ABORT,'audited result correction required'); END''',
  '''CREATE TRIGGER match_result_revisions_update_lock BEFORE UPDATE ON match_result_revisions
BEGIN SELECT RAISE(ABORT,'immutable result revision'); END''',
  '''CREATE TRIGGER match_result_revisions_delete_lock BEFORE DELETE ON match_result_revisions
BEGIN SELECT RAISE(ABORT,'immutable result revision'); END''',
];

const _m11IntegrityTriggers = <String>[
  '''
CREATE TRIGGER team_members_eligibility_guard
BEFORE INSERT ON team_members
WHEN NOT EXISTS (
  SELECT 1
  FROM teams t
  JOIN event_divisions d ON d.id = t.division_id AND d.deleted_at IS NULL
  JOIN events e ON e.id = d.event_id AND e.deleted_at IS NULL
  JOIN event_participants ep ON ep.event_id = e.id AND ep.player_id = NEW.player_id
    AND ep.deleted_at IS NULL AND ep.check_in_status = 'checkedIn'
  JOIN division_participants dp ON dp.event_participant_id = ep.id
    AND dp.division_id = d.id AND dp.deleted_at IS NULL
  WHERE t.id = NEW.team_id AND t.deleted_at IS NULL AND e.status = 'registration'
)
BEGIN
  SELECT RAISE(ABORT, 'team member is not eligible');
END
''',
  '''
CREATE TRIGGER team_members_unique_division_guard
BEFORE INSERT ON team_members
WHEN EXISTS (
  SELECT 1 FROM team_members tm
  JOIN teams existing_team ON existing_team.id = tm.team_id AND existing_team.deleted_at IS NULL
  JOIN teams new_team ON new_team.id = NEW.team_id
  WHERE tm.player_id = NEW.player_id AND tm.deleted_at IS NULL
    AND existing_team.division_id = new_team.division_id
)
BEGIN
  SELECT RAISE(ABORT, 'player already belongs to an active team in this division');
END
''',
];

const _m09IntegrityTriggers = <String>[
  '''
CREATE TRIGGER events_format_required_guard
BEFORE UPDATE OF status ON events
WHEN NEW.status = 'inProgress' AND OLD.status <> 'inProgress' AND EXISTS (
  SELECT 1 FROM event_divisions
  WHERE event_id = NEW.id AND deleted_at IS NULL AND tournament_format IS NULL
)
BEGIN
  SELECT RAISE(ABORT, 'tournament formats must be configured before event begins');
END
''',
  '''
CREATE TRIGGER event_divisions_setup_lock_guard
BEFORE UPDATE OF name, tournament_format, deleted_at ON event_divisions
WHEN (NEW.name IS NOT OLD.name OR
      NEW.tournament_format IS NOT OLD.tournament_format OR
      NEW.deleted_at IS NOT OLD.deleted_at) AND
     (SELECT status FROM events WHERE id = OLD.event_id) <> 'upcoming' AND
     (SELECT deleted_at FROM events WHERE id = OLD.event_id) IS NULL
BEGIN
  SELECT RAISE(ABORT, 'event division setup is locked');
END
''',
];
