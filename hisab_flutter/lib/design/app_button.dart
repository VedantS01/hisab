/// The one button. Disabled when [AppButton.onPressed] is null; [loading]
/// swaps the label for a spinner without changing the button's size.
library;

import 'package:flutter/material.dart';

import 'hisab_design.dart';
import 'tokens.dart';

enum AppButtonVariant { primary, tonal, text }

/// Heights 52 / 44 / 36.
enum AppButtonSize { lg, md, sm }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.lg,
    this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final (bg, fg) = switch (variant) {
      AppButtonVariant.primary => (c.brand, c.onBrand),
      AppButtonVariant.tonal => (c.brandSoft, c.brandText),
      AppButtonVariant.text => (Colors.transparent, c.brandText),
    };
    final (height, padding) = switch (size) {
      AppButtonSize.lg => (52.0, HisabSpace.s24),
      AppButtonSize.md => (44.0, HisabSpace.s16),
      AppButtonSize.sm => (36.0, HisabSpace.s12),
    };
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: HisabSpace.s8),
        ],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    return IgnorePointer(
      ignoring: loading,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor:
              variant == AppButtonVariant.text ? Colors.transparent : c.sunken,
          disabledForegroundColor: c.textTertiary,
          minimumSize: Size(height, height),
          padding: EdgeInsets.symmetric(horizontal: padding),
          visualDensity: VisualDensity.standard,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(HisabRadius.r12))),
          textStyle: HisabType.button,
        ),
        child: loading
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                      opacity: 0, alwaysIncludeSemantics: true, child: content),
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onPressed == null ? c.textTertiary : fg),
                  ),
                ],
              )
            : content,
      ),
    );
  }
}
