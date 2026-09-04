import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/events/event.dart';
import '../../domain/events/event_division.dart';
import '../../domain/matches/match.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/tournament/round_robin_generator.dart';
import '../../domain/tournament/round_robin_tournament.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../accounts/account_models.dart';
import 'single_elimination_service.dart'
    show BracketClock, BracketDisposition, BracketIds;

enum RoundRobinAction { generate, start, result, correct }

final class RoundRobinContext {
  RoundRobinContext({
    required this.event,
    required this.division,
    required Iterable<TournamentTeam> teams,
    required Map<TeamId, String> teamLabels,
    this.tournament,
    this.disposition = BracketDisposition.synchronized,
    this.teamConflict = false,
  }) : teams = List.unmodifiable(teams),
       teamLabels = Map.unmodifiable(teamLabels);
  final Event event;
  final EventDivision division;
  final List<TournamentTeam> teams;
  final Map<TeamId, String> teamLabels;
  final RoundRobinTournament? tournament;
  final BracketDisposition disposition;
  final bool teamConflict;
}

final class RoundRobinCommand {
  RoundRobinCommand({
    required this.operationId,
    required this.eventId,
    required this.divisionId,
    required this.action,
    required this.expectedVersion,
    required this.expectedEventVersion,
    required this.expectedDivisionVersion,
    required this.createdAt,
    this.seedOrder = const [],
    this.teamVersions = const {},
    this.matchIds = const {},
    this.placementIds = const {},
    this.matchKey,
    this.score,
    this.reason,
  });
  final SyncOperationId operationId;
  final EventId eventId;
  final DivisionId divisionId;
  final RoundRobinAction action;
  final int expectedVersion, expectedEventVersion, expectedDivisionVersion;
  final DateTime createdAt;
  final List<TeamId> seedOrder;
  final Map<TeamId, int> teamVersions;
  final Map<PlannedMatchKey, MatchId> matchIds;
  final Map<int, DivisionPlacementId> placementIds;
  final PlannedMatchKey? matchKey;
  final ValidatedScore? score;
  final String? reason;
}

abstract interface class RoundRobinRepository {
  Future<RepositoryResult<RoundRobinContext>> load(
    EventId eventId,
    DivisionId divisionId,
  );
  Future<RepositoryResult<RoundRobinContext>> apply(RoundRobinCommand command);
}

final class RoundRobinService {
  const RoundRobinService({
    required this.repository,
    required this.ids,
    required this.clock,
  });
  final RoundRobinRepository repository;
  final BracketIds ids;
  final BracketClock clock;
  RepositoryResult<TournamentPlan> preview(
    RoundRobinContext context,
    AuthorizationState auth, {
    List<TeamId>? seedOrder,
  }) {
    try {
      _organizer(auth);
      _generationAllowed(context);
      return const RoundRobinGenerator().generate(
        TournamentGenerationRequest(
          eventId: context.event.id,
          division: context.division,
          teams: context.teams,
          organizerOrder: seedOrder,
        ),
      );
    } on DomainFailure catch (f) {
      return RepositoryFailure(f);
    }
  }

  Future<RepositoryResult<RoundRobinContext>> generate(
    RoundRobinContext context,
    AuthorizationState auth, {
    required List<TeamId> seedOrder,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      return const RepositoryFailure(
        ValidationFailure(
          field: 'confirmation',
          message: 'Confirm the reviewed schedule before saving.',
        ),
      );
    }
    final generated = preview(context, auth, seedOrder: seedOrder);
    if (generated case RepositoryFailure(:final failure)) {
      return RepositoryFailure(failure);
    }
    final plan = (generated as RepositorySuccess<TournamentPlan>).value;
    return repository.apply(
      RoundRobinCommand(
        operationId: ids.operationId(),
        eventId: context.event.id,
        divisionId: context.division.id,
        action: RoundRobinAction.generate,
        expectedVersion: context.tournament?.metadata.recordVersion ?? -1,
        expectedEventVersion: context.event.metadata.recordVersion,
        expectedDivisionVersion: context.division.metadata.recordVersion,
        createdAt: clock.nowUtc(),
        seedOrder: seedOrder,
        teamVersions: {
          for (final t in context.teams)
            t.team.id: t.team.metadata.recordVersion,
        },
        matchIds: {for (final m in plan.matches) m.key: ids.matchId()},
      ),
    );
  }

  Future<RepositoryResult<RoundRobinContext>> change(
    RoundRobinContext context,
    AuthorizationState auth, {
    required RoundRobinAction action,
    required PlannedMatchKey key,
    ValidatedScore? score,
    String? reason,
  }) async {
    try {
      _organizer(auth);
      final tournament = context.tournament;
      if (tournament == null) {
        throw const TournamentGenerationFailure(
          code: 'missing_schedule',
          message: 'Generate the schedule first.',
        );
      }
      final command = RoundRobinCommand(
        operationId: ids.operationId(),
        eventId: context.event.id,
        divisionId: context.division.id,
        action: action,
        expectedVersion: tournament.metadata.recordVersion,
        expectedEventVersion: context.event.metadata.recordVersion,
        expectedDivisionVersion: context.division.metadata.recordVersion,
        createdAt: clock.nowUtc(),
        matchKey: key,
        score: score,
        reason: reason,
        placementIds: {
          for (var i = 1; i <= context.teams.length; i++)
            i: DivisionPlacementId(ids.matchId().value),
        },
      );
      applyRoundRobinCommand(context, command);
      return await repository.apply(command);
    } on DomainFailure catch (f) {
      return RepositoryFailure(f);
    }
  }
}

void _organizer(AuthorizationState auth) {
  if (auth != AuthorizationState.organizer) {
    throw const UnauthorizedFailure(
      message: 'Organizer permission is required.',
    );
  }
}

void _generationAllowed(RoundRobinContext c) {
  if (c.event.status != EventStatus.registration ||
      !isRoundRobin(c.division.format) ||
      c.event.metadata.isDeleted ||
      c.division.metadata.isDeleted ||
      c.teamConflict ||
      c.disposition == BracketDisposition.conflicted ||
      (c.tournament != null && !c.tournament!.mayRegenerate)) {
    throw const TournamentGenerationFailure(
      code: 'generation_locked',
      message: 'Generation requires Registration, valid teams and no played results or unresolved conflicts.',
    );
  }
}

RoundRobinTournament applyRoundRobinCommand(
  RoundRobinContext c,
  RoundRobinCommand command,
) {
  if (c.event.id != command.eventId ||
      c.division.id != command.divisionId ||
      c.event.metadata.recordVersion != command.expectedEventVersion ||
      c.division.metadata.recordVersion != command.expectedDivisionVersion ||
      (c.tournament?.metadata.recordVersion ?? -1) != command.expectedVersion) {
    throw const ConflictFailure(
      message:
          'The event, division or schedule changed. Refresh before retrying.',
    );
  }
  if (command.action == RoundRobinAction.generate) {
    _generationAllowed(c);
    if (command.teamVersions.length != c.teams.length ||
        c.teams.any(
          (t) =>
              command.teamVersions[t.team.id] != t.team.metadata.recordVersion,
        )) {
      throw const ConflictFailure(
        message: 'Teams changed after the preview. Review again.',
      );
    }
    final result = const RoundRobinGenerator().generate(
      TournamentGenerationRequest(
        eventId: c.event.id,
        division: c.division,
        teams: c.teams,
        organizerOrder: command.seedOrder,
      ),
    );
    final plan = result.when(success: (v) => v, failure: (f) => throw f);
    if (command.matchIds.length != plan.matches.length ||
        command.matchIds.values.toSet().length != plan.matches.length ||
        plan.matches.any((m) => !command.matchIds.containsKey(m.key))) {
      throw const ValidationFailure(
        field: 'matchIds',
        message: 'Every planned match needs a unique identity.',
      );
    }
    final matchMeta = RecordMetadata(
      createdAt: command.createdAt,
      updatedAt: command.createdAt,
      recordVersion: 0,
    );
    return RoundRobinTournament(
      plan: plan,
      metadata: RecordMetadata(
        createdAt: c.tournament?.metadata.createdAt ?? command.createdAt,
        updatedAt: command.createdAt,
        recordVersion: command.expectedVersion + 1,
      ),
      matches: {
        for (final p in plan.matches)
          p.key: Match(
            id: command.matchIds[p.key]!,
            divisionId: c.division.id,
            status: MatchStatus.queued,
            metadata: matchMeta,
            sideOneTeamId: (p.sideOne as DirectTeamSource).teamId,
            sideTwoTeamId: (p.sideTwo as DirectTeamSource).teamId,
            roundNumber: p.round,
            sequenceNumber: int.parse(p.key.value.split('/m').last),
          ),
      },
    );
  }
  final tournament = c.tournament, key = command.matchKey;
  if (tournament == null || key == null) {
    throw const ValidationFailure(
      field: 'match',
      message: 'An existing match is required.',
    );
  }
  if (command.action == RoundRobinAction.start) {
    return tournament.start(
      key,
      c.event.status,
      command.expectedVersion,
      command.createdAt,
    );
  }
  final row = tournament.matches[key];
  if (command.score == null ||
      row == null ||
      (command.action == RoundRobinAction.correct) !=
          (row.status == MatchStatus.completed)) {
    throw const ValidationFailure(
      field: 'result',
      message: 'Choose the appropriate result or correction action.',
    );
  }
  return tournament.result(
    key: key,
    score: command.score!,
    eventStatus: c.event.status,
    expectedVersion: command.expectedVersion,
    now: command.createdAt,
    operationId: command.operationId,
    correctionReason: command.action == RoundRobinAction.correct
        ? command.reason
        : null,
  );
}
