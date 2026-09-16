/// HDFC delimited .txt export — fixed-width columns whose extents come from
/// the dash ruler under the header. Port of HDFCTXTParser.swift.
library;

import 'dart:convert';

import '../domain.dart';
import 'hdfc_common.dart';

class HdfcTxtParser implements StatementParser {
  @override
  Source get source => Source.hdfc;

  const HdfcTxtParser();

  static String? _decode(List<int> data) {
    try {
      return utf8.decode(data);
    } on FormatException {
      return latin1.decode(data, allowInvalid: true);
    }
  }

  @override
  bool canParse(List<int> data, String filename) {
    if (data.length >= 4 &&
        String.fromCharCodes(data.take(4)) == '%PDF') {
      return false;
    }
    if (data.length >= 2 && data[0] == 0x50 && data[1] == 0x4B) return false;
    final text = _decode(data);
    if (text == null) return false;
    return text.contains('HDFC BANK Ltd.') &&
        text.contains('Statement of accounts');
  }

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    final text = _decode(data);
    if (text == null) throw const UnrecognizedFormatException();
    final lines = text.split(RegExp(r'\r?\n'));

    final ruler = lines.where(isRuler).firstOrNull;
    if (ruler == null) throw const UnrecognizedFormatException();
    final columns = dashRanges(ruler);
    if (columns.length != 7) throw const UnrecognizedFormatException();

    String cell(String line, int index) {
      final range = columns[index];
      if (line.length <= range.$1) return '';
      // A column may bleed a couple of characters past its ruler on the right.
      final upper = index + 1 < columns.length
          ? columns[index + 1].$1 - 1
          : line.length;
      final clamped = upper < line.length ? upper : line.length;
      if (clamped <= range.$1) return '';
      return line.substring(range.$1, clamped).trim();
    }

    final rows = <HdfcRow>[];
    HdfcRow? open;
    final dateRegex = RegExp(r'^\d{2}/\d{2}/\d{2}$');

    for (final rawLine in lines) {
      if (rawLine.contains('STATEMENT SUMMARY')) break;
      if (isFence(rawLine) || isRuler(rawLine)) {
        if (open != null) {
          rows.add(open);
          open = null;
        }
        continue;
      }
      final date = cell(rawLine, 0);
      if (dateRegex.hasMatch(date)) {
        if (open != null) rows.add(open);
        String? nonEmpty(String s) => s.isEmpty ? null : s;
        open = HdfcRow(
          dateText: date,
          narration: cell(rawLine, 1),
          refText: nonEmpty(cell(rawLine, 2)),
          withdrawalText: nonEmpty(cell(rawLine, 4)),
          depositText: nonEmpty(cell(rawLine, 5)),
          balanceText: nonEmpty(cell(rawLine, 6)),
        );
        continue;
      }
      // Narration continuation: date and every non-narration cell blank.
      if (open != null && date.isEmpty) {
        final continuation = cell(rawLine, 1);
        if (continuation.isNotEmpty &&
            cell(rawLine, 2).isEmpty &&
            cell(rawLine, 4).isEmpty &&
            cell(rawLine, 5).isEmpty &&
            cell(rawLine, 6).isEmpty) {
          open.narration += ' $continuation';
        }
      }
    }
    if (open != null) rows.add(open);

    return HdfcStatementTable.parse(
      rows: rows,
      openingBalancePaise: HdfcStatementTable.openingBalanceIn(text),
      period: HdfcStatementTable.periodIn(text),
    );
  }

  static bool isRuler(String line) {
    final trimmed = line.trim();
    return trimmed.length > 20 &&
        trimmed.split('').every((c) => c == '-' || c == ' ') &&
        trimmed.contains('--');
  }

  /// Dash runs as (start, end) offsets.
  static List<(int, int)> dashRanges(String ruler) {
    final ranges = <(int, int)>[];
    int? start;
    for (var index = 0; index < ruler.length; index++) {
      if (ruler[index] == '-') {
        start ??= index;
      } else if (start != null) {
        ranges.add((start, index));
        start = null;
      }
    }
    if (start != null) ranges.add((start, ruler.length));
    return ranges;
  }

  static bool isFence(String line) =>
      line.contains('HDFC BANK Ltd') ||
      line.contains('Page No .:') ||
      line.contains('Statement of accounts') ||
      line.contains('Statement From') ||
      line.contains('Chq./Ref.No.') ||
      line.contains('Account Branch') ||
      line.contains('Registered Office') ||
      line.contains('GSTIN') ||
      line.contains('End Of Statement');
}
