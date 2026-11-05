/// How feed cards look and where they go.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/design.dart';
import '../screens/transactions_screen.dart';
import '../services/incoming_router.dart';
import '../widgets/import_flow.dart';
import 'home_feed.dart';

/// The icons a feed may name, and the insights agent's kinds.
abstract final class FeedIcons {
  static const _byName = <String, IconData>{
    'info': Icons.info_outline,
    'lightbulb': Icons.lightbulb_outline,
    'campaign': Icons.campaign_outlined,
    'security': Icons.shield_outlined,
    'auto_awesome': Icons.auto_awesome,
    'spending': Icons.pie_chart_outline,
    'change': Icons.trending_up,
    'recurring': Icons.autorenew,
    'merchant': Icons.storefront_outlined,
    'saving': Icons.savings_outlined,
  };

  static IconData of(String name) => _byName[name] ?? Icons.info_outline;
}

class FeedCardView extends StatelessWidget {
  final FeedCard card;
  const FeedCardView({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final action = card.action;
    return Padding(
      padding: const EdgeInsets.only(bottom: HisabSpace.s8),
      child: SurfaceCard(
        onTap: action == null ? null : () => openFeedAction(context, action),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(FeedIcons.of(card.icon), color: context.hisab.brand),
            const SizedBox(width: HisabSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.title, style: type.titleMedium),
                  const SizedBox(height: HisabSpace.s2),
                  Text(card.body,
                      style: type.bodySmall?.copyWith(color: context.hisab.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Goes where [action] says. An action this build doesn't know does nothing.
Future<void> openFeedAction(BuildContext context, FeedAction action) async {
  switch (action.open) {
    case 'transactions':
      TransactionsScreen.segment.value = 0;
      TransactionsScreen.requestedCategory.value = action.category;
      IncomingRouter.link.value = LinkTarget.transactions;
    case 'detections':
      TransactionsScreen.segment.value = 1;
      IncomingRouter.link.value = LinkTarget.transactions;
    case 'import':
      await showImportFlow(context);
    case 'url':
      final uri = Uri.tryParse(action.url ?? '');
      if (uri != null && uri.scheme == 'https') {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
  }
}
