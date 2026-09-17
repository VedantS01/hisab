/// Balance-keyed synthetic reference. Port of SyntheticRef.swift — the
/// recipe is shared with iOS, so cross-platform imports dedup.
library;

import '../year_month.dart';

class SyntheticRef {
  static String make(
          {required int balancePaise,
          required DateTime date,
          required int amountPaise}) =>
      'B${balancePaise}D${istCompactDayString(date)}A$amountPaise';
}
