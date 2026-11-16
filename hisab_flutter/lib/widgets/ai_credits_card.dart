/// The install's AI credits, as the gateway reports them: what Find in text
/// and monthly insights spend. Today's free allowance spends first, then the
/// banked balance; on iPhone, credit packs and Hisab Plus (a bigger daily
/// allowance) come from the App Store ([HisabStore]).
library;

import 'package:flutter/material.dart';
import 'package:hisab_agents/hisab_agents.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/design.dart';
import '../services/hisab_model.dart';
import '../services/store.dart';

class AiCreditsCard extends StatefulWidget {
  const AiCreditsCard({super.key});

  @override
  State<AiCreditsCard> createState() => _AiCreditsCardState();
}

class _AiCreditsCardState extends State<AiCreditsCard> {
  late Future<GatewayAccount> _account = gateway.account();

  void _refresh() => setState(() => _account = gateway.account(refresh: true));

  @override
  void initState() {
    super.initState();
    HisabStore.account.addListener(_refresh);
  }

  @override
  void dispose() {
    HisabStore.account.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        child: FutureBuilder<GatewayAccount>(
          future: _account,
          builder: (context, snap) {
            final account = snap.data;
            final failed = snap.hasError;
            return ListTile(
              leading: const IconTile(Icons.auto_awesome),
              title: Row(children: [
                const Text('AI credits'),
                if (account?.plus ?? false) ...[
                  const SizedBox(width: HisabSpace.s8),
                  const StatusTag('Plus', tone: HisabTone.brand),
                ],
              ]),
              subtitle: Text(account != null
                  ? creditsLine(account)
                  : failed
                      ? 'Connect to the internet to see your balance.'
                      : 'Checking…'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await showCreditsSheet(context, account);
                if (mounted) _refresh();
              },
            );
          },
        ),
      );

  /// "58 free today · 287 banked" / "None free today · 287 banked".
  static String creditsLine(GatewayAccount a) {
    if (!a.canSpend) {
      return HisabStore.available
          ? 'None left today. Get more, or more come tomorrow.'
          : 'None left today. More come tomorrow.';
    }
    final today = a.dailyRemaining > 0
        ? '${a.dailyRemaining} free today'
        : 'None free today';
    return '$today · ${a.credits} banked';
  }
}

Future<void> showCreditsSheet(BuildContext context, GatewayAccount? account) =>
    showHisabSheet<void>(
      context: context,
      title: 'AI credits',
      builder: (context) => SingleChildScrollView(
        child: _CreditsSheet(initial: account),
      ),
    );

class _CreditsSheet extends StatefulWidget {
  final GatewayAccount? initial;
  const _CreditsSheet({required this.initial});

  @override
  State<_CreditsSheet> createState() => _CreditsSheetState();
}

class _CreditsSheetState extends State<_CreditsSheet> {
  late GatewayAccount? _account = widget.initial;
  final Future<List<ProductDetails>> _products = HisabStore.products();

  @override
  void initState() {
    super.initState();
    HisabStore.account.addListener(_took);
    HisabStore.status.value = const StoreStatus();
  }

  @override
  void dispose() {
    HisabStore.account.removeListener(_took);
    super.dispose();
  }

  void _took() => setState(() => _account = HisabStore.account.value);

  @override
  Widget build(BuildContext context) {
    final a = _account;
    final c = context.hisab;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Find in text and monthly insights ask a cloud model through Hisab\'s '
          'gateway. Each question costs one credit; an insights run asks a few. '
          'Every day brings ${a?.dailyCap ?? 60} free credits, spent first. Only '
          'once those are gone does Hisab draw on your banked credits.',
          style: HisabType.body.copyWith(color: c.textSecondary),
        ),
        if (a != null) ...[
          const SizedBox(height: HisabSpace.s12),
          Row(children: [
            _stat('Free today', '${a.dailyRemaining} of ${a.dailyCap}'),
            _stat('Banked', '${a.credits}'),
          ]),
          if (a.plus)
            Padding(
              padding: const EdgeInsets.only(top: HisabSpace.s8),
              child: Text('Hisab Plus until ${_day(a.plusUntil!)}',
                  style: HisabType.caption.copyWith(color: c.brandText)),
            ),
        ],
        if (HisabStore.available) ...[
          const Divider(height: 32),
          FutureBuilder<List<ProductDetails>>(
            future: _products,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator()));
              }
              final products = snap.data ?? const [];
              if (products.isEmpty) {
                return Text('The App Store is not reachable right now.',
                    style: HisabType.body.copyWith(color: c.textSecondary));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in products)
                    _ProductTile(product: p, plusActive: a?.plus ?? false),
                ],
              );
            },
          ),
          ValueListenableBuilder<StoreStatus>(
            valueListenable: HisabStore.status,
            builder: (context, status, _) => Column(children: [
              if (status.busy) const LinearProgressIndicator(),
              if (status.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: HisabSpace.s8),
                  child: Text(status.message!,
                      textAlign: TextAlign.center,
                      style: HisabType.caption
                          .copyWith(color: status.error ? c.spend : c.credit)),
                ),
            ]),
          ),
          const SizedBox(height: HisabSpace.s8),
          Text(
            'Hisab Plus renews monthly until cancelled in Settings › Apple ID › '
            'Subscriptions; payment is charged to your Apple ID. Credits you buy '
            'stay on this iPhone\'s Hisab and follow it to a new iPhone through '
            'iCloud Keychain.',
            style: HisabType.caption.copyWith(color: c.textTertiary),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                  onPressed: HisabStore.restore,
                  child: const Text('Restore purchases')),
              TextButton(
                  onPressed: () => launchUrl(Uri.parse(HisabStore.termsUrl)),
                  child: const Text('Terms of Use')),
              TextButton(
                  onPressed: () => launchUrl(Uri.parse(HisabStore.privacyUrl)),
                  child: const Text('Privacy Policy')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: HisabType.caption
                  .copyWith(color: context.hisab.textSecondary)),
          Text(value, style: HisabType.title),
        ]),
      );

  static String _day(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final l = d.toLocal();
    return '${l.day} ${months[l.month - 1]} ${l.year}';
  }
}

class _ProductTile extends StatelessWidget {
  final ProductDetails product;
  final bool plusActive;
  const _ProductTile({required this.product, required this.plusActive});

  @override
  Widget build(BuildContext context) {
    final plus = product.id == HisabStore.plusMonthly;
    final (title, subtitle) = switch (product.id) {
      HisabStore.credits100 => ('100 credits', 'Banked; never expire'),
      HisabStore.credits500 => ('500 credits', 'Banked; never expire'),
      _ => ('Hisab Plus', '300 free credits every day · monthly'),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: IconTile(plus ? Icons.workspace_premium_outlined : Icons.bolt),
      title: Text(title),
      subtitle: Text(plus ? '$subtitle · ${product.price}/month' : subtitle),
      trailing: ValueListenableBuilder<StoreStatus>(
        valueListenable: HisabStore.status,
        builder: (context, status, _) => FilledButton(
          onPressed: status.busy || (plus && plusActive)
              ? null
              : () => HisabStore.buy(product),
          child: Text(plus && plusActive ? 'Active' : product.price),
        ),
      ),
    );
  }
}
