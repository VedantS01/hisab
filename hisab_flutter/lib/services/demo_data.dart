/// Demo data: three synthetic statements (bundled assets) imported through
/// the normal pipeline, mirroring Hisab/Services/DemoData.swift.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:hisab_core/hisab_core.dart';

import '../storage/database.dart';
import 'import_service.dart';

class DemoData {
  static const _files = {
    'assets/demo/demo-gpay.csv': Source.gpay,
    'assets/demo/demo-hdfc.csv': Source.hdfc,
    'assets/demo/demo-idfc.csv': Source.idfc,
  };

  static Future<void> load(ImportService service) async {
    for (final entry in _files.entries) {
      final text = await rootBundle.loadString(entry.key);
      final parser = SyntheticCsvParser(source: entry.value);
      final parsed = parser.parse(utf8.encode(text));
      await service.insertParsedDocument(
        parsed: parsed,
        source: entry.value,
        filename: entry.key.split('/').last,
        fileHash: 'demo-${entry.value.rawValue}',
      );
    }
  }

  static Future<void> eraseAll(AppDatabase db) async {
    await db.delete(db.storedMatches).go();
    await db.delete(db.storedTransactions).go();
    await db.delete(db.storedDocuments).go();
    await db.delete(db.storedCategoryRules).go();
    await db.delete(db.pinnedMonths).go();
  }
}
