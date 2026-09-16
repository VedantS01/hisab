import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../services/queries.dart';
import '../storage/database.dart';
import '../state.dart';
import '../theme.dart';

class BucketsScreen extends StatelessWidget {
  const BucketsScreen({super.key});

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
            title: const Text('Buckets'),
            actions: [
              IconButton(
                icon: const Icon(Icons.push_pin_outlined),
                onPressed: () => _pinMonth(context),
              ),
            ],
          ),
          body: data == null
              ? const Center(child: CircularProgressIndicator())
              : _grid(context, data),
        );
      },
    );
  }

  Widget _grid(BuildContext context, Snapshot data) {
    final grid = Queries.grid(data.documents, data.pins);
    if (grid.months.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No months yet — import a statement or pin a month to start tracking.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    // Columns follow the user's actual imports; pin-only grids fall back to
    // the built-in five so awaiting cells still render.
    final columns = grid.sources.isEmpty ? Source.builtIn : grid.sources;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const SizedBox(
                width: 76,
                child: Text('Month',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600))),
            for (final source in columns)
              Expanded(
                child: Text(_short(source),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (final month in grid.months)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                    width: 76,
                    child: Text(month.displayName,
                        style: const TextStyle(fontSize: 12))),
                for (final source in columns)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _cell(
                          context, data, month, source, grid.state(month, source)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _short(Source source) {
    switch (source.rawValue) {
      case 'gpay':
        return 'GPay';
      case 'paytm':
        return 'Paytm';
      case 'bhim':
        return 'BHIM';
      case 'hdfc':
        return 'HDFC';
      case 'idfc':
        return 'IDFC';
      default:
        return source.displayName;
    }
  }

  Widget _cell(BuildContext context, Snapshot data, YearMonth month,
      Source source, CellState cellState) {
    if (cellState is CellPresent) {
      return InkWell(
        onTap: () => _showDocuments(context, data, month, source,
            cellState.documentIDs),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: HisabTheme.sona.withValues(alpha: 0.16),
            border:
                Border.all(color: HisabTheme.sona.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.check, size: 16, color: HisabTheme.sona),
        ),
      );
    }
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  void _showDocuments(BuildContext context, Snapshot data, YearMonth month,
      Source source, List<String> ids) {
    final docs =
        data.documents.where((d) => ids.contains(d.id)).toList();
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('${source.displayName} · ${month.displayName}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final doc in docs)
              ListTile(
                leading: Icon(HisabTheme.sourceGlyph(source),
                    color: HisabTheme.khataRed),
                title: Text(doc.filename,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${YearMonth.fromDate(DateTime.fromMillisecondsSinceEpoch(doc.periodStartMs, isUtc: true)).displayName}'
                    ' – ${YearMonth.fromDate(DateTime.fromMillisecondsSinceEpoch(doc.periodEndMs, isUtc: true)).displayName}'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pinMonth(BuildContext context) async {
    final state = AppScope.of(context);
    final now = YearMonth.fromDate(DateTime.now());
    final options = [for (var i = -2; i <= 6; i++) now.advancedBy(i)];
    final chosen = await showDialog<YearMonth>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Pin a month'),
        children: [
          for (final month in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, month),
              child: Text(month.displayName),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await state.db.into(state.db.pinnedMonths).insert(
        PinnedMonthsCompanion(monthKey: Value(chosen.toString())),
        mode: InsertMode.insertOrIgnore);
  }
}
