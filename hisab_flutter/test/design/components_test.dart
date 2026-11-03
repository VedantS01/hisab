// Every component pumps in both themes at 320 wide with long content, with
// no exceptions and no overflow (a RenderFlex overflow is a test failure).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/design/design.dart';
import 'package:hisab/design/gallery.dart';

import 'harness.dart';

final _components = <String, Widget Function()>{
  'AmountText': () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final role in AmountRole.values)
            for (final tone in AmountTone.values)
              AmountText(-12345678, role: role, tone: tone),
        ],
      ),
  'BalanceHero': () => const BalanceHero(
        label: 'Net balance across all accounts',
        paise: 123456789012,
        delta: '-4% vs last month',
        deltaTone: HisabTone.credit,
      ),
  'AppButton': () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final variant in AppButtonVariant.values)
            for (final size in AppButtonSize.values) ...[
              AppButton(
                  label: 'Import statement',
                  icon: Icons.upload_file,
                  variant: variant,
                  size: size,
                  onPressed: () {}),
              AppButton(
                  label: 'Saving',
                  variant: variant,
                  size: size,
                  onPressed: null),
              AppButton(
                  label: 'Saving',
                  variant: variant,
                  size: size,
                  loading: true,
                  onPressed: () {}),
            ],
        ],
      ),
  'HisabFilterChip': () => Wrap(
        spacing: 8,
        children: [
          HisabFilterChip(label: 'All', selected: true, onSelected: (_) {}),
          HisabFilterChip(label: 'Food', selected: false, onSelected: (_) {}),
          const HisabFilterChip(
              label: 'Disabled', selected: false, onSelected: null),
        ],
      ),
  'SegmentedTabs': () => SegmentedTabs(
        segments: const ['Week', 'Month', 'Year', 'A very long label'],
        selectedIndex: 3,
        onChanged: (_) {},
      ),
  'SurfaceCard': () => Column(
        children: [
          const SurfaceCard(child: Text('Static card')),
          SurfaceCard(onTap: () {}, child: const Text('Tappable card')),
        ],
      ),
  'BentoTile': () => const Row(
        children: [
          Expanded(
            child: BentoTile(
              value: AmountText(9999999999, role: AmountRole.lg),
              label: 'Biggest category this month',
            ),
          ),
          SizedBox(width: 12),
          Expanded(child: BentoTile(value: Text('46'), label: 'Transactions')),
        ],
      ),
  'TxnRow': () => const Column(
        children: [
          TxnRow(
            leading: MerchantAvatar(name: 'IndiGo Airlines'),
            title: 'IndiGo Airlines booking with a very long merchant name',
            subtitle: 'Travel · HDFC credit card ending 4321',
            paise: 1234567890,
            time: 'Yesterday',
            status: StatusTag('Pending', tone: HisabTone.spend),
          ),
          TxnRow(
            leading: MerchantAvatar(name: 'Salary'),
            title: 'Salary',
            paise: 18500000,
            tone: AmountTone.credit,
          ),
        ],
      ),
  'MerchantAvatar': () => Row(
        children: [
          const MerchantAvatar(name: 'Chaiwala Junction'),
          const MerchantAvatar(name: ''),
          MerchantAvatar(name: 'Zomato', hue: HisabPalette.avatarHues.first),
        ],
      ),
  'SectionHeader': () => SectionHeader(
        title: 'Recent transactions from every account',
        actionLabel: 'See all',
        onAction: () {},
      ),
  'InsightCarousel': () => InsightCarousel(cards: [
        for (var i = 0; i < 4; i++)
          InsightCard(
            icon: Icons.trending_up,
            title: 'Food spending is up 32% this month',
            body: 'You spent ₹4,120 more on food than your three-month '
                'average, mostly on weekday dinners ordered after 10 pm.',
            onTap: () {},
          ),
      ]),
  'BudgetBar': () => const Column(
        children: [
          BudgetBar(value: 0),
          BudgetBar(value: 0.5),
          BudgetBar(value: 0.9),
          BudgetBar(value: 1.5),
        ],
      ),
  'StatusTag': () => Wrap(
        children: [
          for (final tone in HisabTone.values)
            StatusTag('Captured', tone: tone),
        ],
      ),
  'SkeletonBox': () => const Row(
        children: [
          SkeletonBox(width: 40, height: 40, radius: HisabRadius.pill),
          Expanded(child: SkeletonBox(height: 14)),
        ],
      ),
  'EmptyState': () => EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions yet',
        message: 'Import a statement to see where your money goes.',
        actionLabel: 'Import statement',
        onAction: () {},
      ),
  'InfoBanner': () => Column(
        children: [
          const InfoBanner(
            icon: Icons.cloud_off_outlined,
            message: 'Your device is offline.',
            tone: HisabTone.neutral,
          ),
          for (final tone in HisabTone.values)
            InfoBanner(
              icon: Icons.notifications_active_outlined,
              message: 'Capture payments from bank alerts as they arrive.',
              tone: tone,
              actionLabel: 'Allow',
              onAction: () {},
            ),
        ],
      ),
  'HisabBottomNav': () => HisabBottomNav(
        currentIndex: 1,
        onTap: (_) {},
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
};

void main() {
  for (final theme in themes.entries) {
    group('${theme.key} theme', () {
      for (final component in _components.entries) {
        testWidgets(component.key, (tester) async {
          await pumpComponent(tester, component.value(), dark: theme.value);
          await tester.pump(HisabMotion.slow);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('LargeHeader collapses', (tester) async {
        await pumpApp(
          tester,
          Scaffold(
            body: CustomScrollView(slivers: [
              const LargeHeader(title: 'Spends this month'),
              SliverList.list(children: [
                for (var i = 0; i < 30; i++)
                  TxnRow(
                    leading: MerchantAvatar(name: 'Merchant $i'),
                    title: 'Merchant $i',
                    paise: i * 1000,
                  ),
              ]),
            ]),
          ),
          dark: theme.value,
        );
        const title = 'Spends this month';
        final large = find.byWidgetPredicate((w) =>
            w is Text &&
            w.data == title &&
            w.style?.fontSize == HisabType.headline.fontSize);
        final toolbar = find.byWidgetPredicate(
            (w) => w is Text && w.data == title && w.style == null);
        double opacityOf(Finder text) => tester
            .widget<Opacity>(
                find.ancestor(of: text, matching: find.byType(Opacity)).first)
            .opacity;
        expect(opacityOf(large), 1);
        expect(opacityOf(toolbar), 0);

        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pump();
        expect(opacityOf(large), 0);
        expect(opacityOf(toolbar), 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('showHisabSheet', (tester) async {
        await pumpApp(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => AppButton(
                label: 'Open',
                onPressed: () => showHisabSheet<void>(
                  context: context,
                  title: 'Edit category',
                  builder: (_) => const Text('Sheet body'),
                ),
              ),
            ),
          ),
          dark: theme.value,
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Edit category'), findsOneWidget);
        expect(find.text('Sheet body'), findsOneWidget);
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.showDragHandle ?? true, isTrue);
        expect(tester.takeException(), isNull);
      });

      testWidgets('DesignGallery scrolls end to end', (tester) async {
        await pumpApp(tester, const DesignGallery(), dark: theme.value);
        for (var i = 0; i < 12; i++) {
          await tester.drag(
              find.byType(CustomScrollView), const Offset(0, -500));
          await tester.pump(HisabMotion.slow);
        }
        expect(find.text('Overlays'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
