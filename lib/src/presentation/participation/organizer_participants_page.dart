import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/events/event_setup_models.dart';
import '../../application/participation/participation_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import '../../infrastructure/participation/participation_providers.dart';
import '../accounts/account_controller.dart';

class OrganizerParticipantsPage extends ConsumerStatefulWidget {
  const OrganizerParticipantsPage({required this.eventId, super.key});
  final String eventId;
  @override
  ConsumerState<OrganizerParticipantsPage> createState() =>
      _OrganizerParticipantsPageState();
}

class _OrganizerParticipantsPageState
    extends ConsumerState<OrganizerParticipantsPage> {
  bool _loading = true;
  String? _message;
  EventSetup? _setup;
  List<ParticipationRecord> _records = const [];
  Map<EventParticipantId, ParticipationSyncStatus> _statuses = const {};

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await ref.read(participationRealtimeRuntimeProvider)?.start();
      await _load();
    });
  }

  Future<void> _load({bool synchronize = true}) async {
    final eventId = _eventId();
    final eventStore = ref.read(eventSetupStoreProvider);
    final store = ref.read(participationStoreProvider);
    if (eventId == null || eventStore == null || store == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Roster is unavailable.';
        });
      }
      return;
    }
    final setupResult = await eventStore.getSetup(eventId);
    final rosterResult = await store.listForEvent(eventId);
    if (!mounted) return;
    if (setupResult case RepositoryFailure(:final failure)) {
      setState(() {
        _loading = false;
        _message = failure.message;
      });
      return;
    }
    if (rosterResult case RepositoryFailure(:final failure)) {
      setState(() {
        _loading = false;
        _message = failure.message;
      });
      return;
    }
    final records =
        (rosterResult as RepositorySuccess<List<ParticipationRecord>>).value;
    final statuses = <EventParticipantId, ParticipationSyncStatus>{};
    for (final record in records) {
      final status = await store.syncStatus(record.participant.id);
      if (status case RepositorySuccess(:final value)) {
        statuses[record.participant.id] = value;
      }
    }
    if (!mounted) return;
    setState(() {
      _setup = (setupResult as RepositorySuccess<EventSetup>).value;
      _records = records;
      _statuses = statuses;
      _loading = false;
      _message = null;
    });
    final synchronizer = ref.read(participationSynchronizerProvider);
    if (synchronize && synchronizer != null) {
      unawaited(
        synchronizer.synchronize().then((_) {
          if (mounted) {
            _load(synchronize: false);
          }
        }),
      );
    }
  }

  EventId? _eventId() {
    try {
      return EventId(widget.eventId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountControllerProvider);
    if (account.snapshot?.authorization != AuthorizationState.organizer) {
      return const Center(
        child: Text('A confirmed organizer account is required.'),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_message != null) {
      return Center(child: Text(_message!, textAlign: TextAlign.center));
    }
    final setup = _setup!;
    final canStructure = setup.event.status == EventStatus.registration;
    final canCorrect =
        setup.event.status == EventStatus.registration ||
        setup.event.status == EventStatus.inProgress;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            setup.event.name,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text('Participant roster • ${_label(setup.event.status)}'),
          if (setup.event.status == EventStatus.upcoming)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Open registration before adding participants.'),
            ),
          const SizedBox(height: 16),
          if (canStructure)
            FilledButton.icon(
              onPressed: () async {
                await context.push(
                  '/organizer/events/${widget.eventId}/participants/add',
                );
                if (mounted) await _load();
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add participant'),
            ),
          if (setup.divisions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Division teams',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final division in setup.divisions.where(
              (item) => !item.metadata.isDeleted,
            ))
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(division.name),
                subtitle: const Text('Checked-in division participants only'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  '/organizer/events/${widget.eventId}/divisions/${division.id.value}/teams',
                ),
              ),
          ],
          if (_records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No participants are registered.')),
            )
          else
            for (final record in _records)
              _ParticipantCard(
                record: record,
                setup: setup,
                status: _statuses[record.participant.id],
                canStructure: canStructure,
                canCorrect: canCorrect,
                onChanged: _load,
              ),
        ],
      ),
    );
  }
}

class _ParticipantCard extends ConsumerWidget {
  const _ParticipantCard({
    required this.record,
    required this.setup,
    required this.canStructure,
    required this.canCorrect,
    required this.onChanged,
    this.status,
  });
  final ParticipationRecord record;
  final EventSetup setup;
  final ParticipationSyncStatus? status;
  final bool canStructure;
  final bool canCorrect;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAssignments = record.divisions
        .where((row) => !row.metadata.isDeleted)
        .toList();
    final names = activeAssignments
        .map((row) {
          for (final division in setup.divisions) {
            if (division.id == row.divisionId) return division.name;
          }
          return 'Unavailable division';
        })
        .join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.playerDisplayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(names),
            Text(
              record.participant.checkInStatus == CheckInStatus.checkedIn
                  ? 'Checked in'
                  : 'Not checked in',
            ),
            Text(
              'Payment: ${record.payment.status == PaymentStatus.paid ? 'Paid' : 'Unpaid'}',
            ),
            if (status != null &&
                status!.disposition !=
                    ParticipationMutationDisposition.synchronized)
              Chip(label: Text(_syncLabel(status!.disposition))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => context.push(
                    '/players/${record.participant.playerId.value}',
                  ),
                  child: const Text('Player profile'),
                ),
                if (canCorrect)
                  OutlinedButton(
                    onPressed: () => _toggleCheckIn(ref),
                    child: Text(
                      record.participant.checkInStatus ==
                              CheckInStatus.checkedIn
                          ? 'Undo check-in'
                          : 'Check in',
                    ),
                  ),
                if (canCorrect)
                  OutlinedButton(
                    onPressed: () => _togglePayment(context, ref),
                    child: Text(
                      record.payment.status == PaymentStatus.paid
                          ? 'Mark unpaid'
                          : 'Mark paid',
                    ),
                  ),
                if (canStructure)
                  OutlinedButton(
                    onPressed: () => _editDivisions(context, ref),
                    child: const Text('Edit divisions'),
                  ),
                if (canStructure)
                  TextButton(
                    onPressed: () => _remove(context, ref),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleCheckIn(WidgetRef ref) async {
    await ref
        .read(participationServiceProvider)
        .updateCheckIn(
          record,
          record.participant.checkInStatus == CheckInStatus.checkedIn
              ? CheckInStatus.notPresent
              : CheckInStatus.checkedIn,
          setup.event.status,
        );
    await onChanged();
  }

  Future<void> _editDivisions(BuildContext context, WidgetRef ref) async {
    final selected = record.divisions
        .where((row) => !row.metadata.isDeleted)
        .map((row) => row.divisionId)
        .toSet();
    final updated = await showDialog<Set<DivisionId>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Division assignments'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final division in setup.divisions.where(
                  (division) => !division.metadata.isDeleted,
                ))
                  CheckboxListTile(
                    value: selected.contains(division.id),
                    title: Text(division.name),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selected.add(division.id);
                      } else {
                        selected.remove(division.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected),
              child: const Text('Save assignments'),
            ),
          ],
        ),
      ),
    );
    if (updated == null) return;
    await ref
        .read(participationServiceProvider)
        .updateDivisions(current: record, setup: setup, divisionIds: updated);
    await onChanged();
  }

  Future<void> _togglePayment(BuildContext context, WidgetRef ref) async {
    final target = record.payment.status == PaymentStatus.paid
        ? PaymentStatus.unpaid
        : PaymentStatus.paid;
    if (target == PaymentStatus.unpaid) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Correct payment status?'),
          content: const Text(
            'This records the participant as Unpaid. No money is processed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mark unpaid'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref
        .read(participationServiceProvider)
        .updatePayment(record, target, setup.event.status);
    await onChanged();
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove participant?'),
        content: const Text(
          'The records are preserved as history through tombstones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(participationServiceProvider)
        .remove(record, setup.event.status);
    await onChanged();
  }
}

String _label(Enum value) => value.name.replaceAllMapped(
  RegExp(r'([A-Z])'),
  (m) => ' ${m.group(1)!.toLowerCase()}',
);
String _syncLabel(ParticipationMutationDisposition value) => switch (value) {
  ParticipationMutationDisposition.pending => 'Pending synchronization',
  ParticipationMutationDisposition.synchronized => 'Synchronized',
  ParticipationMutationDisposition.blocked => 'Authorization blocked',
  ParticipationMutationDisposition.failed => 'Synchronization failed',
  ParticipationMutationDisposition.conflicted => 'Synchronization conflict',
};
