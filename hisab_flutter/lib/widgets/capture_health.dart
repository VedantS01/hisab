/// The capture-health line on the dashboard. Was half of the Swift app's
/// `NeedsReviewSection.swift`; captured alerts now wait in Detections.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../design/design.dart';
import '../screens/capture_setup_screen.dart';
import '../services/capture_prefs.dart';

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

  /// Value equality, like the Swift twin's `Equatable` — [days] is part of
  /// what the user is shown, so it is part of what "unchanged" means.
  @override
  bool operator ==(Object other) =>
      other is CaptureHealth && other.state == state && other.days == days;

  @override
  int get hashCode => Object.hash(state, days);

  @override
  String toString() => 'CaptureHealth(${state.name}, days: $days)';
}

/// The dashboard's capture-health line.
///
/// SharedPreferences is not a stream, so the health is re-read rather than
/// watched — the twin of the iOS banner's `onAppear`. The two moments it is
/// read are when this widget is created and when the user comes back from the
/// setup screen. The first covers more than it looks: `RootTabs` builds one
/// tab's screen at a time, so every return to the dashboard creates a fresh
/// banner. The second is the one that matters most — a user who has just
/// granted notification access must not land back on the warning that sent
/// them there.
///
/// What it deliberately does NOT do is re-read on every rebuild of the
/// dashboard: the dashboard rebuilds on every database change, and each read
/// is three asynchronous preference lookups.
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
    // The WHOLE value, as the iOS twin compares it. Comparing only `state`
    // froze the day count: a banner reading "No alerts received in 4 days"
    // stayed at 4 for as long as the dashboard was mounted, because every
    // later reading was still `noAlerts` and so was discarded.
    if (mounted && current != _health) {
      setState(() => _health = current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _health.message;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: HisabSpace.s12),
      child: InfoBanner(
        key: const Key('capture-health'),
        icon: Icons.notifications_paused_outlined,
        message: message,
        tone: HisabTone.neutral,
        actionLabel: _health.offersSetup ? 'Check capture setup' : null,
        onAction: _health.offersSetup
            ? () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => captureSetupPage()));
                await _refresh();
              }
            : null,
      ),
    );
  }
}
