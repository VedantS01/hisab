import 'dart:io';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

DateTime ist(int y, int m, int d, [int hour = 12]) =>
    DateTime.utc(y, m, d, hour).subtract(istOffset);

void main() {
  group('Reconciler', () {
    ReconTxn txn(String id, int day, int paise, Direction dir, String? ref) =>
        ReconTxn(
            id: id,
            date: ist(2026, 4, day),
            amountPaise: paise,
            direction: dir,
            reference: ref);

    test('tier 1 reference match wins over dates', () {
      final result = Reconciler.reconcile(
        app: [txn('a1', 1, 100, Direction.debit, 'R1')],
        bank: [txn('b1', 20, 100, Direction.debit, 'R1')],
      );
      expect(result.matches,
          [const MatchPair(appID: 'a1', bankID: 'b1', tier: MatchTier.reference)]);
      expect(result.appUnmatched, isEmpty);
      expect(result.bankOnly, isEmpty);
    });

    test('tier 2 picks the closest date within ±2 days, consuming once', () {
      final result = Reconciler.reconcile(
        app: [txn('a1', 5, 100, Direction.debit, 'X1')],
        bank: [
          txn('b-far', 7, 100, Direction.debit, 'Y1'),
          txn('b-near', 6, 100, Direction.debit, 'Y2'),
        ],
      );
      expect(result.matches.single.bankID, 'b-near');
      expect(result.matches.single.tier, MatchTier.amountDate);
      expect(result.bankOnly, ['b-far']);
    });

    test('direction and window are respected; leftovers reported', () {
      final result = Reconciler.reconcile(
        app: [txn('a1', 5, 100, Direction.debit, null)],
        bank: [
          txn('b-credit', 5, 100, Direction.credit, null),
          txn('b-late', 9, 100, Direction.debit, null),
        ],
      );
      expect(result.matches, isEmpty);
      expect(result.appUnmatched, ['a1']);
      expect(result.bankOnly, unorderedEquals(['b-credit', 'b-late']));
    });
  });

  group('SelfTransfers', () {
    BankTxn bank(String id, Source src, int day, int paise, Direction dir) =>
        BankTxn(
            ReconTxn(
                id: id,
                date: ist(2026, 4, day),
                amountPaise: paise,
                direction: dir,
                reference: null),
            src);

    test('cross-bank equal-amount pair within window is flagged', () {
      final flagged = SelfTransfers.detect([
        bank('d', Source.hdfc, 5, 500000, Direction.debit),
        bank('c', Source.idfc, 6, 500000, Direction.credit),
        bank('other', Source.idfc, 6, 123, Direction.credit),
      ]);
      expect(flagged, {'d', 'c'});
    });

    test('same-bank pair is never a self transfer', () {
      final flagged = SelfTransfers.detect([
        bank('d', Source.hdfc, 5, 500000, Direction.debit),
        bank('c', Source.hdfc, 5, 500000, Direction.credit),
      ]);
      expect(flagged, isEmpty);
    });

    test('generalizes to arbitrary bank sources', () {
      final flagged = SelfTransfers.detect([
        bank('d', const Source('bank:sbi'), 5, 700, Direction.debit),
        bank('c', Source.hdfc, 5, 700, Direction.credit),
      ]);
      expect(flagged, {'d', 'c'});
    });
  });

  group('Analytics', () {
    AnalyticsTxn t(int month, int paise, Direction dir,
            {String cat = 'Food', String merchant = 'M'}) =>
        AnalyticsTxn(
            month: YearMonth(2026, month),
            amountPaise: paise,
            direction: dir,
            category: cat,
            merchant: merchant,
            sourceKind: SourceKind.paymentApp);

    test('monthStats sums directions separately', () {
      final stats = Analytics.monthStats(
          [t(4, 100, Direction.debit), t(4, 250, Direction.credit), t(5, 999, Direction.debit)],
          YearMonth(2026, 4));
      expect(stats.spendPaise, 100);
      expect(stats.incomePaise, 250);
      expect(stats.netPaise, 150);
    });

    test('trend spans count months ending at the anchor', () {
      final trend = Analytics.trend([t(4, 100, Direction.debit)],
          endingAt: YearMonth(2026, 5), count: 3);
      expect(trend.map((s) => s.month),
          [YearMonth(2026, 3), YearMonth(2026, 4), YearMonth(2026, 5)]);
      expect(trend[1].spendPaise, 100);
    });

    test('categoryBreakdown folds the tail into Other', () {
      final txns = [
        t(4, 500, Direction.debit, cat: 'A'),
        t(4, 400, Direction.debit, cat: 'B'),
        t(4, 300, Direction.debit, cat: 'C'),
        t(4, 200, Direction.debit, cat: 'D'),
      ];
      final breakdown =
          Analytics.categoryBreakdown(txns, YearMonth(2026, 4), top: 2);
      expect(breakdown.map((s) => s.category), ['A', 'B', 'Other']);
      expect(breakdown.last.paise, 500);
    });

    test('topMerchants largest-first with alphabetical ties', () {
      final txns = [
        t(4, 300, Direction.debit, merchant: 'Zeta'),
        t(4, 300, Direction.debit, merchant: 'Alpha'),
        t(4, 900, Direction.debit, merchant: 'Big'),
      ];
      final top = Analytics.topMerchants(txns, YearMonth(2026, 4), top: 3);
      expect(top.map((m) => m.merchant), ['Big', 'Alpha', 'Zeta']);
    });
  });

  group('CoverageGrid', () {
    DocumentSummary doc(String id, Source src, int sm, int em) => DocumentSummary(
        id: id,
        source: src,
        period: DatePeriod(ist(2026, sm, 1), ist(2026, em, 28)));

    test('yearly doc lights its column, months newest first, gaps filled', () {
      final grid = CoverageGrid.derive(
          documents: [doc('d1', Source.hdfc, 1, 3), doc('d2', Source.gpay, 5, 5)],
          pinnedMonths: {});
      expect(grid.months.first, YearMonth(2026, 5));
      expect(grid.months.length, 5); // Jan..May, Apr gap-filled
      expect(grid.state(YearMonth(2026, 2), Source.hdfc), isA<CellPresent>());
      expect(grid.state(YearMonth(2026, 4), Source.hdfc), isA<CellAwaiting>());
      expect(grid.sources, [Source.gpay, Source.hdfc]);
    });

    test('pinned month appears awaiting; empty derive is empty', () {
      final grid =
          CoverageGrid.derive(documents: [], pinnedMonths: {YearMonth(2026, 10)});
      expect(grid.months, [YearMonth(2026, 10)]);
      expect(grid.sources, isEmpty);
      expect(CoverageGrid.derive(documents: [], pinnedMonths: {}).months, isEmpty);
    });
  });

  group('Categorizer + Ruleset', () {
    test('first match wins; unknown is Uncategorized', () {
      final rules = [
        const CategoryRule(id: '1', pattern: 'swiggy', category: 'Food Delivery'),
        const CategoryRule(id: '2', pattern: 'sw', category: 'Wrong'),
      ];
      expect(Categorizer.category('UPI/SWIGGY/123', rules), 'Food Delivery');
      expect(Categorizer.category('mystery shop', rules), Categorizer.uncategorized);
    });

    test('bundled india-default ruleset loads, is substantial, no dupes', () {
      final json = File('../../assets/rulesets/india-default.json')
          .readAsStringSync();
      final ruleset = Ruleset.fromJsonString(json);
      expect(ruleset.version, greaterThanOrEqualTo(1));
      expect(ruleset.rules.length, greaterThanOrEqualTo(55));
      final patterns = ruleset.rules.map((r) => r.pattern.toLowerCase()).toList();
      expect(patterns.toSet().length, patterns.length);
      for (final seed in Categorizer.seedRules) {
        expect(patterns, contains(seed.pattern.toLowerCase()),
            reason: 'compiled seed ${seed.pattern} missing');
      }
    });
  });

  group('SuggestionEngine', () {
    final now = ist(2026, 9, 15);
    SpendRecord rec(String merchant, int rupees, int daysAgo,
            {Direction dir = Direction.debit,
            String cat = Categorizer.uncategorized}) =>
        SpendRecord(
            merchant: merchant,
            amountPaise: rupees * 100,
            date: now.subtract(Duration(days: daysAgo)),
            direction: dir,
            effectiveCategory: cat);

    List<SpendRecord> background() => List.generate(
        10, (i) => rec('MISC MERCHANT $i', 2000, 10 + i, cat: 'Shopping'));

    test('qualifying cluster surfaces with totals; ordering by impact', () {
      final queue = SuggestionEngine.queue(records: [
        ...background(),
        rec('BLUE TOKAI 4213', 700, 5),
        rec('BLUE TOKAI 8821', 800, 20),
        rec('BLUE TOKAI 1100', 900, 45),
      ], now: now, muted: {});
      expect(queue.single.merchantPattern, 'blue tokai');
      expect(queue.single.totalPaise, 240000);
      expect(queue.single.count, 3);
    });

    test('gates: floor, single-month, muted, credits/categorized/stale', () {
      expect(
          SuggestionEngine.queue(records: [
            ...background(),
            rec('TINY CHAI', 100, 5),
            rec('TINY CHAI', 100, 35),
            rec('TINY CHAI', 100, 65),
          ], now: now, muted: {}),
          isEmpty);
      expect(
          SuggestionEngine.queue(records: [
            ...background(),
            rec('ONE MONTH', 900, 2),
            rec('ONE MONTH', 900, 3),
            rec('ONE MONTH', 900, 4),
          ], now: now, muted: {}),
          isEmpty);
      expect(
          SuggestionEngine.queue(records: [
            ...background(),
            rec('BLUE TOKAI', 700, 5),
            rec('BLUE TOKAI', 800, 40),
            rec('BLUE TOKAI', 900, 70),
          ], now: now, muted: {'blue tokai'}),
          isEmpty);
      expect(
          SuggestionEngine.queue(records: [
            ...background(),
            rec('SALARY CO', 90000, 5, dir: Direction.credit),
            rec('SALARY CO', 90000, 40, dir: Direction.credit),
            rec('SALARY CO', 90000, 70, dir: Direction.credit),
            rec('OLD HAUNT', 5000, 100),
            rec('OLD HAUNT', 5000, 120),
            rec('OLD HAUNT', 5000, 140),
          ], now: now, muted: {}),
          isEmpty);
    });

    test('normalize strips digits/punctuation and truncates to 3 tokens', () {
      expect(SuggestionEngine.normalize('BLUE TOKAI COFFEE 4213 BLR'),
          'blue tokai coffee');
      expect(SuggestionEngine.normalize('UPI/DR/12345/CHAI-POINT'), 'upi dr chai');
      expect(SuggestionEngine.normalize('  ACME  '), 'acme');
    });
  });
}
