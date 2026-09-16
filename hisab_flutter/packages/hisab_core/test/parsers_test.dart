import 'dart:convert';
import 'dart:io';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

void main() {
  group('SyntheticCsvParser', () {
    const csv = 'hisab-demo-csv,v1\n'
        'period,2026-04-01,2026-04-30\n'
        '2026-04-02,12500,debit,Blue Tokai,R1,UPI/R1/coffee\n'
        '2026-04-05,500000,credit,Acme Corp,R2,salary\n';

    test('parses rows, period, directions', () {
      const parser = SyntheticCsvParser();
      expect(parser.canParse(utf8.encode(csv), 'demo.csv'), isTrue);
      final doc = parser.parse(utf8.encode(csv));
      expect(doc.transactions.length, 2);
      expect(doc.transactions[0].direction, Direction.debit);
      expect(doc.transactions[1].amountPaise, 500000);
      expect(doc.declaredPeriod!.months, [YearMonth(2026, 4)]);
    });

    test('malformed row names its line', () {
      const bad = 'hisab-demo-csv,v1\n2026-04-02,banana,debit,X,R,Y\n';
      expect(() => const SyntheticCsvParser().parse(utf8.encode(bad)),
          throwsA(isA<MalformedRowException>()));
    });
  });

  group('PaytmXlsxParser', () {
    final data = File('test/fixtures/paytm-fixture.xlsx').readAsBytesSync();

    test('canParse + parses fixture with signed amounts and period', () {
      const parser = PaytmXlsxParser();
      expect(parser.canParse(data, 's.xlsx'), isTrue);
      final doc = parser.parse(data);
      expect(doc.transactions, isNotEmpty);
      for (final txn in doc.transactions) {
        expect(txn.amountPaise, greaterThan(0));
      }
      expect(doc.source, Source.paytm);
    });
  });

  group('IdfcXlsxParser', () {
    final data = File('test/fixtures/idfc-fixture.xlsx').readAsBytesSync();

    test('canParse + chain-validated parse with rail refs', () {
      const parser = IdfcXlsxParser();
      expect(parser.canParse(data, 's.xlsx'), isTrue);
      final doc = parser.parse(data);
      expect(doc.transactions, isNotEmpty);
      expect(doc.source, Source.idfc);
      // Rail refs extracted where present (fixture has NEFT/UPI/POS rows).
      expect(doc.transactions.any((t) => t.reference == 'HDFCH00834165953'),
          isTrue);
    });

    test('spec parity: idfc-xlsx spec reproduces the code parser hash-for-hash',
        () {
      final legacy = const IdfcXlsxParser().parse(data);
      final table =
          NormalizedTable.from(data: data, filename: 'statement.xlsx')!;
      final specs = SpecStore.parseAll(Directory('../../assets/formats')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) => f.readAsStringSync()));
      final spec = specs.firstWhere((s) => s.id == 'idfc-xlsx');
      final outcome = SpecExecutor.execute(table: table, spec: spec);
      final txns = (outcome as ChainValidated).transactions;
      expect(txns.length, legacy.transactions.length);
      final legacyHashes =
          legacy.transactions.map((t) => t.contentHash(Source.idfc)).toSet();
      final specHashes =
          txns.map((t) => t.contentHash(Source(spec.sourceID))).toSet();
      expect(specHashes, legacyHashes);
    });
  });

  group('HdfcXlsParser', () {
    final data = File('test/fixtures/hdfc-fixture.xls').readAsBytesSync();

    test('canParse + chain-validated parse with normalized refs', () {
      const parser = HdfcXlsParser();
      expect(parser.canParse(data, 's.xls'), isTrue);
      final doc = parser.parse(data);
      expect(doc.transactions, isNotEmpty);
      expect(doc.source, Source.hdfc);
      for (final txn in doc.transactions) {
        expect(txn.reference, isNotNull);
        expect(txn.reference!.startsWith('0'), isFalse,
            reason: 'refs are zero-stripped');
      }
    });
  });

  group('HdfcTxtParser', () {
    String pad(String s, int w) =>
        s.length >= w ? s.substring(0, w) : s.padRight(w);

    String fixture() {
      const widths = [8, 21, 16, 8, 15, 13, 15];
      String line(List<String> cells) => [
            for (var i = 0; i < widths.length; i++) pad(cells[i], widths[i])
          ].join('  ');
      final ruler = widths.map((w) => '-' * w).join('  ');
      return [
        'HDFC BANK Ltd.',
        'Statement of accounts',
        'Statement From : 01/04/2026 To : 30/04/2026',
        'Opening Balance :',
        '  1000.00',
        line(['Date', 'Narration', 'Chq./Ref.No.', 'Value Dt', 'Withdrawal Amt.',
              'Deposit Amt.', 'Closing Balance']),
        ruler,
        line(['01/04/26', 'UPI-COFFEE SHOP-x', '0000000000000R1', '01/04/26',
              '100.00', '', '900.00']),
        line(['', 'continued narration', '', '', '', '', '']),
        line(['02/04/26', 'NEFT CR-IFSC-ACME-x', '0000000000000R2', '02/04/26',
              '', '50.00', '950.00']),
        ruler,
        'STATEMENT SUMMARY',
      ].join('\n');
    }

    test('dash-ruler slicing, continuation merge, opening-balance chain', () {
      final bytes = utf8.encode(fixture());
      const parser = HdfcTxtParser();
      expect(parser.canParse(bytes, 's.txt'), isTrue);
      final doc = parser.parse(bytes);
      expect(doc.transactions.length, 2);
      expect(doc.transactions[0].narration,
          'UPI-COFFEE SHOP-x continued narration');
      expect(doc.transactions[0].counterparty, 'COFFEE SHOP');
      expect(doc.transactions[0].reference, 'R1');
      expect(doc.transactions[1].direction, Direction.credit);
      expect(doc.transactions[1].counterparty, 'ACME');
      expect(doc.declaredPeriod!.months, [YearMonth(2026, 4)]);
    });

    test('a tampered balance breaks the chain', () {
      final tampered = fixture().replaceAll('950.00', '999.00');
      expect(() => const HdfcTxtParser().parse(utf8.encode(tampered)),
          throwsA(isA<MalformedRowException>()));
    });
  });

  group('liveRegistry', () {
    test('detects each non-PDF format by content', () {
      final registry = liveRegistry();
      final idfc = File('test/fixtures/idfc-fixture.xlsx').readAsBytesSync();
      expect(registry.detect(idfc, 's.xlsx'), isA<IdfcXlsxParser>());
      final paytm = File('test/fixtures/paytm-fixture.xlsx').readAsBytesSync();
      expect(registry.detect(paytm, 's.xlsx'), isA<PaytmXlsxParser>());
      final hdfc = File('test/fixtures/hdfc-fixture.xls').readAsBytesSync();
      expect(registry.detect(hdfc, 's.xls'), isA<HdfcXlsParser>());
      expect(registry.detect(utf8.encode('hisab-demo-csv,v1\n'), 'd.csv'),
          isA<SyntheticCsvParser>());
      expect(registry.detect([0x00], 'x.bin'), isNull);
    });
  });
}
