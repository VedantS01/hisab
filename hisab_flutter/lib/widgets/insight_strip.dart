/// The "For you" strip — mirrors InsightStrip.swift. Furniture, not
/// notification: no badges, no counts, no entrance animation.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../theme.dart';

class InsightStrip extends StatelessWidget {
  final List<Insight> insights;
  final void Function(Insight) onOpen;
  final void Function(Insight) onDismiss;
  final void Function(Insight) onMute;

  const InsightStrip({
    super.key,
    required this.insights,
    required this.onOpen,
    required this.onDismiss,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width * 0.85;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('For you',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        SizedBox(
          // 132 before the dismiss button grew to Material's 48 dp minimum;
          // the extra 32 keeps the detail sentence's three lines intact.
          height: 164,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: insights.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SizedBox(
              width: width,
              child: _InsightCard(
                insight: insights[index],
                onOpen: () => onOpen(insights[index]),
                onDismiss: () => onDismiss(insights[index]),
                onMute: () => onMute(insights[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final Insight insight;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onMute;

  const _InsightCard({
    required this.insight,
    required this.onOpen,
    required this.onDismiss,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$_caption. ${insight.headline}. ${insight.detail}',
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onOpen,
          onLongPress: insight.mute == null ? null : () => _showMute(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icon, size: 14, color: _accent),
                    const SizedBox(width: 4),
                    Text(_caption,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _accent)),
                    const Spacer(),
                    if (insight.kind != InsightKind.committedSpend)
                      // TalkBack announced a bare icon before; iOS has said
                      // "Dismiss" since the strip shipped. The glyph stays
                      // 14 px and the target around it is 48 × 48, Material's
                      // minimum — the card's fixed height above carries the
                      // extra row height so the sentence below keeps its
                      // three lines.
                      Semantics(
                        label: 'Dismiss',
                        button: true,
                        child: InkResponse(
                          onTap: onDismiss,
                          radius: 24,
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.black45),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(insight.headline,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(insight.detail,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMute(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: const Text("Don't show insights like this"),
          onTap: () {
            Navigator.pop(sheetContext);
            onMute();
          },
        ),
      ),
    );
  }

  String get _caption => switch (insight.kind) {
        InsightKind.trend => 'TREND',
        InsightKind.recurringNew ||
        InsightKind.recurringChanged =>
          'RECURRING',
        InsightKind.committedSpend => 'COMMITTED',
        InsightKind.possibleDuplicate ||
        InsightKind.outlierAmount =>
          'UNUSUAL',
      };

  // Display-only: core copy starts with "up "/"down ", pinned by the parity
  // fixture, so the arrow can't drift from the sentence.
  bool get _isDrop => insight.detail.startsWith('down');

  IconData get _icon => switch (insight.kind) {
        InsightKind.trend =>
          _isDrop ? Icons.south_east : Icons.north_east,
        InsightKind.recurringNew || InsightKind.recurringChanged => Icons.repeat,
        InsightKind.committedSpend => Icons.calendar_month,
        InsightKind.possibleDuplicate => Icons.copy_all,
        InsightKind.outlierAmount => Icons.warning_amber,
      };

  Color get _accent => switch (insight.kind) {
        InsightKind.trend =>
          _isDrop ? HisabTheme.hara : HisabTheme.khataRed,
        InsightKind.recurringNew || InsightKind.recurringChanged =>
          HisabTheme.ink,
        InsightKind.committedSpend ||
        InsightKind.possibleDuplicate ||
        InsightKind.outlierAmount =>
          HisabTheme.sona,
      };
}
