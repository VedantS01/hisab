import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart'
    show Categorizer, Suppressions, istDayLabel;

import '../services/capture_notifier.dart';
import '../services/agent_insights.dart';
import '../services/capture_prefs.dart';
import '../services/demo_data.dart';
import '../services/legacy_migration.dart';
import '../services/insight_store.dart';
import '../services/queries.dart';
import '../storage/database.dart';
import '../state.dart';
import '../design/design.dart';
import '../widgets/ai_credits_card.dart';
import '../widgets/rules_section.dart';
import 'capture_setup_screen.dart';

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
              const CaptureSettingsCard(),
              const SizedBox(height: 8),
              if (data != null) RulesSection(rules: data.ruleRows),
              const SizedBox(height: 8),
              const AiCreditsCard(),
              const SizedBox(height: 24),
              const _DangerZone(),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Your ledger stays on this device. AI features send only what you ask '
                  'about — pasted text, or a month\'s totals and merchant names — to '
                  'Hisab\'s gateway and its model provider; statements are read on the phone.\n'
                  'No account · no tracking · open source (Apache-2.0)',
                  textAlign: TextAlign.center,
                  style: HisabType.caption
                      .copyWith(color: context.hisab.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Names Hisab assigns on its own, which a rule may therefore not hand out.
  /// Twin of `RuleEditorSheet.reservedCategories` in `SettingsView.swift`.
  ///
  /// Two of them mean "nothing claimed this row" and the third is decided by
  /// reconciliation before any rule is consulted, so a rule pointing at one
  /// either says nothing or cannot take effect. `Self Transfer` is the one
  /// that actively misleads here: [Queries.analytics] excludes self transfers
  /// by membership in the reconciliation-derived set, never by the label, so a
  /// rule handing out that NAME would make matching rows DISPLAY "Self
  /// Transfer" while every spending total stayed exactly as it was — the user
  /// believing they had taken those payments out of their spending.
  ///
  /// `NeedsReview`'s and the notification's category lists never contained
  /// these three ([CategoryRanker] excludes them), so this field is the last
  /// door.
  static const reservedCategories = [
    Categorizer.uncategorized,
    Categorizer.miscellaneous,
    Categorizer.selfTransfer,
  ];

  /// Why Save is disabled, or null when it is not. Pure, so the same sentence
  /// the dialog shows is the one a test can assert.
  @visibleForTesting
  static String? ruleValidationMessage(String pattern, String category) {
    final trimmedPattern = pattern.trim();
    final trimmedCategory = category.trim();
    if (trimmedPattern.isEmpty) {
      // Trimmed, not just `isEmpty`: a single space passes `isEmpty` and
      // `CategoryMatcher` finds " " inside very nearly every narration — one
      // rule, every transaction.
      return 'Enter some text to match. A blank pattern would match every '
          'transaction.';
    }
    if (trimmedCategory.isEmpty) return 'Enter a category name.';
    for (final reserved in reservedCategories) {
      if (reserved.toLowerCase() == trimmedCategory.toLowerCase()) {
        return '“$reserved” is a name Hisab assigns on its own — choose a '
            'category of your own.';
      }
    }
    return null;
  }

  static Future<void> editRule(
      BuildContext context, StoredCategoryRule? rule) async {
    final state = AppScope.of(context);
    final patternController = TextEditingController(text: rule?.pattern ?? '');
    final categoryController =
        TextEditingController(text: rule?.category ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final message = ruleValidationMessage(
              patternController.text, categoryController.text);
          return AlertDialog(
            title: Text(rule == null ? 'Add rule' : 'Edit rule'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: patternController,
                    onChanged: (_) => setDialogState(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Pattern (contains)')),
                TextField(
                    controller: categoryController,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(labelText: 'Category')),
                // Held back until the user has typed something: an editor
                // that opens already complaining is scolding them for not
                // having started.
                if (message != null &&
                    (patternController.text.isNotEmpty ||
                        categoryController.text.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message,
                        key: const Key('rule-editor-validation'),
                        style: HisabType.caption
                            .copyWith(color: context.hisab.spend)),
                  ),
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
                  child: Text('Delete',
                      style: TextStyle(color: context.hisab.spend)),
                ),
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  // Disabled, not silently ignored: a Save button that
                  // dismisses the editor and stores nothing is the worst of
                  // both.
                  onPressed: message == null
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    final pattern = patternController.text.trim();
    final category = categoryController.text.trim();
    // The dialog disables Save while this is non-null; re-checked here
    // because the dialog is not the only thing that decides what is stored.
    if (ruleValidationMessage(pattern, category) != null) return;
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

/// Capture in Settings: the toggle, what capture last managed to read, and the
/// way through to the setup screen.
///
/// The toggle is duplicated here and on [CaptureSetupScreen] deliberately —
/// both write through [CaptureNotifier.setEnabled], which is the single place
/// capture starts and stops, so the two cannot disagree about what "off"
/// means. Off unsubscribes the listener: no memo is written, not merely no
/// notification.
class CaptureSettingsCard extends StatefulWidget {
  const CaptureSettingsCard({super.key});

  @override
  State<CaptureSettingsCard> createState() => _CaptureSettingsCardState();
}

class _CaptureSettingsCardState extends State<CaptureSettingsCard> {
  bool _enabled = false;
  DateTime? _lastCapture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await CapturePrefs.isEnabled();
    final last = await CapturePrefs.lastCaptureAt();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _lastCapture = last;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final last = _lastCapture;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const IconTile(Icons.notifications_active_outlined),
            title: const Text('Capture bank alerts'),
            subtitle: const Text('Files bank and UPI alerts from this phone.',
                style: TextStyle(fontSize: 12)),
            value: _enabled,
            onChanged: (value) async {
              setState(() => _enabled = value);
              await CaptureNotifier.setEnabled(value,
                  db: state.db, ruleset: state.ruleset);
              await _refresh();
            },
          ),
          ListTile(
            dense: true,
            title: const Text('Last captured'),
            trailing: Text(last == null ? 'Never' : istDayLabel(last),
                style: TextStyle(color: context.hisab.textSecondary)),
          ),
          ListTile(
            dense: true,
            leading: const IconTile(Icons.tune),
            title: const Text('Capture setup'),
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => captureSetupPage()));
              await _refresh();
            },
          ),
        ],
      ),
    );
  }
}

/// Erase all data, last on the page and in red: the one action here that
/// cannot be undone.
class _DangerZone extends StatelessWidget {
  const _DangerZone();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final red = context.hisab.spend;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('DANGER ZONE',
              style: HisabType.caption.copyWith(
                  color: red, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HisabRadius.r16),
            side: BorderSide(color: red.withValues(alpha: 0.5)),
          ),
          color: red.withValues(alpha: 0.06),
          child: ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: red),
            title: Text('Erase all data',
                style: TextStyle(color: red, fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Statements, transactions, memos and rules on this phone.',
                style: TextStyle(fontSize: 12)),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Erase everything?'),
                  content: const Text(
                      'All imported statements, transactions, captured memos, and rules will be removed from this device.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('Erase', style: TextStyle(color: red))),
                  ],
                ),
              );
              if (confirmed != true) return;
              await DemoData.eraseAll(state.db);
              // The Swift app's backup and statement copies (iOS, after the
              // 2.0 migration) are data too.
              await LegacyMigration.eraseLeftovers();
              // Suppressions are keyed by insight id and merchant key;
              // surviving an erase would silently hide cards about data the
              // user no longer has.
              await InsightStore.clearAll();
              // The agent's cards quote the ledger's numbers.
              await AgentInsights.clear();
              // Capture health timestamps and a pending rule offer naming a
              // payee live in SharedPreferences, where eraseAll cannot reach.
              await CapturePrefs.clearCapturedData();
              // A banner already in the shade, or a quiet-hours hold, names a
              // payee whose memo this erase just removed.
              await CaptureNotifier.eraseUserData();
              state.suppressions = const Suppressions();
              await Queries.categoryRules(state.db, state.ruleset);
            },
          ),
        ),
      ],
    );
  }
}
