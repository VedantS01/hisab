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

/// A bank/UPI alert captured but not yet admitted to the ledger. Mirrors
/// StoredPendingMemo in Hisab/Models/StoredModels.swift field-for-field.
/// The raw alert text is deliberately absent: only parsed fields persist.
class StoredPendingMemos extends Table {
  TextColumn get captureHash => text()();
  IntColumn get amountPaise => integer()();
  TextColumn get direction => text()(); // debit | credit
  TextColumn get payee => text()();
  TextColumn get payeeNormalized => text()();
  TextColumn get vpa => text().nullable()();
  TextColumn get accountTail => text().nullable()();
  IntColumn get dateMs => integer()();
  IntColumn get capturedAtMs => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get assignedCategory => text().nullable()();
  TextColumn get mergedTxnUuid => text().nullable()();
  IntColumn get notifiedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {captureHash};
}

@DriftDatabase(tables: [
  StoredDocuments,
  StoredTransactions,
  StoredCategoryRules,
  StoredMatches,
  PinnedMonths,
  StoredPendingMemos,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  /// There was no MigrationStrategy before v2, so every install in the field
  /// carries a v1 database with no pending-memo table. Without this, opening
  /// one throws `no such table` on the first memo query — and a fresh install
  /// (created at v2 by `onCreate`) would never show it.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(storedPendingMemos);
          }
        },
      );
}
