import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/tournament/tournament_contracts.dart';
import 'package:vpc/src/domain/tournament/tournament_invariant_validator.dart';

/// Reuse for each future M13–M15 strategy with its own appropriate fixtures.
void verifyGeneratorConformance(
  TournamentGenerator generator,
  TournamentGenerationRequest request,
) {
  final before = request.teams.map((t) => t.team.id).toList();
  final first =
      (generator.generate(request) as RepositorySuccess<TournamentPlan>).value;
  final reordered = TournamentGenerationRequest(
    eventId: request.eventId,
    division: request.division,
    teams: request.teams.reversed,
    organizerOrder: request.organizerOrder,
  );
  final second = (generator.generate(
    reordered,
  ) as RepositorySuccess<TournamentPlan>).value;
  expect(second, first);
  expect(second.matches.map((m) => m.key), first.matches.map((m) => m.key));
  expect(request.teams.map((t) => t.team.id), before);
  expect(
    const TournamentInvariantValidator().validate(request, first),
    isEmpty,
  );
}
