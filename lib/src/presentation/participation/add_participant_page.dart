import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/events/event_setup_models.dart';
import '../../application/players/player_directory_models.dart';
import '../../application/participation/participation_models.dart';
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
  PlayerDirectoryEntry? _selected;
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
      _selected = null;
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Add participant',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Select an existing permanent community player. Players already registered in this event are hidden.',
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
            _selected = null;
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
        for (final player in _players)
          ListTile(
            leading: Icon(
              _selected?.profile.id == player.profile.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(player.profile.displayName),
            onTap: _finding ? null : () => setState(() => _selected = player),
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
              : const Text('Review and register'),
        ),
      ],
    );
  }

  Future<void> _register() async {
    final setup = _setup;
    final selected = _selected;
    if (setup == null || selected == null || _divisions.isEmpty) {
      setState(() => _message = 'Select one player and at least one division.');
      return;
    }
    final store = ref.read(participationStoreProvider)!;
    final existing = await store.listForEvent(setup.event.id);
    final duplicate = switch (existing) {
      RepositorySuccess(:final value) => value.any(
        (record) => record.participant.playerId == selected.profile.id,
      ),
      RepositoryFailure() => false,
    };
    if (duplicate) {
      setState(
        () => _message = 'This player is already registered for the event.',
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register participant?'),
        content: Text(
          '${selected.profile.displayName}\nNot checked in • Unpaid',
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
    final result = await ref
        .read(participationServiceProvider)
        .register(
          setup: setup,
          playerId: selected.profile.id,
          playerDisplayName: selected.profile.displayName,
          divisionIds: _divisions,
        );
    if (!mounted) return;
    setState(() => _working = false);
    switch (result) {
      case RepositorySuccess(value: ParticipationSaved(:final disposition)):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              disposition == ParticipationMutationDisposition.pending
                  ? 'Registered locally; synchronization is pending.'
                  : 'Participant registered.',
            ),
          ),
        );
        context.pop();
      case RepositoryFailure(:final failure):
        setState(() => _message = failure.message);
    }
  }
}
