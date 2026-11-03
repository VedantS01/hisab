import 'dart:convert';

import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

import 'fake_runtime.dart';

void main() {
  final october = YearMonth(2026, 10);
  final records = <InsightRecord>[];
  void add(int month, int rupees, String category, String merchant) => records.add(InsightRecord(
      id: 'r${records.length}',
      date: DateTime.utc(2026, month, 10, 6),
      amountPaise: rupees * 100,
      direction: Direction.debit,
      category: category,
      merchant: merchant));
  add(9, 2000, 'Food', 'SWIGGY');
  add(10, 3000, 'Food', 'SWIGGY');
  add(9, 18000, 'Rent', 'LANDLORD');
  add(10, 18000, 'Rent', 'LANDLORD');
  add(9, 4000, 'Groceries', 'BIGBASKET');
  add(10, 3000, 'Groceries', 'BIGBASKET');

  LedgerTools asked() =>
      LedgerTools(records, now: DateTime.utc(2026, 11, 3))..compareMonths(october);

  group('grounded holds a sentence to what the tools said', () {
    test("a category's own numbers", () {
      expect(asked().grounded('Food rose to ₹3,000 from ₹2,000 (+50%)'), isTrue);
    });

    test('a number the tools never said', () {
      expect(asked().grounded('Food rose to ₹3,500'), isFalse);
    });

    test("another category's numbers", () {
      expect(asked().grounded('Groceries rose to ₹3,000 from ₹2,000'), isFalse);
    });

    test("the month's total pinned on one category", () {
      // All spending was ₹24,000 in October.
      expect(asked().grounded('Rent took ₹24,000'), isFalse);
      expect(asked().grounded('Total spending was ₹24,000'), isTrue);
    });

    test('a rise the numbers say was a fall', () {
      expect(asked().grounded('Groceries rose to ₹3,000 (25%)'), isFalse);
      expect(asked().grounded('Groceries fell to ₹3,000 (25%)'), isTrue);
    });
  });

  test('the agent keeps grounded cards, in the ledger’s own names', () async {
    final tools = asked();
    final runtime = FakeRuntime([
      jsonEncode({
        'insights': [
          {
            'title': 'Food up',
            'body': 'Food rose to ₹3,000 from ₹2,000 (+50%)',
            'kind': 'change',
            'category': 'food',
            'merchant': 'Zomato',
          },
          {'title': 'Rent', 'body': 'Rent is ₹19,000', 'kind': 'spending', 'category': '', 'merchant': ''},
          {'title': 'Tip', 'body': 'Cook at home more', 'kind': 'saving', 'category': '', 'merchant': ''},
        ]
      })
    ]);

    final cards = await InsightsAgent(runtime).run(tools: tools, month: october);

    expect(cards, hasLength(1));
    expect([cards.single.category, cards.single.merchant], ['Food', null]);
    expect(runtime.requests.single.tools, hasLength(tools.tools.length));
  });
}
