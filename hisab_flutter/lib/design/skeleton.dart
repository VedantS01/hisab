/// Shimmering placeholder; give it the radius of what it stands in for.
library;

import 'package:flutter/material.dart';

import 'hisab_design.dart';
import 'tokens.dart';

class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = HisabRadius.r8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: HisabMotion.shimmer)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final highlight =
        Theme.of(context).brightness == Brightness.dark ? c.outline : c.surface;
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: c.sunken,
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: still
                ? null
                : LinearGradient(
                    colors: [c.sunken, highlight, c.sunken],
                    stops: const [0.35, 0.5, 0.65],
                    transform: _Sweep(_controller.value),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Slides the gradient from one width left of the box to one width right.
class _Sweep extends GradientTransform {
  final double t;

  const _Sweep(this.t);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * t - 1), 0, 0);
}
