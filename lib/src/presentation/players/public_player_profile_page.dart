import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/players/player_directory_models.dart';
import '../../application/history/player_history_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/player_skill.dart';
import '../../infrastructure/players/player_directory_providers.dart';
import '../../infrastructure/history/player_history_providers.dart';
import '../accounts/account_controller.dart';

final publicPlayerProfileProvider = FutureProvider.autoDispose
    .family<RepositoryResult<PlayerDirectoryEntry>, PlayerId>(
      (ref, id) => ref.watch(playerDirectoryReaderProvider).getById(id),
    );

final publicPlayerHistoryProvider = FutureProvider.autoDispose
    .family<RepositoryResult<PlayerHistorySnapshot>?, PlayerId>((ref, id) {
      final reader = ref.watch(playerHistoryReaderProvider);
      return reader?.read(id);
    });

class PublicPlayerProfilePage extends ConsumerWidget {
  const PublicPlayerProfilePage({required this.playerId, super.key});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    PlayerId id;
    try {
      id = PlayerId(playerId);
    } on Exception {
      return const _MissingPlayer();
    }
    final result = ref.watch(publicPlayerProfileProvider(id));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        result.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const _MissingPlayer(),
          data: (repositoryResult) => repositoryResult.when(
            success: (entry) => _Profile(entry: entry),
            failure: (_) => const _MissingPlayer(),
          ),
        ),
      ],
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.entry});

  final PlayerDirectoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizer =
        ref.watch(accountControllerProvider).snapshot?.authorization ==
        AuthorizationState.organizer;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.account_circle_outlined, size: 56),
            const SizedBox(height: 12),
            Text(
              entry.profile.displayName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Permanent community player record',
              semanticsLabel: 'Permanent community player profile',
            ),
            const SizedBox(height: 8),
            Text('Community skill: ${playerSkillLabel(entry.profile.skill)}'),
            if (organizer) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push(
                  '/organizer/players/${entry.profile.id.value}/skill',
                ),
                icon: const Icon(Icons.tune),
                label: const Text('Edit community skill'),
              ),
            ],
            if (organizer &&
                entry.syncState != PlayerSyncPresentation.synchronized) ...[
              const Divider(height: 32),
              Text(_organizerSyncMessage(entry.syncState)),
            ],
            const Divider(height: 32),
            _HistorySection(playerId: entry.profile.id),
          ],
        ),
      ),
    );
  }
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.playerId});
  final PlayerId playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(publicPlayerHistoryProvider(playerId));
    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Loading history…'),
      ),
      error: (_, _) => const Text(
        'History is temporarily unavailable. Pull to refresh and try again.',
      ),
      data: (result) {
        if (result == null) {
          return const Text(
            'History is unavailable until online data is configured.',
          );
        }
        return result.when(
          failure: (failure) => Text(
            failure is RemoteReadFailure
                ? '${failure.message} Pull to refresh and try again.'
                : 'History is temporarily unavailable. Pull to refresh and try again.',
          ),
          success: (snapshot) => _HistoryContents(snapshot: snapshot),
        );
      },
    );
  }
}

class _HistoryContents extends StatelessWidget {
  const _HistoryContents({required this.snapshot});
  final PlayerHistorySnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final s = snapshot.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Career summary', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '${s.matchesPlayed} matches · ${s.wins} wins · ${s.losses} losses · ${s.winRate.toStringAsFixed(0)}% win rate',
        ),
        Text(
          '${s.eventAppearances} event appearances · ${s.divisionAppearances} division appearances',
        ),
        Text(
          '${s.championships} championships · ${s.runnerUpFinishes} runner-up finishes',
        ),
        Text(
          '${s.pointsFor} points for · ${s.pointsAgainst} against · ${s.pointDifferential >= 0 ? '+' : ''}${s.pointDifferential} differential',
        ),
        if (snapshot.hasPendingSync)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Includes local results pending synchronization.'),
          ),
        if (snapshot.hasConflict)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'A synchronization conflict may affect these local totals.',
            ),
          ),
        const Divider(height: 32),
        Text('Recent matches', style: Theme.of(context).textTheme.titleMedium),
        if (snapshot.matches.entries.isEmpty)
          const Text('No completed matches yet.'),
        ...snapshot.matches.entries.map(
          (match) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${match.won ? 'Won' : 'Lost'} ${match.pointsFor}–${match.pointsAgainst} · ${match.opponentName}',
            ),
            subtitle: Text('${match.eventName} · ${match.divisionName}'),
          ),
        ),
        const Divider(height: 32),
        Text(
          'Partner statistics',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (snapshot.partners.isEmpty)
          const Text('No completed partnerships yet.'),
        ...snapshot.partners.map(
          (partner) => Text(
            '${partner.partnerName}: ${partner.wins}–${partner.losses} (${partner.winRate.toStringAsFixed(0)}%)',
          ),
        ),
      ],
    );
  }
}

String _organizerSyncMessage(PlayerSyncPresentation state) => switch (state) {
  PlayerSyncPresentation.synchronized => 'Synchronized',
  PlayerSyncPresentation.pending => 'Pending cloud synchronization.',
  PlayerSyncPresentation.authorizationBlocked =>
    'Waiting for confirmed organizer authorization.',
  PlayerSyncPresentation.failed => 'Synchronization needs attention.',
  PlayerSyncPresentation.conflicted =>
    'A synchronization conflict is preserved and has not been resolved.',
};

class _MissingPlayer extends StatelessWidget {
  const _MissingPlayer();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.person_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'Player not available',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'This permanent player record is missing or no longer public.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
