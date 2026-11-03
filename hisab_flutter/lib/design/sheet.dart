/// Modal bottom sheet: top radius 28, 36x4 handle, 40% scrim (all from the
/// theme), gutter padding and an optional title.
library;

import 'package:flutter/material.dart';

import 'hisab_design.dart';
import 'tokens.dart';

/// Content from [builder] sizes the sheet; return a scrollable if it can be
/// taller than the screen.
Future<T?> showHisabSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              HisabSpace.gutter, 0, HisabSpace.gutter, HisabSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: HisabSpace.s12),
                  child: Text(title,
                      style: HisabType.title
                          .copyWith(color: context.hisab.textPrimary)),
                ),
              Flexible(child: builder(context)),
            ],
          ),
        ),
      ),
    ),
  );
}
