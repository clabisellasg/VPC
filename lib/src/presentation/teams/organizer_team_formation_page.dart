import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/teams/team_formation_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/players/player_skill.dart';
import '../../infrastructure/teams/team_formation_providers.dart';
import '../accounts/account_controller.dart';

class OrganizerTeamFormationPage extends ConsumerStatefulWidget {
  const OrganizerTeamFormationPage({
    required this.eventId,
    required this.divisionId,
    super.key,
  });
  final String eventId;
  final String divisionId;
  @override
  ConsumerState<OrganizerTeamFormationPage> createState() =>
      _OrganizerTeamFormationPageState();
}

class _OrganizerTeamFormationPageState
    extends ConsumerState<OrganizerTeamFormationPage> {
  TeamFormationSnapshot? _snapshot;
  TeamFormationPreview? _preview;
  bool _loading = true;
  String? _message;
  final _selected = <PlayerId>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    await ref.read(teamFormationRealtimeRuntimeProvider)?.start();
    final store = ref.read(teamFormationStoreProvider);
    if (store == null) {
      setState(() {
        _loading = false;
        _message = 'Team formation is not configured.';
      });
      return;
    }
    try {
      await _loadSnapshot();
      final synchronizer = ref.read(teamFormationSynchronizerProvider);
      if (synchronizer != null) {
        await synchronizer.synchronizeDivision(
          EventId(widget.eventId),
          DivisionId(widget.divisionId),
        );
        if (mounted) await _loadSnapshot();
      }
    } catch (_) {
      if (mounted && _snapshot == null) {
        setState(() {
          _loading = false;
          _message = 'This division is not available.';
        });
      }
    }
  }

  Future<void> _loadSnapshot() async {
    final result = await ref
        .read(teamFormationStoreProvider)!
        .load(EventId(widget.eventId), DivisionId(widget.divisionId));
    if (!mounted) return;
    result.when(
      success: (value) => setState(() {
        _snapshot = value;
        _loading = false;
        _message = null;
      }),
      failure: (failure) => setState(() {
        _loading = false;
        _message = failure.message;
      }),
    );
  }

  void _random() => setState(() {
    _preview = ref
        .read(teamFormationServiceProvider)!
        .randomPreview(_snapshot!);
    _message = null;
  });
  void _balanced() => setState(() {
    _preview = ref
        .read(teamFormationServiceProvider)!
        .balancedPreview(_snapshot!);
    _message = null;
  });
  void _manual() {
    if (_selected.length != 2) {
      setState(() => _message = 'Select exactly two unassigned players.');
      return;
    }
    final values = _snapshot!.eligiblePlayers
        .where((p) => _selected.contains(p.playerId))
        .toList();
    try {
      setState(() {
        _preview = ref
            .read(teamFormationServiceProvider)!
            .manual(_snapshot!, values[0], values[1], currentPreview: _preview);
        _selected.clear();
        _message = null;
      });
    } catch (error) {
      setState(() => _message = error.toString());
    }
  }

  Future<void> _confirm() async {
    final result = await ref
        .read(teamFormationServiceProvider)!
        .confirm(_snapshot!, _preview!);
    if (!mounted) return;
    result.when(
      success: (value) => setState(() {
        _snapshot = value;
        _preview = null;
        _selected.clear();
        _message = value.disposition == TeamMutationDisposition.pending
            ? 'Saved locally. Cloud synchronization is pending.'
            : 'Team formation saved.';
      }),
      failure: (failure) => setState(() => _message = failure.message),
    );
    await ref.read(teamFormationSynchronizerProvider)?.synchronize();
    if (mounted) await _load();
  }

  void _releaseTeam(TeamId teamId) => setState(() {
    _preview = ref
        .read(teamFormationServiceProvider)!
        .releaseTeam(_snapshot!, teamId);
    _selected.clear();
    _message = 'Review the replacement, then confirm to return this team to Unassigned.';
  });

  void _undoPreviewPair(TeamId teamId) => setState(() {
    _preview = ref
        .read(teamFormationServiceProvider)!
        .removePreviewTeam(_snapshot!, _preview!, teamId);
    _selected.clear();
    _message = 'Pair removed from the preview. Select players to pair again.';
  });

  void _resetPreview() => setState(() {
    _preview = null;
    _selected.clear();
    _message = 'Unconfirmed pairing changes were discarded.';
  });

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
    if (_snapshot == null) {
      return Center(child: Text(_message ?? 'Team formation unavailable.'));
    }
    final displayedTeams = _preview?.teams ?? _snapshot!.teams;
    final assigned = displayedTeams
        .expand((t) => t.players)
        .map((p) => p.playerId)
        .toSet();
    final unassigned =
        _preview?.unassigned ??
        _snapshot!.eligiblePlayers
            .where((p) => !assigned.contains(p.playerId))
            .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Team formation',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          'Teams are temporary and belong only to this division. ${_snapshot!.eventStatus.name == 'registration' ? '' : 'Formation is locked.'}',
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_message!),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: _manual, child: const Text('Manual pair')),
            OutlinedButton(
              onPressed: _random,
              child: const Text('Random preview'),
            ),
            OutlinedButton(
              onPressed: _balanced,
              child: const Text('Balanced preview'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Unassigned', style: Theme.of(context).textTheme.titleLarge),
        for (final player in unassigned)
          CheckboxListTile(
            value: _selected.contains(player.playerId),
            onChanged: (value) => setState(
              () => value == true
                  ? _selected.add(player.playerId)
                  : _selected.remove(player.playerId),
            ),
            title: Text(player.displayName),
            subtitle: Text(
              '${playerSkillLabel(player.skill)} • ${player.paid ? 'Paid' : 'Unpaid'}',
            ),
          ),
        Text('Current teams', style: Theme.of(context).textTheme.titleLarge),
        for (var i = 0; i < _snapshot!.teams.length; i++)
          ListTile(
            title: Text('Team ${i + 1}'),
            subtitle: Text(
              _snapshot!.teams[i].players.map((p) => p.displayName).join(' + '),
            ),
            trailing: TextButton(
              onPressed: _snapshot!.eventStatus == EventStatus.registration
                  ? () => _releaseTeam(_snapshot!.teams[i].id)
                  : null,
              child: const Text('Return to Unassigned'),
            ),
          ),
        if (_preview != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_preview!.method.name} preview',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_preview!.unrated.isNotEmpty) ...[
                    Text(
                      'Rate every eligible player before balanced generation: ${_preview!.unrated.map((p) => p.displayName).join(', ')}',
                    ),
                    for (final player in _preview!.unrated)
                      TextButton(
                        onPressed: () => context.push(
                          '/organizer/players/${player.playerId.value}/skill',
                        ),
                        child: Text('Rate ${player.displayName}'),
                      ),
                  ] else ...[
                    for (var i = 0; i < _preview!.teams.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Team ${i + 1}: ${_preview!.teams[i].players.map((p) => p.displayName).join(' + ')}${_preview!.teams[i].strength == null ? '' : ' • strength ${_preview!.teams[i].strength}'}',
                        ),
                        trailing: _preview!.method == TeamFormationMethod.manual
                            ? TextButton(
                                onPressed: () =>
                                    _undoPreviewPair(_preview!.teams[i].id),
                                child: const Text('Undo pair'),
                              )
                            : null,
                      ),
                    if (_preview!.unassigned.isNotEmpty)
                      Text(
                        _preview!.unassigned.length == 1
                            ? 'Odd player remains Unassigned: ${_preview!.unassigned.single.displayName}'
                            : 'Players remain Unassigned: ${_preview!.unassigned.map((player) => player.displayName).join(', ')}',
                      ),
                    if (_preview!.spread != null)
                      Text('Balance spread: ${_preview!.spread}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _preview!.teams.isEmpty ? null : _confirm,
                          child: const Text('Confirm replacement'),
                        ),
                        TextButton(
                          onPressed: _resetPreview,
                          child: const Text('Reset preview'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
