/// How to wire a phone's bank and UPI alerts into Hisab on Android, told
/// honestly. Counterpart of `Hisab/Views/CaptureSetupView.swift`.
///
/// The iOS screen has to walk the user through building a Shortcuts
/// automation by hand. Android is shorter — one system permission — but every
/// claim still has to be one the app can keep:
///
/// * Hisab **cannot** enable the listener itself. `requestPermission()` opens
///   the system's notification-access screen; the user grants it there. Even
///   `adb` could not do it with `settings put secure
///   enabled_notification_listeners` alone on API 36 during Task 15 —
///   `cmd notification allow_listener` was needed — which is a good reminder
///   that this is a system-owned switch, not an app-owned one.
/// * Capture **stops** when the app's process is killed and does not resume
///   until Hisab is opened again. That is said here, not hidden, because a
///   user who discovers it as weeks of silence has been let down twice.
/// * Manufacturer battery management (Xiaomi, Oppo, Vivo, Realme, OnePlus)
///   kills background work aggressively. That is said too.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../services/capture_notifier.dart';
import '../services/capture_prefs.dart';
import '../services/notification_capture.dart';
import '../state.dart';
import '../theme.dart';

class CaptureSetupScreen extends StatefulWidget {
  const CaptureSetupScreen({super.key});

  @override
  State<CaptureSetupScreen> createState() => _CaptureSetupScreenState();
}

class _CaptureSetupScreenState extends State<CaptureSetupScreen> {
  /// An inline sample, not a bundled resource. The point is for the user to
  /// watch the real parser succeed before trusting it, and a constant serves
  /// that exactly as well as a file would.
  static const sample =
      'Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis';

  bool _enabled = false;
  bool _accessGranted = false;
  bool _notificationsAllowed = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await CapturePrefs.isEnabled();
    final granted = await _isAccessGranted();
    final allowed = await CaptureNotifier.areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _accessGranted = granted;
      _notificationsAllowed = allowed;
    });
  }

  /// The plugin throws on a platform with no notification-listener concept
  /// (every platform but Android), which must not blank the screen.
  Future<bool> _isAccessGranted() async {
    try {
      return await NotificationCapture.isGranted();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Capture setup')),
      body: ListView(
        key: const Key('capture-setup'),
        padding: const EdgeInsets.all(16),
        children: [
          _section('What this does', [
            const Text(
                'Hisab reads the text of bank and UPI alerts as they appear '
                'in your notification shade: the amount, who it went to, the '
                'UPI ID and the last digits of the account.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            const Text(
                'Only notifications from bank, UPI and SMS apps on a bundled '
                'list are examined at all — a message from a friend is never '
                'read. Nothing is sent anywhere, and the alert text itself is '
                'never stored: only the amount, payee, UPI ID, account tail '
                'and date survive the parse.',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 6),
            Text(
                'A captured alert is a memo, not a ledger entry — your '
                'statements stay the single source of truth, and a memo’s '
                'real output is a categorization rule. A memo is deleted '
                'after ${PendingMemo.expiryDays} days, unless it has been '
                'matched to a row in an imported statement: that one is kept '
                'so the same alert is never captured a second time. Erasing '
                'all data in Settings removes every memo either way.',
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ]),
          _section('Switch it on', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: HisabTheme.khataRed,
              title: const Text('Capture bank alerts'),
              subtitle: const Text(
                  'With this off, nothing is captured at all — not a memo, '
                  'not a notification.',
                  style: TextStyle(fontSize: 12)),
              value: _enabled,
              onChanged: (value) async {
                setState(() => _enabled = value);
                await CaptureNotifier.setEnabled(value,
                    db: state.db, ruleset: state.ruleset);
                await _refresh();
              },
            ),
            if (_enabled && !_accessGranted)
              _warning(
                  'Hisab does not have notification access yet, so no alert '
                  'can reach it. Grant it below.'),
            if (_enabled && !_notificationsAllowed)
              _warning(
                  'Notifications are off for Hisab, so it cannot ask you what '
                  'an unknown payment was. Turn them on in Android Settings '
                  '› Apps › Hisab › Notifications.'),
          ]),
          _section('Grant notification access', [
            const Text(
                'This is a system permission and only you can grant it. The '
                'button opens Android’s notification-access screen; find '
                'Hisab in the list and switch it on.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: HisabTheme.khataRed),
                onPressed: () async {
                  try {
                    await NotificationCapture.requestPermission();
                  } catch (_) {
                    // Not Android, or no such settings screen. The status line
                    // below already says access is not granted.
                  }
                  await _refresh();
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Grant notification access'),
              ),
              const SizedBox(width: 12),
              Text(_accessGranted ? 'Granted' : 'Not granted',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _accessGranted
                          ? HisabTheme.hara
                          : HisabTheme.khataRed)),
            ]),
          ]),
          _section('What can stop it', [
            const Text(
                'Capture runs inside Hisab’s own process. If Android '
                'stops that process — you force-stop the app from Settings, '
                'or the system reclaims memory — alerts keep arriving on your '
                'phone but Hisab stops seeing them, and does not start again '
                'until you open it. This is a real limitation of the current '
                'build, not a setting you can change.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            const Text(
                'Many Indian phones make this worse on purpose. Xiaomi/MIUI, '
                'Oppo, Vivo, Realme and OnePlus ship aggressive battery '
                'management that kills background work. If capture keeps '
                'going quiet, set Hisab’s battery usage to '
                '“Unrestricted” and enable Autostart where your '
                'phone offers it.',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 6),
            const Text(
                'The dashboard warns you after three days without an alert, '
                'so this fails loudly rather than silently.',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
          ]),
          _section('Check the parser', [
            const Text(sample,
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.black54)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _runTest,
              child: const Text('Test it',
                  style: TextStyle(color: HisabTheme.khataRed)),
            ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_testResult!,
                    key: const Key('capture-test-result'),
                    style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 6),
            const Text(
                'Runs the reader on a sample alert and shows what it got out. '
                'Nothing is stored.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: HisabTheme.ink)),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children),
              ),
            ),
          ],
        ),
      );

  Widget _warning(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.notifications_off,
                size: 16, color: HisabTheme.khataRed),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 12, color: HisabTheme.khataRed))),
          ],
        ),
      );

  void _runTest() {
    final memo = AlertParser.parse(sample, DateTime.now());
    if (memo == null) {
      setState(() =>
          _testResult = 'Could not read that alert. Nothing was stored.');
      return;
    }
    final parts = <String>[
      '${Money.formatPaise(memo.amountPaise)} '
          '${memo.direction == Direction.debit ? 'out' : 'in'}',
      'to ${memo.payee}',
      'on ${istDayLabel(memo.date)}',
    ];
    // Only when it adds something: this sample's payee IS its VPA, because the
    // alert names no merchant, and printing it twice reads like a bug.
    final vpa = memo.vpa;
    if (vpa != null && vpa != memo.payee.toLowerCase()) {
      parts.add('UPI $vpa');
    }
    if (memo.accountTail != null) {
      parts.add('a/c ••${memo.accountTail}');
    }
    setState(() => _testResult = 'Read: ${parts.join(', ')}.');
  }
}
