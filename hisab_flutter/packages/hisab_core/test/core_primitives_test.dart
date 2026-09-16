import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

void main() {
  group('YearMonth', () {
    test('advancedBy crosses year boundaries both ways', () {
      expect(YearMonth(2026, 1).advancedBy(-1), YearMonth(2025, 12));
      expect(YearMonth(2026, 12).advancedBy(1), YearMonth(2027, 1));
      expect(YearMonth(2026, 6).advancedBy(-18), YearMonth(2024, 12));
    });

    test('monthsFromThrough is inclusive and ordered', () {
      final months = YearMonth.monthsFromThrough(
          YearMonth(2025, 11), YearMonth(2026, 2));
      expect(months, [
        YearMonth(2025, 11), YearMonth(2025, 12),
        YearMonth(2026, 1), YearMonth(2026, 2),
      ]);
      expect(
          YearMonth.monthsFromThrough(YearMonth(2026, 2), YearMonth(2026, 1)),
          isEmpty);
    });

    test('IST resolution: a UTC evening is the next IST day', () {
      // 2026-03-31 20:00 UTC = 2026-04-01 01:30 IST
      final d = DateTime.utc(2026, 3, 31, 20);
      expect(YearMonth.fromDate(d), YearMonth(2026, 4));
      expect(istDayString(d), '2026-04-01');
      expect(istCompactDayString(d), '20260401');
    });

    test('description and displayName', () {
      expect(YearMonth(2026, 4).toString(), '2026-04');
      expect(YearMonth(2026, 4).displayName, 'Apr 2026');
    });
  });

  group('Money', () {
    test('formatPaise uses Indian grouping', () {
      expect(Money.formatPaise(1234567890), '₹1,23,45,678.90');
      expect(Money.formatPaise(12345678), '₹1,23,456.78');
      expect(Money.formatPaise(-45300), '-₹453.00');
      expect(Money.formatPaise(60000, signed: true), '+₹600.00');
      expect(Money.formatPaise(5), '₹0.05');
    });

    test('signedPaise parses decimals, signs, commas', () {
      expect(Money.signedPaise('-453.00'), -45300);
      expect(Money.signedPaise('+600'), 60000);
      expect(Money.signedPaise('1,23,456.78'), 12345678);
      expect(Money.signedPaise('303594.0'), 30359400);
      expect(Money.signedPaise('1999'), 199900);
      expect(Money.signedPaise('banana'), isNull);
      expect(Money.signedPaise('1.234'), isNull);
      expect(Money.signedPaise(''), isNull);
      expect(Money.signedPaise('12/04/2026'), isNull);
    });
  });

  group('Source', () {
    test('open ids and frozen raw values', () {
      expect(Source.gpay.rawValue, 'gpay');
      expect(Source.paytm.rawValue, 'paytm');
      expect(Source.bhim.rawValue, 'bhim');
      expect(Source.hdfc.rawValue, 'hdfc');
      expect(Source.idfc.rawValue, 'idfc');
      const sbi = Source('bank:sbi');
      expect(sbi.kind, SourceKind.bank);
      expect(sbi.displayName, 'SBI');
      expect(const Source('upi:phonepe').kind, SourceKind.paymentApp);
      expect(const Source('upi:phonepe').displayName, 'Phonepe');
      expect(const Source('hdfc'), Source.hdfc);
      expect(Source.builtIn,
          [Source.gpay, Source.paytm, Source.bhim, Source.hdfc, Source.idfc]);
    });

    test('ordered: apps first, then banks alphabetically, deduped', () {
      final result = Source.ordered(
          [const Source('bank:sbi'), Source.gpay, Source.gpay, Source.hdfc]);
      expect(result, [Source.gpay, Source.hdfc, const Source('bank:sbi')]);
    });
  });

  group('ContentHash — cross-platform parity (pinned from Swift)', () {
    ParsedTransaction txn({String? ref, String narration = 'UPI/PAY/x'}) =>
        ParsedTransaction(
          date: DateTime.fromMillisecondsSinceEpoch(1772600000 * 1000,
              isUtc: true),
          amountPaise: 12345,
          direction: Direction.debit,
          counterparty: 'BLUE TOKAI',
          reference: ref,
          narration: narration,
        );

    test('ref-keyed hashes are byte-identical to the Swift pins', () {
      expect(txn(ref: '425100012345').contentHash(Source.gpay),
          '532f81e564fa279187375979347d870a9e9fc0936d5e7d9e31c22c8d9399b059');
      expect(txn(ref: '425100012345').contentHash(Source.paytm),
          '10f9d2d950eb1553fe9bb45d031f76fdc1c13eec0a31a371dca262f41d14c50c');
      expect(txn(ref: '425100012345').contentHash(Source.bhim),
          '241b83db79cd8ca0eaf1da18dde8a76ff378bb004eb5ef83a0769e3b78aea719');
      expect(txn(ref: '425100012345').contentHash(Source.hdfc),
          '962aaa86d8f4760633d7348644933fe7b30c028b4143580a1e47dbb0b3238bd6');
      expect(txn(ref: '425100012345').contentHash(Source.idfc),
          '219b6e9795333ecb2b41ab73ec0cadcc8ac1cb2387fb8194b7a20ac2535e520a');
    });

    test('refless fallback hash matches the Swift pin', () {
      expect(
          txn(ref: null, narration: '  POS   1234  Coffee ')
              .contentHash(Source.hdfc),
          'a756f6fc0f7b272b2983b46c0a7855aba0d3adfed7de4e9809d8943ddba4657d');
    });

    test('direction distinguishes a refund reusing its payment ref', () {
      final pay = txn(ref: 'R1');
      final refund = ParsedTransaction(
        date: pay.date,
        amountPaise: pay.amountPaise,
        direction: Direction.credit,
        counterparty: pay.counterparty,
        reference: 'R1',
        narration: pay.narration,
      );
      expect(pay.contentHash(Source.idfc),
          isNot(refund.contentHash(Source.idfc)));
    });
  });

  group('Dedup', () {
    test('first occurrence wins within batch and against store', () {
      final a = ParsedTransaction(
          date: DateTime.utc(2026, 4, 1),
          amountPaise: 100,
          direction: Direction.debit,
          counterparty: 'X',
          reference: 'R1',
          narration: 'X');
      final b = ParsedTransaction(
          date: DateTime.utc(2026, 4, 2),
          amountPaise: 200,
          direction: Direction.debit,
          counterparty: 'Y',
          reference: 'R2',
          narration: 'Y');
      final indices = Dedup.newIndices(
          incoming: [a, a, b],
          source: Source.gpay,
          existingHashes: {b.contentHash(Source.gpay)});
      expect(indices, [0]);
    });
  });
}
