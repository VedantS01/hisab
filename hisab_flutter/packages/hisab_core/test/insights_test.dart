import 'dart:io';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

String bundledConfigJson() =>
    File('../../assets/insights/insights-config.json').readAsStringSync();

void main() {
  group('InsightsConfig', () {
    test('bundled config parses with the same values Swift asserts', () {
      final config = InsightsConfig.fromJsonString(bundledConfigJson());
      expect(config.version, 1);
      expect(config.trend.minPct, 25);
      expect(config.trend.minAbsPaise, 50000);
      expect(config.recurrence.minOccurrences, 3);
      expect(config.anomaly.lookbackDays, 35);
      expect(config.ranker.maxCards, 5);
      expect(config.ranker.maxPerType, 3);
    });

    test('bundled config equals the compiled fallback', () {
      expect(InsightsConfig.fromJsonString(bundledConfigJson()),
          InsightsConfig.fallback);
    });
  });

  group('Insight model', () {
    test('insight ids match the digests pinned in Swift', () {
      expect(InsightID.make('trend|Food Delivery|2026-08|40'), 'a84b5c10538a32a7');
      expect(InsightID.make('recurring-new|netflix|64900'), '47007c34745ef802');
      expect(InsightID.make('outlier|txn-42'), '0230759323d235ce');
    });

    test('kind names are the wire names Swift pins', () {
      expect(InsightKind.values.map((k) => k.name).toList(), [
        'trend', 'recurringNew', 'recurringChanged',
        'committedSpend', 'possibleDuplicate', 'outlierAmount',
      ]);
    });

    test('istDaysBetween counts IST calendar days', () {
      final a = DateTime.fromMillisecondsSinceEpoch(1785000000 * 1000, isUtc: true);
      final b = a.add(const Duration(days: 3));
      expect(istDaysBetween(a, b), 3);
      expect(istDaysBetween(b, a), -3);

      // IST has no DST, so an exact day-multiple offset can't distinguish
      // calendar-day truncation from a naive elapsed-seconds/86400 divide.
      // These pin actual IST wall-clock instants to rule that out.
      // 2026-08-03 23:00 IST -> 2026-08-04 01:00 IST: 2 hours elapsed, but
      // it crosses an IST midnight, so it must count as 1 day.
      final crossMidnightBefore =
          DateTime.fromMillisecondsSinceEpoch(1785778200 * 1000, isUtc: true);
      final crossMidnightAfter =
          DateTime.fromMillisecondsSinceEpoch(1785785400 * 1000, isUtc: true);
      expect(istDaysBetween(crossMidnightBefore, crossMidnightAfter), 1);
      expect(istDaysBetween(crossMidnightAfter, crossMidnightBefore), -1);

      // 2026-08-04 00:30 IST -> 2026-08-04 23:30 IST: 23 hours elapsed but
      // stays inside one IST calendar day, so it must count as 0 days.
      final sameDayEarly =
          DateTime.fromMillisecondsSinceEpoch(1785783600 * 1000, isUtc: true);
      final sameDayLate =
          DateTime.fromMillisecondsSinceEpoch(1785866400 * 1000, isUtc: true);
      expect(istDaysBetween(sameDayEarly, sameDayLate), 0);
    });
  });

  group('CompleteMonths', () {
    // IST midnight expressed as a UTC instant.
    DateTime ist(String yyyyMmDd) {
      final p = yyyyMmDd.split('-').map(int.parse).toList();
      return DateTime.utc(p[0], p[1], p[2]).subtract(istOffset);
    }

    test('a month is complete only when one period spans it entirely', () {
      // Apr 1 - Jun 30, both at IST midnight: April and May are covered
      // end to end, but June's last instant is 2026-06-30T23:59:59 IST -
      // past where the period ends - so June is not complete.
      final period = DatePeriod(ist('2026-04-01'), ist('2026-06-30'));
      expect(CompleteMonths.of([period]),
          {YearMonth(2026, 4), YearMonth(2026, 5)});
    });

    test('partial edge months are excluded', () {
      final period = DatePeriod(ist('2026-04-15'), ist('2026-06-14'));
      expect(CompleteMonths.of([period]), {YearMonth(2026, 5)});
    });

    test('latest ignores months after now', () {
      // Jan 1 - Dec 31, both at IST midnight: January-November are
      // complete (December fails for the same reason June did above).
      // notAfter caps at September, which is itself complete, so that's
      // the answer.
      final period = DatePeriod(ist('2026-01-01'), ist('2026-12-31'));
      expect(CompleteMonths.latest([period], ist('2026-09-10')),
          YearMonth(2026, 9));
    });

    test('no periods means no complete months', () {
      expect(CompleteMonths.of([]), isEmpty);
      expect(CompleteMonths.latest([], ist('2026-09-10')), isNull);
    });
  });

  group('TrendDetector', () {
    const config = InsightsConfig.fallback;
    final window = {
      YearMonth(2026, 5),
      YearMonth(2026, 6),
      YearMonth(2026, 7),
      YearMonth(2026, 8),
    };

    DateTime day(String yyyyMmDd) {
      final p = yyyyMmDd.split('-').map(int.parse).toList();
      return DateTime.utc(p[0], p[1], p[2]).subtract(istOffset);
    }

    InsightRecord rec(String id, String iso, int paise, String category,
            [String merchant = 'Shop']) =>
        InsightRecord(
            id: id,
            date: day(iso),
            amountPaise: paise,
            direction: Direction.debit,
            category: category,
            merchant: merchant);

    test('rise above both gates is reported', () {
      // Baseline 1,000.00 per month for three months; August is 2,000.00.
      final (insights, concentration) = TrendDetector.detect(
        records: [
          rec('a', '2026-05-10', 100000, 'Food'),
          rec('b', '2026-06-10', 100000, 'Food'),
          rec('c', '2026-07-10', 100000, 'Food'),
          rec('d', '2026-08-10', 120000, 'Food'),
          rec('e', '2026-08-20', 80000, 'Food'),
        ],
        month: YearMonth(2026, 8),
        completeMonths: window,
        monthDebitTotalPaise: 200000,
        config: config,
      );
      expect(insights.length, 1);
      expect(insights[0].kind, InsightKind.trend);
      expect(insights[0].headline, 'Food: ₹2,000.00');
      expect(insights[0].detail, 'up 100% vs your 3-month average');
      expect(insights[0].mute, const MuteCategory('Food'));
      expect(insights[0].evidenceIDs.toSet(), {'d', 'e'});
      expect(concentration, isEmpty);
    });

    test('drops are reported too', () {
      final (insights, _) = TrendDetector.detect(
        records: [
          rec('a', '2026-05-10', 200000, 'Fuel'),
          rec('b', '2026-06-10', 200000, 'Fuel'),
          rec('c', '2026-07-10', 200000, 'Fuel'),
          rec('d', '2026-08-10', 100000, 'Fuel'),
        ],
        month: YearMonth(2026, 8),
        completeMonths: window,
        monthDebitTotalPaise: 100000,
        config: config,
      );
      expect(insights.length, 1);
      expect(insights[0].detail, 'down 50% vs your 3-month average');
    });

    test('small delta fails the rupee gate even at a high percentage', () {
      // +200% but only ₹200 — below minAbsPaise.
      final (insights, _) = TrendDetector.detect(
        records: [
          rec('a', '2026-05-10', 10000, 'Snacks'),
          rec('b', '2026-06-10', 10000, 'Snacks'),
          rec('c', '2026-07-10', 10000, 'Snacks'),
          rec('d', '2026-08-10', 30000, 'Snacks'),
        ],
        month: YearMonth(2026, 8),
        completeMonths: window,
        monthDebitTotalPaise: 30000,
        config: config,
      );
      expect(insights, isEmpty);
    });

    test('a category with no baseline is not a trend', () {
      final (insights, _) = TrendDetector.detect(
        records: [rec('d', '2026-08-10', 500000, 'Furniture')],
        month: YearMonth(2026, 8),
        completeMonths: window,
        monthDebitTotalPaise: 500000,
        config: config,
      );
      expect(insights, isEmpty);
    });

    test('one dominant purchase is annotated and flagged for collision', () {
      final (insights, concentration) = TrendDetector.detect(
        records: [
          rec('a', '2026-05-10', 100000, 'Shopping'),
          rec('b', '2026-06-10', 100000, 'Shopping'),
          rec('c', '2026-07-10', 100000, 'Shopping'),
          rec('d', '2026-08-10', 50000, 'Shopping'),
          rec('e', '2026-08-11', 1200000, 'Shopping', 'Croma'),
        ],
        month: YearMonth(2026, 8),
        completeMonths: window,
        monthDebitTotalPaise: 1250000,
        config: config,
      );
      expect(insights.length, 1);
      expect(
          insights[0].detail,
          'up 1150% vs your 3-month average — '
              'driven by one ₹12,000.00 payment to Croma');
      expect(concentration, {'e'});
    });

    test('no complete baseline months produces nothing', () {
      final (insights, _) = TrendDetector.detect(
        records: [rec('d', '2026-08-10', 500000, 'Food')],
        month: YearMonth(2026, 8),
        completeMonths: {YearMonth(2026, 8)},
        monthDebitTotalPaise: 500000,
        config: config,
      );
      expect(insights, isEmpty);
    });
  });

  group('RecurrenceDetector', () {
    const config = InsightsConfig.fallback;

    DateTime day(String yyyyMmDd) {
      final p = yyyyMmDd.split('-').map(int.parse).toList();
      return DateTime.utc(p[0], p[1], p[2]).subtract(istOffset);
    }

    InsightRecord rec(String id, String iso, int paise, String merchant) =>
        InsightRecord(
            id: id,
            date: day(iso),
            amountPaise: paise,
            direction: Direction.debit,
            category: 'Subscriptions',
            merchant: merchant);

    InsightRecord credit(String id, String iso, int paise, String merchant) =>
        InsightRecord(
            id: id,
            date: day(iso),
            amountPaise: paise,
            direction: Direction.credit,
            category: 'Subscriptions',
            merchant: merchant);

    final now = day('2026-09-15');

    test('monthly series is discovered', () {
      final series = RecurrenceDetector.series(
        records: [
          rec('a', '2026-06-05', 64900, 'NETFLIX INDIA'),
          rec('b', '2026-07-05', 64900, 'Netflix India'),
          rec('c', '2026-08-05', 64900, 'NETFLIX INDIA'),
          rec('d', '2026-09-05', 64900, 'NETFLIX INDIA'),
        ],
        now: now,
        config: config,
      );
      expect(series.length, 1);
      expect(series[0].merchantKey, 'netflix india');
      expect(series[0].displayMerchant, 'NETFLIX INDIA');
      expect(series[0].cadence, Cadence.monthly);
      expect(series[0].medianPaise, 64900);
      expect(series[0].monthlyEquivalentPaise, 64900);
      expect(series[0].count, 4);
    });

    test('weekly series scales to a monthly equivalent', () {
      final series = RecurrenceDetector.series(
        records: [
          rec('a', '2026-08-25', 30000, 'Milk Wala'),
          rec('b', '2026-09-01', 30000, 'Milk Wala'),
          rec('c', '2026-09-08', 30000, 'Milk Wala'),
          rec('d', '2026-09-15', 30000, 'Milk Wala'),
        ],
        now: now,
        config: config,
      );
      expect(series.length, 1);
      expect(series[0].cadence, Cadence.weekly);
      expect(series[0].monthlyEquivalentPaise, 30000 * 52 ~/ 12);
    });

    test('irregular gaps are not a series', () {
      expect(
          RecurrenceDetector.series(
            records: [
              rec('a', '2026-06-01', 50000, 'Random Shop'),
              rec('b', '2026-06-19', 50000, 'Random Shop'),
              rec('c', '2026-08-02', 50000, 'Random Shop'),
            ],
            now: now,
            config: config,
          ),
          isEmpty);
    });

    test('too few occurrences is not a series', () {
      expect(
          RecurrenceDetector.series(
            records: [
              rec('a', '2026-07-05', 64900, 'Netflix'),
              rec('b', '2026-08-05', 64900, 'Netflix'),
            ],
            now: now,
            config: config,
          ),
          isEmpty);
    });

    test('a stale series is not active and produces no cards', () {
      // Last paid in March; monthly cadence goes inactive after 2 cadences.
      final (insights, _) = RecurrenceDetector.detect(
        records: [
          rec('a', '2025-12-05', 64900, 'Netflix'),
          rec('b', '2026-01-05', 64900, 'Netflix'),
          rec('c', '2026-02-05', 64900, 'Netflix'),
          rec('d', '2026-03-05', 64900, 'Netflix'),
        ],
        now: now,
        monthDebitTotalPaise: 100000,
        config: config,
      );
      expect(insights, isEmpty);
    });

    test('a new series is reported', () {
      final (insights, claimed) = RecurrenceDetector.detect(
        records: [
          rec('a', '2026-07-05', 64900, 'Netflix'),
          rec('b', '2026-08-05', 64900, 'Netflix'),
          rec('c', '2026-09-05', 64900, 'Netflix'),
        ],
        now: now,
        monthDebitTotalPaise: 200000,
        config: config,
      );
      expect(insights.length, 1);
      expect(insights[0].kind, InsightKind.recurringNew);
      expect(insights[0].headline, 'New recurring: Netflix');
      expect(insights[0].detail, '₹649.00 per month since Jul 2026');
      expect(insights[0].mute, const MuteMerchant('netflix'));
      expect(claimed, {'a', 'b', 'c'});
    });

    test('a changed amount is reported', () {
      // Established since February, so not "new"; September jumps 23%.
      final (insights, _) = RecurrenceDetector.detect(
        records: [
          rec('a', '2026-02-05', 64900, 'Netflix'),
          rec('b', '2026-03-05', 64900, 'Netflix'),
          rec('c', '2026-04-05', 64900, 'Netflix'),
          rec('d', '2026-05-05', 64900, 'Netflix'),
          rec('e', '2026-06-05', 64900, 'Netflix'),
          rec('f', '2026-07-05', 64900, 'Netflix'),
          rec('g', '2026-08-05', 64900, 'Netflix'),
          rec('h', '2026-09-05', 79900, 'Netflix'),
        ],
        now: now,
        monthDebitTotalPaise: 200000,
        config: config,
      );
      expect(insights.length, 1);
      expect(insights[0].kind, InsightKind.recurringChanged);
      expect(insights[0].headline, 'Netflix: ₹799.00');
      expect(insights[0].detail, 'usually ₹649.00 per month');
    });

    test('two active series produce a committed spend summary', () {
      final (insights, _) = RecurrenceDetector.detect(
        records: [
          rec('a', '2026-07-05', 64900, 'Netflix'),
          rec('b', '2026-08-05', 64900, 'Netflix'),
          rec('c', '2026-09-05', 64900, 'Netflix'),
          rec('d', '2026-07-10', 1500000, 'Landlord'),
          rec('e', '2026-08-10', 1500000, 'Landlord'),
          rec('f', '2026-09-10', 1500000, 'Landlord'),
        ],
        now: now,
        monthDebitTotalPaise: 2000000,
        config: config,
      );
      final committed =
          insights.where((i) => i.kind == InsightKind.committedSpend).toList();
      expect(committed.length, 1);
      expect(committed[0].headline, '₹15,649.00 per month committed');
      expect(committed[0].detail, 'across 2 recurring payments');
      expect(committed[0].series.length, 2);
      expect(committed[0].mute, isNull);
    });

    test('a refund does not drive the changed amount card', () {
      // Every debit is ₹649, so the series has zero drift. The later credit
      // shares the merchant key but must not be measured against a
      // debit-only median.
      final (insights, _) = RecurrenceDetector.detect(
        records: [
          rec('a', '2026-02-05', 64900, 'Netflix'),
          rec('b', '2026-03-05', 64900, 'Netflix'),
          rec('c', '2026-04-05', 64900, 'Netflix'),
          rec('d', '2026-05-05', 64900, 'Netflix'),
          rec('e', '2026-06-05', 64900, 'Netflix'),
          rec('f', '2026-07-05', 64900, 'Netflix'),
          rec('g', '2026-08-05', 64900, 'Netflix'),
          rec('h', '2026-09-05', 64900, 'Netflix'),
          credit('refund', '2026-09-20', 200000, 'Netflix'),
        ],
        now: now,
        monthDebitTotalPaise: 200000,
        config: config,
      );
      expect(
          insights.where((i) => i.kind == InsightKind.recurringChanged), isEmpty);
      expect(insights, isEmpty);
    });

    test('same-day payments order deterministically by id', () {
      // The two August rows land on one IST day and arrive reverse-sorted;
      // the date-then-id total order must still place "a1" before "z2".
      final series = RecurrenceDetector.series(
        records: [
          rec('a', '2026-06-05', 64900, 'Netflix'),
          rec('b', '2026-07-05', 64900, 'Netflix'),
          rec('z2', '2026-08-05', 64900, 'Netflix'),
          rec('a1', '2026-08-05', 64900, 'Netflix'),
          rec('c', '2026-09-05', 64900, 'Netflix'),
        ],
        now: now,
        config: config,
      );
      expect(series.length, 1);
      expect(series[0].transactionIDs, ['a', 'b', 'a1', 'z2', 'c']);
    });
  });

  group('AnomalyDetector', () {
    const config = InsightsConfig.fallback;

    // "yyyy-MM-dd" lands on IST midnight (a statement row); the longer
    // "yyyy-MM-dd HH:mm" carries a real IST clock time (a payment-app row).
    DateTime stamp(String iso) {
      final parts = iso.split(' ');
      final d = parts[0].split('-').map(int.parse).toList();
      if (parts.length == 1) {
        return DateTime.utc(d[0], d[1], d[2]).subtract(istOffset);
      }
      final t = parts[1].split(':').map(int.parse).toList();
      return DateTime.utc(d[0], d[1], d[2], t[0], t[1]).subtract(istOffset);
    }

    InsightRecord rec(String id, String iso, int paise, String merchant) =>
        InsightRecord(
            id: id,
            date: stamp(iso),
            amountPaise: paise,
            direction: Direction.debit,
            category: 'Food',
            merchant: merchant);

    final now = stamp('2026-09-15');

    test('same-day identical payments are a possible duplicate', () {
      final insights = AnomalyDetector.detect(
        records: [
          rec('a', '2026-09-10', 45000, 'Swiggy'),
          rec('b', '2026-09-10', 45000, 'Swiggy'),
        ],
        now: now,
        monthDebitTotalPaise: 90000,
        config: config,
      );
      expect(insights.length, 1);
      expect(insights[0].kind, InsightKind.possibleDuplicate);
      expect(insights[0].headline, 'Swiggy: ₹450.00 ×2');
      expect(insights[0].detail, '2 identical payments on 10 Sep 2026');
      expect(insights[0].evidenceIDs, ['a', 'b']);
      expect(insights[0].mute, const MuteMerchant('swiggy'));
    });

    test('different merchants at the same amount are not duplicates', () {
      expect(
          AnomalyDetector.detect(
            records: [
              rec('a', '2026-09-10', 45000, 'Swiggy'),
              rec('b', '2026-09-10', 45000, 'Zomato'),
            ],
            now: now,
            monthDebitTotalPaise: 90000,
            config: config,
          ),
          isEmpty);
    });

    test('timestamped payments hours apart are not duplicates', () {
      expect(
          AnomalyDetector.detect(
            records: [
              rec('a', '2026-09-10 09:15', 45000, 'Swiggy'),
              rec('b', '2026-09-10 20:40', 45000, 'Swiggy'),
            ],
            now: now,
            monthDebitTotalPaise: 90000,
            config: config,
          ),
          isEmpty);
    });

    test('timestamped payments within the window are duplicates', () {
      final insights = AnomalyDetector.detect(
        records: [
          rec('a', '2026-09-10 09:15', 45000, 'Swiggy'),
          rec('b', '2026-09-10 09:19', 45000, 'Swiggy'),
        ],
        now: now,
        monthDebitTotalPaise: 90000,
        config: config,
      );
      expect(insights.length, 1);
      expect(insights[0].kind, InsightKind.possibleDuplicate);
    });

    test('an amount far above the merchant median is an outlier', () {
      final records = [
        for (var i = 1; i <= 5; i++)
          rec('p$i', '2026-08-0$i', 30000, 'Blue Tokai'),
        rec('big', '2026-09-10', 250000, 'Blue Tokai'),
      ];
      final insights = AnomalyDetector.detect(
        records: records,
        now: now,
        monthDebitTotalPaise: 400000,
        config: config,
      );
      expect(insights.length, 1);
      expect(insights[0].kind, InsightKind.outlierAmount);
      expect(insights[0].headline, 'Blue Tokai: ₹2,500.00');
      expect(insights[0].detail, 'about 8× your usual ₹300.00');
      expect(insights[0].evidenceIDs, ['big']);
    });

    test('too few priors means no outlier', () {
      final records = [
        for (var i = 1; i <= 4; i++)
          rec('p$i', '2026-08-0$i', 30000, 'Blue Tokai'),
        rec('big', '2026-09-10', 250000, 'Blue Tokai'),
      ];
      expect(
          AnomalyDetector.detect(
            records: records,
            now: now,
            monthDebitTotalPaise: 400000,
            config: config,
          ),
          isEmpty);
    });

    test('a small multiple below the rupee floor is not an outlier', () {
      final records = [
        for (var i = 1; i <= 5; i++)
          rec('p$i', '2026-08-0$i', 10000, 'Chaiwala'),
        rec('big', '2026-09-10', 40000, 'Chaiwala'),
      ];
      expect(
          AnomalyDetector.detect(
            records: records,
            now: now,
            monthDebitTotalPaise: 90000,
            config: config,
          ),
          isEmpty);
    });

    test('anything older than the lookback is ignored', () {
      expect(
          AnomalyDetector.detect(
            records: [
              rec('a', '2026-06-10', 45000, 'Swiggy'),
              rec('b', '2026-06-10', 45000, 'Swiggy'),
            ],
            now: now,
            monthDebitTotalPaise: 90000,
            config: config,
          ),
          isEmpty);
    });
  });

  group('InsightsEngine', () {
    const config = InsightsConfig.fallback;

    DateTime day(String yyyyMmDd) {
      final p = yyyyMmDd.split('-').map(int.parse).toList();
      return DateTime.utc(p[0], p[1], p[2]).subtract(istOffset);
    }

    InsightRecord record(
            String id, String iso, int paise, String category, String merchant) =>
        InsightRecord(
            id: id,
            date: day(iso),
            amountPaise: paise,
            direction: Direction.debit,
            category: category,
            merchant: merchant);

    // Jan-Aug complete, "now" mid-September: August is the latest complete
    // month. The period has to end at 2026-09-01 00:00 IST, because August's
    // last instant is 2026-08-31 23:59:59 - a period ending at 2026-08-31
    // 00:00 leaves August incomplete and every August assertion vacuous.
    final periods = [DatePeriod(day('2026-01-01'), day('2026-09-01'))];
    final now = day('2026-09-15');

    // A rent series (recurring), a Food trend, and a duplicate pair.
    List<InsightRecord> dataset() {
      final rows = <InsightRecord>[];
      const months = ['06', '07', '08'];
      for (var index = 0; index < months.length; index++) {
        rows.add(record(
            'rent$index', '2026-${months[index]}-05', 1500000, 'Housing', 'Landlord'));
        rows.add(record(
            'food$index', '2026-${months[index]}-12', 100000, 'Food', 'Swiggy'));
      }
      rows.add(record('foodspike', '2026-08-20', 300000, 'Food', 'Swiggy'));
      rows.add(record('dup1', '2026-08-25', 45000, 'Food', 'Zomato'));
      rows.add(record('dup2', '2026-08-25', 45000, 'Food', 'Zomato'));
      return rows;
    }

    InsightsResult generate([Suppressions suppressions = const Suppressions()]) =>
        InsightsEngine.generate(
          input: InsightsInput(
              records: dataset(), documentPeriods: periods, now: now),
          config: config,
          suppressions: suppressions,
        );

    test('committed spend is always the last card', () {
      final result = generate();
      expect(result.cards, isNotEmpty);
      expect(result.cards.last.kind, InsightKind.committedSpend);
      expect(
          result.cards
              .where((c) => c.kind == InsightKind.committedSpend)
              .length,
          1);
    });

    test('cards are capped at maxCards', () {
      expect(generate().cards.length, lessThanOrEqualTo(config.ranker.maxCards));
    });

    // Ranking is score descending, id ascending as the tie-break - kind
    // weight only feeds the score, it is not a separate sort key.
    test('cards are ordered by score then id', () {
      final ranked = generate()
          .cards
          .where((c) => c.kind != InsightKind.committedSpend)
          .toList();
      expect(ranked.length, greaterThan(1));
      for (var index = 1; index < ranked.length; index++) {
        final previous = ranked[index - 1];
        final current = ranked[index];
        if (previous.score == current.score) {
          expect(previous.id.compareTo(current.id), lessThan(0),
              reason: 'equal scores must tie-break on id ascending');
        } else {
          expect(previous.score, greaterThan(current.score),
              reason: 'cards must be ordered by score descending');
        }
      }
    });

    test('dismissed ids are removed but still reported in allIDs', () {
      final first = generate().cards[0];
      final result = generate(Suppressions(dismissedIDs: {first.id}));
      expect(result.cards.any((c) => c.id == first.id), isFalse);
      expect(result.allIDs.contains(first.id), isTrue,
          reason: 'allIDs must list every generated id so the app can prune');
    });

    test('muting a merchant silences its cards', () {
      final result = generate(const Suppressions(mutedMerchants: {'zomato'}));
      expect(result.cards.any((c) => c.kind == InsightKind.possibleDuplicate),
          isFalse);
    });

    test('muting a category silences its trend', () {
      final result = generate(const Suppressions(mutedCategories: {'Food'}));
      // The dataset also trends Housing, which muting Food must not touch.
      expect(
          result.cards.any((c) =>
              c.kind == InsightKind.trend && c.headline.startsWith('Food')),
          isFalse);
      expect(
          result.cards.any((c) =>
              c.kind == InsightKind.trend && c.headline.startsWith('Housing')),
          isTrue);
    });

    test('an outlier on a recurring payment is suppressed', () {
      // Six monthly payments plus a spike inside the 35-day anomaly
      // lookback: the recurrence card claims the spike, so no outlier card.
      final rows = [
        for (var index = 1; index <= 6; index++)
          record('g$index', '2026-0$index-05', 200000, 'Bills', 'Gym'),
        record('spike', '2026-09-05', 900000, 'Bills', 'Gym'),
      ];
      final result = InsightsEngine.generate(
        input: InsightsInput(records: rows, documentPeriods: periods, now: now),
        config: config,
        suppressions: const Suppressions(),
      );
      expect(result.cards.any((c) => c.kind == InsightKind.recurringChanged),
          isTrue,
          reason: 'the recurrence card must be the one that owns the spike');
      expect(result.cards.any((c) => c.kind == InsightKind.outlierAmount),
          isFalse);
    });

    test('a duplicated outlier is one duplicate card, not two outliers', () {
      // Five priors set a typical amount; the same recent day then carries
      // two identical charges, each an outlier on its own. "You may have
      // paid twice" supersedes "that was unusually large", twice over.
      final rows = [
        for (var index = 2; index <= 6; index++)
          record('prior$index', '2026-08-1$index', 30000, 'Shopping', 'Acme'),
        record('twin1', '2026-09-10', 200000, 'Shopping', 'Acme'),
        record('twin2', '2026-09-10', 200000, 'Shopping', 'Acme'),
      ];
      final result = InsightsEngine.generate(
        input: InsightsInput(records: rows, documentPeriods: periods, now: now),
        config: config,
        suppressions: const Suppressions(),
      );
      expect(result.cards.any((c) => c.kind == InsightKind.possibleDuplicate),
          isTrue);
      expect(result.cards.any((c) => c.kind == InsightKind.outlierAmount),
          isFalse,
          reason:
              'a possible-duplicate card supersedes outliers on the same rows');
      // Hidden is not ungenerated: the collision-suppressed outlier ids stay
      // in allIDs, so a dismissal isn't pruned while the card is merely
      // suppressed and doesn't come back undismissed when the collision lifts.
      expect(result.allIDs.contains(InsightID.make('outlier|twin1')), isTrue);
      expect(result.allIDs.contains(InsightID.make('outlier|twin2')), isTrue);
    });

    test('without a complete month no trend cards appear', () {
      final partial = [DatePeriod(day('2026-08-15'), day('2026-09-14'))];
      final result = InsightsEngine.generate(
        input: InsightsInput(
            records: dataset(), documentPeriods: partial, now: now),
        config: config,
        suppressions: const Suppressions(),
      );
      expect(result.cards.any((c) => c.kind == InsightKind.trend), isFalse);
    });
  });
}
