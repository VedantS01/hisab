/// Money display: [AmountText] for every rupee figure, [BalanceHero] for the
/// one big number at the top of a screen.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import 'hisab_design.dart';
import 'tokens.dart';

enum AmountRole { hero, lg, md, sm }

/// [credit] is green with "+", [debit] neutral ink with "-", [spend] orange
/// emphasis; [plain] and [spend] show "-" only when the value is negative.
enum AmountTone { plain, credit, debit, spend }

class AmountText extends StatelessWidget {
  final int paise;
  final AmountRole role;
  final AmountTone tone;

  const AmountText(
    this.paise, {
    super.key,
    this.role = AmountRole.md,
    this.tone = AmountTone.plain,
  });

  /// "+₹1,23,456.78" style text for [paise] under [tone].
  static String format(int paise, {AmountTone tone = AmountTone.plain}) {
    final (sign, digits) = _parts(paise, tone);
    return '$sign₹$digits';
  }

  static (String, String) _parts(int paise, AmountTone tone) {
    final sign = switch (tone) {
      AmountTone.credit => '+',
      AmountTone.debit => '-',
      AmountTone.plain || AmountTone.spend => paise < 0 ? '-' : '',
    };
    return (sign, Money.formatPaise(paise.abs()).substring(1));
  }

  static TextStyle _styleFor(AmountRole role) => switch (role) {
        AmountRole.hero => HisabType.display,
        AmountRole.lg => HisabType.titleLg,
        AmountRole.md => HisabType.body.copyWith(fontWeight: FontWeight.w600),
        AmountRole.sm => HisabType.label,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final style = _styleFor(role).copyWith(
      fontFeatures: HisabType.tabular,
      color: switch (tone) {
        AmountTone.credit => c.credit,
        AmountTone.spend => c.spend,
        AmountTone.plain || AmountTone.debit => null,
      },
    );
    final (sign, digits) = _parts(paise, tone);
    // The rupee glyph drops to 60% only where the figure is big enough.
    final glyphScale =
        role == AmountRole.hero || role == AmountRole.lg ? 0.6 : 1.0;
    return Text.rich(
      TextSpan(children: [
        if (sign.isNotEmpty) TextSpan(text: sign),
        TextSpan(
          text: '₹',
          style: TextStyle(fontSize: style.fontSize! * glyphScale),
        ),
        TextSpan(text: digits),
      ]),
      style: style,
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// The headline figure: label, hero amount, optional delta pill.
class BalanceHero extends StatelessWidget {
  final String label;
  final int paise;

  /// Short comparison, e.g. "+12% vs last month". Carries its own sign.
  final String? delta;
  final HisabTone deltaTone;

  const BalanceHero({
    super.key,
    required this.label,
    required this.paise,
    this.delta,
    this.deltaTone = HisabTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final tone = c.tone(deltaTone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HisabSpace.s20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(HisabRadius.r20),
        border: Border.all(color: c.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: HisabType.label.copyWith(color: c.textSecondary)),
          const SizedBox(height: HisabSpace.s4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: AmountText(paise, role: AmountRole.hero),
          ),
          if (delta != null) ...[
            const SizedBox(height: HisabSpace.s12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: HisabSpace.s8, vertical: HisabSpace.s2),
              decoration: BoxDecoration(
                color: tone.bg,
                borderRadius: BorderRadius.circular(HisabRadius.pill),
              ),
              child: Text(delta!,
                  style: HisabType.caption
                      .copyWith(color: tone.fg, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}
