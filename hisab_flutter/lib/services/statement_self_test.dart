/// `--dart-define=STATEMENT_SELFTEST=true`: the on-device half of
/// proposed_mapping_test.dart, for a phone, where the Dart tests can't reach
/// Gemini Nano. Mirrors StatementSelfTest.swift; read-only — nothing touches
/// the database. Prints one STATEMENT-SELFTEST line (adb logcat).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hisab_core/hisab_core.dart';

import 'gemini_nano_column_reader.dart';

class StatementSelfTest {
  static const _csv = '''XYZ BANK LTD
Date,Details,Ref,Amount,Balance
Opening Balance,,,,1000.00
01/04/2026,POS COFFEE,R1,100.00,900.00
02/04/2026,SALARY ACME,R2,50.00,950.00
03/04/2026,UPI GROCER,R3,200.00,750.00
Closing Balance,,,350.00,750.00''';

  static Future<String> run() async {
    if (!await GeminiNanoColumnReader.isAvailable()) {
      return 'STATEMENT-SELFTEST model unavailable';
    }
    final table = NormalizedTable.from(data: utf8.encode(_csv), filename: 'selftest.csv')!;
    final watch = Stopwatch()..start();
    final read = await ProposedMapping.read(table, const GeminiNanoColumnReader());
    final seconds = (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    if (read == null) return 'STATEMENT-SELFTEST refused ($seconds s)';
    final right = listEquals(read.transactions.map((t) => t.direction).toList(),
            [Direction.debit, Direction.credit, Direction.debit]) &&
        listEquals(read.transactions.map((t) => t.amountPaise).toList(), [10000, 5000, 20000]);
    return 'STATEMENT-SELFTEST ${right ? 'read' : 'MISREAD'} ${read.transactions.length} rows ($seconds s)';
  }
}
