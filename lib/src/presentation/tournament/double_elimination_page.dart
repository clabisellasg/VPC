import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/tournament/double_elimination_service.dart';
import '../../application/tournament/single_elimination_service.dart'
    show BracketAction, BracketDisposition;
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/matches/match.dart';
import '../../domain/tournament/double_elimination_generator.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import '../../infrastructure/teams/team_formation_providers.dart';
import '../../infrastructure/tournament/double_elimination_providers.dart';
import '../accounts/account_controller.dart';
import '../events/organizer_event_controller.dart';
import 'match_score_dialog.dart';

class DoubleEliminationPage extends ConsumerStatefulWidget {
  const DoubleEliminationPage({
    required this.eventId,
    required this.divisionId,
    this.organizerRoute = false,
    super.key,
  });
  final String eventId, divisionId;
  final bool organizerRoute;
  @override
  ConsumerState<DoubleEliminationPage> createState() =>
      _DoubleEliminationPageState();
}

class _DoubleEliminationPageState extends ConsumerState<DoubleEliminationPage> {
  DoubleEliminationContext? _context;
  TournamentPlan? _preview;
  List<TeamId> _order = [];
  String? _message;
  bool _loading = true, _busy = false, _refreshing = false;
  Timer? _timer;
  int _request = 0;
  AuthorizationState get _role =>
      ref.read(accountControllerProvider).snapshot?.authorization ??
      AuthorizationState.guest;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_busy) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _request++;
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final request = ++_request;
    try {
      final repository = ref.read(doubleEliminationRepositoryProvider);
      if (repository == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _message = 'Supabase is not configured.';
          });
        }
        return;
      }
      final eventId = EventId(widget.eventId);
      final divisionId = DivisionId(widget.divisionId);
      void present(RepositoryResult<DoubleEliminationContext> result) {
        if (!mounted || request != _request) return;
        setState(() {
          _loading = false;
          result.when(
            success: (value) {
              _context = value;
              _message = null;
              final ids = value.teams.map((team) => team.team.id).toList()
                ..sort((a, b) => a.value.compareTo(b.value));
              if (_order.length != ids.length ||
                  !_order.toSet().containsAll(ids)) {
                _order = ids;
                _preview = null;
              }
            },
            failure: (failure) => _message = failure.message,
          );
        });
      }

      present(await repository.load(eventId, divisionId));
      final local = ref.read(localDoubleEliminationRepositoryProvider);
      if (local != null && _role == AuthorizationState.organizer) {
        await ref.read(eventSetupSynchronizerProvider)?.synchronize();
        await ref.read(teamFormationSynchronizerProvider)?.synchronize();
        await ref.read(doubleEliminationSynchronizerProvider)?.synchronize();
        if (mounted) present(await local.load(eventId, divisionId));
      } else if (local != null && _context?.bracket == null) {
        final remote = ref.read(remoteDoubleEliminationRepositoryProvider);
        if (remote != null) present(await remote.load(eventId, divisionId));
      }
    } on DomainFailure catch (failure) {
      if (mounted) setState(() => _message = failure.message);
    } on Exception {
      if (mounted) {
        setState(() {
          _message =
              'Refresh is unavailable. Existing data may be out of date.';
        });
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Confirm tournament action'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _mutate(
    Future<RepositoryResult<DoubleEliminationContext>> Function() action,
  ) async {
    if (_busy) return;
    _request++;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      if (result.isSuccess) {
        unawaited(
          ref.read(organizerEventControllerProvider.notifier).refresh(),
        );
      }
      setState(() {
        result.when(
          success: (value) {
            _context = value;
            _preview = null;
            _message = value.disposition == BracketDisposition.pending
                ? 'Saved locally; synchronization pending.'
                : 'Saved by the cloud.';
          },
          failure: (failure) => _message = failure.message,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _match(PlannedMatchKey key) async {
    final current = _context;
    final service = ref.read(doubleEliminationServiceProvider);
    if (current == null || service == null || _busy) return;
    final match = current.bracket!.matches[key];
    if (match == null) {
      setState(() => _message = 'Grand Final 2 is used only if necessary.');
      return;
    }
    if (match.status == MatchStatus.queued) {
      if (await _confirm('Start this match?')) {
        await _mutate(
          () => service.change(
            current,
            _role,
            action: BracketAction.start,
            key: key,
          ),
        );
      }
      return;
    }
    if (match.status == MatchStatus.scheduled) {
      setState(
        () => _message = 'This match is blocked until both teams are known.',
      );
      return;
    }
    final correcting = match.status == MatchStatus.completed;
    final input = await showDialog<MatchScoreInput>(
      context: context,
      builder: (_) => MatchScoreDialog(
        correcting: correcting,
        sideOneLabel:
            current.teamLabels[match.sideOneTeamId] ?? 'First team score',
        sideTwoLabel:
            current.teamLabels[match.sideTwoTeamId] ?? 'Second team score',
      ),
    );
    if (input == null || !mounted) return;
    final one = int.tryParse(input.sideOne), two = int.tryParse(input.sideTwo);
    if (one == null || two == null) {
      setState(() => _message = 'Enter two nonnegative whole-number scores.');
      return;
    }
    try {
      await _mutate(
        () => service.change(
          current,
          _role,
          action: correcting ? BracketAction.correct : BracketAction.result,
          key: key,
          score: ValidatedScore(one, two),
          reason: input.reason,
        ),
      );
    } on DomainFailure catch (failure) {
      if (mounted) setState(() => _message = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(doubleEliminationRefreshHintsProvider, (_, next) {
      next.whenData((_) {
        if (!_busy) unawaited(_refresh());
      });
    });
    final organizer =
        ref.watch(accountControllerProvider).snapshot?.authorization ==
        AuthorizationState.organizer;
    if (organizer) ref.watch(doubleEliminationSynchronizerProvider);
    if (widget.organizerRoute && !organizer) {
      return const Center(
        child: Text(
          'Organizer permission is required. The public bracket remains readable.',
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Loading Double Elimination bracket',
        ),
      );
    }
    final current = _context;
    final service = ref.watch(doubleEliminationServiceProvider);
    final canGenerate =
        organizer &&
        current?.event.status == EventStatus.registration &&
        current?.division.format == TournamentFormat.doubleElimination;
    final plan = _preview ?? current?.bracket?.plan;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextButton.icon(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/events/${widget.eventId}'),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to event'),
        ),
        Text(
          '${current?.division.name ?? 'Division'} — Double Elimination',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'A team is eliminated only after two played losses. Grand Final 2 appears only if the losers-bracket finalist wins Grand Final 1.',
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh bracket'),
        ),
        if (_message != null)
          Semantics(liveRegion: true, child: Text(_message!)),
        if (current != null && organizer)
          Text('Synchronization: ${current.disposition.name}'),
        if (canGenerate && current != null) ...[
          Text('Seed order', style: Theme.of(context).textTheme.titleMedium),
          for (var index = 0; index < _order.length; index++)
            ListTile(
              title: Text(
                current.teamLabels[_order[index]] ?? 'Community team',
              ),
              leading: Text('${index + 1}'),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Move seed up',
                    onPressed: index == 0
                        ? null
                        : () => setState(() {
                            final value = _order.removeAt(index);
                            _order.insert(index - 1, value);
                            _preview = null;
                          }),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move seed down',
                    onPressed: index == _order.length - 1
                        ? null
                        : () => setState(() {
                            final value = _order.removeAt(index);
                            _order.insert(index + 1, value);
                            _preview = null;
                          }),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: service == null || _busy
                    ? null
                    : () {
                        final result = service.preview(
                          current,
                          _role,
                          seedOrder: _order,
                        );
                        setState(() {
                          result.when(
                            success: (value) {
                              _preview = value;
                              _message = null;
                            },
                            failure: (failure) => _message = failure.message,
                          );
                        });
                      },
                child: const Text('Preview double-elimination bracket'),
              ),
              if (_preview != null)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _confirm(
                            'Persist this complete winners/losers structure? An unstarted draft is tombstoned during regeneration.',
                          )) {
                            await _mutate(
                              () => service!.generate(
                                current,
                                _role,
                                seedOrder: _order,
                                confirmed: true,
                              ),
                            );
                          }
                        },
                  child: const Text('Confirm generation'),
                ),
            ],
          ),
        ],
        if (_preview != null)
          const Text('Preview only — no records have been saved.'),
        if (current?.bracket?.decided == true) ...[
          Text(
            'Champion: ${current!.teamLabels[current.bracket!.champion] ?? 'Community team'}',
          ),
          Text(
            'Runner-up: ${current.teamLabels[current.bracket!.runnerUp] ?? 'Community team'}',
          ),
        ],
        if (plan == null)
          const Text('No Double Elimination bracket has been generated.')
        else
          DoubleEliminationBracketView(
            plan: plan,
            labels: current?.teamLabels ?? const {},
            matches: _preview == null
                ? current?.bracket?.matches ?? const {}
                : const {},
            onMatch:
                organizer &&
                    !_busy &&
                    _preview == null &&
                    current?.event.status == EventStatus.inProgress
                ? _match
                : null,
          ),
      ],
    );
  }
}

class DoubleEliminationBracketView extends StatelessWidget {
  const DoubleEliminationBracketView({
    required this.plan,
    required this.labels,
    required this.matches,
    this.onMatch,
    super.key,
  });
  final TournamentPlan plan;
  final Map<TeamId, String> labels;
  final Map<PlannedMatchKey, Match> matches;
  final ValueChanged<PlannedMatchKey>? onMatch;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section(context, 'Winners bracket', 'winners'),
      _section(context, 'Losers bracket', 'losers'),
      _section(context, 'Grand finals', 'grandFinal', includeReset: true),
    ],
  );

  Widget _section(
    BuildContext context,
    String title,
    String section, {
    bool includeReset = false,
  }) {
    final planned = plan.matches
        .where(
          (match) =>
              match.section == section ||
              (includeReset && match.section == 'resetFinal'),
        )
        .toList();
    final rounds = planned.map((match) => match.round).toSet().toList()..sort();
    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final round in rounds)
                    SizedBox(
                      width: 280,
                      child: Column(
                        children: [
                          Text(
                            section == 'grandFinal'
                                ? round == 1
                                      ? 'Grand Final 1'
                                      : 'Grand Final 2 — if necessary'
                                : 'Round $round',
                          ),
                          for (final match in planned.where(
                            (value) => value.round == round,
                          ))
                            _card(match),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(PlannedMatch planned) {
    final match = matches[planned.key];
    String source(PlannedParticipantSource value) => switch (value) {
      DirectTeamSource(:final teamId) => labels[teamId] ?? 'Community team',
      MatchOutcomeSource(:final matchKey, :final outcome) =>
        '${outcome == MatchDependencySource.winner ? 'Winner' : 'Loser'} of ${matchKey.value}',
    };
    final one = match?.sideOneTeamId == null
        ? source(planned.sideOne)
        : labels[match!.sideOneTeamId] ?? 'Community team';
    final two = match?.sideTwoTeamId == null
        ? source(planned.sideTwo)
        : labels[match!.sideTwoTeamId] ?? 'Community team';
    final resetMissing =
        planned.key == DoubleEliminationGenerator.resetKey && match == null;
    return Card(
      child: ListTile(
        onTap: onMatch == null ? null : () => onMatch!(planned.key),
        title: Text('$one\nvs\n$two'),
        subtitle: Text(
          resetMissing
              ? 'If necessary — not active'
              : match == null
              ? 'Preview'
              : match.status == MatchStatus.completed
              ? '${match.sideOneScore} – ${match.sideTwoScore} · completed'
              : match.status.name,
        ),
        trailing: onMatch == null || resetMissing
            ? null
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}
