import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/pdfkit_text.dart';

Map<String, Object?> run(String text, List<(String, double, double)> words) => {
      't': text,
      'x0': words.first.$2,
      'x1': words.last.$3,
      'y0': 100.0,
      'y1': 110.0,
      'words': [for (final (t, x0, x1) in words) {'t': t, 'x0': x0, 'x1': x1}],
    };

void main() {
  test('a run holding an amount is cut where words sit far apart', () {
    final pieces = PdfKitText.split(run('UPI/DR/1234/ Shop 5,97,803.00', [
      ('UPI/DR/1234/', 10, 70),
      ('Shop', 72, 92),
      ('5,97,803.00', 300, 350),
    ]));
    expect([for (final p in pieces) (p.text, p.minX, p.maxX)],
        [('UPI/DR/1234/ Shop', 10.0, 92.0), ('5,97,803.00', 300.0, 350.0)]);
    expect(pieces.every((p) => p.minY == 100 && p.maxY == 110), isTrue);
  });

  test('a run of plain words stays whole however wide its gaps', () {
    final pieces = PdfKitText.split(run('Opening   Balance', [
      ('Opening', 10, 50),
      ('Balance', 200, 240),
    ]));
    expect(pieces.single.text, 'Opening   Balance');
  });

  test('cells cut on horizontal gaps', () {
    expect(
        PdfKitText.cells(run('02-Mar-2026 Shop 100.00', [
          ('02-Mar-2026', 10, 50),
          ('Shop', 54, 70),
          ('100.00', 200, 230),
        ])),
        [
          ['02-Mar-2026 Shop', '100.00']
        ]);
    expect(PdfKitText.cells({'t': ' Total ', 'x0': 0, 'x1': 1, 'y0': 0, 'y1': 1}), [
      ['Total']
    ]);
  });
}
