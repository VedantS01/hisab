// Port of ProposedMappingTests.swift, plus the reply parsing a text-only
// model reader (Gemini Nano on Android) relies on.
import 'dart:convert';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

class Fixed implements ColumnRoleProposer {
  final ColumnRoles? roles;
  const Fixed(this.roles);
  @override
  Future<ColumnRoles?> propose(List<String>? header, List<List<String>> rows) async => roles;
}

class Failing implements ColumnRoleProposer {
  @override
  Future<ColumnRoles?> propose(List<String>? header, List<List<String>> rows) =>
      Future.error(StateError('model unavailable'));
}

/// An unsigned amount column, an opening-balance line and a closing line:
/// ColumnInference refuses it (the closing line isn't a date, and it never
/// reads amounts as unsigned), but with the columns named the balance chain
/// settles every direction, the first row's included.
const unsignedCsv = '''XYZ BANK LTD
Date,Details,Ref,Amount,Balance
Opening Balance,,,,1000.00
01/04/2026,POS COFFEE,R1,100.00,900.00
02/04/2026,SALARY ACME,R2,50.00,950.00
03/04/2026,UPI GROCER,R3,200.00,750.00
Closing Balance,,,350.00,750.00''';

const roles = ColumnRoles(date: 0, narration: 1, reference: 2, amount: 3, balance: 4);

NormalizedTable csv(String text) =>
    NormalizedTable.from(data: utf8.encode(text), filename: 'statement.csv')!;

void main() {
  test('the rules alone refuse', () {
    expect(ColumnInference.infer(csv(unsignedCsv)), isNull);
  });

  test('proposed columns read the table when the chain closes', () async {
    final result = (await ProposedMapping.read(csv(unsignedCsv), const Fixed(roles)))!;
    expect(result.transactions.map((t) => t.amountPaise), [10000, 5000, 20000]);
    expect(result.transactions.map((t) => t.direction),
        [Direction.debit, Direction.credit, Direction.debit]);
    expect(result.transactions.map((t) => t.reference), ['R1', 'R2', 'R3']);
    expect(result.transactions.map((t) => t.narration), ['POS COFFEE', 'SALARY ACME', 'UPI GROCER']);
    expect(result.mapping.amountIsUnsigned, isTrue);
  });

  test('one leg called the amount still reads as legs', () async {
    // What an on-device model says of HDFC's "Withdrawal Amt." / "Deposit
    // Amt.": a debit column and an amount column.
    const legs = '''Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
01/04/25,UPI-SAHUL,14.00,,10041.58
02/04/25,NEFT CR-MR VEDANT,,2000.00,12041.58
03/04/25,UPI-SWIGGY,436.00,,11605.58''';
    const proposal = ColumnRoles(date: 0, narration: 1, debit: 2, amount: 3, balance: 4);
    final result = (await ProposedMapping.read(csv(legs), const Fixed(proposal)))!;
    expect(result.transactions.map((t) => t.direction),
        [Direction.debit, Direction.credit, Direction.debit]);
    expect([result.mapping.debit, result.mapping.credit], [2, 3]);
  });

  test('the rightmost money column stands in for a missing balance label', () {
    expect(
        ColumnRoles.fromLabels(['date', 'narration', 'reference', 'valueDate', 'debit', 'credit', 'amount']),
        const ColumnRoles(date: 0, narration: 1, reference: 2, debit: 4, credit: 5, balance: 6));
    expect(ColumnRoles.fromLabels(['other', 'narration', 'balance']), isNull);
  });

  test('a wrong proposal is a refusal', () async {
    const swapped = ColumnRoles(date: 0, narration: 1, reference: 2, amount: 4, balance: 3);
    expect(await ProposedMapping.read(csv(unsignedCsv), const Fixed(swapped)), isNull);
  });

  test('a column outside the table is a refusal', () async {
    const wrong = ColumnRoles(date: 0, narration: 1, reference: 9, amount: 3, balance: 4);
    expect(await ProposedMapping.read(csv(unsignedCsv), const Fixed(wrong)), isNull);
  });

  test('unsigned amounts without an opening line stay unread', () async {
    // Nothing anchors the first row's direction, so both readings close.
    final text = unsignedCsv.replaceFirst('Opening Balance,,,,1000.00\n', '');
    expect(await ProposedMapping.read(csv(text), const Fixed(roles)), isNull);
  });

  test('the resolver falls back to the proposer only on a refusal', () async {
    const resolver = ImportResolver(registry: ParserRegistry([]), specs: []);
    final data = utf8.encode(unsignedCsv);
    expect(resolver.resolve(data: data, filename: 'statement.csv'), isA<ResolutionUnsupported>());
    final read = await resolver.resolveWithProposer(
        data: data, filename: 'statement.csv', proposer: const Fixed(roles));
    expect(read, isA<ResolutionParsed>());
    final doc = (read as ResolutionParsed).document;
    expect(doc.transactions.length, 3);
    expect(doc.source.rawValue.startsWith('bank:'), isTrue);
    expect(
        await resolver.resolveWithProposer(data: data, filename: 'statement.csv', proposer: Failing()),
        isA<ResolutionUnsupported>(),
        reason: 'a proposer that fails leaves the refusal as it was');
  });

  test('the sample shows every column filled at least once', () {
    final body = [
      for (var i = 0; i < 10; i++) ['0$i/04/26', 'UPI $i', '1.00', '', '${100 - i}.00'],
      ['11/04/26', 'SALARY', '', '50.00', '140.00'],
    ];
    final sample = ProposedMapping.sample(body);
    expect(sample.length, ProposedMapping.sampleRows);
    expect(sample.any((r) => r[3].isNotEmpty), isTrue);
  });

  group('ColumnLabelPrompt', () {
    test('asks for one labelled line per column', () {
      final prompt = ColumnLabelPrompt.build(
          ['Date', 'Details', 'Amount', 'Balance'], [['01/04/26', 'COFFEE', '1.00', '9.00']]);
      expect(prompt, contains('Header: 0: Date | 1: Details | 2: Amount | 3: Balance'));
      expect(prompt, contains('exactly 4 lines, one per column from 0 to 3'));
    });

    test('reads the reply leniently, inside the vocabulary', () {
      const reply = '''Here are the labels:
0: date
1 - Narration
**2**: reference
3: Withdrawal
- 4: AMOUNT
9: balance
5: balance''';
      expect(ColumnLabelPrompt.parse(reply, 6),
          ['date', 'narration', 'reference', 'other', 'amount', 'balance']);
    });
  });
}
