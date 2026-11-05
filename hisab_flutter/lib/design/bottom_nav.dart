/// 64 high bottom navigation; the active tab shows its filled icon.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hisab_design.dart';
import 'tokens.dart';

class HisabNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const HisabNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class HisabBottomNav extends StatelessWidget {
  final List<HisabNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const HisabBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    return Material(
      color: c.surface,
      shape: Border(top: BorderSide(color: c.outline)),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _NavButton(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () {
                    if (i != currentIndex) HapticFeedback.selectionClick();
                    onTap(i);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final HisabNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final color = selected ? c.brandText : c.textSecondary;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? item.activeIcon : item.icon,
                  size: 24, color: color),
              const SizedBox(height: HisabSpace.s4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HisabType.caption.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
