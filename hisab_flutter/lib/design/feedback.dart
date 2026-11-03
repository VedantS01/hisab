/// Empty states, tinted banners and the undo snackbar.
library;

import 'package:flutter/material.dart';

import 'app_button.dart';
import 'hisab_design.dart';
import 'tokens.dart';

/// An icon in place of an illustration, a title, one line and one CTA.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    return Padding(
      padding: const EdgeInsets.all(HisabSpace.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(color: c.sunken, shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: c.textSecondary),
          ),
          const SizedBox(height: HisabSpace.s16),
          Text(title,
              textAlign: TextAlign.center,
              style: HisabType.title.copyWith(color: c.textPrimary)),
          const SizedBox(height: HisabSpace.s4),
          Text(message,
              textAlign: TextAlign.center,
              style: HisabType.body.copyWith(color: c.textSecondary)),
          if (actionLabel != null) ...[
            const SizedBox(height: HisabSpace.s20),
            AppButton(
                label: actionLabel!,
                onPressed: onAction,
                size: AppButtonSize.md),
          ],
        ],
      ),
    );
  }
}

/// Radius 12 tinted strip: permission prompts, "Your device is offline."
class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final HisabTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  const InfoBanner({
    super.key,
    required this.icon,
    required this.message,
    this.tone = HisabTone.brand,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final colors = c.tone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: HisabSpace.s12, vertical: HisabSpace.s12),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(HisabRadius.r12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.fg),
          const SizedBox(width: HisabSpace.s12),
          Expanded(
            child: Text(message,
                style: HisabType.label.copyWith(color: c.textPrimary)),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor:
                    tone == HisabTone.neutral ? c.brandText : colors.fg,
                padding: const EdgeInsets.symmetric(horizontal: HisabSpace.s8),
                textStyle:
                    HisabType.label.copyWith(fontWeight: FontWeight.w600),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Floating 4 s snackbar with an Undo action; await `.closed` to commit once
/// it times out.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackbar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 4),
    persist: false,
    action: SnackBarAction(label: 'Undo', onPressed: onUndo),
  ));
}
