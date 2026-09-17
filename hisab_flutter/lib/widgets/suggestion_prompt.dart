/// One-per-day rule suggestion, mirroring SuggestionPrompt.swift. Accept
/// creates an ordinary editable rule; "don't ask" mutes the merchant forever.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/queries.dart';
import '../storage/database.dart';
import '../state.dart';
import '../theme.dart';

Future<void> showSuggestionPrompt(
    BuildContext context, RuleSuggestion suggestion) async {
  final state = AppScope.of(context);
  final ruleRows = await state.db.select(state.db.storedCategoryRules).get();
  final categories = {for (final r in ruleRows) r.category}.toList()..sort();
  final controller = TextEditingController();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 40, color: HisabTheme.sona),
            const SizedBox(height: 12),
            Text(
              "You've spent ${Money.formatPaise(suggestion.totalPaise)} on ${suggestion.displayMerchant} across ${suggestion.count} payments.",
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Text('Categorize these?',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final category in categories.take(8))
                  ActionChip(
                    label: Text(category),
                    onPressed: () => controller.text = category,
                  ),
              ],
            ),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final muted =
                        prefs.getStringList('suggestion.muted') ?? [];
                    if (!muted.contains(suggestion.merchantPattern)) {
                      muted.add(suggestion.merchantPattern);
                      await prefs.setStringList('suggestion.muted', muted);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("Don't ask about this",
                      style: TextStyle(color: Colors.black54)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: HisabTheme.khataRed),
                  onPressed: () async {
                    final category = controller.text.trim();
                    if (category.isEmpty) return;
                    final rows = await state.db
                        .select(state.db.storedCategoryRules)
                        .get();
                    final order = rows.isEmpty
                        ? 0
                        : rows
                                .map((r) => r.sortOrder)
                                .reduce((a, b) => a > b ? a : b) +
                            1;
                    await state.db.into(state.db.storedCategoryRules).insert(
                        StoredCategoryRulesCompanion.insert(
                            id: newId(),
                            pattern: suggestion.merchantPattern,
                            category: category,
                            sortOrder: order));
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save rule'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
