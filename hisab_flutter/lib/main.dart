import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show AssetManifest, MethodChannel, rootBundle;
import 'package:hisab_core/hisab_core.dart';
import 'package:hisab_pdf/hisab_pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Not called from here: compiled in so iOS's headless capture engine can
// start at its `captureMain` entry point in a release build.
// ignore: unused_import
import 'capture_entry.dart';
import 'screens/buckets_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/reconciliation_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transactions_screen.dart';
import 'services/capture_notifier.dart';
import 'services/demo_data.dart';
import 'services/import_service.dart';
import 'services/incoming_router.dart';
import 'services/insight_store.dart';
import 'services/legacy_migration.dart';
import 'services/pdfkit_text.dart';
import 'services/queries.dart';
import 'services/statement_self_test.dart';
import 'state.dart';
import 'design/design.dart';
import 'feed/home_feed.dart';
import 'services/agent_insights.dart';
import 'services/network.dart';
import 'storage/database.dart';
import 'widgets/import_flow.dart';
import 'widgets/memo_review_sheet.dart';
import 'widgets/suggestion_prompt.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installPdfHooks();
  PdfKitText.install();

  final db = AppDatabase(driftDatabase(name: 'hisab'));
  // First, before anything reads preferences: the native half copies the
  // Swift app's settings over as part of the export.
  await LegacyMigration.runIfNeeded(db);
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
      registry: fullRegistry(extra: PdfKitText.parsers), specs: SpecStore.parseAll(specJsons));
  final insightsConfig = InsightsConfig.fromJsonString(
      await rootBundle.loadString('assets/insights/insights-config.json'));
  final suppressions = await InsightStore.load();
  await AgentInsights.load();
  // Not awaited past the cache: the site is fetched in the background.
  await HomeFeed.load();
  await Network.watch();
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
  // Device check for the statement reader's Gemini Nano path (read-only):
  //   --dart-define=STATEMENT_SELFTEST=true, then adb logcat | grep STATEMENT
  if (const bool.fromEnvironment('STATEMENT_SELFTEST')) {
    StatementSelfTest.run().then(debugPrint);
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
  // Files and links opened into Hisab; parked until RootTabs drains them.
  await IncomingRouter.init();

  // iOS captures in a second engine (capture_entry.dart), whose writes this
  // engine's drift streams cannot see; the Runner pings here after each one.
  const MethodChannel('hisab/app').setMethodCallHandler((call) async {
    if (call.method == 'dataChanged') db.markTablesUpdated(db.allTables);
  });

  runApp(AppScope(state: state, child: const HisabApp()));
}

class HisabApp extends StatelessWidget {
  const HisabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hisab',
      // Light only until every screen reads colours from the theme.
      theme: HisabDesign.light(),
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
    IncomingRouter.file.addListener(_onIncoming);
    IncomingRouter.link.addListener(_onIncoming);
  }

  @override
  void dispose() {
    CaptureRouter.reviewRequest.removeListener(_onCaptureResponse);
    CaptureRouter.offerGeneration.removeListener(_onCaptureResponse);
    IncomingRouter.file.removeListener(_onIncoming);
    IncomingRouter.link.removeListener(_onIncoming);
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
        // Same reason as above: a file opened into a closed Hisab arrives
        // before this widget listens.
        _onIncoming();
        await _maybeSuggest();
      });
    }
  }

  /// A file or link opened into Hisab (IncomingRouter). Taken out of the
  /// notifier as it is read, so each is handled once.
  void _onIncoming() {
    if (!mounted) return;
    final target = IncomingRouter.link.value;
    if (target != null) {
      IncomingRouter.link.value = null;
      setState(() => _tab = target == LinkTarget.transactions ? 2 : 0);
    }
    final file = IncomingRouter.file.value;
    if (file == null) return;
    IncomingRouter.file.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final staged = File(file.path);
      if (!await staged.exists()) return;
      final data = await staged.readAsBytes();
      await staged.delete();
      if (!mounted) return;
      setState(() => _tab = 0);
      await importFileBytes(context, filename: file.name, data: data);
    });
    WidgetsBinding.instance.scheduleFrame();
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
  /// the notification carried no payload — land on Detections rather than on
  /// whatever tab was last open.
  Future<void> _presentReview(String hash) async {
    if (!mounted) return;
    if (hash.isEmpty) {
      TransactionsScreen.segment.value = 1;
      setState(() => _tab = 2);
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
    final state = AppScope.of(context);
    return Scaffold(
      body: screens[_tab],
      bottomNavigationBar: StreamBuilder<Snapshot>(
        initialData: state.latest,
        stream: state.snapshots,
        builder: (context, snap) {
          final waiting = snap.data?.detections.length ?? 0;
          final nav = NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(
                  icon: Icon(Icons.bar_chart), label: 'Dashboard'),
              const NavigationDestination(
                  icon: Icon(Icons.calendar_month), label: 'Buckets'),
              NavigationDestination(
                  icon: Badge(
                      isLabelVisible: waiting > 0,
                      label: Text('$waiting'),
                      child: const Icon(Icons.receipt_long)),
                  label: 'Transactions'),
              const NavigationDestination(
                  icon: Icon(Icons.compare_arrows), label: 'Reconcile'),
              const NavigationDestination(
                  icon: Icon(Icons.settings), label: 'Settings'),
            ],
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: Network.offline,
                builder: (context, offline, _) => offline
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(HisabSpace.gutter,
                            HisabSpace.s8, HisabSpace.gutter, HisabSpace.s8),
                        child: InfoBanner(
                            icon: Icons.cloud_off_outlined,
                            message: 'Your device is offline.',
                            tone: HisabTone.neutral),
                      )
                    : const SizedBox.shrink(),
              ),
              nav,
            ],
          );
        },
      ),
    );
  }
}
