/// The install's AI credits, as the gateway reports them: what Find in text
/// and monthly insights spend. In-app purchases will top this up; until then
/// every install's free grant and daily allowance are all there is.
library;

import 'package:flutter/material.dart';
import 'package:hisab_agents/hisab_agents.dart';

import '../services/hisab_model.dart';
import '../theme.dart';

class AiCreditsCard extends StatefulWidget {
  const AiCreditsCard({super.key});

  @override
  State<AiCreditsCard> createState() => _AiCreditsCardState();
}

class _AiCreditsCardState extends State<AiCreditsCard> {
  late Future<GatewayAccount> _account = gateway.account();

  void _refresh() => setState(() => _account = gateway.account(refresh: true));

  @override
  Widget build(BuildContext context) => Card(
        child: FutureBuilder<GatewayAccount>(
          future: _account,
          builder: (context, snap) {
            final account = snap.data;
            final failed = snap.hasError;
            return ListTile(
              leading: const Icon(Icons.auto_awesome, color: HisabTheme.khataRed),
              title: const Text('AI credits'),
              subtitle: Text(account != null
                  ? creditsLine(account)
                  : failed
                      ? 'Connect to the internet to see your balance.'
                      : 'Checking…'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _explain(context, account),
            );
          },
        ),
      );

  /// "287 left · 58 more today" / "None left · more tomorrow".
  static String creditsLine(GatewayAccount a) {
    if (a.credits <= 0) return 'None left. Top-ups are coming soon.';
    if (a.dailyRemaining <= 0) return '${a.credits} left · more tomorrow';
    return '${a.credits} left · ${a.dailyRemaining} more today';
  }

  Future<void> _explain(BuildContext context, GatewayAccount? account) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI credits', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Find in text and monthly insights ask a cloud model through Hisab\'s '
              'gateway. Each question costs one credit; an insights run asks a few. '
              'Every install starts with ${account?.granted ?? 300} and a day allows '
              '${account?.dailyCap ?? 60}.'
              '${account != null ? '\n\nYou have ${account.credits} left and have used '
                  '${account.dailyUsed} today.' : ''}',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.add_card),
                  label: const Text('Get more credits — soon'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _refresh();
                    Navigator.pop(context);
                  },
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
