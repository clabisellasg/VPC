import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/events/event.dart';
import '../../domain/events/event_division.dart';
import '../../domain/matches/match.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/tournament/single_elimination_bracket.dart';
import '../../domain/tournament/single_elimination_generator.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../accounts/account_models.dart';

enum BracketDisposition { synchronized, pending, blocked, failed, conflicted }

enum BracketAction { generate, start, result, correct }

final class BracketContext {
  BracketContext({
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
  final SingleEliminationBracket? bracket;
  final BracketDisposition disposition;
  final bool teamConflict;
}

/// A fixed command, never arbitrary rows or client-selected table names.
final class BracketCommand {
  BracketCommand({
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
}

abstract interface class BracketRepository {
  Future<RepositoryResult<BracketContext>> load(
    EventId eventId,
    DivisionId divisionId,
  );
  Future<RepositoryResult<BracketContext>> apply(BracketCommand command);
}

abstract interface class BracketIds {
  MatchId matchId();
  SyncOperationId operationId();
}

abstract interface class BracketClock {
  DateTime nowUtc();
}

final class SingleEliminationService {
  const SingleEliminationService({
    required this.repository,
    required this.ids,
    required this.clock,
  });
  final BracketRepository repository;
  final BracketIds ids;
  final BracketClock clock;

  RepositoryResult<TournamentPlan> preview(
    BracketContext context,
    AuthorizationState authorization, {
    List<TeamId>? seedOrder,
  }) {
    try {
      _organizer(authorization);
      _generationAllowed(context);
      return const SingleEliminationGenerator().generate(
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

  Future<RepositoryResult<BracketContext>> generate(
    BracketContext context,
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
    final result = preview(context, authorization, seedOrder: seedOrder);
    if (result case RepositoryFailure(:final failure)) {
      return RepositoryFailure(failure);
    }
    final plan = (result as RepositorySuccess<TournamentPlan>).value;
    return repository.apply(
      BracketCommand(
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
          for (final t in context.teams)
            t.team.id: t.team.metadata.recordVersion,
        },
        matchIds: {for (final m in plan.matches) m.key: ids.matchId()},
      ),
    );
  }

  Future<RepositoryResult<BracketContext>> change(
    BracketContext context,
    AuthorizationState authorization, {
    required BracketAction action,
    required PlannedMatchKey key,
    ValidatedScore? score,
    String? reason,
  }) async {
    try {
      _organizer(authorization);
      if (action == BracketAction.generate) {
        throw const ValidationFailure(
          field: 'action',
          message: 'Review generation separately.',
        );
      }
      final bracket = context.bracket;
      if (bracket == null) {
        throw const TournamentGenerationFailure(
          code: 'missing_bracket',
          message: 'Generate the bracket first.',
        );
      }
      final command = BracketCommand(
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
        placementIds: {
          1: DivisionPlacementId(ids.matchId().value),
          2: DivisionPlacementId(ids.matchId().value),
        },
      );
      applyBracketCommand(
        context,
        command,
      ); // validate before any platform mutation
      return await repository.apply(command);
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  static void _organizer(AuthorizationState authorization) {
    if (authorization != AuthorizationState.organizer) {
      throw const UnauthorizedFailure(
        message: 'Organizer permission is required.',
      );
    }
  }
}

void _generationAllowed(BracketContext context) {
  if (context.event.status != EventStatus.registration ||
      context.event.metadata.isDeleted ||
      context.division.metadata.isDeleted ||
      context.division.eventId != context.event.id ||
      context.teamConflict ||
      context.disposition == BracketDisposition.conflicted ||
      (context.bracket != null && !context.bracket!.mayRegenerate)) {
    throw const TournamentGenerationFailure(
      code: 'generation_locked',
      message: 'Generation requires Registration, valid teams and no played results or unresolved conflicts.',
    );
  }
}

/// Shared deterministic local application; the hosted command independently
/// rechecks the same rules and assigns authoritative timestamps.
SingleEliminationBracket applyBracketCommand(
  BracketContext context,
  BracketCommand command,
) {
  if (context.event.id != command.eventId ||
      context.division.id != command.divisionId ||
      context.event.metadata.recordVersion != command.expectedEventVersion ||
      context.division.metadata.recordVersion !=
          command.expectedDivisionVersion ||
      (context.bracket?.metadata.recordVersion ?? -1) !=
          command.expectedVersion) {
    throw const ConflictFailure(
      message:
          'The event, division or bracket changed. Refresh before retrying.',
    );
  }
  if (command.action == BracketAction.generate) {
    _generationAllowed(context);
    if (command.teamVersions.length != context.teams.length ||
        context.teams.any(
          (t) =>
              command.teamVersions[t.team.id] != t.team.metadata.recordVersion,
        )) {
      throw const ConflictFailure(
        message: 'Teams changed after the preview. Review them again.',
      );
    }
    final generated = const SingleEliminationGenerator().generate(
      TournamentGenerationRequest(
        eventId: context.event.id,
        division: context.division,
        teams: context.teams,
        organizerOrder: command.seedOrder,
      ),
    );
    final plan = generated.when(success: (p) => p, failure: (f) => throw f);
    if (command.matchIds.length != plan.matches.length ||
        command.matchIds.values.toSet().length != plan.matches.length ||
        plan.matches.any((m) => !command.matchIds.containsKey(m.key))) {
      throw const ValidationFailure(
        field: 'matchIds',
        message: 'Every planned match needs a unique persistence identity.',
      );
    }
    final meta = RecordMetadata(
      createdAt: command.createdAt,
      updatedAt: command.createdAt,
      recordVersion: 0,
    );
    return SingleEliminationBracket(
      plan: plan,
      metadata: RecordMetadata(
        createdAt: context.bracket?.metadata.createdAt ?? command.createdAt,
        updatedAt: command.createdAt,
        recordVersion: command.expectedVersion + 1,
      ),
      matches: {
        for (final m in plan.matches)
          m.key: Match(
            id: command.matchIds[m.key]!,
            divisionId: context.division.id,
            status: m.status,
            metadata: meta,
            roundNumber: m.round,
            sequenceNumber: int.parse(m.key.value.split('/m').last),
            sideOneTeamId: m.sideOne is DirectTeamSource
                ? (m.sideOne as DirectTeamSource).teamId
                : null,
            sideTwoTeamId: m.sideTwo is DirectTeamSource
                ? (m.sideTwo as DirectTeamSource).teamId
                : null,
          ),
      },
      revisions: context.bracket?.revisions ?? const [],
    );
  }
  final bracket = context.bracket;
  final key = command.matchKey;
  if (bracket == null || key == null) {
    throw const ValidationFailure(
      field: 'match',
      message: 'An existing bracket match is required.',
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
