// IdfcPdfParser over synthetic positioned text: column positions from the
// real statement (y grows up the page), invented rows. The real sample's
// check (161 rows, identical to its XLSX) needs PDFKit and runs on device.
import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

TextFragment f(String text, double minX, double maxX, double y) =>
    TextFragment(text: text, minX: minX, maxX: maxX, minY: y, maxY: y + 9);

List<TextFragment> row(double y,
    {required String date,
    required List<String> particulars,
    String debit = '',
    String credit = '',
    required String balance}) {
  return [
    f(date, 35, 80.8, y),
    f(date, 113.9, 159.7, y),
    for (var i = 0; i < particulars.length; i++)
      f(particulars[i], 192.7, 192.7 + particulars[i].length * 4.5, y - i * 10),
    if (debit.isNotEmpty) f(debit, 395 - debit.length * 4.5, 395, y),
    if (credit.isNotEmpty) f(credit, 475 - credit.length * 4.5, 475, y),
    f(balance, 576 - balance.length * 4.5, 576, y),
  ];
}

List<List<TextFragment>> statement({String ifsc = 'IFSC : IDFB0040001', String closing = '1,850.00'}) => [
      [
        f('STATEMENT OF ACCOUNT', 250, 345, 760),
        // PDFKit's runs come cut at wide gaps; the parser reads the line.
        f('STATEMENT PERIOD', 28, 128, 712.9),
        f(':', 155.8, 158.6, 712.9),
        f('2026-03-01 TO 2026-03-31', 169.7, 291, 712.9),
        f(ifsc, 28, 120, 690),
        f('Date', 60.8, 78.1, 600),
        f('Value Date', 128.1, 168.5, 600),
        f('Particulars', 219.6, 261.0, 600),
        f('Cheque No', 304.5, 333.8, 600),
        f('Debit', 374.9, 394.9, 600),
        f('Credit', 452.2, 475.3, 600),
        f('Balance', 527.2, 557.9, 600),
        ...row(570,
            date: '02-Mar-2026',
            particulars: ['UPI/DR/111122223333/', 'Shop A/HDFC/shopa/UPI'],
            debit: '100.00',
            balance: '900.00'),
        ...row(540,
            date: '03-Mar-2026',
            particulars: ['NEFT/', 'IDFB000000000001/ ACME', 'LTD/HDFC0000001'],
            credit: '1,000.00',
            balance: '1,900.00'),
        ...row(500,
            date: '04-Mar-2026',
            particulars: ['POS-VISA/NAME-', 'CHEAP.COM/607000000001/14:22:47'],
            debit: '50.00',
            balance: closing),
      ]
    ];

const pdf = [0x25, 0x50, 0x44, 0x46, 0x2D];

void main() {
  test('reads the rows with the XLSX parser\'s references and particulars', () {
    final parser = IdfcPdfParser((_) => statement());
    expect(parser.canParse(pdf, 'statement.pdf'), isTrue);
    final doc = parser.parse(pdf);
    expect(doc.source, Source.idfc);
    expect(doc.declaredPeriod?.start, StatementDate.tryParse('2026-03-01', 'yyyy-MM-dd'));
    expect(doc.declaredPeriod?.end, StatementDate.tryParse('2026-03-31', 'yyyy-MM-dd'));
    expect(
        [for (final t in doc.transactions) (t.direction, t.amountPaise, t.counterparty, t.reference)],
        [
          (Direction.debit, 10000, 'Shop A', '111122223333'),
          (Direction.credit, 100000, 'ACME LTD', 'IDFB000000000001'),
          (Direction.debit, 5000, 'NAME-CHEAP.COM', '607000000001'),
        ]);
    // Wrapped lines join as the XLSX prints them: no space after "/" or "-".
    expect(doc.transactions.last.narration, 'POS-VISA/NAME-CHEAP.COM/607000000001/14:22:47');
  });

  test('a balance that does not close is refused, not guessed', () {
    final parser = IdfcPdfParser((_) => statement(closing: '1,800.00'));
    expect(() => parser.parse(pdf), throwsA(isA<MalformedRowException>()));
  });

  test('only IDFC statements, and only when the reader has the text', () {
    expect(IdfcPdfParser((_) => statement(ifsc: 'IFSC : HDFC0000001')).canParse(pdf, 'x.pdf'), isFalse);
    expect(IdfcPdfParser((_) => null).canParse(pdf, 'x.pdf'), isFalse);
    expect(IdfcPdfParser((_) => statement()).canParse(const [0x50, 0x4B, 3, 4], 'x.xlsx'), isFalse);
  });
}
