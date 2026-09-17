/// SQLite storage via drift, mirroring the SwiftData models on iOS.
/// The UNIQUE index on contentHash is the dedup backstop.
library;

import 'package:drift/drift.dart';

part 'database.g.dart';

class StoredDocuments extends Table {
  TextColumn get id => text()();
  TextColumn get sourceRaw => text()();
  TextColumn get filename => text()();
  TextColumn get fileSha256 => text()();
  IntColumn get periodStartMs => integer()();
  IntColumn get periodEndMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class StoredTransactions extends Table {
  TextColumn get uuid => text()();
  TextColumn get contentHash => text().unique()();
  TextColumn get sourceRaw => text()();
  IntColumn get dateMs => integer()();
  IntColumn get amountPaise => integer()();
  TextColumn get direction => text()(); // debit | credit
  TextColumn get counterparty => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get narration => text()();
  TextColumn get categoryOverride => text().nullable()();
  TextColumn get documentId => text()();

  @override
  Set<Column> get primaryKey => {uuid};
}

class StoredCategoryRules extends Table {
  TextColumn get id => text()();
  TextColumn get pattern => text()();
  TextColumn get category => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class StoredMatches extends Table {
  TextColumn get id => text()();
  TextColumn get monthKey => text()(); // "2026-04"
  TextColumn get appUuid => text()();
  TextColumn get bankUuid => text()();
  TextColumn get tier => text()(); // reference | amountDate

  @override
  Set<Column> get primaryKey => {id};
}

class PinnedMonths extends Table {
  TextColumn get monthKey => text()();

  @override
  Set<Column> get primaryKey => {monthKey};
}

@DriftDatabase(tables: [
  StoredDocuments,
  StoredTransactions,
  StoredCategoryRules,
  StoredMatches,
  PinnedMonths,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
