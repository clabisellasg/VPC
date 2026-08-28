import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/accounts/auth_models.dart';
import 'account_controller.dart';
import 'auth_controller.dart';

class OrganizerClaimsPage extends ConsumerStatefulWidget {
  const OrganizerClaimsPage({super.key});

  @override
  ConsumerState<OrganizerClaimsPage> createState() =>
      _OrganizerClaimsPageState();
}

class _OrganizerClaimsPageState extends ConsumerState<OrganizerClaimsPage> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).session;
    final account = ref.watch(accountControllerProvider);
    if (auth is! AuthAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/account/sign-in?from=%2Forganizer%2Fclaims');
        }
      });
      return const Center(child: CircularProgressIndicator());
    }
    if (account.phase == AccountPhase.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (account.snapshot?.authorization != AuthorizationState.organizer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Organizer permission is required to review claims.'),
        ),
      );
    }
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(accountControllerProvider.notifier).loadPendingClaims();
      });
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(accountControllerProvider.notifier).loadPendingClaims(),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Player claims',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Review links between private accounts and existing permanent players.',
          ),
          if (account.isWorking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (account.message != null) ...[
            const SizedBox(height: 12),
            Text(
              account.message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          if (!account.isWorking && account.pendingClaims.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No pending player claims.'),
              ),
            ),
          ...account.pendingClaims.map(
            (claim) => _ClaimReviewCard(claim: claim),
          ),
        ],
      ),
    );
  }
}

class _ClaimReviewCard extends ConsumerWidget {
  const _ClaimReviewCard({required this.claim});

  final PlayerClaim claim;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            claim.playerDisplayName ?? 'Unavailable player',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Requested by ${claim.claimantDisplayName ?? 'Community member'}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _approve(context, ref),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: () => _reject(context, ref),
                icon: const Icon(Icons.close),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve this player link?'),
        content: const Text(
          'Approval atomically links the account to the permanent player and cannot be edited in this milestone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve link'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(accountControllerProvider.notifier).approve(claim.id);
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject claim?'),
        content: TextField(
          controller: reason,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject claim'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(accountControllerProvider.notifier)
          .reject(claim.id, reason: reason.text);
    }
    reason.dispose();
  }
}
