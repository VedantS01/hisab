/// Projections and DB helpers, mirroring Hisab/Services/Queries.swift.
/// Pure list-based projections feed the widgets; DB variants serve the
/// import pipeline.
library;

import 'dart:math';

import 'package:hisab_core/hisab_core.dart';

import '../storage/database.dart';

String newId() {
  final random = Random.secure();
  final hex = List.generate(16, (_) => random.nextInt(16).toRadixString(16));
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${hex.join()}';
}

Direction directionOf(StoredTransaction txn) =>
    txn.direction == 'credit' ? Direction.credit : Direction.debit;

Source sourceOf(StoredTransaction txn) => Source(txn.sourceRaw);

DateTime dateOf(StoredTransaction txn) =>
    DateTime.fromMillisecondsSinceEpoch(txn.dateMs, isUtc: true);

class Queries {
  static List<CategoryRule> rules(List<StoredCategoryRule> rows) {
    final sorted = List.of(rows)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [
      for (final row in sorted)
        CategoryRule(id: row.id, pattern: row.pattern, category: row.category)
    ];
  }

  static Set<String> matchedBankUuids(List<StoredMatche> matches) =>
      matches.map((m) => m.bankUuid).toSet();

  static Set<String> selfTransferUuids(List<StoredTransaction> txns) {
    final bank = [
      for (final txn in txns)
        if (sourceOf(txn).kind == SourceKind.bank)
          BankTxn(
              ReconTxn(
                  id: txn.uuid,
                  date: dateOf(txn),
                  amountPaise: txn.amountPaise,
                  direction: directionOf(txn),
                  reference: txn.reference),
              sourceOf(txn))
    ];
    return SelfTransfers.detect(bank);
  }

  /// Matched bank rows are reconciliation evidence — hidden from history.
  static List<StoredTransaction> visible(
      List<StoredTransaction> txns, List<StoredMatche> matches) {
    final matched = matchedBankUuids(matches);
    return [
      for (final txn in txns)
        if (sourceOf(txn).kind != SourceKind.bank ||
            !matched.contains(txn.uuid))
          txn
    ];
  }

  /// Display/analytics category. Bank-only rows fall back to Miscellaneous;
  /// self transfers are labeled as such.
  static String effectiveCategory(StoredTransaction txn,
      List<CategoryRule> ruleList, Set<String> selfTransfers) {
    if (selfTransfers.contains(txn.uuid)) return Categorizer.selfTransfer;
    final override = txn.categoryOverride;
    if (override != null) return override;
    final auto = Categorizer.category(
        '${txn.counterparty} ${txn.narration}', ruleList);
    if (auto == Categorizer.uncategorized &&
        sourceOf(txn).kind == SourceKind.bank) {
      return Categorizer.miscellaneous;
    }
    return auto;
  }

  static List<AnalyticsTxn> analytics(List<StoredTransaction> txns,
      List<StoredMatche> matches, List<CategoryRule> ruleList) {
    final selfTransfers = selfTransferUuids(txns);
    return [
      for (final txn in visible(txns, matches))
        if (!selfTransfers.contains(txn.uuid))
          AnalyticsTxn(
            month: YearMonth.fromDate(dateOf(txn)),
            amountPaise: txn.amountPaise,
            direction: directionOf(txn),
            category: effectiveCategory(txn, ruleList, selfTransfers),
            merchant: txn.counterparty,
            sourceKind: sourceOf(txn).kind,
          )
    ];
  }

  static CoverageGrid grid(
      List<StoredDocument> documents, List<PinnedMonth> pins) {
    return CoverageGrid.derive(
      documents: [
        for (final doc in documents)
          DocumentSummary(
              id: doc.id,
              source: Source(doc.sourceRaw),
              period: DatePeriod(
                  DateTime.fromMillisecondsSinceEpoch(doc.periodStartMs,
                      isUtc: true),
                  DateTime.fromMillisecondsSinceEpoch(doc.periodEndMs,
                      isUtc: true)))
      ],
      pinnedMonths: {
        for (final pin in pins) _month(pin.monthKey)
      },
    );
  }

  static YearMonth _month(String key) {
    final parts = key.split('-');
    return YearMonth(int.parse(parts[0]), int.parse(parts[1]));
  }

  static (List<ReconTxn>, List<ReconTxn>) reconProjection(
      List<StoredTransaction> txns, YearMonth month) {
    List<ReconTxn> projected(SourceKind kind) => [
          for (final txn in txns)
            if (sourceOf(txn).kind == kind &&
                YearMonth.fromDate(dateOf(txn)) == month)
              ReconTxn(
                  id: txn.uuid,
                  date: dateOf(txn),
                  amountPaise: txn.amountPaise,
                  direction: directionOf(txn),
                  reference: txn.reference)
        ];
    return (projected(SourceKind.paymentApp), projected(SourceKind.bank));
  }

  /// Projection feeding SuggestionEngine.
  static List<SpendRecord> suggestionRecords(List<StoredTransaction> txns,
      List<StoredMatche> matches, List<CategoryRule> ruleList) {
    final selfTransfers = selfTransferUuids(txns);
    return [
      for (final txn in visible(txns, matches))
        SpendRecord(
          merchant: txn.counterparty.isEmpty ? txn.narration : txn.counterparty,
          amountPaise: txn.amountPaise,
          date: dateOf(txn),
          direction: directionOf(txn),
          effectiveCategory: effectiveCategory(txn, ruleList, selfTransfers),
        )
    ];
  }

  // ---- DB variants

  /// Additive seeding: any ruleset pattern the user doesn't already have is
  /// inserted; existing rules — including edited ones — are never touched.
  static Future<List<CategoryRule>> categoryRules(
      AppDatabase db, Ruleset ruleset) async {
    var stored = await db.select(db.storedCategoryRules).get();
    final existing = {for (final r in stored) r.pattern.toLowerCase()};
    final missing = [
      for (final rule in ruleset.rules)
        if (!existing.contains(rule.pattern.toLowerCase())) rule
    ];
    if (missing.isNotEmpty) {
      var order = stored.isEmpty
          ? 0
          : stored.map((r) => r.sortOrder).reduce(max) + 1;
      await db.batch((batch) {
        for (final rule in missing) {
          batch.insert(
              db.storedCategoryRules,
              StoredCategoryRulesCompanion.insert(
                  id: newId(),
                  pattern: rule.pattern,
                  category: rule.category,
                  sortOrder: order++));
        }
      });
      stored = await db.select(db.storedCategoryRules).get();
    }
    return rules(stored);
  }

  static Future<void> recomputeMatches(AppDatabase db, YearMonth month) async {
    final txns = await db.select(db.storedTransactions).get();
    final (app, bank) = reconProjection(txns, month);
    final result = Reconciler.reconcile(app: app, bank: bank);
    final key = month.toString();
    await (db.delete(db.storedMatches)
          ..where((m) => m.monthKey.equals(key)))
        .go();
    await db.batch((batch) {
      for (final match in result.matches) {
        batch.insert(
            db.storedMatches,
            StoredMatchesCompanion.insert(
                id: newId(),
                monthKey: key,
                appUuid: match.appID,
                bankUuid: match.bankID,
                tier: match.tier.name));
      }
    });
  }
}
