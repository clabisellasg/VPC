import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/accounts/account_models.dart';
import '../../application/sync/operational_sync.dart';
import '../accounts/account_controller.dart';
import 'operational_sync_controller.dart';

class OperationalSyncPage extends ConsumerWidget {
  const OperationalSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountControllerProvider).snapshot;
    if (account?.authorization != AuthorizationState.organizer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'A confirmed organizer session is required to manage synchronization.',
          ),
        ),
      );
    }
    final async = ref.watch(operationalSyncControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronization')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Error(
          onRetry: () => ref.invalidate(operationalSyncControllerProvider),
        ),
        data: (snapshot) => RefreshIndicator(
          onRefresh: () => ref
              .read(operationalSyncControllerProvider.notifier)
              .refresh(synchronize: true),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Summary(snapshot: snapshot),
              const SizedBox(height: 16),
              if (snapshot.items.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.cloud_done_outlined),
                    title: Text('All local work is synchronized'),
                    subtitle: Text(
                      'No pending, blocked, failed, or conflicting operations remain.',
                    ),
                  ),
                )
              else
                ...snapshot.items.map((item) => _OperationCard(item: item)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: async.asData?.value.isSynchronizing == true
            ? null
            : () => ref
                  .read(operationalSyncControllerProvider.notifier)
                  .refresh(synchronize: true),
        icon: const Icon(Icons.sync),
        label: const Text('Retry now'),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.snapshot});
  final OperationalSyncSnapshot snapshot;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.isOffline
                ? 'Offline — local work is safe'
                : snapshot.isSynchronizing
                ? 'Synchronizing…'
                : 'Synchronization status',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${snapshot.pendingCount} pending · ${snapshot.conflictCount} conflicts',
          ),
          Text(
            snapshot.lastSuccessfulSync == null
                ? 'No completed pull checkpoint yet.'
                : 'Last successful pull: ${_displayTime(snapshot.lastSuccessfulSync!)}',
          ),
        ],
      ),
    ),
  );
}

String _displayTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
      ? local.hour - 12
      : local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour:$minute $period';
}

class _OperationCard extends ConsumerWidget {
  const _OperationCard({required this.item});
  final OperationalSyncItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(_streamLabel(item.stream)),
          const SizedBox(height: 8),
          Chip(
            avatar: Icon(_icon(item.state), size: 18),
            label: Text(_stateLabel(item.state)),
          ),
          if (item.message != null) Text(item.message!),
          if (item.isConflict) ...[
            const SizedBox(height: 8),
            const Text(
              'Another organizer changed this record first. Choose the cloud version, or revalidate and submit your local intent as a new operation.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _confirm(
                    context,
                    'Use cloud version?',
                    'This cancels the conflicting local intent and refreshes authoritative cloud data.',
                    () => ref
                        .read(operationalSyncControllerProvider.notifier)
                        .useCloud(item.operationId),
                  ),
                  child: const Text('Use cloud version'),
                ),
                FilledButton.tonal(
                  onPressed: () => _confirm(
                    context,
                    'Reapply local change?',
                    'The command will receive a new operation identity and be checked again against current cloud rules.',
                    () => ref
                        .read(operationalSyncControllerProvider.notifier)
                        .reapply(item.operationId),
                  ),
                  child: const Text('Reapply local change'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

Future<void> _confirm(
  BuildContext context,
  String title,
  String body,
  Future<void> Function() action,
) async {
  final accepted =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  if (!accepted || !context.mounted) return;
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The conflict changed or could not be resolved safely. Refresh and try again.',
          ),
        ),
      );
    }
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton(onPressed: onRetry, child: const Text('Try again')),
  );
}

String _streamLabel(OperationalSyncStream s) => switch (s) {
  OperationalSyncStream.players => 'Player directory',
  OperationalSyncStream.events => 'Event setup',
  OperationalSyncStream.participation => 'Participation and payment',
  OperationalSyncStream.teams => 'Teams',
  OperationalSyncStream.singleElimination => 'Single elimination',
  OperationalSyncStream.roundRobin => 'Round robin',
  OperationalSyncStream.doubleElimination => 'Double elimination',
  OperationalSyncStream.courtQueue => 'Court queue',
};
String _stateLabel(OperationalSyncState s) => switch (s) {
  OperationalSyncState.pending => 'Pending',
  OperationalSyncState.uploading => 'Uploading',
  OperationalSyncState.failed => 'Retryable failure',
  OperationalSyncState.authorizationBlocked => 'Authorization blocked',
  OperationalSyncState.conflicted => 'Conflict preserved',
};
IconData _icon(OperationalSyncState s) => switch (s) {
  OperationalSyncState.pending => Icons.schedule,
  OperationalSyncState.uploading => Icons.sync,
  OperationalSyncState.failed => Icons.cloud_off,
  OperationalSyncState.authorizationBlocked => Icons.lock_outline,
  OperationalSyncState.conflicted => Icons.compare_arrows,
};
