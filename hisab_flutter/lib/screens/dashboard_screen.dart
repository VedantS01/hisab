import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../services/queries.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/import_flow.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  YearMonth _selected = YearMonth.fromDate(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return StreamBuilder<Snapshot>(
      stream: state.snapshots,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('हिसाब',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: HisabTheme.khataRed)),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle, color: HisabTheme.khataRed),
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
    final ruleList = Queries.rules(data.ruleRows);
    final txns = Queries.analytics(data.txns, data.matches, ruleList);
    if (txns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book, size: 56, color: HisabTheme.khataRed),
              const SizedBox(height: 12),
              const Text('Your bahi is empty.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                  'Import a statement to begin, or load demo data from Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: HisabTheme.khataRed),
                onPressed: () => showImportFlow(context),
                icon: const Icon(Icons.add),
                label: const Text('Import statement'),
              ),
            ],
          ),
        ),
      );
    }

    final grid = Queries.grid(data.documents, data.pins);
    final months = grid.months.isEmpty
        ? [YearMonth.fromDate(DateTime.now())]
        : grid.months;
    if (!months.contains(_selected)) _selected = months.first;
    final stats = Analytics.monthStats(txns, _selected);
    final trend = Analytics.trend(txns, endingAt: _selected, count: 6);
    final breakdown =
        Analytics.categoryBreakdown(txns, _selected, top: 5);
    final merchants = Analytics.topMerchants(txns, _selected, top: 5);
    final bankVerified = grid.sources.any((s) =>
        s.kind == SourceKind.bank &&
        grid.state(_selected, s) is CellPresent);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final month in months)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(month.displayName),
                    selected: month == _selected,
                    selectedColor: HisabTheme.khataRed.withValues(alpha: 0.15),
                    onSelected: (_) => setState(() => _selected = month),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _heroCard(stats, bankVerified),
        _trendCard(trend),
        _breakdownCard(breakdown),
        _merchantsCard(merchants),
      ],
    );
  }

  Widget _heroCard(MonthStats stats, bool bankVerified) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_selected.displayName} spend',
                  style: const TextStyle(color: Colors.black54)),
              Text(Money.formatPaise(stats.spendPaise),
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: HisabTheme.khataRed)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _pill('In ${Money.formatPaise(stats.incomePaise)}',
                      HisabTheme.hara),
                  const SizedBox(width: 8),
                  _pill('Net ${Money.formatPaise(stats.netPaise, signed: true)}',
                      HisabTheme.ink),
                ],
              ),
              if (bankVerified)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.verified, size: 16, color: HisabTheme.hara),
                    SizedBox(width: 4),
                    Text('Bank statement on file for this month',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black54)),
                  ]),
                ),
            ],
          ),
        ),
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _trendCard(List<MonthStats> trend) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Six-month trend',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: BarChart(
                  BarChartData(
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= trend.length) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                                trend[index].month.displayName.split(' ').first,
                                style: const TextStyle(fontSize: 10));
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < trend.length; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: trend[i].spendPaise / 100,
                            color: trend[i].month == _selected
                                ? HisabTheme.khataRed
                                : HisabTheme.khataRed.withValues(alpha: 0.35),
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _breakdownCard(List<CategorySlice> breakdown) {
    final total = breakdown.fold<int>(0, (a, s) => a + s.paise);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Where it went',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (breakdown.isEmpty)
              const Text('No spending this month',
                  style: TextStyle(color: Colors.black54)),
            for (final slice in breakdown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(slice.category),
                        Text(Money.formatPaise(slice.paise),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : slice.paise / total,
                      minHeight: 5,
                      backgroundColor: HisabTheme.kagaz,
                      color: HisabTheme.sona,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _merchantsCard(List<MerchantSlice> merchants) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Top merchants',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (merchants.isEmpty)
                const Text('Nothing yet',
                    style: TextStyle(color: Colors.black54)),
              for (final merchant in merchants)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                          child: Text(merchant.merchant,
                              overflow: TextOverflow.ellipsis)),
                      Text(Money.formatPaise(merchant.paise),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
