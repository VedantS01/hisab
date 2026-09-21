import 'dart:io';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

String bundledConfigJson() =>
    File('../../assets/insights/insights-config.json').readAsStringSync();

void main() {
  group('InsightsConfig', () {
    test('bundled config parses with the same values Swift asserts', () {
      final config = InsightsConfig.fromJsonString(bundledConfigJson());
      expect(config.version, 1);
      expect(config.trend.minPct, 25);
      expect(config.trend.minAbsPaise, 50000);
      expect(config.recurrence.minOccurrences, 3);
      expect(config.anomaly.lookbackDays, 35);
      expect(config.ranker.maxCards, 5);
      expect(config.ranker.maxPerType, 3);
    });

    test('bundled config equals the compiled fallback', () {
      expect(InsightsConfig.fromJsonString(bundledConfigJson()),
          InsightsConfig.fallback);
    });
  });
}
