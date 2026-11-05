import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../design/design.dart';
import '../feed/feed_view.dart';
import '../feed/home_feed.dart';
import '../services/agent_insights.dart';
import '../services/hisab_model.dart';
import '../services/demo_data.dart';
import '../services/insight_store.dart';
import '../services/incoming_router.dart';
import '../services/queries.dart';
import '../state.dart';
import '../widgets/import_flow.dart';
import '../widgets/insight_evidence_sheet.dart';
import '../widgets/insight_strip.dart';
import '../widgets/capture_health.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  YearMonth _selected = YearMonth.fromDate(DateTime.now());

  /// Pruning drops every dismissal not in the live id set, so it must never
  /// run against an empty set (that would wipe the user's whole dismissal
  /// history) and must not re-run on every rebuild (each dismiss/mute
  /// triggers a setState, which would otherwise fire another SharedPreferences
  /// round trip). A one-shot flag guarded by "the set is non-empty" gives
  /// both properties for free: the call site only exists inside the
  /// isNotEmpty branch, so it is unreachable with an empty set on any path,
  /// and flipping the flag before the (fire-and-forget) call means at most
  /// one prune ever runs for this screen's lifetime.
  bool _pruned = false;

  /// Whether this screen has offered the insights agent its run.
  bool _agentAsked = false;

  /// Debug builds start where a hisab://tab/0?scroll=N link says.
  final _scroll = ScrollController(
      initialScrollOffset: IncomingRouter.debugScroll.value ?? 0);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return StreamBuilder<Snapshot>(
      initialData: state.latest,
      stream: state.snapshots,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text('हिसाब',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: context.hisab.brandText)),
            actions: [
              IconButton(
                icon: Icon(Icons.add_circle, color: context.hisab.brandText),
                onPressed: () => showImportFlow(context),
              ),
            ],
          ),
          body: data == null
              ? const Center(child: CircularProgressIndicator())
              : _body(data),
        );
      },
    );
  }

  Widget _body(Snapshot data) {
    final matcher = Queries.matcher(data.ruleRows);
    // Derived once and handed to both projections: detecting self transfers
    // compares every bank debit against every bank credit, and `_body` runs
    // on every build.
    final selfTransfers = Queries.selfTransferUuids(data.txns);
    final txns = Queries.analytics(data.txns, data.matches, matcher,
        selfTransfers: selfTransfers);
    if (txns.isEmpty) {
      // The capture line and the needs-review card are mounted here too, not
      // only below. A user who relies on capture and has imported nothing yet
      // is exactly the person with memos waiting and no statements — putting
      // these only on the populated dashboard would hide the feature from the
      // people using it most.
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CaptureHealthBanner(),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.menu_book, size: 56, color: context.hisab.brandText),
                const SizedBox(height: 12),
                const Text('Your bahi is empty.',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Import a statement to begin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.hisab.textSecondary)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: context.hisab.brand),
                  onPressed: () => showImportFlow(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Import statement'),
                ),
                // Only on an empty ledger: how a first-time user (and App
                // Review) can see every screen without importing their own
                // statements. Gone once anything real is in.
                TextButton(
                  onPressed: () =>
                      DemoData.load(AppScope.of(context).importService),
                  child: Text('Explore with sample data',
                      style: TextStyle(color: context.hisab.brandText)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Every document, the captured-alerts one included: here the grid only
    // supplies the month picker and bank verification (bank sources alone), and
    // a month with captured rows but no statement yet has to be pickable.
    final grid = Queries.grid(data.documents, data.pins);
    final months = grid.months.isEmpty
        ? [YearMonth.fromDate(DateTime.now())]
        : grid.months;
    if (!months.contains(_selected)) _selected = months.first;
    final stats = Analytics.monthStats(txns, _selected);
    final trend = Analytics.trend(txns, endingAt: _selected, count: 6);
    final breakdown = Analytics.categoryBreakdown(txns, _selected, top: 5);
    final merchants = Analytics.topMerchants(txns, _selected, top: 5);
    final bankVerified = grid.sources.any((s) =>
        s.kind == SourceKind.bank && grid.state(_selected, s) is CellPresent);

    final state = AppScope.of(context);
    final records = Queries.insightRecords(data.txns, data.matches, matcher,
        selfTransfers: selfTransfers);
    final insights = InsightsEngine.generate(
      input: InsightsInput(
        records: records,
        documentPeriods:
            Queries.insightPeriods(Queries.statements(data.documents)),
        now: DateTime.now(),
      ),
      config: state.insightsConfig,
      suppressions: state.suppressions,
    );
    // See `_pruned`'s doc comment for why this guard and this one-shot flag
    // are both load-bearing, not just tidiness.
    if (!_pruned && insights.allIDs.isNotEmpty) {
      _pruned = true;
      InsightStore.prune(insights.allIDs);
    }
    // The first open after a month ends writes that month's insights.
    if (!_agentAsked) {
      _agentAsked = true;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => AgentInsights.maybeRun(records, now: DateTime.now()));
    }

    final now = DateTime.now();
    List<Widget> section(FeedSection section) => switch (section.type) {
          'sampleDataBar' => [
              if (data.documents
                  .any((d) => DemoData.slotKeys.contains(d.fileSha256)))
                _SampleDataBar(onClear: () => DemoData.eraseExisting(state.db)),
            ],
          'captureHealth' => [const CaptureHealthBanner()],
          // Above the month chips, matching iOS: insights speak about the
          // month just ended, so mounting them under the chips would imply
          // they follow the selection. Everything below the chip row does.
          'insights' => [_insights(insights, data, records)],
          'monthPicker' => [
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final month in months)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: HisabFilterChip(
                          label: month.displayName,
                          selected: month == _selected,
                          onSelected: (_) => setState(() => _selected = month),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: HisabSpace.s12),
            ],
          'hero' => [
              _heroCard(stats, bankVerified),
              const SizedBox(height: HisabSpace.s12)
            ],
          'trend' => [
              _trendCard(trend),
              const SizedBox(height: HisabSpace.s12)
            ],
          'breakdown' => [
              _breakdownCard(breakdown),
              const SizedBox(height: HisabSpace.s12)
            ],
          'merchants' => [
              _merchantsCard(merchants),
              const SizedBox(height: HisabSpace.s12)
            ],
          'card' => [
              if (section.card!.until == null ||
                  now.isBefore(section.card!.until!))
                FeedCardView(card: section.card!),
            ],
          _ => const [],
        };

    return ValueListenableBuilder<HomeFeed>(
      valueListenable: HomeFeed.current,
      builder: (context, feed, _) => ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [for (final s in feed.sections) ...section(s)],
      ),
    );
  }

  /// The insights agent's cards for the month just ended where Apple's
  /// models run; the native engine's strip until then, and everywhere else.
  Widget _insights(
      InsightsResult native, Snapshot data, List<InsightRecord> records) {
    final state = AppScope.of(context);
    return ListenableBuilder(
      listenable:
          Listenable.merge([AgentInsights.current, AgentInsights.running]),
      builder: (context, _) {
        final now = DateTime.now();
        final month = AgentInsights.monthFor(now);
        final agent = AgentInsights.current.value;
        final running = AgentInsights.running.value;
        void rewrite() =>
            AgentInsights.maybeRun(records, now: DateTime.now(), force: true);
        if (agent != null && agent.month == month && agent.cards.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text(month.displayName,
                        style: Theme.of(context).textTheme.titleSmall)),
                IconButton(
                  tooltip: 'Write again',
                  icon: const Icon(Icons.refresh),
                  onPressed: running ? null : rewrite,
                ),
              ]),
              InsightCarousel(cards: [
                for (final c in agent.cards)
                  InsightCard(
                    icon: FeedIcons.of(c.kind),
                    title: c.title,
                    body: c.body,
                    onTap: c.category == null
                        ? null
                        : () => openFeedAction(context,
                            FeedAction('transactions', category: c.category)),
                  ),
              ]),
              const SizedBox(height: 8),
            ],
          );
        }
        if (running) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SkeletonBox(height: 124, radius: HisabRadius.r16),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InsightStrip(
              insights: native.cards,
              onOpen: (insight) =>
                  showInsightEvidence(context, insight, data.txns),
              onDismiss: (insight) async {
                await InsightStore.dismiss(insight.id);
                final refreshed = await InsightStore.load();
                if (mounted) setState(() => state.suppressions = refreshed);
              },
              onMute: (insight) async {
                final target = insight.mute;
                if (target == null) return;
                await InsightStore.mute(target);
                final refreshed = await InsightStore.load();
                if (mounted) setState(() => state.suppressions = refreshed);
              },
            ),
            // On demand, where the agent can run and has something to read.
            FutureBuilder<bool>(
              future: hisabModelReady,
              builder: (context, ready) => ready.data == true &&
                      records.any((r) => YearMonth.fromDate(r.date) == month)
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: rewrite,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text('Insights for ${month.displayName}'),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (native.cards.isNotEmpty) const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  /// The month in one card: spend on a plum-to-red gradient, income and net
  /// as pills, the bank's confirmation in gold. The one loud thing on the
  /// page; everything under it is quiet.
  Widget _heroCard(MonthStats stats, bool bankVerified) {
    final c = context.hisab;
    final onHero = Colors.white.withValues(alpha: 0.78);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HisabRadius.r28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.heroStart, c.heroEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: c.heroEnd.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -48,
            child: _orb(168, Colors.white.withValues(alpha: 0.07)),
          ),
          Positioned(
            right: 48,
            bottom: -72,
            child: _orb(132, HisabPalette.goldOnHero.withValues(alpha: 0.14)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                HisabSpace.s20, HisabSpace.s20, HisabSpace.s20, HisabSpace.s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_selected.displayName} spend',
                    style: HisabType.label.copyWith(color: onHero)),
                const SizedBox(height: HisabSpace.s4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.white),
                    child: AmountText(stats.spendPaise, role: AmountRole.hero),
                  ),
                ),
                const SizedBox(height: HisabSpace.s16),
                Wrap(
                  spacing: HisabSpace.s8,
                  runSpacing: HisabSpace.s8,
                  children: [
                    _heroPill('In', AmountText.format(stats.incomePaise),
                        HisabPalette.goldOnHero),
                    _heroPill(
                        'Net',
                        AmountText.format(stats.netPaise,
                            tone: stats.netPaise >= 0
                                ? AmountTone.credit
                                : AmountTone.plain),
                        Colors.white),
                  ],
                ),
                if (bankVerified) ...[
                  const SizedBox(height: HisabSpace.s16),
                  Row(children: [
                    const Icon(Icons.verified_rounded,
                        size: 16, color: HisabPalette.goldOnHero),
                    const SizedBox(width: HisabSpace.s4),
                    Text('Bank statement on file for this month',
                        style: HisabType.caption.copyWith(color: onHero)),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orb(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  Widget _heroPill(String label, String amount, Color tint) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: HisabSpace.s12, vertical: 6),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(HisabRadius.pill),
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$label ',
                style: TextStyle(color: tint.withValues(alpha: 0.85))),
            TextSpan(text: amount),
          ]),
          style: HisabType.label.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
              fontFeatures: HisabType.tabular),
        ),
      );

  Widget _trendCard(List<MonthStats> trend) {
    final c = context.hisab;
    final peak = trend.fold<double>(
        0, (m, s) => s.spendPaise > m ? s.spendPaise.toDouble() : m);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Six-month trend', style: HisabType.title),
          const SizedBox(height: HisabSpace.s12),
          SizedBox(
            height: 132,
            child: BarChart(
              BarChartData(
                maxY: peak == 0 ? 1 : peak / 100 * 1.08,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  handleBuiltInTouches: false,
                  touchCallback: (event, response) {
                    final index = response?.spot?.touchedBarGroupIndex;
                    if (event is FlTapUpEvent && index != null) {
                      setState(() => _selected = trend[index].month);
                    }
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= trend.length) {
                          return const SizedBox.shrink();
                        }
                        final selected = trend[index].month == _selected;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            trend[index].month.displayName.split(' ').first,
                            style: HisabType.caption.copyWith(
                              color: selected ? c.brandText : c.textTertiary,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < trend.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: trend[i].spendPaise / 100,
                        width: 24,
                        borderRadius: BorderRadius.circular(HisabRadius.r8),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: trend[i].month == _selected
                              ? [c.heroEnd, c.gold]
                              : [
                                  c.brand.withValues(alpha: 0.42),
                                  c.brand.withValues(alpha: 0.16)
                                ],
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: peak == 0 ? 1 : peak / 100 * 1.08,
                          color: c.sunken,
                        ),
                      ),
                    ]),
                ],
              ),
              duration: HisabMotion.medium,
              curve: HisabMotion.curve,
            ),
          ),
        ],
      ),
    );
  }

  /// A colour per category, stable within the month: the breakdown's bar,
  /// legend and the merchant avatars read as one system.
  static Color categoryHue(int index) =>
      HisabPalette.avatarHues[index % HisabPalette.avatarHues.length];

  Widget _breakdownCard(List<CategorySlice> breakdown) {
    final c = context.hisab;
    final total = breakdown.fold<int>(0, (a, s) => a + s.paise);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where it went', style: HisabType.title),
          const SizedBox(height: HisabSpace.s12),
          if (breakdown.isEmpty)
            Text('No spending this month',
                style: HisabType.body.copyWith(color: c.textSecondary))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(HisabRadius.pill),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    for (var i = 0; i < breakdown.length; i++)
                      Expanded(
                        flex: breakdown[i].paise.clamp(1, 1 << 30),
                        child: Container(
                          margin: EdgeInsets.only(
                              right: i == breakdown.length - 1 ? 0 : 2),
                          color: categoryHue(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: HisabSpace.s12),
            for (var i = 0; i < breakdown.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: categoryHue(i), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: HisabSpace.s12),
                    Expanded(
                      child: Text(breakdown[i].category,
                          overflow: TextOverflow.ellipsis,
                          style: HisabType.body),
                    ),
                    Text(
                      total == 0
                          ? ''
                          : '${(breakdown[i].paise * 100 / total).round()}%',
                      style: HisabType.caption.copyWith(
                          color: c.textTertiary,
                          fontFeatures: HisabType.tabular),
                    ),
                    const SizedBox(width: HisabSpace.s12),
                    AmountText(breakdown[i].paise, role: AmountRole.md),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _merchantsCard(List<MerchantSlice> merchants) {
    final c = context.hisab;
    final top = merchants.isEmpty ? 0 : merchants.first.paise;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(
          HisabSpace.s16, HisabSpace.s16, HisabSpace.s16, HisabSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top merchants', style: HisabType.title),
          const SizedBox(height: HisabSpace.s8),
          if (merchants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: HisabSpace.s8),
              child: Text('Nothing yet',
                  style: HisabType.body.copyWith(color: c.textSecondary)),
            ),
          for (var i = 0; i < merchants.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HisabSpace.s8),
              child: Row(
                children: [
                  MerchantAvatar(
                      name: merchants[i].merchant, hue: categoryHue(i)),
                  const SizedBox(width: HisabSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(merchants[i].merchant,
                            overflow: TextOverflow.ellipsis,
                            style: HisabType.body
                                .copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: HisabSpace.s4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(HisabRadius.r4),
                          child: LinearProgressIndicator(
                            value: top == 0 ? 0 : merchants[i].paise / top,
                            minHeight: 4,
                            backgroundColor: c.sunken,
                            color: categoryHue(i),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: HisabSpace.s12),
                  AmountText(merchants[i].paise, role: AmountRole.md),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown while the sample statements are loaded, so they are never mistaken
/// for the user's own money.
class _SampleDataBar extends StatelessWidget {
  final Future<void> Function() onClear;
  const _SampleDataBar({required this.onClear});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: HisabSpace.s12),
        child: InfoBanner(
          icon: Icons.science_outlined,
          message: 'Sample data',
          tone: HisabTone.brand,
          actionLabel: 'Clear',
          onAction: onClear,
        ),
      );
}
