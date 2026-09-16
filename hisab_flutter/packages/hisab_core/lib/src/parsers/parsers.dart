/// Parser registry. PDF parsers join in the PDF module (Task F6).
library;

import '../domain.dart';
import 'hdfc_txt_parser.dart';
import 'hdfc_xls_parser.dart';
import 'idfc_xlsx_parser.dart';
import 'paytm_xlsx_parser.dart';
import 'synthetic_csv_parser.dart';

export 'hdfc_common.dart';
export 'hdfc_txt_parser.dart';
export 'hdfc_xls_parser.dart';
export 'idfc_common.dart';
export 'idfc_xlsx_parser.dart';
export 'paytm_xlsx_parser.dart';
export 'synthetic_csv_parser.dart';

/// The live registry, mirroring ParserRegistry.live. Callers append the PDF
/// parsers (which carry the Syncfusion dependency) before use in the app.
ParserRegistry liveRegistry({List<StatementParser> extra = const []}) =>
    ParserRegistry([
      const SyntheticCsvParser(),
      const PaytmXlsxParser(),
      const IdfcXlsxParser(),
      const HdfcTxtParser(),
      const HdfcXlsParser(),
      ...extra,
    ]);
