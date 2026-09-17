import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:hisab_core/hisab_core.dart';
import 'package:hisab_pdf/hisab_pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/buckets_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/reconciliation_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transactions_screen.dart';
import 'services/demo_data.dart';
import 'services/import_service.dart';
import 'services/queries.dart';
import 'state.dart';
import 'storage/database.dart';
import 'theme.dart';
import 'widgets/suggestion_prompt.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installPdfHooks();

  final db = AppDatabase(driftDatabase(name: 'hisab'));
  final specJsons = <String>[];
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  for (final asset in manifest.listAssets()) {
    if (asset.startsWith('assets/formats/') && asset.endsWith('.json')) {
      specJsons.add(await rootBundle.loadString(asset));
    }
  }
  final ruleset = Ruleset.fromJsonString(
      await rootBundle.loadString('assets/rulesets/india-default.json'));
  final resolver = ImportResolver(
      registry: fullRegistry(), specs: SpecStore.parseAll(specJsons));
  final state = AppState(
    db: db,
    importService: ImportService(db: db, resolver: resolver),
    ruleset: ruleset,
  );
  await Queries.categoryRules(db, ruleset); // additive seeding on launch

  // Screenshot/dev harness: flutter build --dart-define=SEED_DEMO=true
  // auto-loads the demo statements on an empty database.
  const seedDemo = bool.fromEnvironment('SEED_DEMO');
  if (seedDemo) {
    final docs = await db.select(db.storedDocuments).get();
    if (docs.isEmpty) await DemoData.load(state.importService);
  }

  runApp(AppScope(state: state, child: const HisabApp()));
}

class HisabApp extends StatelessWidget {
  const HisabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hisab',
      theme: HisabTheme.light(),
      debugShowCheckedModeBanner: false,
      home: const RootTabs(),
    );
  }
}

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _tab = 0;
  bool _suggestionChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_suggestionChecked) {
      _suggestionChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSuggest());
    }
  }

  Future<void> _maybeSuggest() async {
    final state = AppScope.of(context);
    final prefs = await SharedPreferences.getInstance();
    final today = istDayString(DateTime.now());
    if (prefs.getString('suggestion.lastShown') == today) return;
    final muted = (prefs.getStringList('suggestion.muted') ?? []).toSet();
    final txns = await state.db.select(state.db.storedTransactions).get();
    final matches = await state.db.select(state.db.storedMatches).get();
    final ruleRows = await state.db.select(state.db.storedCategoryRules).get();
    final records =
        Queries.suggestionRecords(txns, matches, Queries.rules(ruleRows));
    final queue = SuggestionEngine.queue(
        records: records, now: DateTime.now(), muted: muted);
    if (queue.isEmpty || !mounted) return;
    await showSuggestionPrompt(context, queue.first);
    await prefs.setString('suggestion.lastShown', today);
  }

  @override
  Widget build(BuildContext context) {
    const screens = [
      DashboardScreen(),
      BucketsScreen(),
      TransactionsScreen(),
      ReconciliationScreen(),
      SettingsScreen(),
    ];
    return Scaffold(
      body: screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.bar_chart), label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month), label: 'Buckets'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long), label: 'Transactions'),
          NavigationDestination(
              icon: Icon(Icons.compare_arrows), label: 'Reconcile'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
