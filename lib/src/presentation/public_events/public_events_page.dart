import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/public_events/public_event_models.dart';
import '../../domain/common/domain_enums.dart';
import 'public_events_controller.dart';

class PublicEventsPage extends ConsumerWidget {
  const PublicEventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(publicEventsControllerProvider);
    return switch (state.phase) {
      PublicEventsPhase.loading => const _CenteredState(
        child: CircularProgressIndicator(semanticsLabel: 'Loading events'),
      ),
      PublicEventsPhase.empty => _MessageState(
        icon: Icons.event_busy,
        title: 'No public events yet',
        message: 'Check again when the next club event is announced.',
        actionLabel: 'Refresh',
        onAction: () =>
            ref.read(publicEventsControllerProvider.notifier).refresh(),
      ),
      PublicEventsPhase.error => _MessageState(
        icon: Icons.cloud_off,
        title: 'Events are temporarily unavailable',
        message: state.message ?? 'Please try again.',
        actionLabel: 'Try again',
        onAction: () =>
            ref.read(publicEventsControllerProvider.notifier).refresh(),
      ),
      PublicEventsPhase.unconfigured => const _MessageState(
        icon: Icons.settings_outlined,
        title: 'Public events are not configured',
        message: 'This build needs its public Supabase configuration before online events can load.',
      ),
      PublicEventsPhase.content => _EventCatalogView(state: state),
    };
  }
}

class _EventCatalogView extends ConsumerWidget {
  const _EventCatalogView({required this.state});

  final PublicEventsViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = state.catalog!;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(publicEventsControllerProvider.notifier).refresh(),
      child: CustomScrollView(
        key: const PageStorageKey('public-events-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Public events',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh public events',
                            onPressed: state.isRefreshing
                                ? null
                                : () => ref
                                      .read(
                                        publicEventsControllerProvider.notifier,
                                      )
                                      .refresh(),
                            icon: state.isRefreshing
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      if (state.isCached) ...[
                        const SizedBox(height: 12),
                        const _InfoBanner(
                          icon: Icons.offline_pin_outlined,
                          message: 'Showing saved event information while an online refresh is attempted.',
                        ),
                      ],
                      if (state.message case final message?) ...[
                        const SizedBox(height: 12),
                        _InfoBanner(icon: Icons.cloud_off, message: message),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          for (final group in PublicEventGroup.values)
            _EventSection(group: group, events: catalog.eventsIn(group)),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

class _EventSection extends StatelessWidget {
  const _EventSection({required this.group, required this.events});

  final PublicEventGroup group;
  final List<PublicEventItem> events;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _groupLabel(group),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No ${_groupLabel(group).toLowerCase()} events.',
                    ),
                  )
                else
                  ...events.map((item) => _EventCard(item: item)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.item});

  final PublicEventItem item;

  @override
  Widget build(BuildContext context) {
    final event = item.event;
    final divisionText = switch (item.divisions.length) {
      0 => 'No public divisions',
      1 => '1 division',
      final count => '$count divisions',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: 'Open ${event.name}',
        child: InkWell(
          onTap: () => context.go('/events/${event.id.value}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${statusLabel(event.status)} • ${formatPublicUtc(event.scheduledAt)}',
                      ),
                      const SizedBox(height: 4),
                      Text('${event.courtLabel} • $divisionText'),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 12, top: 8),
                  child: Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _CenteredState(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: child,
    ),
  );
}

String _groupLabel(PublicEventGroup group) => switch (group) {
  PublicEventGroup.current => 'Current',
  PublicEventGroup.upcoming => 'Upcoming',
  PublicEventGroup.completed => 'Completed',
};

String statusLabel(EventStatus status) => switch (status) {
  EventStatus.upcoming => 'Upcoming',
  EventStatus.registration => 'Registration open',
  EventStatus.inProgress => 'In progress',
  EventStatus.completed => 'Completed',
  EventStatus.archived => 'Archived',
};

String formatPublicUtc(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final utc = value.toUtc();
  final hour = utc.hour == 0 ? 12 : (utc.hour > 12 ? utc.hour - 12 : utc.hour);
  final minute = utc.minute.toString().padLeft(2, '0');
  final period = utc.hour >= 12 ? 'PM' : 'AM';
  return '${months[utc.month - 1]} ${utc.day}, ${utc.year} • $hour:$minute $period UTC';
}
