/// When Hisab may interrupt the user about an uncategorized payment.
/// Port of `HisabCore/Sources/HisabCore/Capture/NotificationPolicy.swift`.
library;

import '../year_month.dart';

sealed class NotificationDecision {
  const NotificationDecision();
}

class NotificationSend extends NotificationDecision {
  const NotificationSend();

  @override
  bool operator ==(Object other) => other is NotificationSend;

  @override
  int get hashCode => 0x5E4D;

  @override
  String toString() => 'send';
}

/// Held so Hisab never wakes anyone; deliver at this instant instead.
class NotificationHold extends NotificationDecision {
  final DateTime until;
  const NotificationHold(this.until);

  @override
  bool operator ==(Object other) =>
      other is NotificationHold &&
      other.until.toUtc() == until.toUtc();

  @override
  int get hashCode => until.toUtc().hashCode;

  @override
  String toString() => 'hold(until: ${until.toUtc().toIso8601String()})';
}

/// Today's budget is spent. The needs-review inbox still carries the memo,
/// so nothing is lost — only the interruption is dropped.
class NotificationSuppress extends NotificationDecision {
  const NotificationSuppress();

  @override
  bool operator ==(Object other) => other is NotificationSuppress;

  @override
  int get hashCode => 0x5099;

  @override
  String toString() => 'suppress';
}

class NotificationPolicy {
  static const int dailyCap = 10;
  static const int quietStartHour = 22;
  static const int quietEndHour = 8;

  /// The cap is checked BEFORE quiet hours, exactly as in Swift: once the
  /// day's budget is spent there is nothing to schedule, so a late-night
  /// alert past the cap is suppressed rather than held until morning.
  static NotificationDecision decide(
      {required DateTime now, required int sentToday}) {
    if (sentToday >= dailyCap) return const NotificationSuppress();
    final clock = istClock(now);
    final hour = clock.hour;
    if (!(hour >= quietStartHour || hour < quietEndHour)) {
      return const NotificationSend();
    }

    // Before 08:00 the hold lands today; from 22:00 it lands tomorrow.
    // `DateTime.utc` normalises a day overflow, which is the IST-calendar
    // `date(byAdding: .day, value: 1)` the Swift side performs — IST is a
    // fixed offset with no DST, so no timezone database is involved.
    final day = hour < quietEndHour ? clock.day : clock.day + 1;
    final until =
        DateTime.utc(clock.year, clock.month, day, quietEndHour)
            .subtract(istOffset);
    return NotificationHold(until);
  }
}
