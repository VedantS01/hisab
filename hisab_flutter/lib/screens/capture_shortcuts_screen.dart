/// Capture setup on iOS: alerts reach Hisab through a Shortcuts automation the
/// user builds, so this screen is the walkthrough plus a check of what Hisab
/// can see from its side. Twin of the Swift app's CaptureSetupView and
/// CaptureSystemCheck; the step text is theirs.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/design.dart';
import '../services/capture_notifier.dart';
import '../services/capture_prefs.dart';
import '../services/notification_capture.dart';
import '../state.dart';

class CaptureShortcutsScreen extends StatefulWidget {
  const CaptureShortcutsScreen({super.key});

  @override
  State<CaptureShortcutsScreen> createState() => _CaptureShortcutsScreenState();
}

class _CaptureShortcutsScreenState extends State<CaptureShortcutsScreen>
    with WidgetsBindingObserver {
  bool _enabled = false;
  bool _notificationsAllowed = false;
  bool? _readerWorks;
  (IntakeOutcome, DateTime)? _last;

  static const _sample = 'Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA '
      'vedant@okaxis. UPI Ref No 627775786529';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Shortcuts or Settings: the answers may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await CapturePrefs.isEnabled();
    final allowed = await CaptureNotifier.areNotificationsEnabled();
    final last = await CapturePrefs.lastOutcome();
    final extractor = await NotificationCapture.extractor();
    bool works = false;
    try {
      works = (await extractor?.extract(_sample))?.amountPaise == 45000;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _notificationsAllowed = allowed;
      _last = last;
      _readerWorks = works;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Capture setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('System check', [
            _check('Capture', _enabled, _enabled ? 'On' : 'Off'),
            _check('Reader', _readerWorks ?? true,
                switch (_readerWorks) {
                  null => 'Checking…',
                  true => 'Working',
                  false => 'Unavailable — the basic parser reads alerts',
                }),
            _check('Last alert', _last?.$1 != IntakeOutcome.saveFailed,
                _lastAlertText()),
            _check('Notifications', _notificationsAllowed,
                _notificationsAllowed
                    ? 'Allowed'
                    : 'Off — turn them on in iOS Settings › Notifications › Hisab'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _report,
                child: Text('Report a problem',
                    style: TextStyle(color: context.hisab.brandText)),
              ),
            ),
          ]),
          _section('Capture bank alerts', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Capture bank alerts'),
              value: _enabled,
              onChanged: (value) async {
                await CaptureNotifier.setEnabled(value,
                    db: state.db, ruleset: state.ruleset);
                await _refresh();
              },
            ),
            _note('With this off, the Shortcuts action still runs but declines '
                'the alert and stores nothing.'),
          ]),
          _section('Step 1 — bank SMS', [
            _step(1, 'Open Shortcuts › Automation and create a new automation '
                'with the Message trigger.'),
            _step(2, 'Set Message Contains to Rs, and leave Sender empty. Banks '
                'text from IDs like HDFCBK, which iOS cannot save as a contact, '
                'so a sender filter would never match.'),
            _step(3, 'Set it to run immediately, without asking for confirmation.'),
            _step(4, 'Add exactly one action: Hisab › Add Transaction Alert, '
                'with its Alert Text set to Shortcut Input (the message).'),
            _step(5, 'Leave Note empty. Anything you put there is saved word for '
                'word, so it is for a short note of your own — never the '
                'message body.'),
            _step(6, 'Make a second automation, the same in every way except '
                'that Message Contains is INR.'),
            _note('Between them, Rs and INR catch nearly every bank and UPI SMS. '
                'The automation also runs on an OTP, an offer or a friend\'s text '
                'that mentions Rs; Hisab finds no payment in it and stores '
                'nothing.'),
          ]),
          _section('Step 2 — bank emails (Gmail)', [
            _step(1, 'Add your Gmail account to Apple\'s Mail app: Settings › '
                'Apps › Mail › Mail Accounts › Add Account › Google, with Mail '
                'switched on. The Email trigger only sees mail that arrives in '
                'Apple Mail.'),
            _step(2, 'In Mail Accounts › Fetch New Data, set the Gmail account to '
                'Fetch and the schedule to Every 15 Minutes.'),
            _step(3, 'In Shortcuts, create a new automation with the Email '
                'trigger. Set Account to your Gmail account.'),
            _step(4, 'Set Sender to the address your bank\'s alerts come from. '
                'Add every bank\'s address to the same automation.'),
            _step(5, 'Set it to run immediately, and add the same one action: '
                'Hisab › Add Transaction Alert, with Alert Text set to Shortcut '
                'Input (the email).'),
            _note('An email reaches Hisab when Mail fetches it, so expect up to '
                '15 minutes\' delay.'),
          ]),
          _section('Step 3 — the share-sheet fallback', [
            _step(1, 'In Shortcuts, tap + to create a new shortcut.'),
            _step(2, 'Turn on “Show in Share Sheet”, and set it to receive Text.'),
            _step(3, 'Add one action: Hisab › Add Transaction Alert, with '
                'Shortcut Input as the text.'),
            _step(4, 'Name it something like “Log to Hisab”.'),
            _note('Hisab does not appear in the share sheet on its own; iOS only '
                'offers a shortcut you have built. Once this exists you can '
                'select any alert\'s text, share it, and tap “Log to Hisab”.'),
          ]),
        ],
      ),
    );
  }

  String _lastAlertText() {
    final last = _last;
    if (last == null) return 'No alert has reached Hisab yet';
    final (outcome, at) = last;
    final what = switch (outcome) {
      IntakeOutcome.logged => 'Logged',
      IntakeOutcome.duplicate => 'Already logged',
      IntakeOutcome.notAPayment => 'Not a payment',
      IntakeOutcome.noText => 'The automation passed no text',
      IntakeOutcome.saveFailed => 'Could not be saved',
      IntakeOutcome.captureOff => 'Declined — capture was off',
    };
    return '$what · ${istDayLabel(at)}';
  }

  Future<void> _report() => launchUrl(Uri(
        scheme: 'mailto',
        path: FormatFingerprint.supportAddress,
        queryParameters: {
          'subject': 'Hisab capture problem',
          'body': 'Capture: ${_enabled ? 'on' : 'off'}\n'
              'Reader: ${_readerWorks == true ? 'working' : 'unavailable'}\n'
              'Last alert: ${_lastAlertText()}\n'
              'Notifications: ${_notificationsAllowed ? 'allowed' : 'off'}\n',
        },
      ));

  Widget _check(String label, bool ok, String detail) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? context.hisab.credit : context.hisab.brandText),
        title: Text(label),
        subtitle: Text(detail),
      );

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 22,
              child: Text('$n.',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(text)),
        ]),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: TextStyle(fontSize: 13, color: context.hisab.textSecondary)),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...children,
                ]),
          ),
        ),
      );
}
