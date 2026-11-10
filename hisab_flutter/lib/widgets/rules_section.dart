/// Settings' categorization rules: collapsed to a header by default; open, a
/// search over pattern and category, a category filter, and long-press
/// multi-select to recategorize or delete rules together.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../screens/settings_screen.dart';
import '../storage/database.dart';
import '../state.dart';
import 'txn_sheets.dart';

class RulesSection extends StatefulWidget {
  final List<StoredCategoryRule> rules;
  const RulesSection({super.key, required this.rules});

  @override
  State<RulesSection> createState() => _RulesSectionState();
}

class _RulesSectionState extends State<RulesSection> {
  bool _open = false;
  String _query = '';
  final _categories = <String>{};
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final all = List.of(widget.rules)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final categories = {for (final r in all) r.category}.toList()..sort();
    _categories.retainAll(categories);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final r in all)
        if ((_categories.isEmpty || _categories.contains(r.category)) &&
            (q.isEmpty ||
                r.pattern.toLowerCase().contains(q) ||
                r.category.toLowerCase().contains(q)))
          r
    ];
    _picked.retainAll({for (final r in all) r.id});
    final selecting = _picked.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const IconTile(Icons.rule),
            title: const Text('Categorization rules'),
            subtitle: Text('${all.length} rules',
                style: HisabType.caption.copyWith(color: c.textSecondary)),
            trailing: AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: HisabMotion.fast,
              child: const Icon(Icons.expand_more),
            ),
            onTap: () => setState(() {
              _open = !_open;
              if (!_open) _picked.clear();
            }),
          ),
          if (_open) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  HisabSpace.s16, 0, HisabSpace.s16, HisabSpace.s8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search patterns or categories',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HisabRadius.pill)),
                ),
              ),
            ),
            if (categories.length > 1)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: HisabSpace.s16),
                  children: [
                    for (final cat in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: HisabSpace.s8),
                        child: HisabFilterChip(
                          label: cat,
                          selected: _categories.contains(cat),
                          onSelected: (on) => setState(() => on
                              ? _categories.add(cat)
                              : _categories.remove(cat)),
                        ),
                      ),
                  ],
                ),
              ),
            if (selecting) _selectionBar(shown, categories),
            for (final rule in shown)
              ListTile(
                dense: true,
                selected: _picked.contains(rule.id),
                selectedTileColor: c.brand.withValues(alpha: 0.10),
                leading: selecting
                    ? Icon(
                        _picked.contains(rule.id)
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: c.brandText)
                    : null,
                title: Text(rule.pattern),
                trailing: StatusTag(rule.category, tone: HisabTone.brand),
                onTap: selecting
                    ? () => _toggle(rule.id)
                    : () => SettingsScreen.editRule(context, rule),
                onLongPress: () => _toggle(rule.id),
              ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(HisabSpace.s16),
                child: Text('No rule matches.',
                    style: HisabType.body.copyWith(color: c.textSecondary)),
              ),
            if (!selecting)
              ListTile(
                dense: true,
                leading: const IconTile(Icons.add),
                title: const Text('Add rule'),
                onTap: () => SettingsScreen.editRule(context, null),
              ),
          ],
        ],
      ),
    );
  }

  void _toggle(String id) => setState(
      () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));

  Widget _selectionBar(
      List<StoredCategoryRule> shown, List<String> categories) {
    final everything = shown.every((r) => _picked.contains(r.id));
    return Container(
      color: context.hisab.sunken,
      padding: const EdgeInsets.symmetric(horizontal: HisabSpace.s4),
      child: Row(children: [
        IconButton(
          tooltip: 'Done',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_picked.clear),
        ),
        Expanded(child: Text('${_picked.length} selected')),
        IconButton(
          tooltip: everything ? 'Select none' : 'Select all',
          icon: Icon(everything ? Icons.deselect : Icons.select_all),
          onPressed: () => setState(() => everything
              ? _picked.removeAll(shown.map((r) => r.id))
              : _picked.addAll(shown.map((r) => r.id))),
        ),
        IconButton(
          tooltip: 'Change category',
          icon: const Icon(Icons.sell_outlined),
          onPressed: () => _recategorize(categories),
        ),
        IconButton(
          tooltip: 'Delete',
          icon: Icon(Icons.delete_outline, color: context.hisab.spend),
          onPressed: _delete,
        ),
      ]),
    );
  }

  Future<void> _recategorize(List<String> categories) async {
    final db = AppScope.of(context).db;
    final option = await pickCategory(
        context,
        [
          for (final c in categories)
            if (!SettingsScreen.reservedCategories.contains(c)) c
        ],
        title: 'Category for ${_picked.length} rules');
    if (option == null) return;
    await (db.update(db.storedCategoryRules)
          ..where((r) => r.id.isIn(_picked.toList())))
        .write(StoredCategoryRulesCompanion(category: Value(option)));
    if (mounted) setState(_picked.clear);
  }

  Future<void> _delete() async {
    final db = AppScope.of(context).db;
    final count = _picked.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'rule' : 'rules'}?'),
        content: const Text(
            'Transactions they categorized go back to the remaining rules.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text('Delete', style: TextStyle(color: context.hisab.spend))),
        ],
      ),
    );
    if (confirmed != true) return;
    await (db.delete(db.storedCategoryRules)
          ..where((r) => r.id.isIn(_picked.toList())))
        .go();
    if (mounted) setState(_picked.clear);
  }
}
