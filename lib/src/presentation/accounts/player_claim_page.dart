import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/accounts/auth_models.dart';
import '../../domain/players/permanent_player.dart';
import 'account_controller.dart';
import 'auth_controller.dart';

class PlayerClaimPage extends ConsumerStatefulWidget {
  const PlayerClaimPage({super.key});

  @override
  ConsumerState<PlayerClaimPage> createState() => _PlayerClaimPageState();
}

class _PlayerClaimPageState extends ConsumerState<PlayerClaimPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).session;
    if (auth is! AuthAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/account/sign-in?from=%2Faccount%2Fclaim');
        }
      });
      return const Center(child: CircularProgressIndicator());
    }
    final state = ref.watch(accountControllerProvider);
    final snapshot = state.snapshot;
    if (state.phase == AccountPhase.loading || snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.profile.playerId != null) {
      return const _ClaimMessage(
        title: 'Player already linked',
        body: 'This account is linked to an existing permanent player.',
      );
    }
    final claim = snapshot.claim;
    if (claim != null && claim.status == PlayerClaimStatus.pending) {
      return _ClaimMessage(
        title: 'Claim pending',
        body:
            'An organizer must review your request for ${claim.playerDisplayName ?? 'the selected player'}.',
        action: OutlinedButton(
          onPressed: state.isWorking
              ? null
              : () => ref
                    .read(accountControllerProvider.notifier)
                    .cancelClaim(claim.id),
          child: const Text('Cancel pending claim'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Claim a player',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Select your existing permanent community player. An organizer must approve the link.',
        ),
        const SizedBox(height: 16),
        SearchBar(
          controller: _search,
          hintText: 'Search player names',
          leading: const Icon(Icons.search),
          onSubmitted: (value) =>
              ref.read(accountControllerProvider.notifier).searchPlayers(value),
          trailing: [
            IconButton(
              tooltip: 'Search players',
              onPressed: state.isWorking
                  ? null
                  : () => ref
                        .read(accountControllerProvider.notifier)
                        .searchPlayers(_search.text),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
        if (state.message != null) ...[
          const SizedBox(height: 12),
          Text(
            state.message!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        if (state.isWorking) const LinearProgressIndicator(),
        if (!state.isWorking && state.players.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Search to find an unclaimed permanent player.'),
          ),
        ...state.players.map((player) => _PlayerCard(player: player)),
      ],
    );
  }
}

class _PlayerCard extends ConsumerWidget {
  const _PlayerCard({required this.player});

  final PermanentPlayer player;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(player.displayName),
      subtitle: const Text('Permanent community player'),
      trailing: FilledButton(
        onPressed: () => _confirm(context, ref),
        child: const Text('Request'),
      ),
    ),
  );

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request player link?'),
        content: Text(
          'Request organizer approval to link this account to ${player.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await ref.read(accountControllerProvider.notifier).submitClaim(player.id);
    }
  }
}

class _ClaimMessage extends StatelessWidget {
  const _ClaimMessage({required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(body, textAlign: TextAlign.center),
                if (action != null) ...[const SizedBox(height: 16), action!],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
