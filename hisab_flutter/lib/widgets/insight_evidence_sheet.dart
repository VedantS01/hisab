/// "Show me why" for a card — mirrors InsightEvidenceSheet.swift, down to
/// the "Why this" title, the Close action and the section headers.
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
  final committed = insight.kind == InsightKind.committedSpend;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  Text(insight.headline,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(insight.detail,
                      style: const TextStyle(color: Colors.black54)),
                  const Divider(height: 28),
                  _sectionHeader(
                      committed ? 'Recurring payments' : 'Transactions'),
                  if (committed)
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
                            txn.counterparty.isEmpty
                                ? txn.narration
                                : txn.counterparty,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(istDayLabel(dateOf(txn))),
                        trailing: Text(Money.formatPaise(txn.amountPaise),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _header(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          const Expanded(
            child: Text('Why this',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          // Balances the Close button so the title stays centred.
          const SizedBox(width: 56),
        ],
      ),
    );

Widget _sectionHeader(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: Colors.black54)),
    );
