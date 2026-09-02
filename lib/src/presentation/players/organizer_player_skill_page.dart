import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/accounts/account_models.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/players/player_skill.dart';
import '../../infrastructure/players/player_directory_providers.dart';
import '../accounts/account_controller.dart';

class OrganizerPlayerSkillPage extends ConsumerStatefulWidget {
  const OrganizerPlayerSkillPage({required this.playerId, super.key});
  final String playerId;
  @override
  ConsumerState<OrganizerPlayerSkillPage> createState() =>
      _OrganizerPlayerSkillPageState();
}

class _OrganizerPlayerSkillPageState
    extends ConsumerState<OrganizerPlayerSkillPage> {
  int? _value;
  String? _name;
  String? _message;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final result = await ref
          .read(playerDirectoryReaderProvider)
          .getById(PlayerId(widget.playerId));
      if (!mounted) return;
      result.when(
        success: (entry) => setState(() {
          _name = entry.profile.displayName;
          _value = entry.profile.skill?.value;
          _loading = false;
        }),
        failure: (failure) => setState(() {
          _message = failure.message;
          _loading = false;
        }),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Player not available.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final result = await ref
        .read(playerSkillEditorProvider)
        .update(
          PlayerId(widget.playerId),
          _value == null ? null : PlayerSkill(_value!),
        );
    if (!mounted) {
      return;
    }
    result.when(
      success: (_) => setState(() => _message = 'Community skill saved.'),
      failure: (failure) => setState(() => _message = failure.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountControllerProvider).snapshot?.authorization !=
        AuthorizationState.organizer) {
      return const Center(
        child: Text('A confirmed organizer account is required.'),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Player skill', style: Theme.of(context).textTheme.headlineMedium),
        Text(_name ?? 'Player'),
        const SizedBox(height: 16),
        DropdownButtonFormField<int?>(
          initialValue: _value,
          decoration: const InputDecoration(labelText: 'Community skill'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Unrated')),
            for (var i = 1; i <= 5; i++)
              DropdownMenuItem(
                value: i,
                child: Text('$i — ${PlayerSkill(i).label}'),
              ),
          ],
          onChanged: (value) => setState(() => _value = value),
        ),
        const SizedBox(height: 12),
        const Text(
          'This is an approximate community-organizing aid, not an official competitive rating.',
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_message!),
          ),
        FilledButton(onPressed: _save, child: const Text('Save skill')),
      ],
    );
  }
}
