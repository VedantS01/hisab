import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

void main() {
  // 10 Nov 2026, 14:37 IST.
  final received = DateTime.utc(2026, 11, 10, 9, 7);
  String ist(DateTime d) {
    final c = istClock(d);
    return '${istDayString(d)} ${c.hour.toString().padLeft(2, '0')}:'
        '${c.minute.toString().padLeft(2, '0')}';
  }

  group('AlertCapture.date keeps the time of day', () {
    test('a time written in the alert wins', () {
      final d = AlertCapture.date('2026-11-10',
          receivedAt: received,
          text: 'Rs 450 debited on 10-11-26 at 13:05 IST');
      expect(ist(d), '2026-11-10 13:05');
    });

    test('12-hour clocks', () {
      expect(AlertCapture.timeOfDay('at 02:15 PM'), (14, 15));
      expect(AlertCapture.timeOfDay('at 12:40 am'), (0, 40));
      expect(AlertCapture.timeOfDay('9:05:12 a.m.'), (9, 5));
      expect(AlertCapture.timeOfDay('Rs. 1,250.00 on 10-11-26'), isNull);
    });

    test('dated the day it arrived: the arrival time', () {
      final d = AlertCapture.date('2026-11-10',
          receivedAt: received, text: 'Rs 450 debited on 10-11-26');
      expect(d, received);
    });

    test('dated an earlier day, no time written: that day, midnight', () {
      final d = AlertCapture.date('2026-11-08',
          receivedAt: received, text: 'Rs 450 debited on 08-11-26');
      expect(ist(d), '2026-11-08 00:00');
    });

    test('the day, and so the identity hash, is unchanged', () {
      const alert = ExtractedAlert(
        isTransaction: true,
        direction: Direction.debit,
        amountPaise: 45000,
        payee: 'Chaiwala',
        dateIso: '2026-11-10',
        classConfidence: 1,
      );
      final timed = AlertCapture.memo(alert, receivedAt: received, text: 'x')!;
      final dayOnly = AlertCapture.memo(alert,
          receivedAt: received.add(const Duration(hours: 3)))!;
      expect(timed.captureHash, dayOnly.captureHash);
      expect(timed.date, received);
    });
  });

  test('the parser keeps the arrival time and reads ISO dates as ISO', () {
    final memo = AlertParser.parse(
        'Rs 450.00 debited from a/c XX1234 to VPA chai@okaxis on 2026-11-10',
        received);
    expect(memo, isNotNull);
    expect(memo!.date, received);
  });
}
