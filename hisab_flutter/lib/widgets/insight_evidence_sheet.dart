/// "Show me why" for a card — mirrors InsightEvidenceSheet.swift.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../services/queries.dart';
import '../storage/database.dart';

void showInsightEvidence(
    BuildContext context, Insight insight, List<StoredTransaction> txns) {
  final wanted = insight.evidenceIDs.toSet();
  final rows = [
    for (final txn in txns)
      if (wanted.contains(txn.uuid)) txn
  ]..sort((a, b) => b.dateMs.compareTo(a.dateMs));

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(insight.headline,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(insight.detail,
                style: const TextStyle(color: Colors.black54)),
            const Divider(height: 28),
            if (insight.kind == InsightKind.committedSpend)
              for (final entry in insight.series)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.displayMerchant),
                  subtitle: Text('${Money.formatPaise(entry.medianPaise)} '
                      '${entry.cadence == Cadence.monthly ? 'per month' : 'per week'}'
                      ' · since ${YearMonth.fromDate(entry.firstSeen).displayName}'),
                )
            else
              for (final txn in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      txn.counterparty.isEmpty ? txn.narration : txn.counterparty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(istDayString(dateOf(txn))),
                  trailing: Text(Money.formatPaise(txn.amountPaise),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
          ],
        ),
      ),
    ),
  );
}
