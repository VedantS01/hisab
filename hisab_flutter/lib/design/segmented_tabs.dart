/// 36 high segmented control with a sliding thumb.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hisab_design.dart';
import 'tokens.dart';

class SegmentedTabs extends StatelessWidget {
  final List<String> segments;
  final int selectedIndex;

  /// Called with the tapped index when it differs from [selectedIndex].
  final ValueChanged<int> onChanged;

  const SegmentedTabs({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final count = segments.length;
    final x = count == 1 ? 0.0 : -1 + 2 * selectedIndex / (count - 1);
    return Container(
      padding: const EdgeInsets.all(HisabSpace.s2),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(HisabRadius.r8 + HisabSpace.s2),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              alignment: Alignment(x, 0),
              duration: HisabMotion.medium,
              curve: HisabMotion.curve,
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(HisabRadius.r8),
                    border: Border.all(color: c.outline),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selectedIndex,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (i == selectedIndex) return;
                        HapticFeedback.selectionClick();
                        onChanged(i);
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 32),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: HisabMotion.medium,
                            style: HisabType.label.copyWith(
                              color: i == selectedIndex
                                  ? c.textPrimary
                                  : c.textSecondary,
                              fontWeight: i == selectedIndex
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            child: Text(segments[i],
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
