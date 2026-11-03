// Behaviour of the design-system components: amount formatting and colour,
// and that each interactive component calls back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/design/design.dart';

import 'harness.dart';

void main() {
  group('AmountText.format', () {
    test('groups Indian style with paise', () {
      expect(AmountText.format(12345678), '₹1,23,456.78');
      expect(AmountText.format(123456789012), '₹1,23,45,67,890.12');
      expect(AmountText.format(99900), '₹999.00');
      expect(AmountText.format(100000), '₹1,000.00');
      expect(AmountText.format(5), '₹0.05');
      expect(AmountText.format(0), '₹0.00');
    });

    test('signs by tone', () {
      expect(AmountText.format(-12345678), '-₹1,23,456.78');
      expect(AmountText.format(250000, tone: AmountTone.credit), '+₹2,500.00');
      expect(AmountText.format(45000, tone: AmountTone.debit), '-₹450.00');
      // Credit and debit show the magnitude; the tone owns the sign.
      expect(AmountText.format(-45000, tone: AmountTone.debit), '-₹450.00');
      expect(AmountText.format(-250000, tone: AmountTone.credit), '+₹2,500.00');
      expect(AmountText.format(230000, tone: AmountTone.spend), '₹2,300.00');
      expect(AmountText.format(-230000, tone: AmountTone.spend), '-₹2,300.00');
    });
  });

  group('AmountText widget', () {
    TextStyle renderedStyle(WidgetTester tester) => tester
        .widget<RichText>(find.descendant(
            of: find.byType(AmountText), matching: find.byType(RichText)))
        .text
        .style!;

    for (final theme in themes.entries) {
      final colors = theme.value ? HisabColors.dark : HisabColors.light;

      testWidgets('credit is green, tabular (${theme.key})', (tester) async {
        await pumpComponent(
            tester, const AmountText(250000, tone: AmountTone.credit),
            dark: theme.value);
        expect(find.text('+₹2,500.00'), findsOneWidget);
        final style = renderedStyle(tester);
        expect(style.color, colors.credit);
        expect(
            style.fontFeatures, contains(const FontFeature.tabularFigures()));
      });

      testWidgets('debit is neutral ink, never brand (${theme.key})',
          (tester) async {
        await pumpComponent(
            tester, const AmountText(45000, tone: AmountTone.debit),
            dark: theme.value);
        expect(find.text('-₹450.00'), findsOneWidget);
        final style = renderedStyle(tester);
        expect(style.color, colors.textPrimary);
        expect(style.color, isNot(colors.brand));
      });
    }

    testWidgets('hero shrinks the rupee glyph', (tester) async {
      await pumpComponent(tester, const AmountText(100, role: AmountRole.hero));
      final root = tester
          .widget<RichText>(find.descendant(
              of: find.byType(AmountText), matching: find.byType(RichText)))
          .text as TextSpan;
      final glyph = (root.children!.single as TextSpan).children!.first;
      expect(glyph.toPlainText(), '₹');
      expect(glyph.style!.fontSize, closeTo(24, 0.01));
    });
  });

  testWidgets('SegmentedTabs calls back with the tapped index', (tester) async {
    final taps = <int>[];
    await pumpComponent(
      tester,
      SegmentedTabs(
        segments: const ['Week', 'Month', 'Year'],
        selectedIndex: 0,
        onChanged: taps.add,
      ),
    );
    await tester.tap(find.text('Year'));
    await tester.tap(find.text('Month'));
    await tester.tap(find.text('Week')); // already selected
    expect(taps, [2, 1]);
  });

  testWidgets('SurfaceCard onTap fires and scales while pressed',
      (tester) async {
    var taps = 0;
    await pumpComponent(
        tester, SurfaceCard(onTap: () => taps++, child: const Text('Card')));
    double scale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale(), 1);
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Card')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scale(), 0.98);
    await gesture.up();
    await tester.pump(HisabMotion.slow);
    expect(scale(), 1);
    expect(taps, 1);
  });

  testWidgets('EmptyState CTA fires', (tester) async {
    var taps = 0;
    await pumpComponent(
      tester,
      EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions yet',
        message: 'Import a statement to begin.',
        actionLabel: 'Import statement',
        onAction: () => taps++,
      ),
    );
    await tester.tap(find.text('Import statement'));
    expect(taps, 1);
  });

  testWidgets('AppButton ignores taps while loading', (tester) async {
    var taps = 0;
    await pumpComponent(tester,
        AppButton(label: 'Save', loading: true, onPressed: () => taps++));
    await tester.tap(find.byType(AppButton), warnIfMissed: false);
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('HisabFilterChip reports the toggled selection', (tester) async {
    final changes = <bool>[];
    await pumpComponent(
      tester,
      Column(children: [
        HisabFilterChip(
            label: 'Food', selected: false, onSelected: changes.add),
        HisabFilterChip(label: 'All', selected: true, onSelected: changes.add),
      ]),
    );
    await tester.tap(find.text('Food'));
    await tester.tap(find.text('All'));
    expect(changes, [true, false]);
  });

  testWidgets('HisabBottomNav fills the active icon and reports taps',
      (tester) async {
    final taps = <int>[];
    await pumpComponent(
      tester,
      HisabBottomNav(
        currentIndex: 0,
        onTap: taps.add,
        items: const [
          HisabNavItem(
              icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
          HisabNavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings'),
        ],
      ),
    );
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    await tester.tap(find.text('Settings'));
    expect(taps, [1]);
  });

  testWidgets('InsightCarousel shows at most three cards', (tester) async {
    await pumpComponent(
      tester,
      InsightCarousel(cards: [
        for (var i = 0; i < 5; i++)
          InsightCard(icon: Icons.bolt, title: 'Insight $i', body: 'Body $i'),
      ]),
    );
    final dots = find.descendant(
        of: find.byType(InsightCarousel),
        matching: find.byType(AnimatedContainer));
    expect(dots, findsNWidgets(3));
  });

  testWidgets('showUndoSnackbar offers Undo', (tester) async {
    var undone = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => AppButton(
            label: 'Delete',
            onPressed: () => showUndoSnackbar(context,
                message: 'Transaction deleted', onUndo: () => undone++),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Transaction deleted'), findsNothing);
  });

  testWidgets('showUndoSnackbar times out after 4 s', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => AppButton(
            label: 'Delete',
            onPressed: () => showUndoSnackbar(context,
                message: 'Transaction deleted', onUndo: () {}),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Transaction deleted'), findsNothing);
  });

  test('MerchantAvatar monogram', () {
    expect(MerchantAvatar.monogram('Chaiwala Junction'), 'CJ');
    expect(MerchantAvatar.monogram('  zomato  '), 'Z');
    expect(MerchantAvatar.monogram('Amazon Pay India'), 'AP');
    expect(MerchantAvatar.monogram(''), '?');
  });
}
