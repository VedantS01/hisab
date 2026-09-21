/// A wall-clock ceiling on one `InsightsEngine.generate` pass at a realistic
/// corpus size. Mirrors InsightsPerformanceTests.swift — same generator, same
/// LCG, same record count — so a regression in either core is caught by its
/// own suite.
///
/// This exists because nothing else in either suite could see the defect it
/// guards: every unit fixture is tens of rows and the demo set is 205, while
/// the engine runs synchronously inside the dashboard's `build` — on first
/// paint, on every month-chip tap, on every dismiss. An `O(recent × history)`
/// merchant-normalize loop that is invisible at 205 rows froze the UI for
/// ~1–2 seconds at a year of statements.
library;

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

/// ~2 years of statements at ~200 transactions a month. Above any real user's
/// corpus today, which is the point: the budget has to hold for the user who
/// keeps importing.
const _recordCount = 5000;
const _perMonth = 200;

/// Budget for the best of three passes, chosen against measurements rather
/// than a round number:
///
/// - post-fix, `dart test` (JIT) on an M-series Mac: ~32 ms.
/// - pre-fix, same machine: ~2,200 ms.
///
/// 400 ms sits ~12× above the observed cost and ~5.5× below the regression,
/// so a CI box several times slower than this machine still passes while the
/// quadratic-ish loop coming back fails outright. Best of three rather than a
/// single pass: scheduler noise can only ever add time, so the minimum is the
/// statistic that says what the work costs.
const _budgetMs = 400;

const _categories = [
  'Food',
  'Transport',
  'Shopping',
  'Bills',
  'Housing',
  'Health',
];

/// Deterministic synthetic history: [_perMonth] debits a month across 120
/// merchants, walking backwards from [now]'s month.
List<InsightRecord> _records(int count, DateTime now) {
  const pool = 120;
  final merchants = [
    for (var i = 0; i < pool; i++)
      'Merchant ${String.fromCharCode(97 + i ~/ 26)}${String.fromCharCode(97 + i % 26)}'
  ];
  var seed = 987654321;
  int next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed;
  }

  final base = YearMonth.fromDate(now);
  final rows = <InsightRecord>[];
  for (var i = 0; i < count; i++) {
    final backwards = count - 1 - i;
    final month = base.advancedBy(-(backwards ~/ _perMonth));
    final day = 1 + (backwards % _perMonth) % 28;
    final amount = 10000 + next() % 500000;
    final merchant = merchants[next() % pool];
    rows.add(InsightRecord(
      id: 'txn-$i',
      date: DateTime.utc(month.year, month.month, day, 6, 30),
      amountPaise: amount,
      direction: Direction.debit,
      category: _categories[i % _categories.length],
      merchant: merchant,
    ));
  }
  return rows;
}

InsightsInput _input(int count) {
  // A fixed UTC instant, so the dataset is identical on every run and on both
  // platforms. 12:00 UTC on the last day of the month is 17:30 IST, after
  // every generated row's 12:00 IST.
  final now = DateTime.utc(2026, 9, 30, 12);
  final months = (count + _perMonth - 1) ~/ _perMonth;
  final current = YearMonth.fromDate(now);
  final oldest = current.advancedBy(-(months - 1));
  return InsightsInput(
    records: _records(count, now),
    documentPeriods: [
      DatePeriod(DateTime.utc(oldest.year, oldest.month, 1),
          DateTime.utc(current.year, current.month, 1))
    ],
    now: now,
  );
}

void main() {
  test('generating insights for two years of history stays under budget', () {
    final input = _input(_recordCount);
    var best = double.infinity;
    var cards = 0;
    for (var run = 0; run < 3; run++) {
      final watch = Stopwatch()..start();
      final result = InsightsEngine.generate(
          input: input,
          config: InsightsConfig.fallback,
          suppressions: const Suppressions());
      watch.stop();
      final elapsed = watch.elapsedMicroseconds / 1000;
      if (elapsed < best) best = elapsed;
      cards = result.cards.length;
    }
    // A pass that produced nothing would be free and prove nothing.
    expect(cards, greaterThan(0));
    expect(best, lessThan(_budgetMs),
        reason: 'InsightsEngine.generate took ${best.round()} ms for '
            '$_recordCount records; budget is $_budgetMs ms. '
            "See this file's doc comment.");
  });
}
