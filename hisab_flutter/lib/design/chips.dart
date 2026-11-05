/// Pill filter chip and the small tonal status tag.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hisab_design.dart';
import 'tokens.dart';

/// 32 high pill; selected is a solid brand fill.
class HisabFilterChip extends StatelessWidget {
  final String label;
  final bool selected;

  /// Called with the new selection; null disables the chip.
  final ValueChanged<bool>? onSelected;

  const HisabFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? c.brand : c.surface,
        shape: StadiumBorder(
            side: BorderSide(color: selected ? c.brand : c.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelected == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onSelected!(!selected);
                },
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: HisabSpace.s12),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label,
                style: HisabType.label.copyWith(
                    color: selected ? c.onBrand : c.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 20 high tonal tag: Pending, Captured, Edited.
class StatusTag extends StatelessWidget {
  final String label;
  final HisabTone tone;

  const StatusTag(this.label, {super.key, this.tone = HisabTone.neutral});

  @override
  Widget build(BuildContext context) {
    final colors = context.hisab.tone(tone);
    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      padding: const EdgeInsets.symmetric(
          horizontal: HisabSpace.s8, vertical: HisabSpace.s2),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(HisabRadius.r4),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: HisabType.caption
            .copyWith(color: colors.fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
