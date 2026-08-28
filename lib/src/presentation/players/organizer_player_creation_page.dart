import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/players/player_directory_models.dart';
import '../accounts/account_controller.dart';
import 'player_creation_controller.dart';

class OrganizerPlayerCreationPage extends ConsumerStatefulWidget {
  const OrganizerPlayerCreationPage({super.key});

  @override
  ConsumerState<OrganizerPlayerCreationPage> createState() =>
      _OrganizerPlayerCreationPageState();
}

class _OrganizerPlayerCreationPageState
    extends ConsumerState<OrganizerPlayerCreationPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountControllerProvider);
    if (account.snapshot?.authorization != AuthorizationState.organizer) {
      return const _OrganizerRequired();
    }
    final state = ref.watch(playerCreationControllerProvider);
    ref.listen(playerCreationControllerProvider, (previous, next) {
      if (next.phase == PlayerCreationPhase.created &&
          previous?.phase != PlayerCreationPhase.created) {
        final created = next.created!;
        final wording = created.disposition == PlayerCreationDisposition.pending
            ? 'Player saved locally and pending cloud synchronization.'
            : 'Player created and synchronized.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(wording)));
        context.go('/players/${created.profile.id.value}');
      }
    });
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Add permanent player',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Create one reusable community identity. Check for an existing record first so history stays together.',
        ),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _name,
            autofocus: true,
            enabled: state.phase != PlayerCreationPhase.submitting,
            decoration: const InputDecoration(
              labelText: 'Public display name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            validator: (value) {
              try {
                preparePlayerDisplayName(value ?? '');
                return null;
              } on Exception {
                return 'Enter a display name.';
              }
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        if (state.phase == PlayerCreationPhase.error) ...[
          const SizedBox(height: 12),
          Text(
            state.message ?? 'The player could not be created.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: state.phase == PlayerCreationPhase.submitting
              ? null
              : _submit,
          child: state.phase == PlayerCreationPhase.submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Check and create'),
        ),
        if (state.phase == PlayerCreationPhase.duplicateWarning) ...[
          const SizedBox(height: 24),
          _DuplicateWarning(
            candidates: state.candidates,
            onCreateSeparate: _confirmSeparate,
          ),
        ],
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(playerCreationControllerProvider.notifier).submit(_name.text);
  }

  Future<void> _confirmSeparate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a separate player?'),
        content: const Text(
          'Two people can share a name, but separate records split their histories. Confirm only when this is a different person.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create separate player'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(playerCreationControllerProvider.notifier)
          .submit(_name.text, acknowledgeDuplicate: true);
    }
  }
}

class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({
    required this.candidates,
    required this.onCreateSeparate,
  });

  final List<PublicPlayerProfile> candidates;
  final VoidCallback onCreateSeparate;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A player with this name may already exist',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Reusing the existing permanent record preserves history. Different people may legitimately share the same name.',
          ),
          const SizedBox(height: 12),
          for (final candidate in candidates)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(candidate.displayName),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => context.go('/players/${candidate.id.value}'),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => context.go('/players'),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: onCreateSeparate,
                child: const Text('Create a different person'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _OrganizerRequired extends StatelessWidget {
  const _OrganizerRequired();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            'Organizer access required',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'A currently confirmed organizer account is required to create a permanent player.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
