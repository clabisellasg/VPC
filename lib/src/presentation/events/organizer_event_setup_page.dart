import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/events/event_setup_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import '../accounts/account_controller.dart';
import 'organizer_event_controller.dart';

class OrganizerEventSetupPage extends ConsumerStatefulWidget {
  const OrganizerEventSetupPage({required this.type, this.eventId, super.key});
  final EventType type;
  final String? eventId;

  @override
  ConsumerState<OrganizerEventSetupPage> createState() =>
      _OrganizerEventSetupPageState();
}

class _OrganizerEventSetupPageState
    extends ConsumerState<OrganizerEventSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _venue = TextEditingController(text: 'Community Court');
  final _division = TextEditingController();
  final _divisions = <String>[];
  DateTime? _scheduledAt;
  bool _initialized = false;
  bool _working = false;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    _division.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountControllerProvider);
    if (account.snapshot?.authorization != AuthorizationState.organizer) {
      return const Center(child: Text('Organizer access required.'));
    }
    final state = ref.watch(organizerEventControllerProvider);
    final current = widget.eventId == null
        ? null
        : state.setups
              .where((setup) => setup.event.id.value == widget.eventId)
              .firstOrNull;
    _initialize(current);
    final type = current?.event.type ?? widget.type;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          current == null
              ? (type == EventType.casual
                    ? 'Quick casual setup'
                    : 'Formal event setup')
              : 'Edit event setup',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'New divisions begin without a tournament format. Select formats after opening Registration.',
        ),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Event name'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _venue,
                decoration: const InputDecoration(labelText: 'Venue'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.schedule),
                label: Text(
                  _scheduledAt == null
                      ? 'Choose date and time'
                      : _scheduledAt!.toLocal().toString().substring(0, 16),
                ),
              ),
              const SizedBox(height: 20),
              Text('Divisions', style: Theme.of(context).textTheme.titleMedium),
              if (type == EventType.casual)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Open'),
                  subtitle: Text(
                    'Default quick-casual division • format not configured',
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _division,
                        decoration: const InputDecoration(
                          labelText: 'Division name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _addDivision,
                      tooltip: 'Add division',
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                for (final name in _divisions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(name),
                    subtitle: const Text('Format not configured'),
                    trailing: IconButton(
                      onPressed: () => setState(() => _divisions.remove(name)),
                      tooltip: 'Remove division',
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _working ? null : () => _save(current, type),
                child: _working
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        current == null ? 'Review and create' : 'Save setup',
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _initialize(EventSetup? current) {
    if (_initialized) return;
    _initialized = true;
    if (current != null) {
      _name.text = current.event.name;
      _venue.text = current.event.courtLabel;
      _scheduledAt = current.event.scheduledAt;
      _divisions.addAll(
        current.divisions
            .where((d) => !d.metadata.isDeleted)
            .map((d) => d.name),
      );
    } else {
      _scheduledAt = ref
          .read(eventSetupClockProvider)
          .nowUtc()
          .add(const Duration(days: 1));
      if (widget.type == EventType.casual) {
        _name.text =
            'Casual Play — ${_scheduledAt!.toIso8601String().substring(0, 10)}';
      }
    }
  }

  Future<void> _pickDateTime() async {
    final now = ref.read(eventSetupClockProvider).nowUtc().toLocal();
    final initial = (_scheduledAt ?? now.toUtc()).toLocal();
    final date = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 3650)),
      initialDate: initial,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(
      () => _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc(),
    );
  }

  void _addDivision() {
    final name = _division.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return;
    if (_divisions.any(
      (existing) =>
          normalizeDivisionName(existing) == normalizeDivisionName(name),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Division names must be unique.')),
      );
      return;
    }
    setState(() {
      _divisions.add(name);
      _division.clear();
    });
  }

  Future<void> _save(EventSetup? current, EventType type) async {
    if (!_formKey.currentState!.validate() || _scheduledAt == null) return;
    final divisions = type == EventType.casual ? const ['Open'] : _divisions;
    if (divisions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one division.')),
      );
      return;
    }
    if (current == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Create this event?'),
          content: Text(
            '${_name.text.trim()}\n'
            '${type == EventType.casual ? 'Casual' : 'Formal'} • '
            '${divisions.length} division(s)\n'
            'Select tournament formats after opening Registration.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create event'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _working = true);
    final controller = ref.read(organizerEventControllerProvider.notifier);
    final result = current == null
        ? await controller.create(
            type: type,
            name: _name.text,
            scheduledAt: _scheduledAt!,
            venue: _venue.text,
            divisions: divisions,
          )
        : await controller.update(
            current: current,
            name: _name.text,
            scheduledAt: _scheduledAt!,
            venue: _venue.text,
            divisionNames: divisions,
          );
    if (!mounted) return;
    setState(() => _working = false);
    switch (result) {
      case EventSetupSaved(:final disposition):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              disposition == EventMutationDisposition.pending
                  ? 'Saved locally; synchronization is pending.'
                  : 'Event setup saved.',
            ),
          ),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/organizer/events');
        }
      case EventSetupMutationFailed(:final failure):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;
