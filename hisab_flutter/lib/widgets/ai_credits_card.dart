/// The install's AI credits, as the gateway reports them: what Find in text
/// and monthly insights spend. In-app purchases will top this up; until then
/// every install's daily allowance (spent first) and free grant are all there is.
library;

import 'package:flutter/material.dart';
import 'package:hisab_agents/hisab_agents.dart';

import '../design/design.dart';
import '../services/hisab_model.dart';

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
              leading: const IconTile(Icons.auto_awesome),
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

  /// "58 free today · 287 banked" / "None free today · 287 banked".
  static String creditsLine(GatewayAccount a) {
    if (!a.canSpend) return 'None left today. More tomorrow; top-ups are coming soon.';
    final today = a.dailyRemaining > 0 ? '${a.dailyRemaining} free today' : 'None free today';
    return '$today · ${a.credits} banked';
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
              'Every day brings ${account?.dailyCap ?? 60} free credits, spent first. '
              'Only once those are gone does Hisab draw on your banked credits; '
              'every install starts with ${account?.granted ?? 300}.'
              '${account != null ? '\n\nToday: ${account.dailyRemaining} of ${account.dailyCap} '
                  'free left. Banked: ${account.credits}.' : ''}',
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
