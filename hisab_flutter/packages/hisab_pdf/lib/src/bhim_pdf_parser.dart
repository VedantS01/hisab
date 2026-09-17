/// BHIM "Transaction History" PDF exports — one line per transaction, same
/// grammar under Syncfusion as under PDFKit. Port of BHIMParser.swift.
/// Only SUCCESS rows are recorded.
library;

import 'package:hisab_core/hisab_core.dart';

import 'pdf_text.dart';

class BhimPdfParser implements StatementParser {
  @override
  Source get source => Source.bhim;

  const BhimPdfParser();

  static final _rowRegex = RegExp(
      r'^(\d{2}/\d{2}/\d{4}) (\d{2}:\d{2}:\d{2}) (.+?) (\S+) (PAY|COLLECT) ([\d,]+\.\d{1,2}) (DR|CR) ([A-Z]+)$');
  static final _periodRegex = RegExp(
      r'Transaction History from (\d{2}/\d{2}/\d{4}) to (\d{2}/\d{2}/\d{4})');
  static final _partyRegex = RegExp(r'(\S+)\(([^)]*)\)');

  @override
  bool canParse(List<int> data, String filename) {
    if (PdfText.isLocked(data, null)) {
      final name = filename.toLowerCase();
      return name.contains('bhim') || name.contains('transaction_statement');
    }
    final pages = PdfText.pageTexts(data, null);
    if (pages == null || pages.isEmpty) return false;
    return pages.first.contains('Transaction History') &&
        pages.first.contains('Pay/Collect');
  }

  static DateTime? _dateTime(String d, String t) {
    final dp = d.split('/');
    final tp = t.split(':');
    if (dp.length != 3 || tp.length != 3) return null;
    return DateTime.utc(int.parse(dp[2]), int.parse(dp[1]), int.parse(dp[0]),
            int.parse(tp[0]), int.parse(tp[1]), int.parse(tp[2]))
        .subtract(istOffset);
  }

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    List<String>? pages;
    try {
      pages = PdfText.pageTexts(data, password);
    } catch (_) {
      throw const PasswordRequiredException();
    }
    if (pages == null) throw const UnrecognizedFormatException();
    final text = pages.join('\n');

    DatePeriod? declaredPeriod;
    final periodMatch = _periodRegex.firstMatch(text);
    if (periodMatch != null) {
      final start = _dateTime(periodMatch.group(1)!, '00:00:00');
      final end = _dateTime(periodMatch.group(2)!, '23:59:59');
      if (start != null && end != null) {
        declaredPeriod = DatePeriod(start, end);
      }
    }

    final transactions = <ParsedTransaction>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      final match = _rowRegex.firstMatch(line);
      if (match == null) continue;
      if (match.group(8) != 'SUCCESS') continue;
      final date = _dateTime(match.group(1)!, match.group(2)!);
      final signed = Money.signedPaise(match.group(6)!);
      if (date == null || signed == null) {
        throw MalformedRowException(0, line);
      }
      final direction =
          match.group(7) == 'DR' ? Direction.debit : Direction.credit;

      // Middle: bank name, masked account, then sender(name) receiver(name).
      final middle = match.group(3)!;
      final parties = _partyRegex.allMatches(middle).toList();
      String counterparty;
      if (parties.length >= 2) {
        final party =
            direction == Direction.debit ? parties[1] : parties[0];
        counterparty = (party.group(2) ?? '').trim();
        if (counterparty.isEmpty) counterparty = party.group(1)!;
      } else {
        counterparty =
            middle.length > 40 ? middle.substring(middle.length - 40) : middle;
      }

      transactions.add(ParsedTransaction(
        date: date,
        amountPaise: signed.abs(),
        direction: direction,
        counterparty: counterparty,
        reference: match.group(4),
        narration: '$middle / ${match.group(5)} / ${match.group(8)}',
      ));
    }
    if (transactions.isEmpty) throw const EmptyDocumentException();
    return ParsedDocument(
        source: Source.bhim,
        declaredPeriod: declaredPeriod,
        transactions: transactions);
  }
}
