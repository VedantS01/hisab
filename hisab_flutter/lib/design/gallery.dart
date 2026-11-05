/// Every design-system component on one scrolling page, for screenshots and
/// eyeballing. Not wired into the app.
library;

import 'package:flutter/material.dart';

import 'design.dart';

class DesignGallery extends StatefulWidget {
  const DesignGallery({super.key});

  @override
  State<DesignGallery> createState() => _DesignGalleryState();
}

class _DesignGalleryState extends State<DesignGallery> {
  /// Null follows the ambient theme.
  bool? _dark;
  final _filters = {
    'All': true,
    'Food': false,
    'Travel': false,
    'Bills': false
  };
  var _segment = 1;
  var _tab = 0;

  static Widget _pad(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: HisabSpace.gutter),
        child: child,
      );

  static const _gap = SizedBox(height: HisabSpace.s12);

  @override
  Widget build(BuildContext context) {
    final dark = _dark ?? Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: dark ? HisabDesign.dark() : HisabDesign.light(),
      child: Builder(builder: (context) => _scaffold(context, dark)),
    );
  }

  Widget _scaffold(BuildContext context, bool dark) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          LargeHeader(
            title: 'Design system',
            actions: [
              IconButton(
                tooltip: dark ? 'Light theme' : 'Dark theme',
                icon: Icon(dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined),
                onPressed: () => setState(() => _dark = !dark),
              ),
            ],
          ),
          SliverList.list(children: [
            const SectionHeader(title: 'Balance'),
            _pad(const BalanceHero(
              label: 'Spent this month',
              paise: 4523050,
              delta: '+12% vs September',
              deltaTone: HisabTone.spend,
            )),
            _gap,
            SectionHeader(
                title: 'Bento', actionLabel: 'See all', onAction: () {}),
            _pad(Row(
              children: [
                Expanded(
                  child: BentoTile(
                    value: const AmountText(1250000, role: AmountRole.lg),
                    label: 'Biggest category',
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: HisabSpace.s12),
                const Expanded(
                  child: BentoTile(value: Text('46'), label: 'Transactions'),
                ),
              ],
            )),
            const SectionHeader(title: 'Amounts'),
            _pad(const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AmountText(12345678, role: AmountRole.hero),
                AmountText(250000,
                    role: AmountRole.lg, tone: AmountTone.credit),
                AmountText(45000, tone: AmountTone.debit),
                AmountText(230000, role: AmountRole.sm, tone: AmountTone.spend),
              ],
            )),
            const SectionHeader(title: 'Buttons'),
            _pad(Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                    label: 'Import statement',
                    icon: Icons.upload_file,
                    onPressed: () {}),
                _gap,
                AppButton(
                    label: 'Edit rule',
                    variant: AppButtonVariant.tonal,
                    size: AppButtonSize.md,
                    onPressed: () {}),
                _gap,
                Wrap(
                  spacing: HisabSpace.s12,
                  runSpacing: HisabSpace.s12,
                  children: [
                    AppButton(
                        label: 'Saving',
                        loading: true,
                        size: AppButtonSize.md,
                        onPressed: () {}),
                    const AppButton(
                        label: 'Disabled',
                        size: AppButtonSize.md,
                        onPressed: null),
                    AppButton(
                        label: 'Skip',
                        variant: AppButtonVariant.text,
                        size: AppButtonSize.sm,
                        onPressed: () {}),
                  ],
                ),
              ],
            )),
            const SectionHeader(title: 'Filters'),
            _pad(Wrap(
              spacing: HisabSpace.s8,
              runSpacing: HisabSpace.s8,
              children: [
                for (final entry in _filters.entries)
                  HisabFilterChip(
                    label: entry.key,
                    selected: entry.value,
                    onSelected: (value) =>
                        setState(() => _filters[entry.key] = value),
                  ),
              ],
            )),
            _gap,
            _pad(SegmentedTabs(
              segments: const ['Week', 'Month', 'Year'],
              selectedIndex: _segment,
              onChanged: (index) => setState(() => _segment = index),
            )),
            const SectionHeader(title: 'Transactions'),
            _pad(SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  TxnRow(
                    leading: const MerchantAvatar(name: 'Chaiwala Junction'),
                    title: 'Chaiwala Junction',
                    subtitle: 'Food · UPI',
                    paise: 4500,
                    time: '9:41 am',
                    status: const StatusTag('Captured', tone: HisabTone.credit),
                    onTap: () {},
                  ),
                  const Divider(indent: 68),
                  TxnRow(
                    leading: const MerchantAvatar(name: 'Salary'),
                    title: 'Salary — Acme Pvt Ltd',
                    subtitle: 'HDFC ••4321',
                    paise: 18500000,
                    tone: AmountTone.credit,
                    time: '1 Oct',
                    onTap: () {},
                  ),
                  const Divider(indent: 68),
                  TxnRow(
                    leading: const MerchantAvatar(name: 'Indigo Airlines'),
                    title:
                        'IndiGo Airlines booking with a very long merchant name',
                    subtitle: 'Travel',
                    paise: 1245000,
                    time: 'Yesterday',
                    status: const StatusTag('Pending', tone: HisabTone.spend),
                    onTap: () {},
                  ),
                ],
              ),
            )),
            const SectionHeader(title: 'Insights'),
            InsightCarousel(cards: [
              InsightCard(
                icon: Icons.trending_up,
                title: 'Food is up 32%',
                body:
                    'You spent ₹4,120 more on food this month than your three-month average.',
                onTap: () {},
              ),
              InsightCard(
                icon: Icons.autorenew,
                title: '3 subscriptions renew soon',
                body: 'Netflix, Spotify and iCloud renew in the next 7 days.',
                onTap: () {},
              ),
              const InsightCard(
                icon: Icons.savings_outlined,
                title: 'Good week',
                body: 'Spending is 18% below a usual week.',
              ),
            ]),
            const SectionHeader(title: 'Budgets'),
            _pad(const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BudgetBar(value: 0.45),
                _gap,
                BudgetBar(value: 0.86),
                _gap,
                BudgetBar(value: 1.2),
              ],
            )),
            const SectionHeader(title: 'Status'),
            _pad(const Wrap(
              spacing: HisabSpace.s8,
              children: [
                StatusTag('Pending', tone: HisabTone.spend),
                StatusTag('Captured', tone: HisabTone.credit),
                StatusTag('Edited', tone: HisabTone.brand),
                StatusTag('Manual'),
              ],
            )),
            const SectionHeader(title: 'Loading'),
            _pad(const Row(
              children: [
                SkeletonBox(width: 40, height: 40, radius: HisabRadius.pill),
                SizedBox(width: HisabSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 160, height: 14),
                      SizedBox(height: HisabSpace.s8),
                      SkeletonBox(width: 96, height: 10),
                    ],
                  ),
                ),
                SkeletonBox(width: 64, height: 14),
              ],
            )),
            const SectionHeader(title: 'Banners'),
            _pad(Column(
              children: [
                const InfoBanner(
                  icon: Icons.cloud_off_outlined,
                  message: 'Your device is offline.',
                  tone: HisabTone.neutral,
                ),
                _gap,
                InfoBanner(
                  icon: Icons.notifications_active_outlined,
                  message: 'Capture payments from bank alerts as they arrive.',
                  actionLabel: 'Allow',
                  onAction: () {},
                ),
              ],
            )),
            const SectionHeader(title: 'Empty state'),
            _pad(SurfaceCard(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions yet',
                message: 'Import a statement to see where your money goes.',
                actionLabel: 'Import statement',
                onAction: () {},
              ),
            )),
            const SectionHeader(title: 'Overlays'),
            _pad(Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Sheet',
                    variant: AppButtonVariant.tonal,
                    size: AppButtonSize.md,
                    onPressed: () => showHisabSheet<void>(
                      context: context,
                      title: 'Edit category',
                      builder: (context) =>
                          const Text('Sheet content goes here.'),
                    ),
                  ),
                ),
                const SizedBox(width: HisabSpace.s12),
                Expanded(
                  child: AppButton(
                    label: 'Undo',
                    variant: AppButtonVariant.tonal,
                    size: AppButtonSize.md,
                    onPressed: () => showUndoSnackbar(context,
                        message: 'Transaction deleted', onUndo: () {}),
                  ),
                ),
              ],
            )),
            const SizedBox(height: HisabSpace.s32),
          ]),
        ],
      ),
      bottomNavigationBar: HisabBottomNav(
        currentIndex: _tab,
        onTap: (index) => setState(() => _tab = index),
        items: const [
          HisabNavItem(
              icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
          HisabNavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long,
              label: 'Spends'),
          HisabNavItem(
              icon: Icons.insights_outlined,
              activeIcon: Icons.insights,
              label: 'Insights'),
          HisabNavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings'),
        ],
      ),
    );
  }
}
