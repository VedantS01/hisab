/// The capture-health line, the dashboard's "Needs review" card, and the
/// inbox behind it. Twin of `Hisab/Views/NeedsReviewSection.swift`.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../screens/capture_setup_screen.dart';
import '../services/capture_prefs.dart';
import '../services/memo_store.dart';
import '../state.dart';
import '../storage/database.dart';
import '../theme.dart';
import 'memo_review_sheet.dart';

// MARK: - health

/// What capture is currently doing, as far as the two timestamps can say.
enum CaptureHealthState {
  /// Capture is off; the user is not owed a warning about it.
  off,

  /// Capture is on, nothing has arrived, and nothing ever has.
  neverArrived,

  /// Capture is on and nothing has arrived for [CaptureHealth.days] days.
  noAlerts,

  /// Alerts are arriving and none of them parse. Their setup is fine.
  unreadable,

  healthy,
}

/// What the two capture timestamps say about whether capture is still working.
///
/// ONE timestamp cannot tell "nothing is reaching Hisab" from "everything
/// reaches Hisab and none of it parses", and those need OPPOSITE remediations:
/// go and re-check notification access, versus nothing you can do, wait for an
/// update. A warning that confidently sends a user to fix a working setup is
/// worse than no warning at all. So the copy is driven by both
/// `lastAttemptAt` (stamped on EVERY allowlisted alert, before the enable gate
/// and before the parse) and `lastCaptureAt` (successful parses only).
///
/// On Android this line carries a second job the iOS twin does not have.
/// Capture does not survive process death — the listener plugin re-subscribes
/// only when Hisab is opened — so after a force-stop, alerts arrive and
/// NOTHING is stamped at all. That failure is invisible by construction, and
/// [CaptureHealthState.noAlerts] at the 3-day mark is the only thing that
/// surfaces it. It is why the warning offers the setup screen (which says
/// plainly what to do) rather than staying silent.
@immutable
class CaptureHealth {
  final CaptureHealthState state;

  /// Days since the last arrival, for [CaptureHealthState.noAlerts].
  final int days;

  const CaptureHealth(this.state, {this.days = 0});

  /// Three IST days: a weekend without a single bank alert is ordinary, four
  /// days without one is not.
  static const staleDays = 3;

  static CaptureHealth evaluate({
    required bool enabled,
    required DateTime? lastAttemptAt,
    required DateTime? lastCaptureAt,
    required DateTime now,
  }) {
    if (!enabled) return const CaptureHealth(CaptureHealthState.off);
    if (lastAttemptAt == null) {
      return const CaptureHealth(CaptureHealthState.neverArrived);
    }
    final sinceAttempt = istDaysBetween(lastAttemptAt, now);
    if (sinceAttempt > staleDays) {
      return CaptureHealth(CaptureHealthState.noAlerts, days: sinceAttempt);
    }
    if (lastCaptureAt == null) {
      return const CaptureHealth(CaptureHealthState.unreadable);
    }
    return istDaysBetween(lastCaptureAt, now) > staleDays
        ? const CaptureHealth(CaptureHealthState.unreadable)
        : const CaptureHealth(CaptureHealthState.healthy);
  }

  static Future<CaptureHealth> current({DateTime? now}) async => evaluate(
        enabled: await CapturePrefs.isEnabled(),
        lastAttemptAt: await CapturePrefs.lastAttemptAt(),
        lastCaptureAt: await CapturePrefs.lastCaptureAt(),
        now: now ?? DateTime.now(),
      );

  String? get message {
    switch (state) {
      case CaptureHealthState.off:
      case CaptureHealthState.healthy:
        return null;
      case CaptureHealthState.neverArrived:
        return 'No alerts have reached Hisab yet. Notification access has to '
            'be granted by hand — Hisab cannot switch it on for you.';
      case CaptureHealthState.noAlerts:
        return 'No alerts received in $days days. Capture stops when Hisab is '
            'force-stopped or its battery use is restricted, and only '
            'restarts when the app is opened.';
      case CaptureHealthState.unreadable:
        return 'Alerts are arriving but Hisab could not read them. Nothing on '
            'your side is broken; a bank has probably changed its message '
            'wording.';
    }
  }

  /// Only the two states the user can actually act on link to the setup
  /// screen. [CaptureHealthState.unreadable] deliberately does NOT: their
  /// setup is fine, and sending them to re-grant access would be a lie.
  bool get offersSetup =>
      state == CaptureHealthState.neverArrived ||
      state == CaptureHealthState.noAlerts;
}

/// The dashboard's capture-health line. Re-read on every build of the
/// dashboard, because SharedPreferences is not a stream.
class CaptureHealthBanner extends StatefulWidget {
  const CaptureHealthBanner({super.key});

  @override
  State<CaptureHealthBanner> createState() => _CaptureHealthBannerState();
}

class _CaptureHealthBannerState extends State<CaptureHealthBanner> {
  CaptureHealth _health = const CaptureHealth(CaptureHealthState.off);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final current = await CaptureHealth.current();
    if (mounted && current.state != _health.state) {
      setState(() => _health = current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _health.message;
    if (message == null) return const SizedBox.shrink();
    return Card(
      key: const Key('capture-health'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: HisabTheme.sona, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(message,
                        style: const TextStyle(fontSize: 13))),
              ],
            ),
            if (_health.offersSetup)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const CaptureSetupScreen()));
                    await _refresh();
                  },
                  child: const Text('Check capture setup',
                      style: TextStyle(color: HisabTheme.khataRed)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// MARK: - the dashboard section

/// Captured alerts Hisab could not categorize, on the dashboard.
///
/// Fed from the watched memo stream in [Snapshot], so a memo captured while
/// the app is open — or a category assigned from a notification button — shows
/// up without anything telling the view to look again.
class NeedsReviewSection extends StatelessWidget {
  final Snapshot data;
  const NeedsReviewSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final pending = data.pendingMemos;
    if (pending.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('needs-review-section'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Needs review',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Container(
                  key: const Key('needs-review-count'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
                  decoration: const BoxDecoration(
                      color: HisabTheme.khataRed,
                      borderRadius: BorderRadius.all(Radius.circular(999))),
                  child: Text('${pending.length}',
                      style: const TextStyle(
                          color: HisabTheme.kagaz,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            for (final memo in pending.take(5))
              InkWell(
                onTap: () => showMemoReviewSheet(context, memo.captureHash),
                child: MemoRow(memo: memo),
              ),
            if (pending.length > 5)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const NeedsReviewInbox())),
                child: Text('See all ${pending.length}',
                    style: const TextStyle(color: HisabTheme.khataRed)),
              ),
          ],
        ),
      ),
    );
  }
}

class MemoRow extends StatelessWidget {
  final StoredPendingMemo memo;
  final bool showsChevron;
  const MemoRow({super.key, required this.memo, this.showsChevron = true});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(memo.payee,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                      istStamp(DateTime.fromMillisecondsSinceEpoch(
                          memo.capturedAtMs,
                          isUtc: true)),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
            Text(Money.formatPaise(memo.amountPaise),
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: HisabTheme.amountColor(memo.directionValue))),
            if (showsChevron)
              const Icon(Icons.chevron_right,
                  size: 16, color: Colors.black26),
          ],
        ),
      );
}

// MARK: - the inbox

/// Where "See all" goes, and where a notification with no resolvable memo
/// lands. A real list, never a blank screen.
class NeedsReviewInbox extends StatelessWidget {
  const NeedsReviewInbox({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Needs review')),
      body: StreamBuilder<Snapshot>(
        initialData: state.latest,
        stream: state.snapshots,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final pending = data.pendingMemos;
          return ListView(
            key: const Key('needs-review-inbox'),
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                      'Nothing waiting. Captured alerts Hisab cannot '
                      'categorize show up here.',
                      style: TextStyle(color: Colors.black54)),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final memo in pending)
                        InkWell(
                          onTap: () =>
                              showMemoReviewSheet(context, memo.captureHash),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            child: MemoRow(memo: memo),
                          ),
                        ),
                    ],
                  ),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune, color: HisabTheme.khataRed),
                  title: const Text('Capture setup'),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const CaptureSetupScreen())),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
