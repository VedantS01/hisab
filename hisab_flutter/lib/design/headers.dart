/// Section titles and the collapsing large-title app bar.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'hisab_design.dart';
import 'tokens.dart';

/// Full-bleed row: 17/600 title and an optional text action. Owns its gutter,
/// like `TxnRow`.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
            start: HisabSpace.gutter, end: HisabSpace.s8),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HisabType.title.copyWith(color: c.textPrimary)),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: HisabSpace.s8),
                  textStyle:
                      HisabType.label.copyWith(fontWeight: FontWeight.w600),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pinned sliver app bar: a 28/700 title that collapses into a 17/600 one,
/// over a blurred, translucent background. Use inside a CustomScrollView.
class LargeHeader extends StatelessWidget {
  final String title;
  final List<Widget>? actions;

  const LargeHeader({super.key, required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    return SliverAppBar(
      pinned: true,
      expandedHeight: kToolbarHeight + 52,
      backgroundColor: c.bg.withValues(alpha: 0.85),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      actions: actions,
      title: _Fade(
        appearing: true,
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: const SizedBox.expand(),
            ),
          ),
          PositionedDirectional(
            start: HisabSpace.gutter,
            end: HisabSpace.gutter,
            bottom: HisabSpace.s12,
            child: _Fade(
              appearing: false,
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HisabType.headline.copyWith(color: c.textPrimary)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Fade(
              appearing: true,
              child: Divider(height: 1, color: c.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades with the app bar's collapse: in over the last 40% when [appearing],
/// out over the first 60% otherwise.
class _Fade extends StatelessWidget {
  final bool appearing;
  final Widget child;

  const _Fade({required this.appearing, required this.child});

  @override
  Widget build(BuildContext context) {
    final settings =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    var collapsed = 0.0;
    if (settings != null && settings.maxExtent > settings.minExtent) {
      collapsed = ((settings.maxExtent - settings.currentExtent) /
              (settings.maxExtent - settings.minExtent))
          .clamp(0.0, 1.0);
    }
    final opacity = appearing
        ? ((collapsed - 0.6) / 0.4).clamp(0.0, 1.0)
        : (1 - collapsed / 0.6).clamp(0.0, 1.0);
    return Opacity(opacity: opacity, child: child);
  }
}
