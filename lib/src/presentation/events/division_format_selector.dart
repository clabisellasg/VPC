import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/accounts/account_models.dart';
import '../../application/events/event_setup_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/events/event_division.dart';
import '../accounts/account_controller.dart';
import 'organizer_event_controller.dart';

String tournamentFormatLabel(TournamentFormat format) => switch (format) {
  TournamentFormat.singleElimination => 'Single Elimination',
  TournamentFormat.doubleElimination => 'Double Elimination',
  TournamentFormat.singleRoundRobin => 'Single Round Robin',
  TournamentFormat.doubleRoundRobin => 'Double Round Robin',
};
String tournamentFormatMilestone(TournamentFormat format) => switch (format) {
  TournamentFormat.singleElimination => 'M13',
  TournamentFormat.doubleElimination => 'M15',
  TournamentFormat.singleRoundRobin ||
  TournamentFormat.doubleRoundRobin => 'M14',
};

class DivisionFormatSelector extends ConsumerStatefulWidget {
  const DivisionFormatSelector({
    required this.setup,
    required this.division,
    super.key,
  });
  final EventSetup setup;
  final EventDivision division;
  @override
  ConsumerState<DivisionFormatSelector> createState() =>
      _DivisionFormatSelectorState();
}

class _DivisionFormatSelectorState
    extends ConsumerState<DivisionFormatSelector> {
  TournamentFormat? _selection;
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final division = widget.division;
    final format = _selection ?? division.format;
    final canEdit =
        ref.watch(accountControllerProvider).snapshot?.authorization ==
            AuthorizationState.organizer &&
        widget.setup.event.status == EventStatus.registration &&
        widget.setup.readiness[division.id]?.generatedMatches == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${division.name} — ${division.format == null ? 'Not configured' : tournamentFormatLabel(division.format!)}',
          ),
          if (canEdit) ...[
            DropdownButtonFormField<TournamentFormat>(
              initialValue: format,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '${division.name} tournament format',
              ),
              items: [
                for (final value in TournamentFormat.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(tournamentFormatLabel(value)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _selection = value),
            ),
            if (format != null)
              Text(
                'Selecting this format creates no matches. Generation: ${tournamentFormatMilestone(format)}.',
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed:
                    _saving || format == null || format == division.format
                    ? null
                    : () => _save(format),
                child: Text(_saving ? 'Saving format…' : 'Save format'),
              ),
            ),
          ] else
            const Text(
              'Format is read-only outside Registration or after match structure exists.',
            ),
        ],
      ),
    );
  }

  Future<void> _save(TournamentFormat format) async {
    setState(() => _saving = true);
    final result = await ref
        .read(organizerEventControllerProvider.notifier)
        .selectFormat(widget.setup, widget.division.id, format);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _selection = null;
    });
    final message = switch (result) {
      EventSetupSaved(:final disposition) =>
        disposition == EventMutationDisposition.pending
            ? 'Format saved locally; synchronization pending.'
            : 'Format saved. No matches were generated.',
      EventSetupMutationFailed(:final failure) => failure.message,
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
