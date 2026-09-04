import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/events/event_setup_models.dart';
import '../../application/players/player_directory_models.dart';
import '../../application/participation/participation_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/repository_result.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import '../../infrastructure/participation/participation_providers.dart';
import '../../infrastructure/players/player_directory_providers.dart';
import '../accounts/account_controller.dart';

class AddParticipantPage extends ConsumerStatefulWidget {
  const AddParticipantPage({required this.eventId, super.key});
  final String eventId;
  @override
  ConsumerState<AddParticipantPage> createState() => _AddParticipantPageState();
}

class _AddParticipantPageState extends ConsumerState<AddParticipantPage> {
  final _search = TextEditingController();
  EventSetup? _setup;
  List<PlayerDirectoryEntry> _players = const [];
  List<ParticipationRecord> _registered = const [];
  final _selected = <PlayerId, PlayerDirectoryEntry>{};
  final _recentlyAdded = <PlayerId>{};
  final _divisions = <DivisionId>{};
  String? _message;
  bool _working = false;
  bool _finding = false;
  int _searchRequest = 0;
  PlayerDirectoryCursor? _nextCursor;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _searchRequest++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = EventId(widget.eventId);
      final setupResult = await ref.read(eventSetupStoreProvider)!.getSetup(id);
      if (setupResult case RepositorySuccess(:final value)) _setup = value;
      await _find();
    } catch (_) {
      if (mounted) setState(() => _message = 'Registration is unavailable.');
    }
  }

  Future<void> _find({bool more = false}) async {
    final request = ++_searchRequest;
    final reader = ref.read(playerDirectoryReaderProvider);
    final store = ref.read(participationStoreProvider);
    final query = PlayerDirectoryQuery(
      searchText: _search.text,
      after: more ? _nextCursor : null,
    );
    setState(() {
      _finding = true;
    });
    try {
      if (store == null) {
        throw const PersistenceUnavailableFailure(
          message: 'Participation unavailable',
        );
      }
      final roster = (await store.listForEvent(EventId(widget.eventId)))
          .when(success: (value) => value, failure: (failure) => throw failure);
      final registered = roster
          .where(
            (r) =>
                r.participant.eventId == EventId(widget.eventId) &&
                !r.participant.metadata.isDeleted,
          )
          .map((r) => r.participant.playerId)
          .toSet();
      final page = (await reader.readPage(query))
          .when(success: (value) => value, failure: (failure) => throw failure);
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _registered = roster;
        _players = [
          if (more) ..._players,
          ...page.entries,
        ].where((p) => !registered.contains(p.profile.id)).toList();
        // Continue from the unfiltered page so registered entries cannot hide
        // eligible players on later pages.
        _nextCursor = page.nextCursor;
        _message = null;
      });
    } on Exception {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _players = const [];
        _nextCursor = null;
        _message = 'Unable to check the event roster. Please search again.';
      });
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => _finding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountControllerProvider).snapshot?.authorization !=
        AuthorizationState.organizer) {
      return const Center(child: Text('Organizer access required.'));
    }
    final setup = _setup;
    final activeRegistered = _registered
        .where((record) => !record.participant.metadata.isDeleted)
        .toList();
    final recent = activeRegistered
        .where((record) => _recentlyAdded.contains(record.participant.playerId))
        .toList();
    final checkedIn = activeRegistered
        .where(
          (record) =>
              !_recentlyAdded.contains(record.participant.playerId) &&
              record.participant.checkInStatus == CheckInStatus.checkedIn,
        )
        .toList();
    final awaitingCheckIn = activeRegistered
        .where(
          (record) =>
              !_recentlyAdded.contains(record.participant.playerId) &&
              record.participant.checkInStatus != CheckInStatus.checkedIn,
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Add participant',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Select one or more permanent community players. Registered players are listed separately below.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Search players',
            suffixIcon: IconButton(
              onPressed: _find,
              tooltip: 'Search',
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) => _find(),
          onChanged: (_) => setState(() {
            _searchRequest++;
            _finding = false;
            _players = const [];
            _nextCursor = null;
          }),
        ),
        if (_message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
        if (_finding) const LinearProgressIndicator(),
        if (!_finding && _players.isEmpty && _message == null)
          const Text(
            'No unregistered players on this page. Search by name or load more.',
          ),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('${_selected.length} selected'),
          ),
        if (_players.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Available players',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        for (final player in _players)
          CheckboxListTile(
            value: _selected.containsKey(player.profile.id),
            title: Text(player.profile.displayName),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _finding
                ? null
                : (checked) => setState(() {
                    if (checked == true) {
                      _selected[player.profile.id] = player;
                    } else {
                      _selected.remove(player.profile.id);
                    }
                  }),
          ),
        if (_nextCursor != null)
          TextButton(
            onPressed: _finding ? null : () => _find(more: true),
            child: const Text('Load more players'),
          ),
        TextButton.icon(
          onPressed: () => context.push('/organizer/players/new'),
          icon: const Icon(Icons.person_add),
          label: const Text('Create a permanent player first'),
        ),
        if (activeRegistered.isNotEmpty) ...[
          const Divider(),
          if (recent.isNotEmpty) ...[
            Text(
              'Added this session',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final record in recent)
              ListTile(
                leading: const Icon(Icons.person_add_alt_1),
                title: Text(record.playerDisplayName),
                subtitle: const Text('Not checked in'),
              ),
          ],
          if (checkedIn.isNotEmpty) ...[
            Text('Checked in', style: Theme.of(context).textTheme.titleMedium),
            for (final record in checkedIn)
              ListTile(
                leading: const Icon(Icons.how_to_reg),
                title: Text(record.playerDisplayName),
                subtitle: const Text('Already registered'),
              ),
          ],
          if (awaitingCheckIn.isNotEmpty) ...[
            Text(
              'Registered • awaiting check-in',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final record in awaitingCheckIn)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(record.playerDisplayName),
                subtitle: const Text('Already registered'),
              ),
          ],
        ],
        if (setup != null) ...[
          const Divider(),
          Text('Divisions', style: Theme.of(context).textTheme.titleMedium),
          for (final division in setup.divisions.where(
            (d) => !d.metadata.isDeleted,
          ))
            CheckboxListTile(
              value: _divisions.contains(division.id),
              title: Text(division.name),
              onChanged: (selected) => setState(() {
                if (selected == true) {
                  _divisions.add(division.id);
                } else {
                  _divisions.remove(division.id);
                }
              }),
            ),
        ],
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Initial status'),
          subtitle: Text('Not checked in • Unpaid'),
        ),
        FilledButton(
          onPressed: _working || _finding ? null : _register,
          child: _working
              ? const CircularProgressIndicator()
              : Text(
                  _selected.isEmpty
                      ? 'Select players to register'
                      : 'Review and register ${_selected.length}',
                ),
        ),
      ],
    );
  }

  Future<void> _register() async {
    final setup = _setup;
    final selected = _selected.values.toList();
    if (setup == null || selected.isEmpty || _divisions.isEmpty) {
      setState(() => _message = 'Select at least one player and one division.');
      return;
    }
    final store = ref.read(participationStoreProvider)!;
    final existing = await store.listForEvent(setup.event.id);
    final duplicateNames = switch (existing) {
      RepositorySuccess(:final value) =>
        selected
            .where(
              (player) => value.any(
                (record) => record.participant.playerId == player.profile.id,
              ),
            )
            .map((player) => player.profile.displayName)
            .toList(),
      RepositoryFailure() => <String>[],
    };
    if (duplicateNames.isNotEmpty) {
      setState(
        () => _message =
            '${duplicateNames.join(', ')} already registered for this event.',
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register participant?'),
        content: Text(
          '${selected.map((player) => player.profile.displayName).join('\n')}\n\n'
          '${selected.length} participant${selected.length == 1 ? '' : 's'} • Not checked in • Unpaid',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Register'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    var registered = 0;
    var pending = false;
    DomainFailure? firstFailure;
    for (final player in selected) {
      final result = await ref
          .read(participationServiceProvider)
          .register(
            setup: setup,
            playerId: player.profile.id,
            playerDisplayName: player.profile.displayName,
            divisionIds: _divisions,
          );
      switch (result) {
        case RepositorySuccess(value: ParticipationSaved(:final disposition)):
          registered++;
          pending =
              pending ||
              disposition == ParticipationMutationDisposition.pending;
          _recentlyAdded.add(player.profile.id);
        case RepositoryFailure(:final failure):
          firstFailure ??= failure;
      }
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _selected.clear();
      _message = firstFailure?.message;
    });
    if (registered > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$registered participant${registered == 1 ? '' : 's'} registered'
            '${pending ? ' locally; synchronization is pending.' : '.'}',
          ),
        ),
      );
      await _find();
    }
  }
}
