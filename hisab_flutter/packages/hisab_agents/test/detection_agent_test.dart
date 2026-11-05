import 'dart:convert';

import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

import 'fake_runtime.dart';

void main() {
  final received = DateTime.parse('2026-11-02T09:00:00+05:30');
  const sms = 'Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. '
      'UPI Ref No 627775786529';

  Map<String, Object?> row({
    String status = 'completed',
    String date = '22-09-26',
    String amount = '450.00',
    String direction = 'debit',
    String counterparty = 'vedant@okaxis',
    String vpa = 'vedant@okaxis',
    String reference = '627775786529',
    String accountTail = '1234',
  }) =>
      {
        'status': status, 'date': date, 'amount': amount, 'direction': direction,
        'counterparty': counterparty, 'vpa': vpa, 'reference': reference,
        'accountTail': accountTail,
      };

  group('validate holds the model to the text', () {
    test('a faithful row passes whole', () {
      final d = DetectionAgent.validate(row(), sms, received)!;
      expect([istDayString(d.date), d.amountPaise, d.direction, d.vpa, d.reference, d.accountTail],
          ['2026-09-22', 45000, Direction.debit, 'vedant@okaxis', '627775786529', '1234']);
      expect(d.complete, isTrue);
    });

    test('an amount not in the text drops the row', () {
      expect(DetectionAgent.validate(row(amount: '540.00'), sms, received), isNull);
    });

    test('a made-up reference, name or date is dropped, the row kept', () {
      final d = DetectionAgent.validate(
          row(reference: '999999999999', counterparty: 'Zomato', date: '2023-10-05'), sms, received)!;
      expect(d.reference, isNull);
      expect(d.counterparty, '');
      // The date the text gives, read by the alert parser.
      expect(istDayString(d.date), '2026-09-22');
      expect(d.complete, isFalse);
    });

    test('a label copied with the reference is cut away', () {
      const text = 'Paid to Swiggy\n₹349\n1 Nov 2026, 8:14 pm\nUPI transaction ID: 630512398765';
      final d = DetectionAgent.validate(
          row(amount: '₹349', date: '1 Nov 2026', reference: 'UPI transaction ID: 630512398765',
              counterparty: 'Swiggy', vpa: '', accountTail: ''),
          text, received)!;
      expect([d.reference, istDayString(d.date), d.amountPaise], ['630512398765', '2026-11-01', 34900]);
    });

    test('no date in the text means the day it arrived', () {
      const text = 'Rs 99.00 debited from a/c XX1234 to ZEPTO';
      final d = DetectionAgent.validate(row(amount: '99.00', date: '', reference: ''), text, received)!;
      expect([istDayString(d.date), d.dated], ['2026-11-02', false]);
    });
  });

  test('a pasted history goes one block per request on the device', () {
    const history = 'Paid to A\n₹10\n1 Nov 2026\n\nPaid to B\n₹20\n2 Nov 2026';
    expect(DetectionAgent.blocks(history, 2400), ['Paid to A\n₹10\n1 Nov 2026', 'Paid to B\n₹20\n2 Nov 2026']);
    expect(DetectionAgent.blocks(sms, 2400), [sms]);
  });

  test('long text is cut at line breaks', () {
    final text = List.filled(5, 'x' * 9).join('\n');
    expect(DetectionAgent.chunks(text, 20), ['x' * 9 + '\n' + 'x' * 9, 'x' * 9 + '\n' + 'x' * 9, 'x' * 9]);
  });

  test('only completed movements are kept', () async {
    final runtime = FakeRuntime([
      jsonEncode({
        'transactions': [row(status: 'otp'), row()]
      })
    ]);
    final found = await DetectionAgent(runtime).detect(sms, receivedAt: received);
    expect(found, hasLength(1));
    expect(runtime.requests.single.transform, isTrue);
  });

  test('a guardrail refusal is asked again as text lines', () async {
    final runtime = FakeRuntime([
      const ModelFailure('refused'),
      'completed | 22-09-26 | 450.00 | debit | vedant@okaxis | vedant@okaxis | 627775786529 | 1234',
    ]);
    final found = await DetectionAgent(runtime).detect(sms, receivedAt: received);
    expect(found.single.reference, '627775786529');
    expect(runtime.requests.last.schema, isNull);
  });
}
