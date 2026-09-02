import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/events/event_setup_models.dart';
import '../../domain/common/domain_enums.dart';
import '../accounts/account_controller.dart';
import 'organizer_event_controller.dart';

class OrganizerEventsPage extends ConsumerWidget {
  const OrganizerEventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountControllerProvider);
    if (account.snapshot?.authorization != AuthorizationState.organizer) {
      return const _OrganizerRequired();
    }
    final state = ref.watch(organizerEventControllerProvider);
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(organizerEventControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Organizer events',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              PopupMenuButton<EventType>(
                tooltip: 'Create event',
                onSelected: (type) =>
                    context.push('/organizer/events/new?type=${type.name}'),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: EventType.casual,
                    child: Text('Quick casual event'),
                  ),
                  PopupMenuItem(
                    value: EventType.formal,
                    child: Text('Formal event'),
                  ),
                ],
                child: const Chip(
                  avatar: Icon(Icons.add),
                  label: Text('Create'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.phase == OrganizerEventPhase.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state.phase == OrganizerEventPhase.unavailable)
            _Message(text: state.message ?? 'Events are unavailable.')
          else if (state.setups.isEmpty)
            const _Message(text: 'No organizer events are available yet.')
          else
            for (final setup in state.setups)
              _EventCard(
                setup: setup,
                syncStatus: state.syncStatuses[setup.event.id],
              ),
        ],
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.setup, this.syncStatus});
  final EventSetup setup;
  final EventSetupSyncStatus? syncStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = nextEventStatus(setup.event.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              setup.event.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${_label(setup.event.type)} • ${_label(setup.event.status)} • ${setup.divisions.where((d) => !d.metadata.isDeleted).length} division(s)',
            ),
            if (syncStatus != null &&
                syncStatus!.disposition !=
                    EventMutationDisposition.synchronized) ...[
              const SizedBox(height: 8),
              Semantics(
                label: 'Event synchronization status',
                child: Chip(
                  avatar: Icon(_syncIcon(syncStatus!.disposition), size: 18),
                  label: Text(_syncLabel(syncStatus!.disposition)),
                ),
              ),
              if (syncStatus!.message case final message?)
                Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (setup.hasUnconfiguredFormats &&
                setup.event.status == EventStatus.registration) ...[
              const SizedBox(height: 8),
              const Text(
                'Tournament-format configuration is coming in M12. This event cannot begin yet.',
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => context.push(
                    '/organizer/events/${setup.event.id.value}/participants',
                  ),
                  child: const Text('Manage participants'),
                ),
                if (setup.event.status == EventStatus.upcoming)
                  OutlinedButton(
                    onPressed: () => context.push(
                      '/organizer/events/${setup.event.id.value}/setup',
                    ),
                    child: const Text('Edit setup'),
                  ),
                if (next != null)
                  FilledButton.tonal(
                    onPressed: () => _confirmAdvance(context, ref, next),
                    child: Text('Advance to ${_label(next)}'),
                  ),
                OutlinedButton(
                  onPressed: () =>
                      context.push('/events/${setup.event.id.value}'),
                  child: const Text('Public details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAdvance(
    BuildContext context,
    WidgetRef ref,
    EventStatus next,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Advance to ${_label(next)}?'),
        content: Text(
          next == EventStatus.completed || next == EventStatus.archived
              ? 'The event remains preserved in history.'
              : 'Lifecycle changes move forward one step and cannot be reversed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(organizerEventControllerProvider.notifier)
        .advance(setup);
    if (!context.mounted) return;
    final message = switch (result) {
      EventSetupSaved(:final disposition) =>
        disposition == EventMutationDisposition.pending
            ? 'Lifecycle change saved locally and pending synchronization.'
            : 'Lifecycle advanced.',
      EventSetupMutationFailed(:final failure) => failure.message,
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OrganizerRequired extends StatelessWidget {
  const _OrganizerRequired();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'A confirmed organizer account is required to manage events.',
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

String _label(Enum value) => value.name
    .replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    )
    .replaceFirstMapped(
      RegExp(r'^.'),
      (match) => match.group(0)!.toUpperCase(),
    );

String _syncLabel(EventMutationDisposition disposition) =>
    switch (disposition) {
      EventMutationDisposition.pending => 'Pending synchronization',
      EventMutationDisposition.synchronized => 'Synchronized',
      EventMutationDisposition.blocked => 'Synchronization blocked',
      EventMutationDisposition.conflicted => 'Synchronization conflict',
    };

IconData _syncIcon(EventMutationDisposition disposition) =>
    switch (disposition) {
      EventMutationDisposition.pending => Icons.cloud_upload_outlined,
      EventMutationDisposition.synchronized => Icons.cloud_done_outlined,
      EventMutationDisposition.blocked => Icons.cloud_off_outlined,
      EventMutationDisposition.conflicted => Icons.warning_amber_rounded,
    };
