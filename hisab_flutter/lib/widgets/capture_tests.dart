/// "Test your setup": checks that prove each part of capture works, by
/// running it. The reader test reads text in the app; on iOS the shortcut and
/// SMS tests send a marked sample through the user's own shortcut or
/// automation and wait for it to come back ([CaptureProbe]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/design.dart';
import '../services/capture_intake.dart';
import '../services/capture_probe.dart';
import '../services/notification_capture.dart';
import 'memo_review_sheet.dart' show istStamp;

/// The share-sheet shortcut's name, as the setup steps tell the user to
/// spell it; the shortcut test runs it by name.
const shareShortcutName = 'Log to Hisab';

enum _Probe { shortcut, sms }

class CaptureTests extends StatefulWidget {
  /// Called when a round trip passes, so the screen can tick its step.
  final void Function(String which)? onPassed;
  const CaptureTests({super.key, this.onPassed});

  @override
  State<CaptureTests> createState() => _CaptureTestsState();
}

class _CaptureTestsState extends State<CaptureTests>
    with WidgetsBindingObserver {
  final _waiting = <_Probe, (String id, DateTime sent)>{};
  final _results = <_Probe, ProbeResult>{};
  final _missed = <_Probe>{};
  Timer? _poll;

  static const _waitFor = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(resumed: true);
  }

  Future<void> _start(_Probe which) async {
    final now = DateTime.now();
    final id = CaptureProbe.newId();
    final sample = CaptureProbe.sample(id, now);
    setState(() {
      _waiting[which] = (id, now);
      _results.remove(which);
      _missed.remove(which);
    });
    _poll ??= Timer.periodic(const Duration(seconds: 3), (_) => _check());
    final uri = switch (which) {
      _Probe.shortcut => Uri.parse('shortcuts://x-callback-url/run-shortcut'
          '?name=${Uri.encodeComponent(shareShortcutName)}'
          '&input=text&text=${Uri.encodeComponent(sample)}'
          '&x-success=${Uri.encodeComponent('hisab://capture-test')}'
          '&x-error=${Uri.encodeComponent('hisab://capture-test')}'),
      _Probe.sms => Uri.parse('sms:&body=${Uri.encodeComponent(sample)}'),
    };
    if (!await launchUrl(uri) && mounted) {
      setState(() {
        _waiting.remove(which);
        _missed.add(which);
      });
    }
  }

  /// A result for a test in flight; past [_waitFor] (or, for the shortcut,
  /// once Shortcuts has handed back without one) the test has missed.
  Future<void> _check({bool resumed = false}) async {
    if (_waiting.isEmpty) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    final last = await CaptureProbe.last();
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      for (final which in List.of(_waiting.keys)) {
        final (id, sent) = _waiting[which]!;
        if (last != null && last.id == id) {
          _waiting.remove(which);
          _results[which] = last;
          if (last.read && last.captureOn) widget.onPassed?.call(which.name);
        } else if (now.difference(sent) > _waitFor) {
          _waiting.remove(which);
          _missed.add(which);
        }
      }
    });
    // Shortcuts returns only after the action has run and written its result,
    // so coming back with nothing means it never reached Hisab.
    if (resumed && _waiting.containsKey(_Probe.shortcut)) {
      Future.delayed(const Duration(seconds: 2), () async {
        if (!mounted || !_waiting.containsKey(_Probe.shortcut)) return;
        final again = await CaptureProbe.last();
        if (!mounted) return;
        final (id, _) = _waiting[_Probe.shortcut]!;
        if (again?.id != id) {
          setState(() {
            _waiting.remove(_Probe.shortcut);
            _missed.add(_Probe.shortcut);
          });
        } else {
          await _check();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Test your setup',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                'Each test sends a ₹1 sample that Hisab reads and then throws '
                'away. Nothing is saved to your ledger.',
                style: TextStyle(
                    fontSize: 13, color: context.hisab.textSecondary)),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.document_scanner_outlined,
              title: 'Reader',
              subtitle: 'Paste any bank SMS or email and see what Hisab reads.',
              action: 'Try',
              onAction: () => showReaderTest(context),
            ),
            if (ios) ...[
              _probeTile(
                _Probe.shortcut,
                icon: Icons.ios_share,
                title: 'Share shortcut',
                subtitle: 'Runs your “$shareShortcutName” shortcut with the '
                    'sample and comes back.',
                action: 'Run',
                missed: 'Nothing reached Hisab. Check the shortcut is named '
                    'exactly “$shareShortcutName” and its Hisab action’s '
                    'Alert Text is Shortcut Input.',
              ),
              _probeTile(
                _Probe.sms,
                icon: Icons.sms_outlined,
                title: 'SMS automation',
                subtitle: 'Opens Messages with the sample: send it to your own '
                    'number, then come back here.',
                action: 'Send',
                missed: 'No SMS reached Hisab in two minutes. Check the '
                    'automation’s Message Contains is Rs, it runs immediately, '
                    'and its Hisab action’s Alert Text is Shortcut Input.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String action,
    required VoidCallback? onAction,
    Widget? below,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconTile(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: context.hisab.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onAction, child: Text(action)),
          ]),
          if (below != null)
            Padding(
                padding: const EdgeInsets.only(left: 52, top: 6), child: below),
        ]),
      );

  Widget _probeTile(_Probe which,
      {required IconData icon,
      required String title,
      required String subtitle,
      required String action,
      required String missed}) {
    final waiting = _waiting.containsKey(which);
    final result = _results[which];
    final Widget? below = waiting
        ? Row(children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('Waiting for it to reach Hisab…',
                style: TextStyle(
                    fontSize: 12, color: context.hisab.textSecondary)),
          ])
        : result != null
            ? ProbeReadout(result: result, sentAt: result.at)
            : _missed.contains(which)
                ? _line(false, missed)
                : null;
    return _tile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      action: waiting ? 'Again' : action,
      onAction: () => _start(which),
      below: below,
    );
  }

  Widget _line(bool ok, String text) => _CheckLine(ok: ok, text: text);
}

class _CheckLine extends StatelessWidget {
  final bool ok;
  final String text;
  const _CheckLine({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              size: 16,
              color: ok ? context.hisab.credit : context.hisab.brandText),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

/// What a sample came back as, field by field, each ticked when it is what
/// was sent: ₹1.00, a debit, and the minute it was sent.
class ProbeReadout extends StatelessWidget {
  final ProbeResult result;
  final DateTime sentAt;
  const ProbeReadout({super.key, required this.result, required this.sentAt});

  @override
  Widget build(BuildContext context) {
    if (!result.read) {
      return const _CheckLine(
          ok: false,
          text: 'It reached Hisab, but no payment was read in it. Report a '
              'problem below.');
    }
    final date = result.date;
    final sent = istClock(sentAt), got = date == null ? null : istClock(date);
    final timeOk = got != null &&
        got.year == sent.year &&
        got.month == sent.month &&
        got.day == sent.day &&
        got.hour == sent.hour &&
        got.minute == sent.minute;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!result.captureOn)
        const _CheckLine(
            ok: false,
            text: 'Capture is off: real alerts would be declined. Turn it on '
                'above.'),
      _CheckLine(ok: true, text: 'Reached Hisab · ${istStamp(result.at)}'),
      _CheckLine(
          ok: result.amountPaise == 100,
          text: 'Amount ${Money.formatPaise(result.amountPaise ?? 0)}'),
      _CheckLine(
          ok: result.direction == Direction.debit,
          text:
              result.direction == Direction.credit ? 'Money in' : 'Money out'),
      if (result.payee != null)
        _CheckLine(ok: true, text: 'To ${result.payee}'),
      if (result.reference != null)
        _CheckLine(ok: true, text: 'Ref ${result.reference}'),
      _CheckLine(
          ok: timeOk,
          text: date == null
              ? 'No date read'
              : 'When ${istStamp(date)}${timeOk ? '' : ' (expected the time it was sent)'}'),
    ]);
  }
}

/// Paste an alert, see what Hisab reads — nothing saved.
Future<void> showReaderTest(BuildContext context) {
  final text = TextEditingController(
      text: CaptureProbe.sample('', DateTime.now())
          .replaceAll(' ${CaptureProbe.marker}', ''));
  ProbeResult? result;
  var busy = false;
  return showHisabSheet<void>(
    context: context,
    title: 'Reader test',
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: text,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Paste a bank SMS or email'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setSheet(() => busy = true);
                      final now = DateTime.now();
                      final (memo, row) = await CaptureIntake.read(text.text,
                          now, await NotificationCapture.extractor());
                      setSheet(() {
                        busy = false;
                        result = ProbeResult(
                          id: '',
                          at: now,
                          captureOn: true,
                          amountPaise: memo?.amountPaise ?? row?.amountPaise,
                          direction: memo?.direction ?? row?.direction,
                          payee: memo?.payee ?? row?.counterparty,
                          reference: row?.reference,
                          date: memo?.date ?? row?.date,
                        );
                      });
                    },
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Read it'),
            ),
            if (result != null) ...[
              const SizedBox(height: 12),
              _ReaderResult(result: result!),
            ],
          ],
        ),
      ),
    ),
  ).whenComplete(text.dispose);
}

class _ReaderResult extends StatelessWidget {
  final ProbeResult result;
  const _ReaderResult({required this.result});

  @override
  Widget build(BuildContext context) {
    if (!result.read) {
      return const _CheckLine(
          ok: false, text: 'No payment found in that text.');
    }
    final date = result.date;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _CheckLine(
          ok: true,
          text:
              '${result.direction == Direction.credit ? 'Money in' : 'Money out'}'
              ' · ${Money.formatPaise(result.amountPaise!)}'),
      _CheckLine(
          ok: result.payee != null, text: 'Payee ${result.payee ?? '—'}'),
      _CheckLine(
          ok: result.reference != null,
          text: 'Ref ${result.reference ?? '— (matched by amount and date)'}'),
      _CheckLine(
          ok: date != null,
          text: 'When ${date == null ? '—' : istStamp(date)}'),
    ]);
  }
}
