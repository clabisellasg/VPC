import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/public_events/public_event_models.dart';
import '../../domain/common/domain_enums.dart';
import 'public_events_controller.dart';
import 'public_events_page.dart';

class PublicEventDetailsPage extends ConsumerWidget {
  const PublicEventDetailsPage({required this.eventId, super.key});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(publicEventsControllerProvider);
    final item = state.catalog?.eventById(eventId);
    if (item != null) {
      return _Details(item: item);
    }
    if (state.phase == PublicEventsPhase.loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading event'),
      );
    }
    if (state.phase == PublicEventsPhase.error ||
        state.phase == PublicEventsPhase.unconfigured) {
      return _MissingEvent(
        title: 'Event unavailable',
        message: state.message ?? 'This event could not be loaded.',
      );
    }
    return const _MissingEvent(
      title: 'Event not found',
      message: 'This public event is unavailable or no longer listed.',
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.item});

  final PublicEventItem item;

  @override
  Widget build(BuildContext context) {
    final event = item.event;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _backToEvents(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to events'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                event.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(statusLabel(event.status))),
                  Chip(label: Text(_eventTypeLabel(event.type))),
                ],
              ),
              const SizedBox(height: 20),
              _DetailRow(
                icon: Icons.schedule,
                label: 'Date and time',
                value: formatPublicUtc(event.scheduledAt),
              ),
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Court',
                value: event.courtLabel,
              ),
              const SizedBox(height: 28),
              Text('Divisions', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (item.divisions.isEmpty)
                const Text('No public divisions are listed for this event.')
              else
                ...item.divisions.map(
                  (division) => Card(
                    child: ListTile(
                      title: Text(division.name),
                      subtitle: Text(
                        division.format == null
                            ? 'Format not configured yet'
                            : _formatLabel(division.format!),
                      ),
                      leading: const Icon(Icons.groups_outlined),
                      trailing:
                          division.format ==
                                  TournamentFormat.singleElimination ||
                              division.format ==
                                  TournamentFormat.singleRoundRobin ||
                              division.format ==
                                  TournamentFormat.doubleRoundRobin
                          ? const Icon(Icons.account_tree_outlined)
                          : null,
                      onTap:
                          division.format !=
                                  TournamentFormat.singleElimination &&
                              division.format !=
                                  TournamentFormat.singleRoundRobin &&
                              division.format !=
                                  TournamentFormat.doubleRoundRobin
                          ? null
                          : () => context.push(
                              division.format ==
                                      TournamentFormat.singleElimination
                                  ? '/events/${event.id.value}/divisions/${division.id.value}/bracket'
                                  : division.format ==
                                            TournamentFormat.singleRoundRobin ||
                                        division.format ==
                                            TournamentFormat.doubleRoundRobin
                                  ? '/events/${event.id.value}/divisions/${division.id.value}/round-robin'
                                  : '/events/${event.id.value}',
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, semanticLabel: label),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(value),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MissingEvent extends StatelessWidget {
  const _MissingEvent({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_busy, size: 48),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.go('/events'),
            child: const Text('View public events'),
          ),
        ],
      ),
    ),
  );
}

void _backToEvents(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/events');
  }
}

String _eventTypeLabel(EventType type) => switch (type) {
  EventType.casual => 'Casual event',
  EventType.formal => 'Formal event',
};

String _formatLabel(TournamentFormat format) => switch (format) {
  TournamentFormat.singleElimination => 'Single elimination',
  TournamentFormat.doubleElimination => 'Double elimination',
  TournamentFormat.singleRoundRobin => 'Single round robin',
  TournamentFormat.doubleRoundRobin => 'Double round robin',
};
