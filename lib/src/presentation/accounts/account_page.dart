import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/accounts/auth_models.dart';
import 'account_controller.dart';
import 'auth_controller.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final account = ref.watch(accountControllerProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Account', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        switch (auth.session) {
          AuthRestoring() => const _LoadingAccount(),
          AuthUnconfigured() => const _AccountMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Account services are not configured',
            body: 'Public event browsing remains available in this build.',
          ),
          AuthAwaitingEmailConfirmation(:final email) => _AccountMessage(
            icon: Icons.mark_email_read_outlined,
            title: 'Check your email',
            body: 'Confirmation guidance was sent to $email.',
          ),
          AuthAuthenticated(:final user) => _AuthenticatedAccount(
            email: user.email,
            state: account,
          ),
          _ => const _SignedOutAccount(),
        },
      ],
    );
  }
}

class _SignedOutAccount extends StatelessWidget {
  const _SignedOutAccount();

  @override
  Widget build(BuildContext context) => _AccountMessage(
    icon: Icons.account_circle_outlined,
    title: 'No account required for public events',
    body: 'Sign in to view a private account or request a link to an existing community player.',
    actions: [
      FilledButton(
        onPressed: () => context.go('/account/sign-in'),
        child: const Text('Sign in'),
      ),
      OutlinedButton(
        onPressed: () => context.go('/account/register'),
        child: const Text('Register'),
      ),
    ],
  );
}

class _AuthenticatedAccount extends ConsumerWidget {
  const _AuthenticatedAccount({required this.email, required this.state});

  final String email;
  final AccountViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.phase == AccountPhase.loading) {
      return const _LoadingAccount();
    }
    if (state.phase == AccountPhase.unavailable) {
      return _AccountMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Account status unavailable',
        body: 'You may be offline. Cached role information is not treated as authority.',
        actions: [
          OutlinedButton(
            onPressed: () =>
                ref.read(accountControllerProvider.notifier).refresh(),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    final snapshot = state.snapshot;
    if (snapshot == null) {
      return const _LoadingAccount();
    }
    final role = switch (snapshot.authorization) {
      AuthorizationState.organizer => 'Organizer',
      AuthorizationState.member => 'Member',
      _ => 'Authorization unavailable',
    };
    final claim = snapshot.claim;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              snapshot.profile.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(email),
            const SizedBox(height: 12),
            Chip(
              label: Text(role),
              avatar: const Icon(Icons.verified_user_outlined),
            ),
            const Divider(height: 32),
            Text(
              'Player identity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (snapshot.profile.playerId != null) ...[
              const Text('Linked to an existing permanent community player.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    context.go('/players/${snapshot.profile.playerId!.value}'),
                icon: const Icon(Icons.person_outline),
                label: const Text('Open public player profile'),
              ),
            ] else if (claim != null)
              Text('Claim status: ${_claimLabel(claim.status)}')
            else
              const Text('No permanent player is linked to this account.'),
            const SizedBox(height: 16),
            if (snapshot.profile.playerId == null)
              FilledButton.tonalIcon(
                onPressed: () => context.go('/account/claim'),
                icon: const Icon(Icons.link),
                label: Text(
                  claim == null ? 'Claim an existing player' : 'View claim',
                ),
              ),
            if (snapshot.authorization == AuthorizationState.organizer) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.go('/organizer/claims'),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review player claims'),
              ),
            ],
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

String _claimLabel(PlayerClaimStatus status) => switch (status) {
  PlayerClaimStatus.pending => 'Pending organizer review',
  PlayerClaimStatus.approved => 'Approved',
  PlayerClaimStatus.rejected => 'Rejected',
  PlayerClaimStatus.cancelled => 'Cancelled',
};

class _LoadingAccount extends StatelessWidget {
  const _LoadingAccount();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: CircularProgressIndicator(),
    ),
  );
}

class _AccountMessage extends StatelessWidget {
  const _AccountMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    ),
  );
}
