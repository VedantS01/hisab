/// The transaction list row and its merchant avatar.
library;

import 'package:flutter/material.dart';

import 'amount_text.dart';
import 'chips.dart';
import 'hisab_design.dart';
import 'tokens.dart';

/// 40px monogram on a category tint.
class MerchantAvatar extends StatelessWidget {
  final String name;

  /// Category hue; when null one is picked from [name] so a merchant keeps
  /// its colour.
  final Color? hue;

  const MerchantAvatar({super.key, required this.name, this.hue});

  /// Initials of the first two words: "Chaiwala Junction" -> "CJ".
  static String monogram(String name) {
    final letters = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    const hues = HisabPalette.avatarHues;
    final base =
        hue ?? hues[name.codeUnits.fold(0, (a, b) => a + b) % hues.length];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.alphaBlend(
        base.withValues(alpha: isDark ? 0.28 : 0.12), c.surface);
    final fg = isDark ? Color.lerp(base, Colors.white, 0.55)! : base;
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          monogram(name),
          maxLines: 1,
          style:
              HisabType.label.copyWith(color: fg, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// 64 high row: avatar, title, subtitle (+ optional tag), amount and time.
class TxnRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final int paise;
  final AmountTone tone;
  final String? time;
  final StatusTag? status;
  final VoidCallback? onTap;

  const TxnRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    required this.paise,
    this.tone = AmountTone.debit,
    this.time,
    this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final secondary = HisabType.caption.copyWith(color: c.textSecondary);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: HisabSpace.gutter, vertical: HisabSpace.s12),
          // The amount never takes more than 40% of the row; past that it
          // scales down rather than squeezing the title out.
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                leading,
                const SizedBox(width: HisabSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HisabType.body.copyWith(
                            fontWeight: FontWeight.w500, color: c.textPrimary),
                      ),
                      if (subtitle != null || status != null)
                        Padding(
                          padding: const EdgeInsets.only(top: HisabSpace.s2),
                          child: _SubtitleLine(
                              subtitle: subtitle,
                              style: secondary,
                              status: status),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: HisabSpace.s12),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: AmountText(paise, tone: tone),
                      ),
                      if (time != null)
                        Padding(
                          padding: const EdgeInsets.only(top: HisabSpace.s2),
                          child: Text(time!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: secondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtitle then tag on one line; the tag keeps its width and the subtitle
/// ellipsises into what is left.
class _SubtitleLine extends StatelessWidget {
  final String? subtitle;
  final TextStyle style;
  final StatusTag? status;

  const _SubtitleLine({
    required this.subtitle,
    required this.style,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final gap = subtitle != null && status != null ? HisabSpace.s8 : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (subtitle != null)
            Flexible(
              child: Text(subtitle!,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          SizedBox(width: gap),
          if (status != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth:
                      (constraints.maxWidth - gap).clamp(0, double.infinity)),
              child: status,
            ),
        ],
      ),
    );
  }
}
