import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/events/event.dart';
import '../../domain/events/event_division.dart';
import '../../domain/matches/match.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/tournament/double_elimination_bracket.dart';
import '../../domain/tournament/double_elimination_generator.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../accounts/account_models.dart';
import 'single_elimination_service.dart'
    show BracketAction, BracketClock, BracketDisposition, BracketIds;

final class DoubleEliminationContext {
  DoubleEliminationContext({
    required this.event,
    required this.division,
    required Iterable<TournamentTeam> teams,
    required Map<TeamId, String> teamLabels,
    this.bracket,
    this.disposition = BracketDisposition.synchronized,
    this.teamConflict = false,
  }) : teams = List.unmodifiable(teams),
       teamLabels = Map.unmodifiable(teamLabels);
  final Event event;
  final EventDivision division;
  final List<TournamentTeam> teams;
  final Map<TeamId, String> teamLabels;
  final DoubleEliminationBracket? bracket;
  final BracketDisposition disposition;
  final bool teamConflict;
}

final class DoubleEliminationCommand {
  DoubleEliminationCommand({
    required this.operationId,
    required this.eventId,
    required this.divisionId,
    required this.action,
    required this.expectedVersion,
    required this.expectedEventVersion,
    required this.expectedDivisionVersion,
    required this.createdAt,
    Iterable<TeamId> seedOrder = const [],
    Map<TeamId, int> teamVersions = const {},
    Map<PlannedMatchKey, MatchId> matchIds = const {},
    Map<int, DivisionPlacementId> placementIds = const {},
    this.matchKey,
    this.score,
    this.reason,
    this.proposed,
  }) : seedOrder = List.unmodifiable(seedOrder),
       teamVersions = Map.unmodifiable(teamVersions),
       matchIds = Map.unmodifiable(matchIds),
       placementIds = Map.unmodifiable(placementIds);
  final SyncOperationId operationId;
  final EventId eventId;
  final DivisionId divisionId;
  final BracketAction action;
  final int expectedVersion, expectedEventVersion, expectedDivisionVersion;
  final DateTime createdAt;
  final List<TeamId> seedOrder;
  final Map<TeamId, int> teamVersions;
  final Map<PlannedMatchKey, MatchId> matchIds;
  final Map<int, DivisionPlacementId> placementIds;
  final PlannedMatchKey? matchKey;
  final ValidatedScore? score;
  final String? reason;
  final DoubleEliminationBracket? proposed;

  DoubleEliminationCommand withProposed(DoubleEliminationBracket value) =>
      DoubleEliminationCommand(
        operationId: operationId,
        eventId: eventId,
        divisionId: divisionId,
        action: action,
        expectedVersion: expectedVersion,
        expectedEventVersion: expectedEventVersion,
        expectedDivisionVersion: expectedDivisionVersion,
        createdAt: createdAt,
        seedOrder: seedOrder,
        teamVersions: teamVersions,
        matchIds: matchIds,
        placementIds: placementIds,
        matchKey: matchKey,
        score: score,
        reason: reason,
        proposed: value,
      );

  DoubleEliminationCommand withReservedResetMatchId(MatchId value) =>
      DoubleEliminationCommand(
        operationId: operationId,
        eventId: eventId,
        divisionId: divisionId,
        action: action,
        expectedVersion: expectedVersion,
        expectedEventVersion: expectedEventVersion,
        expectedDivisionVersion: expectedDivisionVersion,
        createdAt: createdAt,
        seedOrder: seedOrder,
        teamVersions: teamVersions,
        matchIds: {...matchIds, DoubleEliminationGenerator.resetKey: value},
        placementIds: placementIds,
        matchKey: matchKey,
        score: score,
        reason: reason,
        proposed: proposed?.withReservedResetMatchId(value),
      );
}

abstract interface class DoubleEliminationRepository {
  Future<RepositoryResult<DoubleEliminationContext>> load(
    EventId eventId,
    DivisionId divisionId,
  );
  Future<RepositoryResult<DoubleEliminationContext>> apply(
    DoubleEliminationCommand command,
  );
}

final class DoubleEliminationService {
  const DoubleEliminationService({
    required this.repository,
    required this.ids,
    required this.clock,
  });
  final DoubleEliminationRepository repository;
  final BracketIds ids;
  final BracketClock clock;

  RepositoryResult<TournamentPlan> preview(
    DoubleEliminationContext context,
    AuthorizationState authorization, {
    List<TeamId>? seedOrder,
  }) {
    try {
      _organizer(authorization);
      _generationAllowed(context);
      return const DoubleEliminationGenerator().generate(
        TournamentGenerationRequest(
          eventId: context.event.id,
          division: context.division,
          teams: context.teams,
          organizerOrder: seedOrder,
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  Future<RepositoryResult<DoubleEliminationContext>> generate(
    DoubleEliminationContext context,
    AuthorizationState authorization, {
    required List<TeamId> seedOrder,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      return const RepositoryFailure(
        ValidationFailure(
          field: 'confirmation',
          message: 'Confirm the reviewed bracket before saving.',
        ),
      );
    }
    final generated = preview(context, authorization, seedOrder: seedOrder);
    if (generated case RepositoryFailure(:final failure)) {
      return RepositoryFailure(failure);
    }
    final plan = (generated as RepositorySuccess<TournamentPlan>).value;
    final command = DoubleEliminationCommand(
      operationId: ids.operationId(),
      eventId: context.event.id,
      divisionId: context.division.id,
      action: BracketAction.generate,
      expectedVersion: context.bracket?.metadata.recordVersion ?? -1,
      expectedEventVersion: context.event.metadata.recordVersion,
      expectedDivisionVersion: context.division.metadata.recordVersion,
      createdAt: clock.nowUtc(),
      seedOrder: seedOrder,
      teamVersions: {
        for (final team in context.teams)
          team.team.id: team.team.metadata.recordVersion,
      },
      matchIds: {for (final match in plan.matches) match.key: ids.matchId()},
    );
    return repository.apply(
      command.withProposed(applyDoubleEliminationCommand(context, command)),
    );
  }

  Future<RepositoryResult<DoubleEliminationContext>> change(
    DoubleEliminationContext context,
    AuthorizationState authorization, {
    required BracketAction action,
    required PlannedMatchKey key,
    ValidatedScore? score,
    String? reason,
  }) async {
    try {
      _organizer(authorization);
      final bracket = context.bracket;
      if (bracket == null || action == BracketAction.generate) {
        throw const ValidationFailure(
          field: 'match',
          message: 'An active Double Elimination match is required.',
        );
      }
      final command = DoubleEliminationCommand(
        operationId: ids.operationId(),
        eventId: context.event.id,
        divisionId: context.division.id,
        action: action,
        expectedVersion: bracket.metadata.recordVersion,
        expectedEventVersion: context.event.metadata.recordVersion,
        expectedDivisionVersion: context.division.metadata.recordVersion,
        createdAt: clock.nowUtc(),
        matchKey: key,
        score: score,
        reason: reason,
        matchIds: {
          DoubleEliminationGenerator.resetKey: bracket.reservedResetMatchId,
        },
        placementIds: {
          1: DivisionPlacementId(ids.matchId().value),
          2: DivisionPlacementId(ids.matchId().value),
        },
      );
      return await repository.apply(
        command.withProposed(applyDoubleEliminationCommand(context, command)),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }
}

void _organizer(AuthorizationState authorization) {
  if (authorization != AuthorizationState.organizer) {
    throw const UnauthorizedFailure(
      message: 'Organizer permission is required.',
    );
  }
}

void _generationAllowed(DoubleEliminationContext context) {
  if (context.event.status != EventStatus.registration ||
      context.division.format != TournamentFormat.doubleElimination ||
      context.event.metadata.isDeleted ||
      context.division.metadata.isDeleted ||
      context.division.eventId != context.event.id ||
      context.teamConflict ||
      context.disposition == BracketDisposition.conflicted ||
      (context.bracket != null && !context.bracket!.mayRegenerate)) {
    throw const TournamentGenerationFailure(
      code: 'generation_locked',
      message: 'Generation requires Registration, complete teams and no protected progress or conflict.',
    );
  }
}

DoubleEliminationBracket applyDoubleEliminationCommand(
  DoubleEliminationContext context,
  DoubleEliminationCommand command,
) {
  if (context.event.id != command.eventId ||
      context.division.id != command.divisionId ||
      context.event.metadata.recordVersion != command.expectedEventVersion ||
      context.division.metadata.recordVersion !=
          command.expectedDivisionVersion ||
      (context.bracket?.metadata.recordVersion ?? -1) !=
          command.expectedVersion) {
    throw const ConflictFailure(
      message: 'The event, division or bracket changed. Refresh and retry.',
    );
  }
  if (command.action == BracketAction.generate) {
    _generationAllowed(context);
    if (command.teamVersions.length != context.teams.length ||
        context.teams.any(
          (team) =>
              command.teamVersions[team.team.id] !=
              team.team.metadata.recordVersion,
        )) {
      throw const ConflictFailure(
        message: 'Teams changed after preview. Review them again.',
      );
    }
    final generated = const DoubleEliminationGenerator().generate(
      TournamentGenerationRequest(
        eventId: context.event.id,
        division: context.division,
        teams: context.teams,
        organizerOrder: command.seedOrder,
      ),
    );
    final plan = generated.when(
      success: (value) => value,
      failure: (f) => throw f,
    );
    if (command.matchIds.length != plan.matches.length ||
        command.matchIds.values.toSet().length != plan.matches.length ||
        plan.matches.any((match) => !command.matchIds.containsKey(match.key))) {
      throw const ValidationFailure(
        field: 'matchIds',
        message: 'Every real or conditional match needs one stable identity.',
      );
    }
    final meta = RecordMetadata(
      createdAt: command.createdAt,
      updatedAt: command.createdAt,
      recordVersion: 0,
    );
    return DoubleEliminationBracket(
      plan: plan,
      reservedResetMatchId:
          command.matchIds[DoubleEliminationGenerator.resetKey]!,
      metadata: RecordMetadata(
        createdAt: context.bracket?.metadata.createdAt ?? command.createdAt,
        updatedAt: command.createdAt,
        recordVersion: command.expectedVersion + 1,
      ),
      matches: {
        for (final planned in plan.matches)
          if (planned.key != DoubleEliminationGenerator.resetKey)
            planned.key: Match(
              id: command.matchIds[planned.key]!,
              divisionId: context.division.id,
              status: planned.status,
              metadata: meta,
              sideOneTeamId: planned.sideOne is DirectTeamSource
                  ? (planned.sideOne as DirectTeamSource).teamId
                  : null,
              sideTwoTeamId: planned.sideTwo is DirectTeamSource
                  ? (planned.sideTwo as DirectTeamSource).teamId
                  : null,
              roundNumber: planned.round,
              sequenceNumber: plan.matches.indexOf(planned) + 1,
            ),
      },
      revisions: context.bracket?.revisions ?? const [],
    );
  }
  final bracket = context.bracket, key = command.matchKey;
  if (bracket == null || key == null) {
    throw const ValidationFailure(
      field: 'match',
      message: 'An active Double Elimination match is required.',
    );
  }
  if (command.action == BracketAction.start) {
    return bracket.start(
      key,
      context.event.status,
      command.expectedVersion,
      command.createdAt,
    );
  }
  final current = bracket.matches[key];
  if (command.score == null ||
      current == null ||
      (command.action == BracketAction.correct) !=
          (current.status == MatchStatus.completed)) {
    throw const ValidationFailure(
      field: 'result',
      message: 'Choose the appropriate result or correction action.',
    );
  }
  return bracket.result(
    key: key,
    score: command.score!,
    eventStatus: context.event.status,
    expectedVersion: command.expectedVersion,
    now: command.createdAt,
    operationId: command.operationId,
    correctionReason: command.action == BracketAction.correct
        ? command.reason
        : null,
  );
}
