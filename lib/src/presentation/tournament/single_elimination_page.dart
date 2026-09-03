import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/tournament/single_elimination_service.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import '../../infrastructure/teams/team_formation_providers.dart';
import '../../infrastructure/tournament/bracket_providers.dart';
import '../accounts/account_controller.dart';
import '../events/organizer_event_controller.dart';
import 'single_elimination_bracket_view.dart';
import 'match_score_dialog.dart';

class SingleEliminationPage extends ConsumerStatefulWidget {
  const SingleEliminationPage({
    required this.eventId,
    required this.divisionId,
    this.organizerRoute = false,
    super.key,
  });
  final String eventId, divisionId;
  final bool organizerRoute;
  @override
  ConsumerState<SingleEliminationPage> createState() =>
      _SingleEliminationPageState();
}

class _SingleEliminationPageState extends ConsumerState<SingleEliminationPage> {
  BracketContext? _context;
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
      final repo = ref.read(bracketRepositoryProvider);
      if (repo == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _message = 'Supabase is not configured.';
          });
        }
        return;
      }
      final eid = EventId(widget.eventId), did = DivisionId(widget.divisionId);
      void present(RepositoryResult<BracketContext> result) {
        if (!mounted || request != _request) return;
        setState(() {
          _loading = false;
          result.when(
            success: (value) {
              _context = value;
              _message = null;
              final ids = value.teams.map((t) => t.team.id).toList()
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

      present(await repo.load(eid, did));
      if (!mounted || request != _request) return;
      final local = ref.read(localBracketRepositoryProvider);
      if (local != null && _role == AuthorizationState.organizer) {
        await ref.read(eventSetupSynchronizerProvider)?.synchronize();
        await ref.read(teamFormationSynchronizerProvider)?.synchronize();
        if (!mounted || _role != AuthorizationState.organizer) return;
        await ref.read(bracketSynchronizerProvider)?.synchronize();
        await ref.read(eventSetupSynchronizerProvider)?.synchronize();
        present(await local.load(eid, did));
      } else if (local != null && _context?.bracket == null) {
        final remote = ref.read(remoteBracketRepositoryProvider);
        if (remote != null) present(await remote.load(eid, did));
      }
    } on DomainFailure catch (failure) {
      if (mounted) setState(() => _message = failure.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _message = 'Refresh is unavailable. Previously loaded data may be out of date.',
        );
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Confirm tournament action'),
          content: Text(message),
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
    Future<RepositoryResult<BracketContext>> Function() action,
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
      setState(
        () => result.when(
          success: (value) {
            _context = value;
            _preview = null;
            _message = value.disposition == BracketDisposition.pending
                ? 'Saved locally; synchronization pending.'
                : 'Saved by the cloud.';
          },
          failure: (failure) => _message = failure.message,
        ),
      );
    } on DomainFailure catch (failure) {
      if (mounted) setState(() => _message = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _match(PlannedMatchKey key) async {
    final current = _context,
        service = ref.read(singleEliminationServiceProvider);
    if (current == null || service == null || _busy) return;
    final match = current.bracket!.matches[key]!;
    if (match.status == MatchStatus.queued) {
      if (await _confirm(
        'Start this match? Once started, a feeder result that changes its teams can no longer be corrected.',
      )) {
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
        () => _message =
            'Both winners must be known before this match can start.',
      );
      return;
    }
    final correcting = match.status == MatchStatus.completed;
    final accepted = await showDialog<MatchScoreInput>(
      context: context,
      builder: (_) => MatchScoreDialog(
        correcting: correcting,
        sideOneLabel:
            current.teamLabels[match.sideOneTeamId] ?? 'First team score',
        sideTwoLabel:
            current.teamLabels[match.sideTwoTeamId] ?? 'Second team score',
      ),
    );
    if (accepted != null && mounted) {
      final a = int.tryParse(accepted.sideOne),
          b = int.tryParse(accepted.sideTwo);
      if (a == null || b == null) {
        setState(() => _message = 'Enter two nonnegative whole-number scores.');
      } else {
        try {
          final score = ValidatedScore(a, b);
          await _mutate(
            () => service.change(
              current,
              _role,
              action: correcting ? BracketAction.correct : BracketAction.result,
              key: key,
              score: score,
              reason: accepted.reason,
            ),
          );
        } on DomainFailure catch (failure) {
          if (mounted) setState(() => _message = failure.message);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bracketRefreshHintsProvider, (previous, next) {
      next.whenData((_) {
        if (!_busy) unawaited(_refresh());
      });
    });
    final account = ref.watch(accountControllerProvider);
    final organizer =
        account.snapshot?.authorization == AuthorizationState.organizer;
    // Watching retains the owned synchronizer while this page is active.
    if (organizer) ref.watch(bracketSynchronizerProvider);
    if (widget.organizerRoute && !organizer) {
      return const Center(
        child: Text(
          'Organizer permission is required. Public brackets remain available from event details.',
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading bracket'),
      );
    }
    final current = _context,
        service = ref.watch(singleEliminationServiceProvider);
    final canGenerate =
        organizer &&
        current?.event.status == EventStatus.registration &&
        current?.division.format == TournamentFormat.singleElimination;
    final plan = _preview ?? current?.bracket?.plan;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/events/${widget.eventId}');
              }
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to event'),
          ),
          Text(
            '${current?.division.name ?? 'Division'} — Single Elimination',
            style: Theme.of(context).textTheme.headlineSmall,
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
          if (current != null &&
              current.division.format != TournamentFormat.singleElimination)
            const Text(
              'Select Single Elimination during Registration before using this generator.',
            ),
          if (canGenerate && current != null) ...[
            const Text(
              'Seed order (no skill-based ranking). Reorder, preview, then explicitly confirm. Regeneration replaces only unstarted draft matches.',
            ),
            for (var i = 0; i < _order.length; i++)
              ListTile(
                title: Text(
                  '${i + 1}. ${current.teamLabels[_order[i]] ?? 'Community team'}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Move seed up',
                      onPressed: _busy || i == 0
                          ? null
                          : () {
                              setState(() {
                                final t = _order.removeAt(i);
                                _order.insert(i - 1, t);
                                _preview = null;
                              });
                            },
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move seed down',
                      onPressed: _busy || i == _order.length - 1
                          ? null
                          : () {
                              setState(() {
                                final t = _order.removeAt(i);
                                _order.insert(i + 1, t);
                                _preview = null;
                              });
                            },
                      icon: const Icon(Icons.arrow_downward),
                    ),
                  ],
                ),
              ),
            FilledButton(
              onPressed: _busy || service == null
                  ? null
                  : () {
                      final result = service.preview(
                        current,
                        _role,
                        seedOrder: _order,
                      );
                      setState(
                        () => result.when(
                          success: (p) {
                            _preview = p;
                            _message = null;
                          },
                          failure: (f) => _message = f.message,
                        ),
                      );
                    },
              child: const Text('Preview bracket'),
            ),
            if (_preview != null)
              OutlinedButton(
                onPressed: _busy || service == null
                    ? null
                    : () async {
                        if (await _confirm(
                          'Persist this bracket? Any previous unstarted draft structure will be tombstoned, not deleted.',
                        )) {
                          await _mutate(
                            () => service.generate(
                              current,
                              _role,
                              seedOrder: List.of(_order),
                              confirmed: true,
                            ),
                          );
                        }
                      },
                child: const Text('Confirm generation'),
              ),
          ],
          if (_busy)
            const LinearProgressIndicator(
              semanticsLabel: 'Saving tournament operation',
            ),
          if (plan == null)
            const Text(
              'No bracket has been generated. Selecting a format alone does not create matches.',
            ),
          if (current?.bracket?.champion != null) ...[
            Text(
              'Champion: ${current!.teamLabels[current.bracket!.champion] ?? 'Community team'}',
            ),
            Text(
              'Runner-up: ${current.teamLabels[current.bracket!.runnerUp] ?? 'Community team'}',
            ),
          ],
          if (_preview != null)
            Semantics(
              liveRegion: true,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Preview only — no records have been saved.'),
              ),
            ),
          if (plan != null && current != null)
            SingleEliminationBracketView(
              plan: plan,
              labels: current.teamLabels,
              matches: _preview == null ? current.bracket!.matches : const {},
              onMatch:
                  organizer &&
                      !_busy &&
                      _preview == null &&
                      current.event.status == EventStatus.inProgress
                  ? _match
                  : null,
            ),
        ],
      ),
    );
  }
}
