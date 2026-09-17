import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../services/demo_data.dart';
import '../services/queries.dart';
import '../storage/database.dart';
import '../state.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return StreamBuilder<Snapshot>(
      initialData: state.latest,
      stream: state.snapshots,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.auto_awesome,
                          color: HisabTheme.sona),
                      title: const Text('Load demo data'),
                      subtitle: const Text(
                          'Three months of synthetic statements to explore every screen'),
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await DemoData.load(state.importService);
                        messenger.showSnackBar(const SnackBar(
                            content: Text('Demo data loaded')));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_forever,
                          color: HisabTheme.khataRed),
                      title: const Text('Erase all data'),
                      onTap: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Erase everything?'),
                            content: const Text(
                                'All imported statements, transactions, and rules will be removed from this device.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Erase',
                                      style: TextStyle(
                                          color: HisabTheme.khataRed))),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await DemoData.eraseAll(state.db);
                          await Queries.categoryRules(state.db, state.ruleset);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('Categorization rules',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Text('First match wins. Tap a rule to edit it.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              if (data != null)
                Card(
                  child: Column(
                    children: [
                      for (final rule in List.of(data.ruleRows)
                        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
                        ListTile(
                          dense: true,
                          title: Text(rule.pattern),
                          trailing: Text(rule.category,
                              style: const TextStyle(
                                  color: HisabTheme.khataRed)),
                          onTap: () => _editRule(context, rule),
                        ),
                      ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.add, color: HisabTheme.khataRed),
                        title: const Text('Add rule'),
                        onTap: () => _editRule(context, null),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Hisab keeps everything on this device.\nNo account · no network · open source (Apache-2.0)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editRule(
      BuildContext context, StoredCategoryRule? rule) async {
    final state = AppScope.of(context);
    final patternController = TextEditingController(text: rule?.pattern ?? '');
    final categoryController =
        TextEditingController(text: rule?.category ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(rule == null ? 'Add rule' : 'Edit rule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: patternController,
                decoration:
                    const InputDecoration(labelText: 'Pattern (contains)')),
            TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: 'Category')),
          ],
        ),
        actions: [
          if (rule != null)
            TextButton(
              onPressed: () async {
                await (state.db.delete(state.db.storedCategoryRules)
                      ..where((r) => r.id.equals(rule.id)))
                    .go();
                if (context.mounted) Navigator.pop(context, false);
              },
              child: const Text('Delete',
                  style: TextStyle(color: HisabTheme.khataRed)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final pattern = patternController.text.trim();
    final category = categoryController.text.trim();
    if (pattern.isEmpty || category.isEmpty) return;
    if (rule == null) {
      final rows = await state.db.select(state.db.storedCategoryRules).get();
      final order = rows.isEmpty
          ? 0
          : rows.map((r) => r.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
      await state.db.into(state.db.storedCategoryRules).insert(
          StoredCategoryRulesCompanion.insert(
              id: newId(),
              pattern: pattern,
              category: category,
              sortOrder: order));
    } else {
      await (state.db.update(state.db.storedCategoryRules)
            ..where((r) => r.id.equals(rule.id)))
          .write(StoredCategoryRulesCompanion(
              pattern: Value(pattern), category: Value(category)));
    }
  }
}
