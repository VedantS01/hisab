import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

MatchSide side(
  String id, {
  int amount = 45000,
  Direction? direction = Direction.debit,
  DateTime? date,
  String? tail,
  String? vpa,
  String payee = '',
  String narration = '',
  String? reference,
  bool row = false,
}) =>
    MatchSide(
      id: id,
      amountPaise: amount,
      direction: direction,
      date: date ?? DateTime.utc(2026, 10, 22, 9),
      accountTail: tail,
      vpa: vpa,
      payee: payee,
      narration: narration,
      reference: reference,
      isLedgerRow: row,
    );

void main() {
  group('judge', () {
    test('a shared reference is decisive; a different one is a veto', () {
      final d = side('d', reference: 'UPI627775786529', amount: 1);
      expect(
          DetectionMatcher.judge(
              d, side('r', reference: 'upi627775786529', amount: 999, row: true)),
          MatchVerdict.merge);
      expect(
          DetectionMatcher.judge(d,
              side('r', reference: 'UPI000', amount: 1, vpa: 'x@okaxis', row: true)),
          MatchVerdict.none);
    });

    test('amount must agree; direction only when both sides know it', () {
      expect(DetectionMatcher.judge(side('d'), side('r', amount: 45001, row: true)),
          MatchVerdict.none);
      expect(
          DetectionMatcher.judge(
              side('d'), side('r', direction: Direction.credit, row: true)),
          MatchVerdict.none);
      expect(
          DetectionMatcher.judge(side('d', direction: null),
              side('r', direction: Direction.credit, row: true)),
          MatchVerdict.suggested);
    });

    test('outside three days is a veto; inside, amount and time alone only suggest',
        () {
      expect(
          DetectionMatcher.judge(
              side('d'), side('r', date: DateTime.utc(2026, 10, 26, 9), row: true)),
          MatchVerdict.none);
      expect(
          DetectionMatcher.judge(
              side('d'), side('r', date: DateTime.utc(2026, 10, 25, 9), row: true)),
          MatchVerdict.suggested);
    });

    test('account tails: equal is a merge, different is a veto, one missing is neutral',
        () {
      expect(
          DetectionMatcher.judge(
              side('d', tail: '1234'), side('r', tail: 'XX1234', row: true)),
          MatchVerdict.merge);
      expect(
          DetectionMatcher.judge(
              side('d', tail: '1234'), side('r', tail: '9876', row: true)),
          MatchVerdict.none);
      expect(DetectionMatcher.judge(side('d', tail: '1234'), side('r', row: true)),
          MatchVerdict.suggested);
    });

    test("a detection's tail found in the row's narration counts as the tail agreeing",
        () {
      expect(
          DetectionMatcher.judge(side('d', tail: '4321'),
              side('r', narration: 'POS 12345 AMAZON CARD XX4321', row: true)),
          MatchVerdict.merge);
    });

    test('counterparty: whole VPA, its handle in the narration, or the first word of a name',
        () {
      expect(
          DetectionMatcher.judge(
              side('d', vpa: 'ram@okhdfc'), side('e', vpa: 'ram@okhdfc')),
          MatchVerdict.merge);
      expect(
          DetectionMatcher.judge(side('d', vpa: 'ram@okhdfc'),
              side('r', narration: 'UPI/sriram@okhdfc/pay', row: true)),
          MatchVerdict.suggested,
          reason: 'ram is not sriram');
      expect(
          DetectionMatcher.judge(side('d', vpa: 'ram@okhdfc'),
              side('r', narration: 'UPI-RAM@OKHDFC-627775', row: true)),
          MatchVerdict.merge);
      expect(
          DetectionMatcher.judge(side('d', payee: 'Blue Tokai Coffee'),
              side('r', narration: 'UPI/BLUE TOKAI/PAY', row: true)),
          MatchVerdict.merge);
      expect(
          DetectionMatcher.judge(side('d', payee: 'Om Stores'),
              side('r', narration: 'UPI/OM/TRF', row: true)),
          MatchVerdict.suggested,
          reason: 'two letters are not a name');
    });
  });

  group('pair', () {
    test('each row is claimed once, nearest first; a tie stays unpaired', () {
      final sms = side('sms', vpa: 'ram@okhdfc', date: DateTime.utc(2026, 10, 22, 9));
      final email =
          side('email', vpa: 'ram@okhdfc', date: DateTime.utc(2026, 10, 22, 9, 5));
      final row = side('row',
          narration: 'UPI-RAM@OKHDFC-1',
          date: DateTime.utc(2026, 10, 22, 9, 1),
          row: true);
      expect(DetectionMatcher.pair([sms, email], [row]), {'sms': 'row'});

      final twin = side('row2',
          narration: 'UPI-RAM@OKHDFC-2',
          date: DateTime.utc(2026, 10, 22, 9, 1),
          row: true);
      expect(DetectionMatcher.pair([sms], [row, twin]), isEmpty,
          reason: 'two rows equally close');
      expect(DetectionMatcher.suggestions(sms, [row, twin]).map((s) => s.$2),
          everyElement(MatchVerdict.merge));
    });

    test('two detections of one payment pair with each other', () {
      final sms = side('sms', tail: '1234', date: DateTime.utc(2026, 10, 22, 9));
      final email =
          side('email', tail: 'XX1234', date: DateTime.utc(2026, 10, 22, 9, 3));
      expect(DetectionMatcher.pair([email], [sms]), {'email': 'sms'});
    });
  });

  group('union', () {
    test('fills every empty field; the bank row wins a conflict', () {
      final memo = side('memo',
          payee: 'Blue Tokai', tail: '1234', date: DateTime.utc(2026, 10, 22, 9));
      final row = side('row',
          payee: 'BLUE TOKAI COFFEE ROASTERS',
          narration: 'UPI/BLUE TOKAI',
          reference: 'UPI1',
          row: true,
          date: DateTime.utc(2026, 10, 23));
      final merged = DetectionMatcher.union(memo, row);
      expect(merged.id, 'memo');
      expect(merged.payee, 'BLUE TOKAI COFFEE ROASTERS');
      expect(merged.date, DateTime.utc(2026, 10, 23));
      expect(merged.accountTail, '1234');
      expect(merged.reference, 'UPI1');
      expect(merged.isLedgerRow, isTrue);
    });

    test('between two detections the earlier one wins', () {
      final first = side('first', payee: 'Ram', date: DateTime.utc(2026, 10, 22, 9));
      final later = side('later', payee: 'Ram Kumar', vpa: 'ram@okhdfc', tail: '1234');
      final merged = DetectionMatcher.union(first, later);
      expect(merged.payee, 'Ram');
      expect(merged.vpa, 'ram@okhdfc');
      expect(merged.accountTail, '1234');
      expect(merged.date, DateTime.utc(2026, 10, 22, 9));
    });
  });
}
