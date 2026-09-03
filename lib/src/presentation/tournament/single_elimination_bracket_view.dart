import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/common/domain_enums.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/matches/match.dart';
import '../../domain/tournament/tournament_contracts.dart';

/// Real round columns with connected matchup positions; no list masquerading
/// as a bracket. Bye cells are visual seed metadata, not playable records.
class SingleEliminationBracketView extends StatefulWidget {
  const SingleEliminationBracketView({
    required this.plan,
    required this.labels,
    this.matches = const {},
    this.onMatch,
    super.key,
  });
  final TournamentPlan plan;
  final Map<TeamId, String> labels;
  final Map<PlannedMatchKey, Match> matches;
  final void Function(PlannedMatchKey)? onMatch;
  @override
  State<SingleEliminationBracketView> createState() =>
      _SingleEliminationBracketViewState();
}

class _SingleEliminationBracketViewState
    extends State<SingleEliminationBracketView> {
  final _scroll = ScrollController();
  TournamentPlan get plan => widget.plan;
  Map<TeamId, String> get labels => widget.labels;
  Map<PlannedMatchKey, Match> get matches => widget.matches;
  void Function(PlannedMatchKey)? get onMatch => widget.onMatch;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(double distance) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      (_scroll.offset + distance).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = int.parse(plan.metadata['bracketSize']!);
    final seeds = (jsonDecode(plan.metadata['seedOrder']!) as List)
        .cast<String>();
    final positions = (jsonDecode(plan.metadata['seedPositions']!) as List)
        .cast<int>();
    final rounds = (math.log(size) / math.ln2).round();
    final cellHeight =
        240.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2.5);
    const width = 300.0, gap = 36.0;
    final height = size / 2 * cellHeight;
    String label(TeamId? id) => id == null
        ? 'TBD'
        : '${seeds.indexOf(id.value) + 1}. ${labels[id] ?? 'Community team'}';
    TeamId? direct(PlannedParticipantSource source) =>
        source is DirectTeamSource ? source.teamId : null;
    final bracket = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: rounds * (width + gap) - gap,
        height: height + 40,
        child: Stack(
          children: [
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              bottom: 0,
              child: CustomPaint(
                painter: _BracketConnectors(
                  rounds: rounds,
                  size: size,
                  cellHeight: cellHeight,
                  width: width,
                  gap: gap,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            for (var round = 1; round <= rounds; round++) ...[
              Positioned(
                left: (round - 1) * (width + gap),
                top: 0,
                width: width,
                child: Text(
                  round == rounds ? 'Final' : 'Round $round',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (var pos = 1; pos <= size ~/ math.pow(2, round); pos++)
                Builder(
                  builder: (context) {
                    final key = PlannedMatchKey('se/r$round/m$pos');
                    final planned = plan.matches
                        .where((m) => m.key == key)
                        .firstOrNull;
                    final actual = matches[key];
                    final step = cellHeight * math.pow(2, round - 1);
                    Widget content;
                    if (planned == null && round == 1) {
                      final a = positions[(pos - 1) * 2],
                          b = positions[(pos - 1) * 2 + 1];
                      final seed = a <= seeds.length ? a : b;
                      content = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label(TeamId(seeds[seed - 1])),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text('BYE — advances without a played match'),
                        ],
                      );
                    } else if (planned != null) {
                      final one =
                              actual?.sideOneTeamId ?? direct(planned.sideOne),
                          two =
                              actual?.sideTwoTeamId ?? direct(planned.sideTwo);
                      final status = actual?.status ?? planned.status;
                      final statusLabel = switch (status) {
                        MatchStatus.scheduled => 'Pending',
                        MatchStatus.queued => 'Ready',
                        MatchStatus.inProgress => 'In progress',
                        MatchStatus.completed => 'Completed',
                      };
                      content = Semantics(
                        label:
                            'Round $round match $pos. ${label(one)} against ${label(two)}. $statusLabel',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${label(one)}${actual?.sideOneScore == null ? '' : ' — ${actual!.sideOneScore}'}',
                              style: TextStyle(
                                fontWeight:
                                    actual?.winnerTeamId == one && one != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const Divider(),
                            Text(
                              '${label(two)}${actual?.sideTwoScore == null ? '' : ' — ${actual!.sideTwoScore}'}',
                              style: TextStyle(
                                fontWeight:
                                    actual?.winnerTeamId == two && two != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            Text(statusLabel),
                            if (round < rounds)
                              Text(
                                'Winner → Round ${round + 1}, match ${(pos + 1) ~/ 2}',
                              ),
                            if (onMatch != null && actual != null)
                              TextButton(
                                onPressed: () => onMatch!(key),
                                child: Text(
                                  status == MatchStatus.queued
                                      ? 'Start match'
                                      : status == MatchStatus.completed
                                      ? 'Correct result'
                                      : 'Enter result',
                                ),
                              ),
                          ],
                        ),
                      );
                    } else {
                      content = const Text('BYE advancement');
                    }
                    return Positioned(
                      left: (round - 1) * (width + gap),
                      top: 40 + (pos - 0.5) * step - cellHeight / 2,
                      width: width,
                      height: cellHeight,
                      child: Card(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: content,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflow = rounds * (width + gap) - gap > constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (overflow)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _move(-(width + gap)),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Earlier rounds'),
                  ),
                  TextButton.icon(
                    onPressed: () => _move(width + gap),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Later rounds'),
                  ),
                ],
              ),
            Scrollbar(
              controller: _scroll,
              thumbVisibility: overflow,
              trackVisibility: overflow,
              interactive: true,
              scrollbarOrientation: ScrollbarOrientation.top,
              notificationPredicate: (notification) => notification.depth == 0,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: bracket,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BracketConnectors extends CustomPainter {
  const _BracketConnectors({
    required this.rounds,
    required this.size,
    required this.cellHeight,
    required this.width,
    required this.gap,
    required this.color,
  });
  final int rounds, size;
  final double cellHeight, width, gap;
  final Color color;
  @override
  void paint(Canvas canvas, Size dimensions) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var r = 1; r < rounds; r++) {
      final step = cellHeight * math.pow(2, r - 1),
          x = (r - 1) * (width + gap) + width;
      for (var p = 1; p <= size ~/ math.pow(2, r); p++) {
        final y = (p - .5) * step, target = ((p + 1) ~/ 2 - .5) * step * 2;
        canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..lineTo(x + gap / 2, y)
            ..lineTo(x + gap / 2, target)
            ..lineTo(x + gap, target),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BracketConnectors old) =>
      old.size != size || old.cellHeight != cellHeight || old.color != color;
}
