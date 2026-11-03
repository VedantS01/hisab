/// 8dp budget progress: brand, then warn from 80%, then spend when over.
library;

import 'package:flutter/material.dart';

import 'hisab_design.dart';
import 'tokens.dart';

class BudgetBar extends StatelessWidget {
  /// Spent divided by budget; above 1 is over budget.
  final double value;

  static const warnAt = 0.8;

  const BudgetBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final fill = value >= 1
        ? c.spend
        : value >= warnAt
            ? c.warn
            : c.brand;
    const radius = BorderRadius.all(Radius.circular(HisabRadius.r4));
    return Semantics(
      value: '${(value * 100).round()}%',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: HisabMotion.slow,
        curve: HisabMotion.curve,
        builder: (context, width, _) => Container(
          height: 8,
          alignment: AlignmentDirectional.centerStart,
          decoration: BoxDecoration(color: c.sunken, borderRadius: radius),
          child: FractionallySizedBox(
            widthFactor: width,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: fill, borderRadius: radius),
            ),
          ),
        ),
      ),
    );
  }
}
