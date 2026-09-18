import 'dart:convert';
import 'dart:io';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

List<String> bundledSpecJsons() => Directory('../../assets/formats')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.json'))
    .map((f) => f.readAsStringSync())
    .toList();

void main() {
  group('NormalizedTable', () {
    test('csv splits, trims, respects quoted commas', () {
      final t = NormalizedTable.from(
          data: utf8.encode(
              'Date,Narration,Balance\n01/04/2026,"POS, COFFEE",900.00\n'),
          filename: 'a.csv');
      expect(t!.container, 'csv');
      expect(t.rows[1], ['01/04/2026', 'POS, COFFEE', '900.00']);
    });

    test('txt splits on runs of spaces', () {
      final t = NormalizedTable.from(
          data: utf8.encode(
              'Date         Narration            Amount     Balance\n01/04/26     POS COFFEE           100.00     900.00\n'),
          filename: 'a.txt');
      expect(t!.rows[1], ['01/04/26', 'POS COFFEE', '100.00', '900.00']);
    });

    test('xlsx fixture produces rows via archive+xml', () {
      final data = File('test/fixtures/paytm-fixture.xlsx').readAsBytesSync();
      final t = NormalizedTable.from(data: data, filename: 's.xlsx');
      expect(t!.container, 'xlsx');
      expect(t.rows.length, greaterThan(3));
    });

    test('xls fixture produces rows via MinimalXls port', () {
      final data = File('test/fixtures/hdfc-fixture.xls').readAsBytesSync();
      final t = NormalizedTable.from(data: data, filename: 's.xls');
      expect(t!.container, 'xls');
      expect(t.rows.length, greaterThan(3));
    });

    test('garbage returns null', () {
      expect(NormalizedTable.from(data: [0, 1, 2], filename: 'a.xlsx'), isNull);
    });
  });

  group('SyntheticRef', () {
    test('recipe matches the shared cross-platform format', () {
      final d = DateTime.utc(2026, 4, 1).subtract(istOffset);
      expect(
          SyntheticRef.make(balancePaise: 90000, date: d, amountPaise: 10000),
          'B90000D20260401A10000');
    });
  });

  group('ChainInterpreter', () {
    // Shared story: open 1,000.00 → −100 (900) → +50 (950) → −200 (750).
    test('debit/credit columns validate with directions and refs', () {
      final rows = [
        ['01/04/2026', 'POS COFFEE', 'R1', '100.00', '', '900.00'],
        ['02/04/2026', 'SALARY', 'R2', '', '50.00', '950.00'],
        ['03/04/2026', 'UPI GROCER', 'R3', '200.00', '', '750.00'],
      ];
      const m = ColumnMapping(
          date: 0, narration: 1, reference: 2, debit: 3, credit: 4,
          balance: 5, dateFormat: 'dd/MM/yyyy');
      final outcome = ChainInterpreter.interpret(rows: rows, mapping: m);
      final txns = (outcome as ChainValidated).transactions;
      expect(txns.map((t) => t.direction),
          [Direction.debit, Direction.credit, Direction.debit]);
      expect(txns.map((t) => t.amountPaise), [10000, 5000, 20000]);
      expect(txns[0].reference, 'R1');
    });

    test('signed amount validates; missing ref column → synthetic', () {
      final rows = [
        ['01/04/2026', 'POS COFFEE', '-100.00', '900.00'],
        ['02/04/2026', 'SALARY', '50.00', '950.00'],
      ];
      const m = ColumnMapping(
          date: 0, narration: 1, amount: 2, balance: 3,
          dateFormat: 'dd/MM/yyyy');
      final txns =
          (ChainInterpreter.interpret(rows: rows, mapping: m) as ChainValidated)
              .transactions;
      expect(txns[0].reference, 'B90000D20260401A10000');
    });

    test('DR/CR qualifier validates case-insensitively', () {
      final rows = [
        ['01/04/2026', 'POS COFFEE', '100.00', 'DR', '900.00'],
        ['02/04/2026', 'SALARY', '50.00', 'cr', '950.00'],
      ];
      const m = ColumnMapping(
          date: 0, narration: 1, amount: 2, drcr: 3, balance: 4,
          dateFormat: 'dd/MM/yyyy');
      final txns =
          (ChainInterpreter.interpret(rows: rows, mapping: m) as ChainValidated)
              .transactions;
      expect(txns.map((t) => t.direction), [Direction.debit, Direction.credit]);
    });

    test('unsigned amounts: opening balance anchors; without it, ambiguous', () {
      final rows = [
        ['01/04/2026', 'POS COFFEE', '100.00', '900.00'],
        ['02/04/2026', 'SALARY', '50.00', '950.00'],
        ['03/04/2026', 'UPI GROCER', '200.00', '750.00'],
      ];
      const m = ColumnMapping(
          date: 0, narration: 1, amount: 2, balance: 3,
          amountIsUnsigned: true, dateFormat: 'dd/MM/yyyy');
      final anchored = ChainInterpreter.interpret(
          rows: rows, mapping: m, openingBalancePaise: 100000);
      expect((anchored as ChainValidated).transactions.map((t) => t.direction),
          [Direction.debit, Direction.credit, Direction.debit]);
      final unanchored = ChainInterpreter.interpret(rows: rows, mapping: m);
      expect(unanchored, isA<ChainBroken>());
      expect((unanchored as ChainBroken).detail, contains('ambiguous'));
    });

    test('chain break and column/chain disagreement report the row', () {
      final tampered = [
        ['01/04/2026', 'POS', 'R1', '100.00', '', '900.00'],
        ['02/04/2026', 'SALARY', 'R2', '', '50.00', '999.00'],
      ];
      const m = ColumnMapping(
          date: 0, narration: 1, reference: 2, debit: 3, credit: 4,
          balance: 5, dateFormat: 'dd/MM/yyyy');
      final broken = ChainInterpreter.interpret(rows: tampered, mapping: m);
      expect((broken as ChainBroken).rowIndex, 1);

      final disagree = [
        ['01/04/2026', 'POS', 'R1', '100.00', '', '900.00'],
        ['02/04/2026', 'SALARY', 'R2', '50.00', '', '950.00'],
      ];
      final out = ChainInterpreter.interpret(rows: disagree, mapping: m);
      expect((out as ChainBroken).rowIndex, 1);
    });

    test('reference patterns extract rail refs from narration', () {
      final rows = [
        ['01/04/2026', 'UPI/DR/606435614627/Somebody/x', '100.00', '', '900.00'],
      ];
      const m = ColumnMapping(
          date: 0, narration: 1, debit: 2, credit: 3, balance: 4,
          dateFormat: 'dd/MM/yyyy',
          referencePatterns: [r'^UPI\/(?:DR|CR)\/\s*([^\/]+?)\s*\/']);
      final txns =
          (ChainInterpreter.interpret(rows: rows, mapping: m) as ChainValidated)
              .transactions;
      expect(txns[0].reference, '606435614627');
    });
  });

  group('SpecExecutor', () {
    const sbiLikeSpec = FormatSpec(
      id: 'test-sbi',
      sourceID: 'bank:sbi',
      bankName: 'State Bank of India',
      headerPatterns: {
        'date': r'^txn date$', 'narration': r'^description$',
        'reference': 'ref no', 'debit': r'^debit$',
        'credit': r'^credit$', 'balance': r'^balance$',
      },
      furniturePatterns: ['statement of account'],
      dateFormats: ['dd/MM/yyyy'],
      signConvention: 'debitCredit',
    );

    NormalizedTable sbiLikeTable() => NormalizedTable(rows: [
          ['STATE BANK OF INDIA'],
          ['Statement of Account'],
          ['Txn Date', 'Description', 'Ref No./Cheque No.', 'Debit', 'Credit', 'Balance'],
          ['01/04/2026', 'POS COFFEE', 'R1', '100.00', '', '900.00'],
          ['02/04/2026', 'SALARY CREDIT', 'R2', '', '50.00', '950.00'],
          ['03/04/2026', 'UPI GROCER', 'R3', '200.00', '', '750.00'],
        ], container: 'csv');

    test('validates matching table; furniture stripped; nil on foreign', () {
      final outcome =
          SpecExecutor.execute(table: sbiLikeTable(), spec: sbiLikeSpec);
      expect((outcome as ChainValidated).transactions.length, 3);

      final withFurniture = sbiLikeTable();
      withFurniture.rows.insert(4, ['Statement of Account contd.']);
      final furnished =
          SpecExecutor.execute(table: withFurniture, spec: sbiLikeSpec);
      expect((furnished as ChainValidated).transactions.length, 3);

      final foreign = NormalizedTable(rows: [
        ['Date', 'Transaction Details', 'Amount'],
        ['01/04/2026', 'Paid to X', '-100'],
      ], container: 'csv');
      expect(SpecExecutor.execute(table: foreign, spec: sbiLikeSpec), isNull);
    });

    test('tampered balance is broken; detect gate blocks wrong bank', () {
      final tampered = sbiLikeTable();
      tampered.rows[4][5] = '999.00';
      expect(SpecExecutor.execute(table: tampered, spec: sbiLikeSpec),
          isA<ChainBroken>());

      const gated = FormatSpec(
        id: 'gated', sourceID: 'bank:pnb', bankName: 'PNB',
        headerPatterns: {
          'date': r'^txn date$', 'narration': r'^description$',
          'debit': r'^debit$', 'credit': r'^credit$', 'balance': r'^balance$',
        },
        dateFormats: ['dd/MM/yyyy'], signConvention: 'debitCredit',
        detectPatterns: ['punjab national'],
      );
      expect(SpecExecutor.execute(table: sbiLikeTable(), spec: gated), isNull);
    });
  });

  group('Bundled specs', () {
    test('all nine parse; each validates its fixture; zero cross-detection',
        () {
      final specs = SpecStore.parseAll(bundledSpecJsons());
      expect(specs.length, greaterThanOrEqualTo(9));
      for (final spec in specs) {
        if (spec.id == 'idfc-xlsx') continue;
        final data =
            File('test/fixtures/${spec.id}-fixture.csv').readAsBytesSync();
        final table = NormalizedTable.from(data: data, filename: 'f.csv')!;
        final outcome = SpecExecutor.execute(table: table, spec: spec);
        expect(outcome, isA<ChainValidated>(),
            reason: '${spec.id} failed its own fixture');
        expect((outcome as ChainValidated).transactions.length,
            greaterThanOrEqualTo(10));
        for (final other in specs) {
          if (other.id == spec.id) continue;
          expect(SpecExecutor.execute(table: table, spec: other), isNull,
              reason: '${other.id} cross-detected ${spec.id}');
        }
      }
    });
  });

  group('ColumnInference', () {
    NormalizedTable table(List<List<String>> rows) =>
        NormalizedTable(rows: rows, container: 'csv');

    final headered = [
      ['STATE BANK OF INDIA'],
      ['Txn Date', 'Description', 'Ref No.', 'Debit', 'Credit', 'Balance'],
      ['01/04/2026', 'POS COFFEE SHOP', 'R1', '100.00', '', '900.00'],
      ['02/04/2026', 'SALARY CREDIT ACME', 'R2', '', '50.00', '950.00'],
      ['03/04/2026', 'UPI GROCER PAY', 'R3', '200.00', '', '750.00'],
      ['04/04/2026', 'POS BOOKSTORE', 'R4', '150.00', '', '600.00'],
    ];

    test('headered debit/credit table infers, shuffle-invariant', () {
      final base = ColumnInference.infer(table(headered))!;
      expect(base.transactions.length, 4);
      expect(base.transactions[0].reference, 'R1');

      final shuffled = [
        ['Balance', 'Debit', 'Credit', 'Txn Date', 'Description'],
        ['900.00', '100.00', '', '01/04/2026', 'POS COFFEE SHOP'],
        ['950.00', '', '50.00', '02/04/2026', 'SALARY CREDIT ACME'],
        ['750.00', '200.00', '', '03/04/2026', 'UPI GROCER PAY'],
        ['600.00', '150.00', '', '04/04/2026', 'POS BOOKSTORE'],
      ];
      final moved = ColumnInference.infer(table(shuffled))!;
      expect(moved.transactions.map((t) => t.amountPaise),
          base.transactions.map((t) => t.amountPaise));
    });

    test('signed, drcr, and headerless variants infer', () {
      expect(
          ColumnInference.infer(table([
            ['Date', 'Narration', 'Amount', 'Balance'],
            ['01/04/2026', 'POS COFFEE SHOP', '-100.00', '900.00'],
            ['02/04/2026', 'SALARY CREDIT ACME', '50.00', '950.00'],
            ['03/04/2026', 'UPI GROCER PAY', '-200.00', '750.00'],
          ])),
          isNotNull);
      expect(
          ColumnInference.infer(table([
            ['Tran Date', 'Particulars', 'Amount(INR)', 'DR/CR', 'Balance'],
            ['01/04/2026', 'POS COFFEE SHOP', '100.00', 'DR', '900.00'],
            ['02/04/2026', 'SALARY CREDIT ACME', '50.00', 'CR', '950.00'],
            ['03/04/2026', 'UPI GROCER PAY', '200.00', 'DR', '750.00'],
          ])),
          isNotNull);
      expect(
          ColumnInference.infer(table([
            ['01/04/2026', 'POS COFFEE SHOP', '100.00', '', '900.00'],
            ['02/04/2026', 'SALARY CREDIT ACME', '', '50.00', '950.00'],
            ['03/04/2026', 'UPI GROCER PAY', '200.00', '', '750.00'],
          ])),
          isNotNull);
    });

    test('broken chain refuses to infer', () {
      final tampered = headered.map((r) => List<String>.from(r)).toList();
      tampered[3][5] = '999.00';
      expect(ColumnInference.infer(table(tampered)), isNull);
    });
  });

  group('FormatFingerprint', () {
    NormalizedTable sample() => NormalizedTable(rows: [
          ['CANARA BANK', ''],
          ['Date', 'Narration', 'Amount', 'Balance'],
          ['01/04/2026', 'SALARY ACME CORP 987654', '100.00', '900.00'],
          ['02/04/2026', 'POS COFFEE 4413', '150.00', '850.00'],
        ], container: 'csv');

    test('no body cell value ever appears; header and shapes captured', () {
      final fp = FormatFingerprint.make(sample());
      final everything = fp.toJsonString() + fp.emailBody(appVersion: '1.1.0');
      for (final secret in [
        'SALARY', 'ACME', '987654', 'COFFEE', '4413', '01/04/2026', '100.00'
      ]) {
        expect(everything.contains(secret), isFalse,
            reason: 'leaked body value: $secret');
      }
      expect(fp.headerRow, ['Date', 'Narration', 'Amount', 'Balance']);
      expect(fp.cellShapes[0], 'NN/NN/NNNN');
      expect(fp.cellShapes[2], 'NNN.NN');
      expect(fp.bankNameGuess, 'Canara');
    });

    test('mailto targets support address with encoded body', () {
      final uri = FormatFingerprint.make(sample()).mailtoUri(appVersion: '1.1.0');
      expect(uri.scheme, 'mailto');
      expect(uri.path, FormatFingerprint.supportAddress);
      expect(uri.queryParameters['subject'], 'Hisab format request');
      expect(uri.queryParameters['body'],
          FormatFingerprint.make(sample()).emailBody(appVersion: '1.1.0'));
    });
  });

  group('ImportResolver', () {
    ImportResolver resolver({List<FormatSpec> specs = const []}) =>
        ImportResolver(registry: const ParserRegistry([]), specs: specs);

    const sbiSpec = FormatSpec(
      id: 'test-sbi', sourceID: 'bank:sbi', bankName: 'SBI',
      headerPatterns: {
        'date': r'^txn date$', 'narration': r'^description$',
        'reference': 'ref no', 'debit': r'^debit$',
        'credit': r'^credit$', 'balance': r'^balance$',
      },
      dateFormats: ['dd/MM/yyyy'], signConvention: 'debitCredit',
    );

    const sbiCsv = 'Txn Date,Description,Ref No./Cheque No.,Debit,Credit,Balance\n'
        '01/04/2026,POS COFFEE,R1,100.00,,900.00\n'
        '02/04/2026,SALARY,R2,,50.00,950.00\n';

    test('supportedFormatNames lists parsers then spec banks, deduped', () {
      // Pinned to the exact list ImportResolverTests.swift asserts.
      final specs = bundledSpecJsons().map(FormatSpec.fromJsonString).toList();
      final res = ImportResolver(registry: const ParserRegistry([]), specs: specs);
      expect(res.supportedFormatNames, [
        'Google Pay', 'Paytm', 'BHIM UPI', 'HDFC Bank', 'IDFC First Bank',
        'Axis Bank', 'Bank of Baroda', 'ICICI Bank', 'Kotak Mahindra Bank',
        'Punjab National Bank', 'State Bank of India',
      ]);
    });

    test('spec parses when no code parser matches', () {
      final res = resolver(specs: [sbiSpec])
          .resolve(data: utf8.encode(sbiCsv), filename: 'sbi.csv');
      final doc = (res as ResolutionParsed).document;
      expect(doc.source, const Source('bank:sbi'));
      expect(doc.transactions.length, 2);
    });

    test('inference catches unknown bank and slugs the guess', () {
      const csv = 'CANARA BANK\n'
          'Date,Narration,Debit,Credit,Balance\n'
          '01/04/2026,POS COFFEE SHOP,100.00,,900.00\n'
          '02/04/2026,SALARY CREDIT ACME,,50.00,950.00\n'
          '03/04/2026,UPI GROCER PAY,200.00,,750.00\n';
      final res =
          resolver().resolve(data: utf8.encode(csv), filename: 'unknown.csv');
      expect((res as ResolutionParsed).document.source,
          const Source('bank:canara'));
    });

    test('garbage is unsupported with fingerprint; tamper is unverified', () {
      final garbage =
          resolver().resolve(data: [0, 1], filename: 'x.xlsx');
      expect((garbage as ResolutionUnsupported).fingerprint.container, 'xlsx');

      final tampered = sbiCsv.replaceAll('950.00', '999.00');
      final res = resolver(specs: [sbiSpec])
          .resolve(data: utf8.encode(tampered), filename: 'sbi.csv');
      expect(res, isA<ResolutionUnverified>());
    });
  });
}
