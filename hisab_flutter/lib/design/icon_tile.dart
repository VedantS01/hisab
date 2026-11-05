/// A rounded, tinted square around an icon: the leading of a settings row,
/// so a list of rows reads as a set of distinct things.
library;

import 'package:flutter/material.dart';

import 'hisab_design.dart';
import 'tokens.dart';

class IconTile extends StatelessWidget {
  final IconData icon;
  final HisabTone tone;

  /// A specific hue instead of a tone (category colours).
  final Color? hue;

  const IconTile(this.icon, {super.key, this.tone = HisabTone.brand, this.hue});

  @override
  Widget build(BuildContext context) {
    final colors = context.hisab.tone(tone);
    final fg = hue ?? colors.fg;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: hue != null ? hue!.withValues(alpha: 0.14) : colors.bg,
        borderRadius: BorderRadius.circular(HisabRadius.r12),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}
