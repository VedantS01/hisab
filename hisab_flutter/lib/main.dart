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
import 'services/capture_notifier.dart';
import 'services/demo_data.dart';
import 'services/import_service.dart';
import 'services/insight_store.dart';
import 'services/queries.dart';
import 'state.dart';
import 'storage/database.dart';
import 'theme.dart';
import 'widgets/memo_review_sheet.dart';
import 'widgets/needs_review_section.dart';
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
  final insightsConfig = InsightsConfig.fromJsonString(
      await rootBundle.loadString('assets/insights/insights-config.json'));
  final suppressions = await InsightStore.load();
  final state = AppState(
    db: db,
    importService: ImportService(db: db, resolver: resolver),
    ruleset: ruleset,
    insightsConfig: insightsConfig,
    suppressions: suppressions,
  );
  await Queries.categoryRules(db, ruleset); // additive seeding on launch

  // Screenshot/dev harness: flutter build --dart-define=SEED_DEMO=true
  // auto-loads the demo statements on an empty database.
  const seedDemo = bool.fromEnvironment('SEED_DEMO');
  if (seedDemo) {
    final docs = await db.select(db.storedDocuments).get();
    if (docs.isEmpty) await DemoData.load(state.importService);
  }

  // Capture. `CaptureNotifier.init` owns the whole lifecycle: notification
  // delivery, a notification response that LAUNCHED the app, and subscribing
  // the listener — but only when the user has capture switched on.
  //
  // Task 15's `CAPTURE_ENABLE` dart-define and its bare
  // `NotificationCapture.start()` are both gone. They existed so the service
  // was reachable before a toggle did; the toggle is now `CaptureSetupScreen`,
  // linked from Settings and from the dashboard's health line, and a
  // dart-define that switched capture on behind the toggle's back would
  // contradict the one guarantee the toggle has to make.
  await CaptureNotifier.init(db: db, ruleset: ruleset);

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

  /// One capture sheet at a time. Two notification responses in quick
  /// succession would otherwise stack sheets on top of each other, and the
  /// second would measure its rule offer against a database the first is
  /// still writing to.
  bool _presenting = false;

  /// Set when a response arrives while [_pumpCaptureQueue] is already running,
  /// so the loop goes round once more instead of leaving it sitting there.
  bool _requeue = false;

  @override
  void initState() {
    super.initState();
    CaptureRouter.reviewRequest.addListener(_onCaptureResponse);
    CaptureRouter.offerGeneration.addListener(_onCaptureResponse);
  }

  @override
  void dispose() {
    CaptureRouter.reviewRequest.removeListener(_onCaptureResponse);
    CaptureRouter.offerGeneration.removeListener(_onCaptureResponse);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_suggestionChecked) {
      _suggestionChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // The FIRST pump is not optional, and not merely an optimisation over
        // the listeners: `CaptureNotifier.init` replays a response that
        // LAUNCHED the app, from `main`, before `runApp` — so on a cold launch
        // `reviewRequest` already holds its hash by the time this widget
        // exists, and `addListener` does not fire for a value a notifier
        // already holds. On Android that is the COMMON case, because the
        // capture listener has no background isolate and the app is usually
        // not running when the user taps. Relying on the listener alone was
        // exactly the bug: the value was written in `main` and read nowhere.
        //
        // Offers are drained in the same pass, and first among equals: a
        // category chosen from a notification button while Hisab was closed
        // has already been applied, and the question it left behind is the
        // durable value the whole feature exists to produce.
        await _pumpCaptureQueue();
        await _maybeSuggest();
      });
    }
  }

  /// A notification response — a body tap, "Later", or a category button —
  /// reached one of the two router notifiers.
  void _onCaptureResponse() {
    if (!mounted) return;
    // Deferred to the end of the frame, because a notifier callback can land
    // in the middle of one and a sheet may not be pushed during a build. The
    // explicit `scheduleFrame` is what makes that safe: a response arriving
    // while the app sits idle — which is every response, since nothing else
    // is happening when a notification is tapped — would otherwise leave the
    // callback waiting for a frame nothing has asked for.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pumpCaptureQueue());
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Presents everything a notification response has queued up, one sheet at
  /// a time: memos to review first, then every pending rule offer. Each offer
  /// sheet clears its own offer whichever button the user presses, and a
  /// review request is taken out of the notifier as it is read, so this
  /// terminates.
  Future<void> _pumpCaptureQueue() async {
    // Already running: it will pick up whatever has just arrived, because
    // both queues are re-read at the top of every iteration. [_requeue]
    // covers the one gap — an arrival after the last read and before the
    // loop ends.
    if (_presenting) {
      _requeue = true;
      return;
    }
    _presenting = true;
    try {
      do {
        _requeue = false;
        for (var guard = 0; guard < 20 && mounted; guard++) {
          final hash = _takeReviewRequest();
          if (hash != null) {
            await _presentReview(hash);
            continue;
          }
          final offers = await CaptureNotifier.pendingRuleOffers();
          if (offers.isEmpty || !mounted) break;
          await showQueuedRuleOffer(context, offers.first);
          // Defensive: a sheet dismissed by a back gesture never runs its
          // buttons, so clear the offer here too rather than looping forever.
          await CaptureNotifier.clearOffer(offers.first.captureHash);
        }
      } while (_requeue && mounted);
    } finally {
      _presenting = false;
    }
  }

  /// The hash of a memo waiting to be reviewed, or null.
  ///
  /// The notifier is cleared AS THE VALUE IS TAKEN, never left behind for a
  /// sheet that is already up to find later: `ValueNotifier` does not notify
  /// for a value equal to the one it holds, so a hash stranded here would
  /// silently drop every subsequent tap on that same memo's notification —
  /// permanently, for the life of the process.
  String? _takeReviewRequest() {
    final hash = CaptureRouter.reviewRequest.value;
    if (hash != null) CaptureRouter.reviewRequest.value = null;
    return hash;
  }

  /// A notification body tap, or "Later": open the memo. An empty hash means
  /// the notification carried no payload — land on the inbox rather than on
  /// whatever tab was last open.
  Future<void> _presentReview(String hash) async {
    if (!mounted) return;
    if (hash.isEmpty) {
      await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NeedsReviewInbox()));
    } else {
      await showMemoReviewSheet(context, hash);
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
        Queries.suggestionRecords(txns, matches, Queries.matcher(ruleRows));
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
