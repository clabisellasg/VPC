import 'package:flutter/material.dart';

typedef MatchScoreInput = ({String sideOne, String sideTwo, String reason});

/// The route owns its controllers until the exit animation has unmounted the
/// fields. Returning from showDialog alone does not mean those fields are gone.
class MatchScoreDialog extends StatefulWidget {
  const MatchScoreDialog({
    required this.correcting,
    required this.sideOneLabel,
    required this.sideTwoLabel,
    super.key,
  });
  final bool correcting;
  final String sideOneLabel, sideTwoLabel;
  @override
  State<MatchScoreDialog> createState() => _MatchScoreDialogState();
}

class _MatchScoreDialogState extends State<MatchScoreDialog> {
  final _one = TextEditingController(),
      _two = TextEditingController(),
      _reason = TextEditingController();
  @override
  void dispose() {
    _one.dispose();
    _two.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.correcting ? 'Correct completed result' : 'Record final score',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _one,
            decoration: InputDecoration(labelText: widget.sideOneLabel),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _two,
            decoration: InputDecoration(labelText: widget.sideTwoLabel),
            keyboardType: TextInputType.number,
          ),
          if (widget.correcting)
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Correction reason (required)',
              ),
            ),
          const Text('One game to 11, win by two, no score cap.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          sideOne: _one.text,
          sideTwo: _two.text,
          reason: _reason.text,
        )),
        child: const Text('Confirm score'),
      ),
    ],
  );
}
