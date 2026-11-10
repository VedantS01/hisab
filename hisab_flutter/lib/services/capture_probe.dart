/// Setup tests that go the whole way: a sample alert carrying a marker is
/// handed to the user's own shortcut or automation, comes back through the
/// "Add Transaction Alert" action exactly as a bank's would, and is read by
/// the same reader. [CaptureIntake] sees the marker, records what it read
/// here and stores nothing in the ledger; the setup screen shows the result.
library;

import 'dart:convert';
import 'dart:math';

import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What one test alert came back as.
class ProbeResult {
  final String id;
  final DateTime at;

  /// Whether capture was on: with it off, real alerts are declined.
  final bool captureOn;
  final int? amountPaise;
  final Direction? direction;
  final String? payee;
  final String? reference;
  final DateTime? date;

  const ProbeResult({
    required this.id,
    required this.at,
    required this.captureOn,
    this.amountPaise,
    this.direction,
    this.payee,
    this.reference,
    this.date,
  });

  bool get read => amountPaise != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'captureOn': captureOn,
        'amountPaise': amountPaise,
        'direction': direction?.name,
        'payee': payee,
        'reference': reference,
        'date': date?.millisecondsSinceEpoch,
      };

  static ProbeResult fromJson(Map<String, Object?> j) {
    DateTime? ms(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true) : null;
    final dir = j['direction'] as String?;
    return ProbeResult(
      id: j['id'] as String,
      at: ms(j['at'])!,
      captureOn: j['captureOn'] as bool? ?? false,
      amountPaise: j['amountPaise'] as int?,
      direction: dir == null ? null : Direction.values.byName(dir),
      payee: j['payee'] as String?,
      reference: j['reference'] as String?,
      date: ms(j['date']),
    );
  }
}

abstract final class CaptureProbe {
  static const marker = 'HISAB-TEST-';
  static const _key = 'capture.probe';
  static final _id = RegExp('$marker([A-Za-z0-9]+)');

  /// The test id in [text], or null for a real alert.
  static String? idIn(String text) => _id.firstMatch(text)?.group(1);

  static String newId() =>
      Random().nextInt(1 << 30).toRadixString(36).padLeft(6, '0');

  /// A ₹1 debit dated and timed [now] in IST, shaped like a bank SMS, so the
  /// readout can show the time was kept as well as the day.
  static String sample(String id, DateTime now) {
    final c = istClock(now);
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Rs.1.00 debited from a/c XX0000 on '
        '${two(c.day)}-${two(c.month)}-${two(c.year % 100)} at '
        '${two(c.hour)}:${two(c.minute)} to VPA hisab.test@upi. '
        'UPI Ref No 000000000001. $marker$id';
  }

  static Future<void> record(ProbeResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(result.toJson()));
  }

  /// The latest test result. Reloaded: on iOS the Shortcuts action runs in
  /// another engine, which writes behind this one's cache.
  static Future<ProbeResult?> last() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return ProbeResult.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }
}
