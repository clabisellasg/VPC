import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/tournament/round_robin_service.dart';
import '../../application/tournament/single_elimination_service.dart'
    show BracketDisposition;
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/matches/match.dart';
import '../../domain/tournament/round_robin_generator.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import '../../infrastructure/teams/team_formation_providers.dart';
import '../../infrastructure/tournament/round_robin_providers.dart';
import '../accounts/account_controller.dart';
import '../events/organizer_event_controller.dart';
import 'match_score_dialog.dart';

class RoundRobinPage extends ConsumerStatefulWidget {
  const RoundRobinPage({
    required this.eventId,
    required this.divisionId,
    this.organizerRoute = false,
    super.key,
  });
  final String eventId, divisionId;
  final bool organizerRoute;
  @override
  ConsumerState<RoundRobinPage> createState() => _RoundRobinPageState();
}

class _RoundRobinPageState extends ConsumerState<RoundRobinPage> {
  RoundRobinContext? _context;
  TournamentPlan? _preview;
  List<TeamId> _order = [];
  String? _message;
  bool _loading = true, _busy = false, _refreshing = false;
  bool _seedOrderChanged = false;
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
      final repo = ref.read(roundRobinRepositoryProvider);
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
      void present(RepositoryResult<RoundRobinContext> result) {
        if (!mounted || request != _request) return;
        setState(() {
          _loading = false;
          result.when(
            success: (v) {
              _context = v;
              _message = null;
              final ids = v.teams.map((t) => t.team.id).toList()
                ..sort((a, b) => a.value.compareTo(b.value));
              if (_order.length != ids.length ||
                  !_order.toSet().containsAll(ids)) {
                _order = ids;
                _preview = null;
                _seedOrderChanged = false;
              }
            },
            failure: (f) => _message = f.message,
          );
        });
      }

      present(await repo.load(eid, did));
      if (!mounted || request != _request) return;
      final local = ref.read(localRoundRobinRepositoryProvider);
      if (local != null && _role == AuthorizationState.organizer) {
        await ref.read(eventSetupSynchronizerProvider)?.synchronize();
        await ref.read(teamFormationSynchronizerProvider)?.synchronize();
        if (!mounted || _role != AuthorizationState.organizer) return;
        await ref.read(roundRobinSynchronizerProvider)?.synchronize();
        present(await local.load(eid, did));
      } else if (local != null && _context?.tournament == null) {
        final remote = ref.read(remoteRoundRobinRepositoryProvider);
        if (remote != null) present(await remote.load(eid, did));
      }
    } on DomainFailure catch (f) {
      if (mounted) setState(() => _message = f.message);
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
        builder: (d) => AlertDialog(
          title: const Text('Confirm tournament action'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editSeedOrder(RoundRobinContext data) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Text('Seed order', style: Theme.of(context).textTheme.titleLarge),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Round-robin scheduling uses this order; skill does not reorder teams.',
                ),
              ),
              if (_seedOrderChanged)
                const Chip(
                  avatar: Icon(Icons.swap_vert, size: 18),
                  label: Text('Order changed'),
                ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: _order.length,
                  onReorderItem: (oldIndex, newIndex) => updateSheet(() {
                    final team = _order.removeAt(oldIndex);
                    _order.insert(newIndex, team);
                    _preview = null;
                    _seedOrderChanged = true;
                  }),
                  itemBuilder: (_, index) => ListTile(
                    key: ValueKey(_order[index]),
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(
                      data.teamLabels[_order[index]] ?? 'Community team',
                    ),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: const Tooltip(
                        message: 'Drag to reorder seed',
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _mutate(
    Future<RepositoryResult<RoundRobinContext>> Function() action,
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
          success: (v) {
            _context = v;
            _preview = null;
            _message = v.disposition == BracketDisposition.pending
                ? 'Saved locally; synchronization pending.'
                : 'Saved by the cloud.';
          },
          failure: (f) => _message = f.message,
        ),
      );
    } on DomainFailure catch (f) {
      if (mounted) setState(() => _message = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _match(PlannedMatchKey key) async {
    final c = _context, s = ref.read(roundRobinServiceProvider);
    if (c == null || s == null || _busy) return;
    final match = c.tournament!.matches[key]!;
    if (match.status == MatchStatus.queued) {
      if (await _confirm('Start this independent round-robin match?')) {
        await _mutate(
          () => s.change(c, _role, action: RoundRobinAction.start, key: key),
        );
      }
      return;
    }
    final correcting = match.status == MatchStatus.completed;
    final accepted = await showDialog<MatchScoreInput>(
      context: context,
      builder: (_) => MatchScoreDialog(
        correcting: correcting,
        sideOneLabel: c.teamLabels[match.sideOneTeamId] ?? 'First team score',
        sideTwoLabel: c.teamLabels[match.sideTwoTeamId] ?? 'Second team score',
      ),
    );
    if (accepted == null || !mounted) return;
    final a = int.tryParse(accepted.sideOne),
        b = int.tryParse(accepted.sideTwo);
    if (a == null || b == null) {
      setState(() => _message = 'Enter two nonnegative whole-number scores.');
      return;
    }
    try {
      await _mutate(
        () => s.change(
          c,
          _role,
          action: correcting
              ? RoundRobinAction.correct
              : RoundRobinAction.result,
          key: key,
          score: ValidatedScore(a, b),
          reason: accepted.reason,
        ),
      );
    } on DomainFailure catch (f) {
      if (mounted) setState(() => _message = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      roundRobinRefreshHintsProvider,
      (_, next) => next.whenData((_) {
        if (!_busy) unawaited(_refresh());
      }),
    );
    final account = ref.watch(accountControllerProvider),
        organizer =
            account.snapshot?.authorization == AuthorizationState.organizer;
    if (organizer) ref.watch(roundRobinSynchronizerProvider);
    if (widget.organizerRoute && !organizer) {
      return const Center(
        child: Text(
          'Organizer permission is required. Public schedules remain available from event details.',
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Loading round-robin tournament',
        ),
      );
    }
    final c = _context,
        s = ref.watch(roundRobinServiceProvider),
        canGenerate =
            organizer &&
            c?.event.status == EventStatus.registration &&
            isRoundRobin(c?.division.format),
        plan = _preview ?? c?.tournament?.plan;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('/events/${widget.eventId}'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to event'),
                ),
                Text(
                  '${c?.division.name ?? 'Division'} — ${c?.division.format == TournamentFormat.doubleRoundRobin ? 'Double' : 'Single'} Round Robin',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                    if (canGenerate)
                      FilledButton(
                        onPressed: _busy || s == null
                            ? null
                            : () {
                                final result = s.preview(
                                  c!,
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
                        child: const Text('Preview schedule'),
                      ),
                    if (_preview != null)
                      OutlinedButton(
                        onPressed: _busy || s == null
                            ? null
                            : () async {
                                if (await _confirm(
                                  'Persist this schedule? Any previous unstarted draft is tombstoned, not deleted.',
                                )) {
                                  await _mutate(
                                    () => s.generate(
                                      c!,
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
                ),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                if (c != null && organizer)
                  Text('Synchronization: ${c.disposition.name}'),
                if (_preview != null)
                  const Text('Preview only — no records have been saved.'),
                if (plan == null)
                  const Text('No round-robin schedule has been generated.'),
                if (canGenerate && c != null && _order.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => _editSeedOrder(c),
                      icon: const Icon(Icons.reorder),
                      label: const Text('Review seed order'),
                    ),
                  ),
                const TabBar(
                  tabs: [
                    Tab(text: 'Schedule'),
                    Tab(text: 'Standings'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _Schedule(
                  plan: plan,
                  contextData: c,
                  preview: _preview != null,
                  onMatch:
                      organizer &&
                          !_busy &&
                          _preview == null &&
                          c?.event.status == EventStatus.inProgress
                      ? _match
                      : null,
                ),
                _Standings(contextData: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Schedule extends StatelessWidget {
  const _Schedule({
    required this.plan,
    required this.contextData,
    required this.preview,
    required this.onMatch,
  });
  final TournamentPlan? plan;
  final RoundRobinContext? contextData;
  final bool preview;
  final void Function(PlannedMatchKey)? onMatch;
  @override
  Widget build(BuildContext context) {
    if (plan == null) return const Center(child: Text('Schedule unavailable.'));
    final rests = Map<String, dynamic>.from(
      jsonDecode(plan!.metadata['restingByRound']!) as Map,
    );
    final rounds = plan!.matches.map((m) => m.round).toSet().toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final r in rounds) ...[
          Text(
            '${plan!.metadata['legs'] == '2' ? 'Leg ${r <= int.parse(plan!.metadata['roundsPerLeg']!) ? 1 : 2} · ' : ''}Round ${r > int.parse(plan!.metadata['roundsPerLeg']!) ? r - int.parse(plan!.metadata['roundsPerLeg']!) : r}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (rests['$r'] != null)
            Text(
              'Resting: ${contextData?.teamLabels[TeamId(rests['$r'] as String)] ?? 'Community team'}',
            ),
          for (final p in plan!.matches.where((m) => m.round == r))
            _MatchTile(
              planned: p,
              actual: preview ? null : contextData?.tournament?.matches[p.key],
              labels: contextData?.teamLabels ?? const {},
              onTap: onMatch == null ? null : () => onMatch!(p.key),
            ),
        ],
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.planned,
    required this.actual,
    required this.labels,
    required this.onTap,
  });
  final PlannedMatch planned;
  final Match? actual;
  final Map<TeamId, String> labels;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final a =
            actual?.sideOneTeamId ??
            (planned.sideOne as DirectTeamSource).teamId,
        b =
            actual?.sideTwoTeamId ??
            (planned.sideTwo as DirectTeamSource).teamId;
    return Card(
      child: ListTile(
        title: Text(
          '${labels[a] ?? 'Community team'}  vs  ${labels[b] ?? 'Community team'}',
        ),
        subtitle: Text(
          actual?.sideOneScore == null
              ? (actual?.status.name ?? 'Ready')
              : '${actual!.sideOneScore} – ${actual!.sideTwoScore} · ${actual!.status.name}',
        ),
        trailing: onTap == null
            ? null
            : TextButton(
                onPressed: onTap,
                child: Text(
                  actual?.status == MatchStatus.completed
                      ? 'Correct result'
                      : actual?.status == MatchStatus.queued
                      ? 'Start match'
                      : 'Enter result',
                ),
              ),
      ),
    );
  }
}

class _Standings extends StatelessWidget {
  const _Standings({required this.contextData});
  final RoundRobinContext? contextData;
  @override
  Widget build(BuildContext context) {
    final t = contextData?.tournament;
    if (t == null) {
      return const Center(
        child: Text('Standings appear after schedule generation.'),
      );
    }
    final rows = t.standings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (t.complete && rows.length >= 2)
          Semantics(
            container: true,
            label:
                'Final placements. Champion ${contextData!.teamLabels[rows[0].teamId] ?? 'Community team'}. Runner-up ${contextData!.teamLabels[rows[1].teamId] ?? 'Community team'}.',
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Final placements',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Champion: ${contextData!.teamLabels[rows[0].teamId] ?? 'Community team'}',
                    ),
                    Text(
                      'Runner-up: ${contextData!.teamLabels[rows[1].teamId] ?? 'Community team'}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Team')),
              DataColumn(label: Text('P')),
              DataColumn(label: Text('W')),
              DataColumn(label: Text('L')),
              DataColumn(label: Text('PF')),
              DataColumn(label: Text('PA')),
              DataColumn(label: Text('Diff')),
              DataColumn(label: Text('Tie-break')),
            ],
            rows: [
              for (final r in rows)
                DataRow(
                  cells: [
                    DataCell(Text('${r.rank}')),
                    DataCell(
                      Text(
                        contextData!.teamLabels[r.teamId] ?? 'Community team',
                      ),
                    ),
                    DataCell(Text('${r.played}')),
                    DataCell(Text('${r.wins}')),
                    DataCell(Text('${r.losses}')),
                    DataCell(Text('${r.pointsFor}')),
                    DataCell(Text('${r.pointsAgainst}')),
                    DataCell(Text('${r.difference}')),
                    DataCell(Text(r.tieBreak.label)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
