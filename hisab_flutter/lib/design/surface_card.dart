/// Flat outlined surfaces: [SurfaceCard] for content, [BentoTile] for one
/// number and its label in a two-column summary.
library;

import 'package:flutter/material.dart';

import 'hisab_design.dart';
import 'tokens.dart';

/// Radius 16, 1px outline, no shadow. Scales to 0.98 while pressed when
/// [onTap] is set.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const SurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(HisabSpace.s16),
  });

  @override
  Widget build(BuildContext context) => _Surface(
        radius: HisabRadius.r16,
        padding: padding,
        onTap: onTap,
        child: child,
      );
}

/// Radius 20 tile: [value] (styled title-lg, tabular) over a [label]. Put
/// two in a Row of Expanded for the bento grid.
class BentoTile extends StatelessWidget {
  final Widget value;
  final String label;
  final VoidCallback? onTap;

  const BentoTile({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    return _Surface(
      radius: HisabRadius.r20,
      padding: const EdgeInsets.all(HisabSpace.s16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: DefaultTextStyle.merge(
              style:
                  HisabType.titleLg.copyWith(fontFeatures: HisabType.tabular),
              child: value,
            ),
          ),
          const SizedBox(height: HisabSpace.s4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HisabType.label.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}

class _Surface extends StatefulWidget {
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Widget child;

  const _Surface({
    required this.radius,
    required this.padding,
    required this.onTap,
    required this.child,
  });

  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final content = Padding(padding: widget.padding, child: widget.child);
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: HisabMotion.fast,
      curve: HisabMotion.curve,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.radius),
          side: BorderSide(color: c.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.onTap == null
            ? content
            : InkWell(
                onTap: widget.onTap,
                onHighlightChanged: (value) => setState(() => _pressed = value),
                child: content,
              ),
      ),
    );
  }
}
