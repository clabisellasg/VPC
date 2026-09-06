import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/court/court_queue_service.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../infrastructure/court/court_queue_providers.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import '../../infrastructure/tournament/bracket_providers.dart';
import '../../infrastructure/tournament/double_elimination_providers.dart';
import '../../infrastructure/tournament/round_robin_providers.dart';
import '../accounts/account_controller.dart';

class EventCourtPage extends ConsumerStatefulWidget {
  const EventCourtPage({
    required this.eventId,
    this.organizerRoute = false,
    super.key,
  });
  final String eventId;
  final bool organizerRoute;

  @override
  ConsumerState<EventCourtPage> createState() => _EventCourtPageState();
}

class _EventCourtPageState extends ConsumerState<EventCourtPage> {
  CourtQueueSnapshot? _snapshot;
  String? _message;
  bool _loading = true, _busy = false;
  Timer? _timer;
  int _request = 0;
  AuthorizationState get _role =>
      ref.read(accountControllerProvider).snapshot?.authorization ??
      AuthorizationState.guest;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _request++;
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final request = ++_request;
    final repository = ref.read(courtQueueRepositoryProvider);
    if (repository == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Supabase is not configured.';
        });
      }
      return;
    }
    try {
      RepositoryResult<CourtQueueSnapshot> result = await repository.load(
        EventId(widget.eventId),
      );
      final local = ref.read(localCourtQueueRepositoryProvider);
      if (_role == AuthorizationState.organizer) {
        await ref.read(eventSetupSynchronizerProvider)?.synchronize();
        await ref.read(bracketSynchronizerProvider)?.synchronize();
        await ref.read(roundRobinSynchronizerProvider)?.synchronize();
        await ref.read(doubleEliminationSynchronizerProvider)?.synchronize();
        final service = ref.read(courtQueueServiceProvider);
        if (service != null) {
          result = await service.refresh(EventId(widget.eventId));
        }
        await ref.read(courtQueueSynchronizerProvider)?.synchronize();
        if (local != null) result = await local.load(EventId(widget.eventId));
      } else if (local != null) {
        // A freshly installed Android app has no cached matches yet. Preserve
        // the local-first read, then use the anonymous public endpoint as an
        // online fallback without opening organizer synchronization.
        final remote = ref.read(remoteCourtQueueRepositoryProvider);
        if (remote != null) {
          final authoritative = await remote.load(EventId(widget.eventId));
          if (authoritative.isSuccess) result = authoritative;
        }
      }
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        result.when(
          success: (value) {
            _snapshot = value;
            _message = null;
          },
          failure: (failure) => _message = failure.message,
        );
      });
    } on DomainFailure catch (failure) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = failure.message;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Refresh is unavailable. Cached court information may be out of date.';
        });
      }
    }
  }

  Future<void> _start() async {
    final snapshot = _snapshot, service = ref.read(courtQueueServiceProvider);
    if (snapshot == null || service == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await service.startNext(snapshot, _role);
      if (!mounted) return;
      setState(
        () => result.when(
          success: (value) {
            _snapshot = value;
            _message = value.disposition == CourtQueueDisposition.pending
                ? 'Match started locally; synchronization pending.'
                : 'Match started.';
          },
          failure: (failure) => _message = failure.message,
        ),
      );
      await ref.read(courtQueueSynchronizerProvider)?.synchronize();
      final local = ref.read(localCourtQueueRepositoryProvider);
      if (local != null) {
        final synchronized = await local.load(EventId(widget.eventId));
        if (mounted) {
          synchronized.when(
            success: (value) => setState(() {
              _snapshot = value;
              _message = value.disposition == CourtQueueDisposition.synchronized
                  ? 'Match started and synchronized.'
                  : 'Match started locally; ${_disposition(value.disposition).toLowerCase()}.';
            }),
            failure: (_) {},
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountControllerProvider);
    final organizer =
        account.snapshot?.authorization == AuthorizationState.organizer;
    ref.listen(courtQueueRefreshHintsProvider, (_, next) {
      next.whenData((_) => unawaited(_refresh()));
    });
    if (widget.organizerRoute && !organizer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'A confirmed organizer account is required to operate the court.',
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading court queue'),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return _CourtMessage(
        message: _message ?? 'Court queue unavailable.',
        onRetry: _refresh,
      );
    }
    final ordered = const CourtSchedulingPolicy().order(snapshot);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            snapshot.eventName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'One-court queue • matches start only when an organizer chooses Start next match.',
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!),
            ),
          if (snapshot.disposition != CourtQueueDisposition.synchronized)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Chip(
                avatar: const Icon(Icons.cloud_upload_outlined),
                label: Text(_disposition(snapshot.disposition)),
              ),
            ),
          const SizedBox(height: 20),
          Text('Now Playing', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (snapshot.current == null)
            const Card(
              child: ListTile(
                leading: Icon(Icons.sports_tennis),
                title: Text('Court available'),
                subtitle: Text('No match starts automatically.'),
              ),
            )
          else
            _MatchCard(
              match: snapshot.current!,
              current: true,
              onOpen: () => _openTournament(snapshot.current!),
            ),
          const SizedBox(height: 18),
          Text('Up Next', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (ordered.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No READY matches'),
                subtitle: Text(
                  'Complete or progress tournament matches, then refresh.',
                ),
              ),
            )
          else
            _MatchCard(
              match: ordered.first.match,
              emphasized: true,
              onOpen: () => _openTournament(ordered.first.match),
            ),
          if (organizer && snapshot.current == null && ordered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start next match'),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            'Remaining queue',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final item in ordered.skip(1))
            _MatchCard(
              match: item.match,
              onOpen: () => _openTournament(item.match),
            ),
          if (ordered.length <= 1)
            const Text('No additional matches are waiting.'),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh and reconcile'),
          ),
        ],
      ),
    );
  }

  void _openTournament(CourtMatchView match) {
    final base =
        '/events/${widget.eventId}/divisions/${match.match.divisionId.value}';
    context.push(switch (match.format) {
      TournamentFormat.singleElimination => '$base/bracket',
      TournamentFormat.doubleElimination => '$base/double-elimination',
      TournamentFormat.singleRoundRobin ||
      TournamentFormat.doubleRoundRobin => '$base/round-robin',
    });
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.onOpen,
    this.current = false,
    this.emphasized = false,
  });
  final CourtMatchView match;
  final VoidCallback onOpen;
  final bool current, emphasized;
  @override
  Widget build(BuildContext context) => Card(
    color: emphasized ? Theme.of(context).colorScheme.secondaryContainer : null,
    child: Semantics(
      label:
          '${current ? 'Now Playing' : 'Queued match'} ${match.sideOneLabel} versus ${match.sideTwoLabel}',
      child: ListTile(
        leading: Icon(current ? Icons.sports_tennis : Icons.schedule),
        title: Text('${match.sideOneLabel} vs ${match.sideTwoLabel}'),
        subtitle: Text(
          '${match.divisionName} • ${_format(match.format)} • Round ${match.match.roundNumber ?? '—'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    ),
  );
}

class _CourtMessage extends StatelessWidget {
  const _CourtMessage({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

String _format(TournamentFormat value) => switch (value) {
  TournamentFormat.singleElimination => 'Single Elimination',
  TournamentFormat.doubleElimination => 'Double Elimination',
  TournamentFormat.singleRoundRobin => 'Single Round Robin',
  TournamentFormat.doubleRoundRobin => 'Double Round Robin',
};

String _disposition(CourtQueueDisposition value) => switch (value) {
  CourtQueueDisposition.pending => 'Synchronization pending',
  CourtQueueDisposition.blocked => 'Authorization blocked',
  CourtQueueDisposition.failed => 'Synchronization failed',
  CourtQueueDisposition.conflicted => 'Synchronization conflict',
  CourtQueueDisposition.synchronized => 'Synchronized',
};
