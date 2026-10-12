// The real bank PDFs in samples/ read through the generic path alone (no
// dedicated parser, no spec), checked against what the dedicated parsers read
// from the same statement. Port of GenericPDFSamplesTests.swift. Local-only:
// skipped when samples/ is absent.
@Tags(['samples'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:hisab_pdf/hisab_pdf.dart';

const samplesDir = '/Users/vedant/personal/hisab/samples';

String key(ParsedTransaction t) =>
    '${t.date.toIso8601String()} ${t.amountPaise} ${t.direction.name}';

void main() {
  final available = Directory(samplesDir).existsSync();
  setUpAll(installPdfHooks);
  const generic = ImportResolver(registry: ParserRegistry([]), specs: []);

  test('HDFC PDF: the generic path reads what HdfcPdfParser reads', () {
    if (!available) return markTestSkipped('samples not present');
    final data = File('$samplesDir/hdfc/Acct Statement_3293_23062026_13.38.47.pdf').readAsBytesSync();
    const password = '135244908';
    final expected = const HdfcPdfParser().parse(data, password: password);
    final resolution = generic.resolve(data: data, filename: 'statement.pdf', password: password);
    expect(resolution, isA<ResolutionParsed>());
    final doc = (resolution as ResolutionParsed).document;
    expect(doc.transactions.map(key).toList()..sort(), expected.transactions.map(key).toList()..sort());
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('IDFC PDF stays unread: its narrations lose glyphs, its XLSX reads exactly', () {
    if (!available) return markTestSkipped('samples not present');
    final pdf = File('$samplesDir/idfc/IDFCFIRSTBankstatement_10061308816.pdf').readAsBytesSync();
    // The layout reader would close the chain on this PDF — every date, amount
    // and direction matches the XLSX — but "UPI/DR/606435614627" comes out as
    // "UPI/D/60643614627", so it must not import from here.
    expect(generic.resolve(data: pdf, filename: 'statement.pdf'), isNot(isA<ResolutionParsed>()));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
