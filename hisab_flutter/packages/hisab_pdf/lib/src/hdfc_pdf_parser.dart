/// HDFC "Statement of account" PDFs, reconstructed geometrically from word
/// bounds (the columns interleave in the raw text stream). Columns are
/// anchored at the header words' x positions; a row starts where the Date
/// column holds dd/MM/yy; continuation lines live wholly in the Narration
/// column. Table semantics shared with TXT/XLS via HdfcStatementTable, so all
/// three renditions produce identical identities.
library;

import 'package:hisab_core/hisab_core.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'pdf_text.dart';

class HdfcPdfParser implements StatementParser {
  @override
  Source get source => Source.hdfc;

  const HdfcPdfParser();

  static final _dateRegex = RegExp(r'^\d{2}/\d{2}/\d{2}$');

  @override
  bool canParse(List<int> data, String filename) {
    if (PdfText.isLocked(data, null)) {
      return filename.toLowerCase().contains('acct statement');
    }
    final pages = PdfText.pageTexts(data, null);
    if (pages == null || pages.isEmpty) return false;
    return pages.first.contains('Statement of account') &&
        pages.first.contains('Chq./Ref.No.');
  }

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    PdfDocument? doc;
    try {
      doc = PdfText.open(data, password);
    } catch (_) {
      throw const PasswordRequiredException();
    }
    if (doc == null) throw const UnrecognizedFormatException();
    try {
      return _parse(doc);
    } finally {
      doc.dispose();
    }
  }

  ParsedDocument _parse(PdfDocument doc) {
    // Column anchors from the header line (page 1; later pages reuse them).
    List<double>? anchors; // date, narration, ref, valueDt, withdrawal, deposit, balance
    final rows = <HdfcRow>[];
    HdfcRow? open;
    final allText = StringBuffer();
    var done = false;

    for (var pageIndex = 0; pageIndex < doc.pages.count && !done; pageIndex++) {
      final lines = PdfText.pageLines(doc, pageIndex);
      for (final line in lines) {
        allText.writeln(line.text);
        if (line.text.contains('STATEMENT SUMMARY')) {
          done = true;
          break;
        }
        if (anchors == null) {
          if (line.text.contains('Narration') &&
              line.text.contains('Withdrawal')) {
            PdfWordBox? headerWord(String prefix) {
              for (final word in line.words) {
                if (word.text.startsWith(prefix)) return word;
              }
              return null;
            }

            final headers = [
              headerWord('Date'), headerWord('Narration'), headerWord('Chq.'),
              headerWord('Value'), headerWord('Withdrawal'),
              headerWord('Deposit'), headerWord('Closing'),
            ];
            if (!headers.contains(null)) {
              // Data cells are left-aligned text or numbers right-aligned
              // against the NEXT column's header, so each boundary is the
              // following header's left edge (with slack). The narrow Date
              // column instead ends just past its own header.
              final date = headers[0]!;
              anchors = [
                date.x + date.width + 8,          // date | narration
                headers[2]!.x - 4,                // narration | ref
                headers[3]!.x - 4,                // ref | value dt
                headers[4]!.x - 4,                // value dt | withdrawal
                headers[5]!.x - 4,                // withdrawal | deposit
                headers[6]!.x - 4,                // deposit | closing balance
              ];
            }
          }
          continue;
        }

        final boundaries = anchors;
        int columnOf(PdfWordBox word) {
          final cx = word.x + word.width / 2;
          for (var i = 0; i < boundaries.length; i++) {
            if (cx < boundaries[i]) return i;
          }
          return boundaries.length;
        }

        // Bucket the line's words into columns.
        final cells = List.generate(7, (_) => <String>[]);
        for (final word in line.words) {
          cells[columnOf(word)].add(word.text);
        }
        String cell(int i) => cells[i].join(' ').trim();

        final date = cell(0);
        if (_dateRegex.hasMatch(date)) {
          if (open != null) rows.add(open);
          String? nonEmpty(String s) => s.isEmpty ? null : s;
          open = HdfcRow(
            dateText: date,
            narration: cell(1),
            refText: nonEmpty(cell(2)),
            withdrawalText: nonEmpty(cell(4)),
            depositText: nonEmpty(cell(5)),
            balanceText: nonEmpty(cell(6)),
          );
          continue;
        }
        // Continuation: every word inside the narration column, an open row.
        if (open != null &&
            cell(1).isNotEmpty &&
            cell(0).isEmpty &&
            cell(2).isEmpty &&
            cell(3).isEmpty &&
            cell(4).isEmpty &&
            cell(5).isEmpty &&
            cell(6).isEmpty) {
          // Narration is display-only for HDFC (identity comes from the ref
          // column or the balance-keyed synthetic), so wrap spacing is cosmetic.
          open.narration += ' ${cell(1)}';
        }
      }
    }
    if (open != null) rows.add(open);
    if (anchors == null) throw const UnrecognizedFormatException();

    return HdfcStatementTable.parse(
      rows: rows,
      openingBalancePaise: null,
      period: HdfcStatementTable.periodIn(allText.toString()),
    );
  }
}
