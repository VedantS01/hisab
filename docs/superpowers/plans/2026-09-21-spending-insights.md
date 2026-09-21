# Spending Insights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface neutral, factual observations about the user's own spending as a "For you" card strip on the dashboard of both apps, computed entirely on-device from already-imported statements.

**Architecture:** A pure function in each core — `InsightsEngine.generate(input:config:suppressions:)` — runs three independent detectors (trend, recurrence, anomaly) over the same visible-transaction projection analytics already uses, then a ranker applies collision rules, suppressions, and caps. Nothing derived is persisted; the only stored state is user intent (dismissed insight ids, muted merchants/categories) in UserDefaults / SharedPreferences. Thresholds live in one bundled JSON synced between the two cores.

**Tech Stack:** Swift 6 (HisabCore, SwiftUI app), Dart/Flutter (hisab_core, Flutter app), XCTest, `package:test`, JSON resources bundled via SwiftPM `.copy("Resources")` and Flutter assets.

**Spec:** `docs/superpowers/specs/2026-09-18-spending-insights-design.md`

## Global Constraints

- **Zero network, always.** No new dependencies that touch the network; no notifications, no permissions. Violating this breaks the store-compliance posture.
- **Two cores, byte-identical behavior.** Every core type and function added in Swift gets a Dart twin with the same name, same field names, same order of operations. The Swift sources are the executable specification.
- **Integer arithmetic only for anything that affects ordering or ids.** No `Double` in scores — floating point risks cross-platform ordering drift. Scores are `Int64` (Swift) / `int` (Dart).
- **Money is integer paise** throughout; format for display only via `Money.formatPaise`.
- **Dates resolve in IST.** Use `YearMonth.istCalendar` (Swift) / `istClock`, `istDayString` (Dart).
- **Copy is generated in core**, not in the UI, so both platforms render identical sentences and the parity fixture can assert them.
- **Tone: neutral observation only.** Amounts, percentages, dates. No advice verbs ("consider", "you should", "save"), no judgment words ("overspending", "too much"). This is a compliance requirement, not a style preference.
- **Conservative by default.** When a signal is ambiguous (no baseline, too few priors, a partial month), emit nothing.
- **Commit after every task** with the repo's trailer:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF
  ```
- **CPU gate before any compile or test suite:** `J=$(~/.claude/scripts/cpu-gate.sh)` then cap parallelism at `$J`.
- **Dart tests mirror the Swift tests case-for-case.** Where a task spells out Swift test code and then says "mirror it", write every case out in Dart with the *same* assertions and the same expected strings — the Swift block is the source of truth for what the numbers and copy must be. Never skip a case, and never weaken an assertion to make it pass; a divergence means the port is wrong.
- **Median convention:** for an even-length sorted list, take the lower median (`sorted[(n - 1) / 2]`, integer division). Both platforms must use it or the parity fixture will disagree.

## File Structure

**Swift core** — `HisabCore/Sources/HisabCore/Insights/`
| File | Responsibility |
|---|---|
| `InsightsConfig.swift` | Codable thresholds + bundled loader + fallback |
| `Insight.swift` | `InsightKind`, `MuteTarget`, `RecurringSeries`, `Insight`, `InsightRecord`, `InsightsInput`, `Suppressions`, `InsightsResult`, id derivation |
| `CompleteMonths.swift` | Months fully covered by a statement period; `ISTDay` helper |
| `TrendDetector.swift` | Category month-over-average deltas |
| `RecurrenceDetector.swift` | Series discovery → new / changed / committed |
| `AnomalyDetector.swift` | Possible duplicates + amount outliers |
| `InsightsEngine.swift` | Orchestration: detectors → collisions → suppression → ranking |

**Swift resource** — `HisabCore/Sources/HisabCore/Resources/insights/insights-config.json`

**Dart core** — `hisab_flutter/packages/hisab_core/lib/src/insights/` with the same seven filenames in snake_case (`insights_config.dart`, `insight.dart`, `complete_months.dart`, `trend_detector.dart`, `recurrence_detector.dart`, `anomaly_detector.dart`, `insights_engine.dart`), exported from `lib/hisab_core.dart`.

**iOS app** — `Hisab/Services/InsightStore.swift` (suppression persistence), `Hisab/Views/Components/InsightStrip.swift` (strip + cards), `Hisab/Views/InsightEvidenceSheet.swift`; modifications to `Hisab/Services/Queries.swift` and `Hisab/Views/DashboardView.swift`.

**Flutter app** — `hisab_flutter/lib/services/insight_store.dart`, `hisab_flutter/lib/widgets/insight_strip.dart`, `hisab_flutter/lib/widgets/insight_evidence_sheet.dart`; modifications to `lib/services/queries.dart`, `lib/screens/dashboard_screen.dart`, `lib/main.dart`, `pubspec.yaml`.

**Shared test fixture** — `HisabCore/Tests/HisabCoreTests/Fixtures/insights-parity.json`, copied to `hisab_flutter/packages/hisab_core/test/fixtures/` by `tool/sync_assets.sh`.

---

### Task 1: Config asset and loaders

**Files:**
- Create: `HisabCore/Sources/HisabCore/Resources/insights/insights-config.json`
- Create: `HisabCore/Sources/HisabCore/Insights/InsightsConfig.swift`
- Create: `hisab_flutter/packages/hisab_core/lib/src/insights/insights_config.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (add export)
- Modify: `tool/sync_assets.sh` (sync the new resource directory)
- Modify: `hisab_flutter/pubspec.yaml` (declare `assets/insights/`)
- Test: `HisabCore/Tests/HisabCoreTests/InsightsConfigTests.swift`
- Test: `hisab_flutter/packages/hisab_core/test/insights_test.dart`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `InsightsConfig` with nested `Trend`, `Recurrence`, `Anomaly`, `Ranker`; `InsightsConfig.bundled()` (Swift), `InsightsConfig.fromJsonString(String)` (Dart), `InsightsConfig.fallback` on both. Weight keys are the `InsightKind` raw values from Task 2: `trend`, `recurringNew`, `recurringChanged`, `committedSpend`, `possibleDuplicate`, `outlierAmount`.

- [ ] **Step 1: Write the config JSON**

Create `HisabCore/Sources/HisabCore/Resources/insights/insights-config.json`:

```json
{
  "version": 1,
  "trend": {
    "minPct": 25,
    "minAbsPaise": 50000,
    "windowMonths": 3,
    "concentrationPct": 70
  },
  "recurrence": {
    "minOccurrences": 3,
    "monthlyMinDays": 28,
    "monthlyMaxDays": 33,
    "weeklyMinDays": 6,
    "weeklyMaxDays": 8,
    "amountSpreadPct": 15,
    "changedPct": 10,
    "newWithinMonths": 2,
    "activeWithinCadences": 2
  },
  "anomaly": {
    "outlierMultiple": 3,
    "outlierMinPaise": 100000,
    "minPriors": 5,
    "lookbackDays": 35,
    "duplicateWindowMinutes": 10
  },
  "ranker": {
    "maxCards": 5,
    "maxPerType": 3,
    "weights": {
      "possibleDuplicate": 4,
      "recurringNew": 3,
      "recurringChanged": 3,
      "outlierAmount": 2,
      "trend": 1,
      "committedSpend": 0
    }
  }
}
```

- [ ] **Step 2: Write the failing Swift test**

Create `HisabCore/Tests/HisabCoreTests/InsightsConfigTests.swift`:

```swift
import XCTest
@testable import HisabCore

final class InsightsConfigTests: XCTestCase {
    func testBundledConfigLoadsWithSaneValues() {
        let config = InsightsConfig.bundled()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.trend.minPct, 25)
        XCTAssertEqual(config.trend.minAbsPaise, 50_000)
        XCTAssertEqual(config.recurrence.minOccurrences, 3)
        XCTAssertEqual(config.anomaly.lookbackDays, 35)
        XCTAssertEqual(config.ranker.maxCards, 5)
        XCTAssertEqual(config.ranker.maxPerType, 3)
    }

    func testBundledConfigMatchesTheCompiledFallback() {
        // The fallback exists only for a missing resource; if the two ever
        // diverge, tuning would silently depend on which one loaded.
        XCTAssertEqual(InsightsConfig.bundled(), InsightsConfig.fallback)
    }

    func testEveryInsightKindHasARankerWeight() {
        let config = InsightsConfig.bundled()
        for kind in InsightKind.allCases {
            XCTAssertNotNil(config.ranker.weights[kind.rawValue],
                            "missing ranker weight for \(kind.rawValue)")
        }
    }
}
```

Note: `testEveryInsightKindHasARankerWeight` will not compile until Task 2 adds `InsightKind`. Comment that one test out for this task and uncomment it as the final step of Task 2 (the step list there says so).

- [ ] **Step 3: Run the Swift test to verify it fails**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter InsightsConfigTests`
Expected: FAIL — "cannot find 'InsightsConfig' in scope".

- [ ] **Step 4: Implement the Swift config**

Create `HisabCore/Sources/HisabCore/Insights/InsightsConfig.swift`:

```swift
import Foundation

/// Tunable thresholds for the insight detectors. Bundled as
/// Resources/insights/insights-config.json and synced into the Flutter
/// assets — numbers only, never logic, so tuning ships by editing one
/// file rather than two codebases.
public struct InsightsConfig: Codable, Sendable, Equatable {
    public struct Trend: Codable, Sendable, Equatable {
        public var minPct: Int
        public var minAbsPaise: Int64
        public var windowMonths: Int
        public var concentrationPct: Int
    }

    public struct Recurrence: Codable, Sendable, Equatable {
        public var minOccurrences: Int
        public var monthlyMinDays: Int
        public var monthlyMaxDays: Int
        public var weeklyMinDays: Int
        public var weeklyMaxDays: Int
        public var amountSpreadPct: Int
        public var changedPct: Int
        public var newWithinMonths: Int
        /// A series counts as active while its last payment is within this
        /// many cadence-lengths of now; cancelled subscriptions age out.
        public var activeWithinCadences: Int
    }

    public struct Anomaly: Codable, Sendable, Equatable {
        public var outlierMultiple: Int
        public var outlierMinPaise: Int64
        public var minPriors: Int
        public var lookbackDays: Int
        public var duplicateWindowMinutes: Int
    }

    public struct Ranker: Codable, Sendable, Equatable {
        public var maxCards: Int
        public var maxPerType: Int
        /// Keyed by InsightKind.rawValue. Integers: scores must stay exact.
        public var weights: [String: Int64]
    }

    public var version: Int
    public var trend: Trend
    public var recurrence: Recurrence
    public var anomaly: Anomaly
    public var ranker: Ranker

    public static func bundled() -> InsightsConfig {
        if let url = Bundle.module.url(forResource: "insights-config", withExtension: "json",
                                       subdirectory: "Resources/insights"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(InsightsConfig.self, from: data) {
            return config
        }
        return fallback
    }

    /// Mirrors the bundled JSON exactly; used only if the resource is missing.
    public static let fallback = InsightsConfig(
        version: 1,
        trend: Trend(minPct: 25, minAbsPaise: 50_000, windowMonths: 3,
                     concentrationPct: 70),
        recurrence: Recurrence(minOccurrences: 3, monthlyMinDays: 28, monthlyMaxDays: 33,
                               weeklyMinDays: 6, weeklyMaxDays: 8, amountSpreadPct: 15,
                               changedPct: 10, newWithinMonths: 2, activeWithinCadences: 2),
        anomaly: Anomaly(outlierMultiple: 3, outlierMinPaise: 100_000, minPriors: 5,
                         lookbackDays: 35, duplicateWindowMinutes: 10),
        ranker: Ranker(maxCards: 5, maxPerType: 3,
                       weights: ["possibleDuplicate": 4, "recurringNew": 3,
                                 "recurringChanged": 3, "outlierAmount": 2,
                                 "trend": 1, "committedSpend": 0]))
}
```

- [ ] **Step 5: Run the Swift test to verify it passes**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter InsightsConfigTests`
Expected: PASS (2 tests, the third still commented out).

- [ ] **Step 6: Wire the asset sync and declare the Flutter asset**

In `tool/sync_assets.sh`, add the insights pair. Change the three variable definitions and both loops so the file reads:

```bash
SRC_FORMATS="HisabCore/Sources/HisabCore/Resources/formats"
SRC_RULESETS="HisabCore/Sources/HisabCore/Resources/rulesets"
SRC_INSIGHTS="HisabCore/Sources/HisabCore/Resources/insights"
SRC_FIXTURES="HisabCore/Tests/HisabCoreTests/Fixtures"
DST_FORMATS="hisab_flutter/assets/formats"
DST_RULESETS="hisab_flutter/assets/rulesets"
DST_INSIGHTS="hisab_flutter/assets/insights"
DST_FIXTURES="hisab_flutter/packages/hisab_core/test/fixtures"
```

and add `"$SRC_INSIGHTS:$DST_INSIGHTS"` to the `--check` loop's pair list, plus the three copy lines at the bottom:

```bash
rm -rf "$DST_FORMATS" "$DST_RULESETS" "$DST_INSIGHTS" "$DST_FIXTURES"
mkdir -p "$DST_FORMATS" "$DST_RULESETS" "$DST_INSIGHTS" "$DST_FIXTURES"
cp "$SRC_FORMATS"/* "$DST_FORMATS"/
cp "$SRC_RULESETS"/* "$DST_RULESETS"/
cp "$SRC_INSIGHTS"/* "$DST_INSIGHTS"/
cp "$SRC_FIXTURES"/* "$DST_FIXTURES"/
echo "synced formats, rulesets, insights, fixtures"
```

In `hisab_flutter/pubspec.yaml`, add `    - assets/insights/` to the `assets:` list, after `- assets/rulesets/`.

Then run: `tool/sync_assets.sh`
Expected: prints `synced formats, rulesets, insights, fixtures`, and `hisab_flutter/assets/insights/insights-config.json` now exists.

- [ ] **Step 7: Write the failing Dart test**

Create `hisab_flutter/packages/hisab_core/test/insights_test.dart`:

```dart
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
```

- [ ] **Step 8: Run the Dart test to verify it fails**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: FAIL — `InsightsConfig` is undefined.

- [ ] **Step 9: Implement the Dart config**

Create `hisab_flutter/packages/hisab_core/lib/src/insights/insights_config.dart`:

```dart
/// Tunable thresholds for the insight detectors. Port of
/// InsightsConfig.swift; the bundled JSON is the same file, synced by
/// tool/sync_assets.sh.
library;

import 'dart:convert';

class TrendConfig {
  final int minPct;
  final int minAbsPaise;
  final int windowMonths;
  final int concentrationPct;
  const TrendConfig({
    required this.minPct,
    required this.minAbsPaise,
    required this.windowMonths,
    required this.concentrationPct,
  });

  factory TrendConfig.fromJson(Map<String, dynamic> j) => TrendConfig(
        minPct: j['minPct'] as int,
        minAbsPaise: j['minAbsPaise'] as int,
        windowMonths: j['windowMonths'] as int,
        concentrationPct: j['concentrationPct'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is TrendConfig &&
      other.minPct == minPct &&
      other.minAbsPaise == minAbsPaise &&
      other.windowMonths == windowMonths &&
      other.concentrationPct == concentrationPct;

  @override
  int get hashCode =>
      Object.hash(minPct, minAbsPaise, windowMonths, concentrationPct);
}

class RecurrenceConfig {
  final int minOccurrences;
  final int monthlyMinDays;
  final int monthlyMaxDays;
  final int weeklyMinDays;
  final int weeklyMaxDays;
  final int amountSpreadPct;
  final int changedPct;
  final int newWithinMonths;
  final int activeWithinCadences;
  const RecurrenceConfig({
    required this.minOccurrences,
    required this.monthlyMinDays,
    required this.monthlyMaxDays,
    required this.weeklyMinDays,
    required this.weeklyMaxDays,
    required this.amountSpreadPct,
    required this.changedPct,
    required this.newWithinMonths,
    required this.activeWithinCadences,
  });

  factory RecurrenceConfig.fromJson(Map<String, dynamic> j) => RecurrenceConfig(
        minOccurrences: j['minOccurrences'] as int,
        monthlyMinDays: j['monthlyMinDays'] as int,
        monthlyMaxDays: j['monthlyMaxDays'] as int,
        weeklyMinDays: j['weeklyMinDays'] as int,
        weeklyMaxDays: j['weeklyMaxDays'] as int,
        amountSpreadPct: j['amountSpreadPct'] as int,
        changedPct: j['changedPct'] as int,
        newWithinMonths: j['newWithinMonths'] as int,
        activeWithinCadences: j['activeWithinCadences'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is RecurrenceConfig &&
      other.minOccurrences == minOccurrences &&
      other.monthlyMinDays == monthlyMinDays &&
      other.monthlyMaxDays == monthlyMaxDays &&
      other.weeklyMinDays == weeklyMinDays &&
      other.weeklyMaxDays == weeklyMaxDays &&
      other.amountSpreadPct == amountSpreadPct &&
      other.changedPct == changedPct &&
      other.newWithinMonths == newWithinMonths &&
      other.activeWithinCadences == activeWithinCadences;

  @override
  int get hashCode => Object.hash(minOccurrences, monthlyMinDays, monthlyMaxDays,
      weeklyMinDays, weeklyMaxDays, amountSpreadPct, changedPct,
      newWithinMonths, activeWithinCadences);
}

class AnomalyConfig {
  final int outlierMultiple;
  final int outlierMinPaise;
  final int minPriors;
  final int lookbackDays;
  final int duplicateWindowMinutes;
  const AnomalyConfig({
    required this.outlierMultiple,
    required this.outlierMinPaise,
    required this.minPriors,
    required this.lookbackDays,
    required this.duplicateWindowMinutes,
  });

  factory AnomalyConfig.fromJson(Map<String, dynamic> j) => AnomalyConfig(
        outlierMultiple: j['outlierMultiple'] as int,
        outlierMinPaise: j['outlierMinPaise'] as int,
        minPriors: j['minPriors'] as int,
        lookbackDays: j['lookbackDays'] as int,
        duplicateWindowMinutes: j['duplicateWindowMinutes'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is AnomalyConfig &&
      other.outlierMultiple == outlierMultiple &&
      other.outlierMinPaise == outlierMinPaise &&
      other.minPriors == minPriors &&
      other.lookbackDays == lookbackDays &&
      other.duplicateWindowMinutes == duplicateWindowMinutes;

  @override
  int get hashCode => Object.hash(outlierMultiple, outlierMinPaise, minPriors,
      lookbackDays, duplicateWindowMinutes);
}

class RankerConfig {
  final int maxCards;
  final int maxPerType;

  /// Keyed by InsightKind.name. Integers: scores must stay exact.
  final Map<String, int> weights;
  const RankerConfig({
    required this.maxCards,
    required this.maxPerType,
    required this.weights,
  });

  factory RankerConfig.fromJson(Map<String, dynamic> j) => RankerConfig(
        maxCards: j['maxCards'] as int,
        maxPerType: j['maxPerType'] as int,
        weights: {
          for (final e in (j['weights'] as Map<String, dynamic>).entries)
            e.key: e.value as int
        },
      );

  @override
  bool operator ==(Object other) {
    if (other is! RankerConfig) return false;
    if (other.maxCards != maxCards || other.maxPerType != maxPerType) {
      return false;
    }
    if (other.weights.length != weights.length) return false;
    for (final e in weights.entries) {
      if (other.weights[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(maxCards, maxPerType, weights.length);
}

class InsightsConfig {
  final int version;
  final TrendConfig trend;
  final RecurrenceConfig recurrence;
  final AnomalyConfig anomaly;
  final RankerConfig ranker;
  const InsightsConfig({
    required this.version,
    required this.trend,
    required this.recurrence,
    required this.anomaly,
    required this.ranker,
  });

  factory InsightsConfig.fromJsonString(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    return InsightsConfig(
      version: j['version'] as int,
      trend: TrendConfig.fromJson(j['trend'] as Map<String, dynamic>),
      recurrence:
          RecurrenceConfig.fromJson(j['recurrence'] as Map<String, dynamic>),
      anomaly: AnomalyConfig.fromJson(j['anomaly'] as Map<String, dynamic>),
      ranker: RankerConfig.fromJson(j['ranker'] as Map<String, dynamic>),
    );
  }

  /// Mirrors the bundled JSON exactly; used only if the asset is missing.
  static const fallback = InsightsConfig(
    version: 1,
    trend: TrendConfig(
        minPct: 25, minAbsPaise: 50000, windowMonths: 3, concentrationPct: 70),
    recurrence: RecurrenceConfig(
        minOccurrences: 3,
        monthlyMinDays: 28,
        monthlyMaxDays: 33,
        weeklyMinDays: 6,
        weeklyMaxDays: 8,
        amountSpreadPct: 15,
        changedPct: 10,
        newWithinMonths: 2,
        activeWithinCadences: 2),
    anomaly: AnomalyConfig(
        outlierMultiple: 3,
        outlierMinPaise: 100000,
        minPriors: 5,
        lookbackDays: 35,
        duplicateWindowMinutes: 10),
    ranker: RankerConfig(maxCards: 5, maxPerType: 3, weights: {
      'possibleDuplicate': 4,
      'recurringNew': 3,
      'recurringChanged': 3,
      'outlierAmount': 2,
      'trend': 1,
      'committedSpend': 0,
    }),
  );

  @override
  bool operator ==(Object other) =>
      other is InsightsConfig &&
      other.version == version &&
      other.trend == trend &&
      other.recurrence == recurrence &&
      other.anomaly == anomaly &&
      other.ranker == ranker;

  @override
  int get hashCode => Object.hash(version, trend, recurrence, anomaly, ranker);
}
```

Add to `hisab_flutter/packages/hisab_core/lib/hisab_core.dart`, keeping the list alphabetical within its block:

```dart
export 'src/insights/insights_config.dart';
```

- [ ] **Step 10: Run the Dart test to verify it passes**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 11: Commit**

```bash
git add HisabCore/Sources/HisabCore/Resources/insights HisabCore/Sources/HisabCore/Insights HisabCore/Tests/HisabCoreTests/InsightsConfigTests.swift hisab_flutter/assets/insights hisab_flutter/packages/hisab_core/lib hisab_flutter/packages/hisab_core/test/insights_test.dart hisab_flutter/pubspec.yaml tool/sync_assets.sh
git commit -m "feat(insights): bundled threshold config in both cores

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 2: Insight model, IST day helper, and id derivation

**Files:**
- Create: `HisabCore/Sources/HisabCore/Insights/Insight.swift`
- Create: `hisab_flutter/packages/hisab_core/lib/src/insights/insight.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (export)
- Modify: `HisabCore/Tests/HisabCoreTests/InsightsConfigTests.swift` (uncomment the weights test)
- Test: `HisabCore/Tests/HisabCoreTests/InsightModelTests.swift`
- Test: `hisab_flutter/packages/hisab_core/test/insights_test.dart` (add a group)

**Interfaces:**
- Consumes: `InsightsConfig` (Task 1).
- Produces: `InsightKind` (raw values `trend`, `recurringNew`, `recurringChanged`, `committedSpend`, `possibleDuplicate`, `outlierAmount`), `Cadence` (`monthly`/`weekly`), `MuteTarget`, `RecurringSeries`, `Insight`, `InsightRecord`, `InsightsInput`, `Suppressions`, `InsightsResult`, `InsightID.make(_:)`, and in Swift only `ISTDay.string(_:)` / `ISTDay.daysBetween(_:_:)` (Dart already has `istDayString`; Dart gains `istDaysBetween`).

- [ ] **Step 1: Write the failing Swift test**

Create `HisabCore/Tests/HisabCoreTests/InsightModelTests.swift`:

```swift
import XCTest
@testable import HisabCore

final class InsightModelTests: XCTestCase {
    // Pinned so the Dart twin asserts the identical digests — the same
    // discipline as the content-hash pin tests.
    func testInsightIDsArePinnedAcrossPlatforms() {
        XCTAssertEqual(InsightID.make("trend|Food Delivery|2026-08|40"), "a84b5c10538a32a7")
        XCTAssertEqual(InsightID.make("recurring-new|netflix|64900"), "47007c34745ef802")
        XCTAssertEqual(InsightID.make("outlier|txn-42"), "0230759323d235ce")
    }

    func testKindRawValuesAreTheWireNames() {
        XCTAssertEqual(InsightKind.allCases.map(\.rawValue),
                       ["trend", "recurringNew", "recurringChanged",
                        "committedSpend", "possibleDuplicate", "outlierAmount"])
    }

    func testISTDayStringResolvesInIndianStandardTime() {
        // 2026-08-03 19:00 UTC is already 2026-08-04 in IST (+05:30).
        let date = Date(timeIntervalSince1970: 1_785_351_600)
        XCTAssertEqual(ISTDay.string(date), "2026-08-04")
    }

    func testISTDaysBetweenCountsCalendarDays() {
        let a = Date(timeIntervalSince1970: 1_785_000_000)
        let b = a.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(ISTDay.daysBetween(a, b), 3)
        XCTAssertEqual(ISTDay.daysBetween(b, a), -3)
    }
}
```

- [ ] **Step 2: Run the Swift test to verify it fails**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter InsightModelTests`
Expected: FAIL — "cannot find 'InsightID' in scope".

- [ ] **Step 3: Implement the Swift model**

Create `HisabCore/Sources/HisabCore/Insights/Insight.swift`:

```swift
import Foundation
import CryptoKit

/// "yyyy-MM-dd" and day arithmetic in IST — the same day key the content
/// hashes use, hoisted so the detectors don't each build a DateFormatter.
public enum ISTDay {
    public static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Whole IST calendar days from `from` to `to`; negative when `to` is earlier.
    public static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let cal = YearMonth.istCalendar
        let start = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

public enum InsightKind: String, Sendable, Codable, CaseIterable {
    case trend
    case recurringNew
    case recurringChanged
    case committedSpend
    case possibleDuplicate
    case outlierAmount
}

public enum Cadence: String, Sendable, Codable, Equatable {
    case monthly
    case weekly
}

/// What a card's overflow "don't show this" action suppresses.
public enum MuteTarget: Sendable, Equatable {
    case merchant(String)   // normalized merchant key
    case category(String)
}

public struct RecurringSeries: Sendable, Equatable {
    public let merchantKey: String
    public let displayMerchant: String
    public let cadence: Cadence
    public let medianPaise: Int64
    /// Weekly series are scaled by 52/12 so one number sums across cadences.
    public let monthlyEquivalentPaise: Int64
    public let firstSeen: Date
    public let lastSeen: Date
    public let count: Int
    public let transactionIDs: [String]

    public init(merchantKey: String, displayMerchant: String, cadence: Cadence,
                medianPaise: Int64, monthlyEquivalentPaise: Int64,
                firstSeen: Date, lastSeen: Date, count: Int, transactionIDs: [String]) {
        self.merchantKey = merchantKey
        self.displayMerchant = displayMerchant
        self.cadence = cadence
        self.medianPaise = medianPaise
        self.monthlyEquivalentPaise = monthlyEquivalentPaise
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.count = count
        self.transactionIDs = transactionIDs
    }
}

/// One card. Copy is generated in core so both platforms render the same
/// sentence and the parity fixture can assert it.
public struct Insight: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: InsightKind
    public let headline: String
    public let detail: String
    /// Transaction ids the card is evidence for; the evidence sheet lists them.
    public let evidenceIDs: [String]
    /// Populated for `.committedSpend` only.
    public let series: [RecurringSeries]
    public let score: Int64
    public let mute: MuteTarget?

    public init(id: String, kind: InsightKind, headline: String, detail: String,
                evidenceIDs: [String], series: [RecurringSeries] = [],
                score: Int64, mute: MuteTarget?) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.detail = detail
        self.evidenceIDs = evidenceIDs
        self.series = series
        self.score = score
        self.mute = mute
    }
}

/// One transaction as the insight engine sees it: the analytics projection
/// (deduped, self transfers excluded, matched bank rows excluded) plus the
/// row id so cards can point back at their evidence.
public struct InsightRecord: Sendable, Equatable {
    public let id: String
    public let date: Date
    public let amountPaise: Int64
    public let direction: Direction
    public let category: String
    public let merchant: String

    public init(id: String, date: Date, amountPaise: Int64, direction: Direction,
                category: String, merchant: String) {
        self.id = id
        self.date = date
        self.amountPaise = amountPaise
        self.direction = direction
        self.category = category
        self.merchant = merchant
    }
}

public struct InsightsInput: Sendable {
    public let records: [InsightRecord]
    /// Statement periods, used to decide which months are complete.
    public let documentPeriods: [DatePeriod]
    public let now: Date

    public init(records: [InsightRecord], documentPeriods: [DatePeriod], now: Date) {
        self.records = records
        self.documentPeriods = documentPeriods
        self.now = now
    }
}

public struct Suppressions: Sendable, Equatable {
    public var dismissedIDs: Set<String>
    public var mutedMerchants: Set<String>
    public var mutedCategories: Set<String>

    public init(dismissedIDs: Set<String> = [], mutedMerchants: Set<String> = [],
                mutedCategories: Set<String> = []) {
        self.dismissedIDs = dismissedIDs
        self.mutedMerchants = mutedMerchants
        self.mutedCategories = mutedCategories
    }
}

public struct InsightsResult: Sendable {
    /// Ranked, capped, suppression-applied — exactly what the strip shows.
    public let cards: [Insight]
    /// Every id generated this pass before suppression; the app prunes its
    /// dismissed set to this so stored ids can't grow without bound.
    public let allIDs: Set<String>

    public init(cards: [Insight], allIDs: Set<String>) {
        self.cards = cards
        self.allIDs = allIDs
    }
}

public enum InsightID {
    /// First 16 hex characters of SHA256 over the canonical string. Content
    /// derived, so a dismissed insight stays dismissed across recomputes but
    /// materially new numbers produce a new id.
    public static func make(_ canonical: String) -> String {
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}
```

- [ ] **Step 4: Run the Swift test to verify it passes**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter InsightModelTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Uncomment the config weights test and re-run**

In `HisabCore/Tests/HisabCoreTests/InsightsConfigTests.swift`, uncomment `testEveryInsightKindHasARankerWeight`.

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter InsightsConfigTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Write the failing Dart test**

Add to `hisab_flutter/packages/hisab_core/test/insights_test.dart`, inside `main()`:

```dart
  group('Insight model', () {
    test('insight ids match the digests pinned in Swift', () {
      expect(InsightID.make('trend|Food Delivery|2026-08|40'), 'a84b5c10538a32a7');
      expect(InsightID.make('recurring-new|netflix|64900'), '47007c34745ef802');
      expect(InsightID.make('outlier|txn-42'), '0230759323d235ce');
    });

    test('kind names are the wire names Swift pins', () {
      expect(InsightKind.values.map((k) => k.name).toList(), [
        'trend', 'recurringNew', 'recurringChanged',
        'committedSpend', 'possibleDuplicate', 'outlierAmount',
      ]);
    });

    test('istDaysBetween counts IST calendar days', () {
      final a = DateTime.fromMillisecondsSinceEpoch(1785000000 * 1000, isUtc: true);
      final b = a.add(const Duration(days: 3));
      expect(istDaysBetween(a, b), 3);
      expect(istDaysBetween(b, a), -3);
    });
  });
```

- [ ] **Step 7: Run the Dart test to verify it fails**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: FAIL — `InsightID` undefined.

- [ ] **Step 8: Implement the Dart model**

Add to `hisab_flutter/packages/hisab_core/lib/src/year_month.dart`, below `istCompactDayString`:

```dart
/// Whole IST calendar days from [from] to [to]; negative when [to] is earlier.
int istDaysBetween(DateTime from, DateTime to) {
  final a = istClock(from);
  final b = istClock(to);
  final dayA = DateTime.utc(a.year, a.month, a.day);
  final dayB = DateTime.utc(b.year, b.month, b.day);
  return dayB.difference(dayA).inDays;
}
```

Create `hisab_flutter/packages/hisab_core/lib/src/insights/insight.dart`:

```dart
/// Insight value types. Port of Insight.swift — field names, enum names and
/// the id recipe must stay identical; the pin tests enforce it.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain.dart';

enum InsightKind {
  trend,
  recurringNew,
  recurringChanged,
  committedSpend,
  possibleDuplicate,
  outlierAmount,
}

enum Cadence { monthly, weekly }

/// What a card's overflow "don't show this" action suppresses.
sealed class MuteTarget {
  const MuteTarget();
}

class MuteMerchant extends MuteTarget {
  final String merchantKey;
  const MuteMerchant(this.merchantKey);
  @override
  bool operator ==(Object other) =>
      other is MuteMerchant && other.merchantKey == merchantKey;
  @override
  int get hashCode => merchantKey.hashCode;
}

class MuteCategory extends MuteTarget {
  final String category;
  const MuteCategory(this.category);
  @override
  bool operator ==(Object other) =>
      other is MuteCategory && other.category == category;
  @override
  int get hashCode => category.hashCode;
}

class RecurringSeries {
  final String merchantKey;
  final String displayMerchant;
  final Cadence cadence;
  final int medianPaise;

  /// Weekly series are scaled by 52/12 so one number sums across cadences.
  final int monthlyEquivalentPaise;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int count;
  final List<String> transactionIDs;
  const RecurringSeries({
    required this.merchantKey,
    required this.displayMerchant,
    required this.cadence,
    required this.medianPaise,
    required this.monthlyEquivalentPaise,
    required this.firstSeen,
    required this.lastSeen,
    required this.count,
    required this.transactionIDs,
  });
}

/// One card. Copy is generated in core so both platforms render the same
/// sentence and the parity fixture can assert it.
class Insight {
  final String id;
  final InsightKind kind;
  final String headline;
  final String detail;

  /// Transaction ids the card is evidence for.
  final List<String> evidenceIDs;

  /// Populated for committedSpend only.
  final List<RecurringSeries> series;
  final int score;
  final MuteTarget? mute;
  const Insight({
    required this.id,
    required this.kind,
    required this.headline,
    required this.detail,
    required this.evidenceIDs,
    this.series = const [],
    required this.score,
    required this.mute,
  });
}

class InsightRecord {
  final String id;
  final DateTime date;
  final int amountPaise;
  final Direction direction;
  final String category;
  final String merchant;
  const InsightRecord({
    required this.id,
    required this.date,
    required this.amountPaise,
    required this.direction,
    required this.category,
    required this.merchant,
  });
}

class InsightsInput {
  final List<InsightRecord> records;
  final List<DatePeriod> documentPeriods;
  final DateTime now;
  const InsightsInput({
    required this.records,
    required this.documentPeriods,
    required this.now,
  });
}

class Suppressions {
  final Set<String> dismissedIDs;
  final Set<String> mutedMerchants;
  final Set<String> mutedCategories;
  const Suppressions({
    this.dismissedIDs = const {},
    this.mutedMerchants = const {},
    this.mutedCategories = const {},
  });
}

class InsightsResult {
  /// Ranked, capped, suppression-applied — exactly what the strip shows.
  final List<Insight> cards;

  /// Every id generated this pass before suppression; the app prunes its
  /// dismissed set to this.
  final Set<String> allIDs;
  const InsightsResult({required this.cards, required this.allIDs});
}

class InsightID {
  /// First 16 hex characters of SHA256 over the canonical string.
  static String make(String canonical) =>
      sha256.convert(utf8.encode(canonical)).toString().substring(0, 16);
}
```

Add the export to `hisab_flutter/packages/hisab_core/lib/hisab_core.dart`:

```dart
export 'src/insights/insight.dart';
```

- [ ] **Step 9: Run the Dart test to verify it passes**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: PASS (5 tests total in the file).

- [ ] **Step 10: Commit**

```bash
git add HisabCore/Sources/HisabCore/Insights HisabCore/Tests/HisabCoreTests hisab_flutter/packages/hisab_core
git commit -m "feat(insights): shared value types and content-derived ids

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 3: Complete-month detection

**Files:**
- Create: `HisabCore/Sources/HisabCore/Insights/CompleteMonths.swift`
- Create: `hisab_flutter/packages/hisab_core/lib/src/insights/complete_months.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (export)
- Test: `HisabCore/Tests/HisabCoreTests/CompleteMonthsTests.swift`
- Test: `hisab_flutter/packages/hisab_core/test/insights_test.dart` (add a group)

**Interfaces:**
- Consumes: `DatePeriod`, `YearMonth` (existing core types).
- Produces: `CompleteMonths.of(_ periods: [DatePeriod]) -> Set<YearMonth>` and `CompleteMonths.latest(_ periods: [DatePeriod], notAfter: Date) -> YearMonth?` (Swift); `CompleteMonths.of(List<DatePeriod>) -> Set<YearMonth>` and `CompleteMonths.latest(List<DatePeriod>, DateTime) -> YearMonth?` (Dart).

- [ ] **Step 1: Write the failing Swift test**

Create `HisabCore/Tests/HisabCoreTests/CompleteMonthsTests.swift`:

```swift
import XCTest
@testable import HisabCore

final class CompleteMonthsTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    func testAMonthIsCompleteOnlyWhenOnePeriodSpansItEntirely() {
        // Apr 1 – Jun 30 covers April and May fully; June ends exactly on the 30th.
        let period = DatePeriod(start: date("2026-04-01"), end: date("2026-06-30"))
        let months = CompleteMonths.of([period])
        XCTAssertEqual(months, [YearMonth(year: 2026, month: 4),
                                YearMonth(year: 2026, month: 5),
                                YearMonth(year: 2026, month: 6)])
    }

    func testPartialEdgeMonthsAreExcluded() {
        // The statement starts mid-April and stops mid-June: only May is whole.
        let period = DatePeriod(start: date("2026-04-15"), end: date("2026-06-14"))
        XCTAssertEqual(CompleteMonths.of([period]), [YearMonth(year: 2026, month: 5)])
    }

    func testLatestIgnoresMonthsAfterNow() {
        let period = DatePeriod(start: date("2026-01-01"), end: date("2026-12-31"))
        let latest = CompleteMonths.latest([period], notAfter: date("2026-09-10"))
        XCTAssertEqual(latest, YearMonth(year: 2026, month: 9))
    }

    func testNoPeriodsMeansNoCompleteMonths() {
        XCTAssertTrue(CompleteMonths.of([]).isEmpty)
        XCTAssertNil(CompleteMonths.latest([], notAfter: date("2026-09-10")))
    }
}
```

- [ ] **Step 2: Run the Swift test to verify it fails**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter CompleteMonthsTests`
Expected: FAIL — "cannot find 'CompleteMonths' in scope".

- [ ] **Step 3: Implement in Swift**

Create `HisabCore/Sources/HisabCore/Insights/CompleteMonths.swift`:

```swift
import Foundation

/// Which months a statement covers end to end. Every month-level comparison
/// uses these: the newest bucket is usually a partial statement, and
/// comparing a half-imported month against full ones is the classic
/// "spending down 60%!" lie.
public enum CompleteMonths {
    public static func of(_ periods: [DatePeriod]) -> Set<YearMonth> {
        var result: Set<YearMonth> = []
        for period in periods {
            for month in period.months {
                let edges = bounds(month)
                if period.start <= edges.start && period.end >= edges.end {
                    result.insert(month)
                }
            }
        }
        return result
    }

    /// Newest complete month that isn't in the future.
    public static func latest(_ periods: [DatePeriod], notAfter now: Date) -> YearMonth? {
        let cap = YearMonth(date: now)
        return of(periods).filter { $0 <= cap }.max()
    }

    /// First instant of the month and its last second, both in IST.
    static func bounds(_ month: YearMonth) -> (start: Date, end: Date) {
        let cal = YearMonth.istCalendar
        var comps = DateComponents()
        comps.year = month.year
        comps.month = month.month
        comps.day = 1
        let start = cal.date(from: comps)!
        let next = cal.date(byAdding: .month, value: 1, to: start)!
        return (start, next.addingTimeInterval(-1))
    }
}
```

- [ ] **Step 4: Run the Swift test to verify it passes**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter CompleteMonthsTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Write the failing Dart test**

Add to `hisab_flutter/packages/hisab_core/test/insights_test.dart`, inside `main()`:

```dart
  group('CompleteMonths', () {
    // IST midnight expressed as a UTC instant.
    DateTime ist(String yyyyMmDd) {
      final p = yyyyMmDd.split('-').map(int.parse).toList();
      return DateTime.utc(p[0], p[1], p[2]).subtract(istOffset);
    }

    test('a month is complete only when one period spans it entirely', () {
      final period = DatePeriod(ist('2026-04-01'), ist('2026-06-30'));
      expect(CompleteMonths.of([period]),
          {YearMonth(2026, 4), YearMonth(2026, 5), YearMonth(2026, 6)});
    });

    test('partial edge months are excluded', () {
      final period = DatePeriod(ist('2026-04-15'), ist('2026-06-14'));
      expect(CompleteMonths.of([period]), {YearMonth(2026, 5)});
    });

    test('latest ignores months after now', () {
      final period = DatePeriod(ist('2026-01-01'), ist('2026-12-31'));
      expect(CompleteMonths.latest([period], ist('2026-09-10')),
          YearMonth(2026, 9));
    });

    test('no periods means no complete months', () {
      expect(CompleteMonths.of([]), isEmpty);
      expect(CompleteMonths.latest([], ist('2026-09-10')), isNull);
    });
  });
```

Note: the Swift test's `date("2026-06-30")` is IST midnight on the 30th, which is before the month's last second — so `CompleteMonths.of` must treat a period ending at the *start* of the final day as covering it. It does not. Use `ist('2026-06-30')` here and `date("2026-06-30")` there consistently, and make the first Swift assertion expect **April and May only**. Fix both tests to the same expectation before implementing: a period ending at 2026-06-30T00:00 IST does **not** complete June. Amend the Swift test's first assertion to:

```swift
        XCTAssertEqual(months, [YearMonth(year: 2026, month: 4),
                                YearMonth(year: 2026, month: 5)])
```

and the Dart one to `{YearMonth(2026, 4), YearMonth(2026, 5)}`. Same for `testLatestIgnoresMonthsAfterNow`: a period ending 2026-12-31T00:00 IST completes January–November, and `notAfter 2026-09-10` caps it at **August**; change both expectations to `YearMonth(year: 2026, month: 8)` / `YearMonth(2026, 8)`.

- [ ] **Step 6: Run the Dart test to verify it fails**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: FAIL — `CompleteMonths` undefined.

- [ ] **Step 7: Implement in Dart**

Create `hisab_flutter/packages/hisab_core/lib/src/insights/complete_months.dart`:

```dart
/// Which months a statement covers end to end. Port of CompleteMonths.swift.
library;

import '../domain.dart';
import '../year_month.dart';

class CompleteMonths {
  static Set<YearMonth> of(List<DatePeriod> periods) {
    final result = <YearMonth>{};
    for (final period in periods) {
      for (final month in period.months) {
        final (start, end) = bounds(month);
        if (!period.start.isAfter(start) && !period.end.isBefore(end)) {
          result.add(month);
        }
      }
    }
    return result;
  }

  /// Newest complete month that isn't in the future.
  static YearMonth? latest(List<DatePeriod> periods, DateTime now) {
    final cap = YearMonth.fromDate(now);
    final eligible = [
      for (final m in of(periods))
        if (m.compareTo(cap) <= 0) m
    ]..sort();
    return eligible.isEmpty ? null : eligible.last;
  }

  /// First instant of the month and its last second, both in IST, expressed
  /// as UTC instants (IST midnight is UTC 18:30 the previous day).
  static (DateTime, DateTime) bounds(YearMonth month) {
    final start = DateTime.utc(month.year, month.month, 1).subtract(istOffset);
    final next = month.advancedBy(1);
    final end = DateTime.utc(next.year, next.month, 1)
        .subtract(istOffset)
        .subtract(const Duration(seconds: 1));
    return (start, end);
  }
}
```

Add the export to `lib/hisab_core.dart`:

```dart
export 'src/insights/complete_months.dart';
```

- [ ] **Step 8: Run the Dart test to verify it passes**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add HisabCore hisab_flutter/packages/hisab_core
git commit -m "feat(insights): complete-month detection from statement periods

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 4: TrendDetector

**Files:**
- Create: `HisabCore/Sources/HisabCore/Insights/TrendDetector.swift`
- Create: `hisab_flutter/packages/hisab_core/lib/src/insights/trend_detector.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (export)
- Test: `HisabCore/Tests/HisabCoreTests/TrendDetectorTests.swift`
- Test: `hisab_flutter/packages/hisab_core/test/insights_test.dart` (add a group)

**Interfaces:**
- Consumes: `InsightRecord`, `Insight`, `InsightID`, `InsightsConfig`, `Money.formatPaise`, `YearMonth`.
- Produces: `TrendDetector.detect(records:month:completeMonths:monthDebitTotalPaise:config:) -> (insights: [Insight], concentrationIDs: Set<String>)` (Swift) and `TrendDetector.detect(...) -> (List<Insight>, Set<String>)` (Dart, positional record). `concentrationIDs` feeds the engine's collision rule in Task 7.

- [ ] **Step 1: Write the failing Swift test**

Create `HisabCore/Tests/HisabCoreTests/TrendDetectorTests.swift`:

```swift
import XCTest
@testable import HisabCore

final class TrendDetectorTests: XCTestCase {
    private let config = InsightsConfig.fallback

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func record(_ id: String, _ iso: String, _ paise: Int64,
                        _ category: String, _ merchant: String = "Shop") -> InsightRecord {
        InsightRecord(id: id, date: day(iso), amountPaise: paise, direction: .debit,
                      category: category, merchant: merchant)
    }

    private let window: Set<YearMonth> = [YearMonth(year: 2026, month: 5),
                                          YearMonth(year: 2026, month: 6),
                                          YearMonth(year: 2026, month: 7),
                                          YearMonth(year: 2026, month: 8)]

    func testRiseAboveBothGatesIsReported() {
        // Baseline 1,000.00 per month for three months; August is 2,000.00.
        let records = [record("a", "2026-05-10", 100_000, "Food"),
                       record("b", "2026-06-10", 100_000, "Food"),
                       record("c", "2026-07-10", 100_000, "Food"),
                       record("d", "2026-08-10", 120_000, "Food"),
                       record("e", "2026-08-20", 80_000, "Food")]
        let (insights, concentration) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 200_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .trend)
        XCTAssertEqual(insights[0].headline, "Food: ₹2,000.00")
        XCTAssertEqual(insights[0].detail, "up 100% vs your 3-month average")
        XCTAssertEqual(insights[0].mute, .category("Food"))
        XCTAssertEqual(Set(insights[0].evidenceIDs), ["d", "e"])
        XCTAssertTrue(concentration.isEmpty)
    }

    func testDropsAreReportedToo() {
        let records = [record("a", "2026-05-10", 200_000, "Fuel"),
                       record("b", "2026-06-10", 200_000, "Fuel"),
                       record("c", "2026-07-10", 200_000, "Fuel"),
                       record("d", "2026-08-10", 100_000, "Fuel")]
        let (insights, _) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 100_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].detail, "down 50% vs your 3-month average")
    }

    func testSmallDeltaFailsTheRupeeGateEvenAtAHighPercentage() {
        // +200% but only ₹200 — below minAbsPaise.
        let records = [record("a", "2026-05-10", 10_000, "Snacks"),
                       record("b", "2026-06-10", 10_000, "Snacks"),
                       record("c", "2026-07-10", 10_000, "Snacks"),
                       record("d", "2026-08-10", 30_000, "Snacks")]
        let (insights, _) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 30_000, config: config)
        XCTAssertTrue(insights.isEmpty)
    }

    func testACategoryWithNoBaselineIsNotATrend() {
        let records = [record("d", "2026-08-10", 500_000, "Furniture")]
        let (insights, _) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 500_000, config: config)
        XCTAssertTrue(insights.isEmpty)
    }

    func testOneDominantPurchaseIsAnnotatedAndFlaggedForCollision() {
        let records = [record("a", "2026-05-10", 100_000, "Shopping"),
                       record("b", "2026-06-10", 100_000, "Shopping"),
                       record("c", "2026-07-10", 100_000, "Shopping"),
                       record("d", "2026-08-10", 50_000, "Shopping"),
                       record("e", "2026-08-11", 1_200_000, "Shopping", "Croma")]
        let (insights, concentration) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 1_250_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].detail,
                       "up 1150% vs your 3-month average — driven by one ₹12,000.00 payment to Croma")
        XCTAssertEqual(concentration, ["e"])
    }

    func testNoCompleteBaselineMonthsProducesNothing() {
        let records = [record("d", "2026-08-10", 500_000, "Food")]
        let (insights, _) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: [YearMonth(year: 2026, month: 8)],
            monthDebitTotalPaise: 500_000, config: config)
        XCTAssertTrue(insights.isEmpty)
    }
}
```

- [ ] **Step 2: Run the Swift test to verify it fails**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter TrendDetectorTests`
Expected: FAIL — "cannot find 'TrendDetector' in scope".

- [ ] **Step 3: Implement in Swift**

Create `HisabCore/Sources/HisabCore/Insights/TrendDetector.swift`:

```swift
import Foundation

/// Category spend in the latest complete month against the average of the
/// preceding complete months. Both gates must clear — a percentage without
/// rupees is noise, and rupees without a percentage is just a big month.
public enum TrendDetector {
    public static func detect(records: [InsightRecord], month: YearMonth,
                              completeMonths: Set<YearMonth>,
                              monthDebitTotalPaise: Int64,
                              config: InsightsConfig) -> (insights: [Insight],
                                                          concentrationIDs: Set<String>) {
        let settings = config.trend
        let weight = config.ranker.weights[InsightKind.trend.rawValue] ?? 0

        var window: [YearMonth] = []
        var cursor = month.advanced(by: -1)
        var steps = 0
        while window.count < settings.windowMonths && steps < 24 {
            if completeMonths.contains(cursor) { window.append(cursor) }
            cursor = cursor.advanced(by: -1)
            steps += 1
        }
        guard !window.isEmpty else { return ([], []) }
        let windowSet = Set(window)

        let debits = records.filter { $0.direction == .debit }
        var currentRows: [String: [InsightRecord]] = [:]
        var baseline: [String: Int64] = [:]
        for row in debits {
            let rowMonth = YearMonth(date: row.date)
            if rowMonth == month {
                currentRows[row.category, default: []].append(row)
            } else if windowSet.contains(rowMonth) {
                baseline[row.category, default: 0] += row.amountPaise
            }
        }

        var insights: [Insight] = []
        var concentrationIDs: Set<String> = []
        // Sorted so output order never depends on dictionary iteration order.
        for category in currentRows.keys.sorted() {
            let rows = currentRows[category] ?? []
            let currentTotal = rows.reduce(Int64(0)) { $0 + $1.amountPaise }
            let baselineSum = baseline[category] ?? 0
            guard baselineSum > 0 else { continue }
            let average = baselineSum / Int64(window.count)
            guard average > 0 else { continue }
            let delta = currentTotal - average
            let pct = Int(delta * 100 / average)
            guard abs(pct) >= settings.minPct, abs(delta) >= settings.minAbsPaise else { continue }

            var detail = pct >= 0
                ? "up \(pct)% vs your \(window.count)-month average"
                : "down \(-pct)% vs your \(window.count)-month average"
            if delta > 0, let driver = rows.max(by: { $0.amountPaise < $1.amountPaise }),
               driver.amountPaise * 100 >= delta * Int64(settings.concentrationPct) {
                detail += " — driven by one \(Money.formatPaise(driver.amountPaise))"
                    + " payment to \(driver.merchant)"
                concentrationIDs.insert(driver.id)
            }

            let magnitude = abs(delta) * 1000 / max(monthDebitTotalPaise, 1)
            insights.append(Insight(
                id: InsightID.make("trend|\(category)|\(month.description)|\(pct)"),
                kind: .trend,
                headline: "\(category): \(Money.formatPaise(currentTotal))",
                detail: detail,
                evidenceIDs: rows.map(\.id).sorted(),
                score: magnitude * weight,
                mute: .category(category)))
        }
        return (insights, concentrationIDs)
    }
}
```

- [ ] **Step 4: Run the Swift test to verify it passes**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter TrendDetectorTests`
Expected: PASS (6 tests). If a headline mismatches, print the actual value and reconcile against `Money.formatPaise` (it renders `₹2,000.00` with Indian grouping) rather than editing the formatter.

- [ ] **Step 5: Write the failing Dart test**

Add to `hisab_flutter/packages/hisab_core/test/insights_test.dart`, inside `main()`. Mirror the six Swift cases exactly; helpers:

```dart
  group('TrendDetector', () {
    const config = InsightsConfig.fallback;
    final window = {
      YearMonth(2026, 5), YearMonth(2026, 6),
      YearMonth(2026, 7), YearMonth(2026, 8),
    };

    DateTime day(String yyyyMmDd) {
      final p = yyyyMmDd.split('-').map(int.parse).toList();
      return DateTime.utc(p[0], p[1], p[2]).subtract(istOffset);
    }

    InsightRecord rec(String id, String iso, int paise, String category,
            [String merchant = 'Shop']) =>
        InsightRecord(
            id: id,
            date: day(iso),
            amountPaise: paise,
            direction: Direction.debit,
            category: category,
            merchant: merchant);

    test('rise above both gates is reported', () {
      final (insights, concentration) = TrendDetector.detect(
        records: [
          rec('a', '2026-05-10', 100000, 'Food'),
          rec('b', '2026-06-10', 100000, 'Food'),
          rec('c', '2026-07-10', 100000, 'Food'),
          rec('d', '2026-08-10', 120000, 'Food'),
          rec('e', '2026-08-20', 80000, 'Food'),
        ],
        month: YearMonth(2026, 8),
        completeMonths: window,
        monthDebitTotalPaise: 200000,
        config: config,
      );
      expect(insights.length, 1);
      expect(insights[0].kind, InsightKind.trend);
      expect(insights[0].headline, 'Food: ₹2,000.00');
      expect(insights[0].detail, 'up 100% vs your 3-month average');
      expect(insights[0].mute, const MuteCategory('Food'));
      expect(insights[0].evidenceIDs.toSet(), {'d', 'e'});
      expect(concentration, isEmpty);
    });

    // …then: drops reported; small delta fails the rupee gate; no baseline
    // is not a trend; one dominant purchase is annotated and returned in
    // concentration; no complete baseline months produces nothing. Assert
    // the same strings the Swift test pins.
  });
```

Write out all six tests — do not leave the comment as a placeholder.

- [ ] **Step 6: Run the Dart test to verify it fails**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: FAIL — `TrendDetector` undefined.

- [ ] **Step 7: Implement in Dart**

Create `hisab_flutter/packages/hisab_core/lib/src/insights/trend_detector.dart`:

```dart
/// Category month-over-average deltas. Port of TrendDetector.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../year_month.dart';
import 'insight.dart';
import 'insights_config.dart';

class TrendDetector {
  static (List<Insight>, Set<String>) detect({
    required List<InsightRecord> records,
    required YearMonth month,
    required Set<YearMonth> completeMonths,
    required int monthDebitTotalPaise,
    required InsightsConfig config,
  }) {
    final settings = config.trend;
    final weight = config.ranker.weights[InsightKind.trend.name] ?? 0;

    final window = <YearMonth>[];
    var cursor = month.advancedBy(-1);
    var steps = 0;
    while (window.length < settings.windowMonths && steps < 24) {
      if (completeMonths.contains(cursor)) window.add(cursor);
      cursor = cursor.advancedBy(-1);
      steps++;
    }
    if (window.isEmpty) return (<Insight>[], <String>{});
    final windowSet = window.toSet();

    final currentRows = <String, List<InsightRecord>>{};
    final baseline = <String, int>{};
    for (final row in records) {
      if (row.direction != Direction.debit) continue;
      final rowMonth = YearMonth.fromDate(row.date);
      if (rowMonth == month) {
        currentRows.putIfAbsent(row.category, () => []).add(row);
      } else if (windowSet.contains(rowMonth)) {
        baseline[row.category] = (baseline[row.category] ?? 0) + row.amountPaise;
      }
    }

    final insights = <Insight>[];
    final concentrationIDs = <String>{};
    // Sorted so output order never depends on map iteration order.
    for (final category in currentRows.keys.toList()..sort()) {
      final rows = currentRows[category]!;
      final currentTotal = rows.fold<int>(0, (a, r) => a + r.amountPaise);
      final baselineSum = baseline[category] ?? 0;
      if (baselineSum <= 0) continue;
      final average = baselineSum ~/ window.length;
      if (average <= 0) continue;
      final delta = currentTotal - average;
      final pct = delta * 100 ~/ average;
      if (pct.abs() < settings.minPct || delta.abs() < settings.minAbsPaise) {
        continue;
      }

      var detail = pct >= 0
          ? 'up $pct% vs your ${window.length}-month average'
          : 'down ${-pct}% vs your ${window.length}-month average';
      if (delta > 0) {
        final driver = rows.reduce((a, b) => a.amountPaise >= b.amountPaise ? a : b);
        if (driver.amountPaise * 100 >= delta * settings.concentrationPct) {
          detail += ' — driven by one ${Money.formatPaise(driver.amountPaise)}'
              ' payment to ${driver.merchant}';
          concentrationIDs.add(driver.id);
        }
      }

      final magnitude = delta.abs() *
          1000 ~/
          (monthDebitTotalPaise > 1 ? monthDebitTotalPaise : 1);
      insights.add(Insight(
        id: InsightID.make('trend|$category|$month|$pct'),
        kind: InsightKind.trend,
        headline: '$category: ${Money.formatPaise(currentTotal)}',
        detail: detail,
        evidenceIDs: [for (final r in rows) r.id]..sort(),
        score: magnitude * weight,
        mute: MuteCategory(category),
      ));
    }
    return (insights, concentrationIDs);
  }
}
```

Note: Swift's `max(delta) by amountPaise` picks the *last* maximum on ties while Dart's `reduce` with `>=` also picks the last; keep both as written so ties resolve identically. `'$month'` uses `YearMonth.toString()`, which must render `yyyy-MM` exactly like Swift's `description` — verify in the pin test if a mismatch appears.

Add the export to `lib/hisab_core.dart`:

```dart
export 'src/insights/trend_detector.dart';
```

- [ ] **Step 8: Run the Dart test to verify it passes**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add HisabCore hisab_flutter/packages/hisab_core
git commit -m "feat(insights): category trend detector in both cores

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 5: RecurrenceDetector

**Files:**
- Create: `HisabCore/Sources/HisabCore/Insights/RecurrenceDetector.swift`
- Create: `hisab_flutter/packages/hisab_core/lib/src/insights/recurrence_detector.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (export)
- Test: `HisabCore/Tests/HisabCoreTests/RecurrenceDetectorTests.swift`
- Test: `hisab_flutter/packages/hisab_core/test/insights_test.dart` (add a group)

**Interfaces:**
- Consumes: `InsightRecord`, `Insight`, `RecurringSeries`, `Cadence`, `InsightID`, `InsightsConfig`, `ISTDay.daysBetween` / `istDaysBetween`, `SuggestionEngine.normalize`, `Money.formatPaise`.
- Produces: `RecurrenceDetector.series(records:now:config:) -> [RecurringSeries]` and `RecurrenceDetector.detect(records:now:monthDebitTotalPaise:config:) -> (insights: [Insight], claimedIDs: Set<String>)`. `claimedIDs` is every transaction id belonging to a discovered series; Task 7 uses it to suppress outlier cards for expected recurring payments.

- [ ] **Step 1: Write the failing Swift test**

Create `HisabCore/Tests/HisabCoreTests/RecurrenceDetectorTests.swift`:

```swift
import XCTest
@testable import HisabCore

final class RecurrenceDetectorTests: XCTestCase {
    private let config = InsightsConfig.fallback

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func record(_ id: String, _ iso: String, _ paise: Int64,
                        _ merchant: String) -> InsightRecord {
        InsightRecord(id: id, date: day(iso), amountPaise: paise, direction: .debit,
                      category: "Subscriptions", merchant: merchant)
    }

    private let now = "2026-09-15"

    func testMonthlySeriesIsDiscovered() {
        let records = [record("a", "2026-06-05", 64_900, "NETFLIX INDIA"),
                       record("b", "2026-07-05", 64_900, "Netflix India"),
                       record("c", "2026-08-05", 64_900, "NETFLIX INDIA"),
                       record("d", "2026-09-05", 64_900, "NETFLIX INDIA")]
        let series = RecurrenceDetector.series(records: records, now: day(now), config: config)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].merchantKey, "netflix india")
        XCTAssertEqual(series[0].displayMerchant, "NETFLIX INDIA")
        XCTAssertEqual(series[0].cadence, .monthly)
        XCTAssertEqual(series[0].medianPaise, 64_900)
        XCTAssertEqual(series[0].monthlyEquivalentPaise, 64_900)
        XCTAssertEqual(series[0].count, 4)
    }

    func testWeeklySeriesScalesToAMonthlyEquivalent() {
        let records = [record("a", "2026-08-25", 30_000, "Milk Wala"),
                       record("b", "2026-09-01", 30_000, "Milk Wala"),
                       record("c", "2026-09-08", 30_000, "Milk Wala"),
                       record("d", "2026-09-15", 30_000, "Milk Wala")]
        let series = RecurrenceDetector.series(records: records, now: day(now), config: config)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].cadence, .weekly)
        XCTAssertEqual(series[0].monthlyEquivalentPaise, 30_000 * 52 / 12)
    }

    func testIrregularGapsAreNotASeries() {
        let records = [record("a", "2026-06-01", 50_000, "Random Shop"),
                       record("b", "2026-06-19", 50_000, "Random Shop"),
                       record("c", "2026-08-02", 50_000, "Random Shop")]
        XCTAssertTrue(RecurrenceDetector.series(records: records, now: day(now),
                                                config: config).isEmpty)
    }

    func testTooFewOccurrencesIsNotASeries() {
        let records = [record("a", "2026-07-05", 64_900, "Netflix"),
                       record("b", "2026-08-05", 64_900, "Netflix")]
        XCTAssertTrue(RecurrenceDetector.series(records: records, now: day(now),
                                                config: config).isEmpty)
    }

    func testAStaleSeriesIsNotActiveAndProducesNoCards() {
        // Last paid in March; monthly cadence goes inactive after 2 cadences.
        let records = [record("a", "2025-12-05", 64_900, "Netflix"),
                       record("b", "2026-01-05", 64_900, "Netflix"),
                       record("c", "2026-02-05", 64_900, "Netflix"),
                       record("d", "2026-03-05", 64_900, "Netflix")]
        let (insights, _) = RecurrenceDetector.detect(
            records: records, now: day(now), monthDebitTotalPaise: 100_000, config: config)
        XCTAssertTrue(insights.isEmpty)
    }

    func testANewSeriesIsReported() {
        let records = [record("a", "2026-07-05", 64_900, "Netflix"),
                       record("b", "2026-08-05", 64_900, "Netflix"),
                       record("c", "2026-09-05", 64_900, "Netflix")]
        let (insights, claimed) = RecurrenceDetector.detect(
            records: records, now: day(now), monthDebitTotalPaise: 200_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .recurringNew)
        XCTAssertEqual(insights[0].headline, "New recurring: Netflix")
        XCTAssertEqual(insights[0].detail, "₹649.00 per month since Jul 2026")
        XCTAssertEqual(insights[0].mute, .merchant("netflix"))
        XCTAssertEqual(claimed, ["a", "b", "c"])
    }

    func testAChangedAmountIsReported() {
        // Established since February, so not "new"; September jumps 23%.
        let records = [record("a", "2026-02-05", 64_900, "Netflix"),
                       record("b", "2026-03-05", 64_900, "Netflix"),
                       record("c", "2026-04-05", 64_900, "Netflix"),
                       record("d", "2026-05-05", 64_900, "Netflix"),
                       record("e", "2026-06-05", 64_900, "Netflix"),
                       record("f", "2026-07-05", 64_900, "Netflix"),
                       record("g", "2026-08-05", 64_900, "Netflix"),
                       record("h", "2026-09-05", 79_900, "Netflix")]
        let (insights, _) = RecurrenceDetector.detect(
            records: records, now: day(now), monthDebitTotalPaise: 200_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .recurringChanged)
        XCTAssertEqual(insights[0].headline, "Netflix: ₹799.00")
        XCTAssertEqual(insights[0].detail, "usually ₹649.00 per month")
    }

    func testTwoActiveSeriesProduceACommittedSpendSummary() {
        var records = [record("a", "2026-07-05", 64_900, "Netflix"),
                       record("b", "2026-08-05", 64_900, "Netflix"),
                       record("c", "2026-09-05", 64_900, "Netflix")]
        records += [record("d", "2026-07-10", 1_500_000, "Landlord"),
                    record("e", "2026-08-10", 1_500_000, "Landlord"),
                    record("f", "2026-09-10", 1_500_000, "Landlord")]
        let (insights, _) = RecurrenceDetector.detect(
            records: records, now: day(now), monthDebitTotalPaise: 2_000_000, config: config)
        let committed = insights.filter { $0.kind == .committedSpend }
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed[0].headline, "₹15,649.00 per month committed")
        XCTAssertEqual(committed[0].detail, "across 2 recurring payments")
        XCTAssertEqual(committed[0].series.count, 2)
        XCTAssertNil(committed[0].mute)
    }
}
```

- [ ] **Step 2: Run the Swift test to verify it fails**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter RecurrenceDetectorTests`
Expected: FAIL — "cannot find 'RecurrenceDetector' in scope".

- [ ] **Step 3: Implement in Swift**

Create `HisabCore/Sources/HisabCore/Insights/RecurrenceDetector.swift`:

```swift
import Foundation

/// Repeating payments: rent, SIPs, EMIs, subscriptions. A series needs
/// enough occurrences, a stable interval, and a stable amount — the latest
/// payment is allowed to deviate, because that deviation is the "changed"
/// signal we want to report.
public enum RecurrenceDetector {
    public static func series(records: [InsightRecord], now: Date,
                              config: InsightsConfig) -> [RecurringSeries] {
        let settings = config.recurrence
        var groups: [String: [InsightRecord]] = [:]
        for row in records where row.direction == .debit {
            let key = SuggestionEngine.normalize(row.merchant)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(row)
        }

        var result: [RecurringSeries] = []
        for key in groups.keys.sorted() {
            let members = (groups[key] ?? []).sorted { $0.date < $1.date }
            guard members.count >= settings.minOccurrences else { continue }

            var gaps: [Int] = []
            for index in 1..<members.count {
                gaps.append(ISTDay.daysBetween(members[index - 1].date, members[index].date))
            }
            let medianGap = median(gaps.map(Int64.init))
            let cadence: Cadence
            if medianGap >= Int64(settings.monthlyMinDays), medianGap <= Int64(settings.monthlyMaxDays) {
                cadence = .monthly
            } else if medianGap >= Int64(settings.weeklyMinDays), medianGap <= Int64(settings.weeklyMaxDays) {
                cadence = .weekly
            } else {
                continue
            }

            let medianAmount = median(members.map(\.amountPaise))
            guard medianAmount > 0 else { continue }
            let stable = members.filter {
                abs($0.amountPaise - medianAmount) * 100 <= medianAmount * Int64(settings.amountSpreadPct)
            }
            guard stable.count >= settings.minOccurrences else { continue }

            let lastSeen = members[members.count - 1].date
            let cadenceDays = cadence == .monthly ? settings.monthlyMaxDays : settings.weeklyMaxDays
            let staleAfter = cadenceDays * settings.activeWithinCadences
            guard ISTDay.daysBetween(lastSeen, now) <= staleAfter else { continue }

            // Most common raw spelling; ties resolve alphabetically, matching
            // SuggestionEngine's display choice.
            var rawCounts: [String: Int] = [:]
            for member in members { rawCounts[member.merchant, default: 0] += 1 }
            let display = rawCounts.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key ?? key

            result.append(RecurringSeries(
                merchantKey: key,
                displayMerchant: display,
                cadence: cadence,
                medianPaise: medianAmount,
                monthlyEquivalentPaise: cadence == .monthly ? medianAmount : medianAmount * 52 / 12,
                firstSeen: members[0].date,
                lastSeen: lastSeen,
                count: members.count,
                transactionIDs: members.map(\.id)))
        }
        return result
    }

    public static func detect(records: [InsightRecord], now: Date,
                              monthDebitTotalPaise: Int64,
                              config: InsightsConfig) -> (insights: [Insight],
                                                          claimedIDs: Set<String>) {
        let settings = config.recurrence
        let weights = config.ranker.weights
        let found = series(records: records, now: now, config: config)
        guard !found.isEmpty else { return ([], []) }

        var insights: [Insight] = []
        var claimed: Set<String> = []
        let newCutoff = YearMonth(date: now).advanced(by: -settings.newWithinMonths)

        for entry in found {
            claimed.formUnion(entry.transactionIDs)
            let cadenceWord = entry.cadence == .monthly ? "per month" : "per week"

            if YearMonth(date: entry.firstSeen) >= newCutoff {
                let magnitude = entry.monthlyEquivalentPaise * 1000 / max(monthDebitTotalPaise, 1)
                insights.append(Insight(
                    id: InsightID.make("recurring-new|\(entry.merchantKey)|\(entry.medianPaise)"),
                    kind: .recurringNew,
                    headline: "New recurring: \(entry.displayMerchant)",
                    detail: "\(Money.formatPaise(entry.medianPaise)) \(cadenceWord)"
                        + " since \(YearMonth(date: entry.firstSeen).displayName)",
                    evidenceIDs: entry.transactionIDs,
                    score: magnitude * (weights[InsightKind.recurringNew.rawValue] ?? 0),
                    mute: .merchant(entry.merchantKey)))
                continue  // a brand-new series can't also be "changed"
            }

            guard let latest = records
                .filter { SuggestionEngine.normalize($0.merchant) == entry.merchantKey }
                .max(by: { $0.date < $1.date }) else { continue }
            let drift = abs(latest.amountPaise - entry.medianPaise)
            if drift * 100 >= entry.medianPaise * Int64(settings.changedPct) {
                let magnitude = drift * 1000 / max(monthDebitTotalPaise, 1)
                insights.append(Insight(
                    id: InsightID.make("recurring-changed|\(entry.merchantKey)|\(latest.amountPaise)"),
                    kind: .recurringChanged,
                    headline: "\(entry.displayMerchant): \(Money.formatPaise(latest.amountPaise))",
                    detail: "usually \(Money.formatPaise(entry.medianPaise)) \(cadenceWord)",
                    evidenceIDs: entry.transactionIDs,
                    score: magnitude * (weights[InsightKind.recurringChanged.rawValue] ?? 0),
                    mute: .merchant(entry.merchantKey)))
            }
        }

        if found.count >= 2 {
            let total = found.reduce(Int64(0)) { $0 + $1.monthlyEquivalentPaise }
            insights.append(Insight(
                id: InsightID.make("committed|\(found.count)|\(total)"),
                kind: .committedSpend,
                headline: "\(Money.formatPaise(total)) per month committed",
                detail: "across \(found.count) recurring payments",
                evidenceIDs: found.flatMap(\.transactionIDs),
                series: found,
                score: 0,  // pinned last by the ranker, never ranked on merit
                mute: nil))
        }
        return (insights, claimed)
    }

    /// Lower median of a sorted copy; both platforms must agree exactly.
    static func median(_ values: [Int64]) -> Int64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }
}
```

- [ ] **Step 4: Run the Swift test to verify it passes**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter RecurrenceDetectorTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Implement in Dart and mirror the tests**

Create `hisab_flutter/packages/hisab_core/lib/src/insights/recurrence_detector.dart` as a direct port. Structure, names, and order of operations follow the Swift file exactly:

```dart
/// Repeating payments: rent, SIPs, EMIs, subscriptions.
/// Port of RecurrenceDetector.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../suggestion_engine.dart';
import '../year_month.dart';
import 'insight.dart';
import 'insights_config.dart';

class RecurrenceDetector {
  static List<RecurringSeries> series({
    required List<InsightRecord> records,
    required DateTime now,
    required InsightsConfig config,
  }) {
    final settings = config.recurrence;
    final groups = <String, List<InsightRecord>>{};
    for (final row in records) {
      if (row.direction != Direction.debit) continue;
      final key = SuggestionEngine.normalize(row.merchant);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(row);
    }

    final result = <RecurringSeries>[];
    for (final key in groups.keys.toList()..sort()) {
      final members = groups[key]!..sort((a, b) => a.date.compareTo(b.date));
      if (members.length < settings.minOccurrences) continue;

      final gaps = <int>[];
      for (var i = 1; i < members.length; i++) {
        gaps.add(istDaysBetween(members[i - 1].date, members[i].date));
      }
      final medianGap = median(gaps);
      final Cadence cadence;
      if (medianGap >= settings.monthlyMinDays &&
          medianGap <= settings.monthlyMaxDays) {
        cadence = Cadence.monthly;
      } else if (medianGap >= settings.weeklyMinDays &&
          medianGap <= settings.weeklyMaxDays) {
        cadence = Cadence.weekly;
      } else {
        continue;
      }

      final medianAmount = median([for (final m in members) m.amountPaise]);
      if (medianAmount <= 0) continue;
      final stable = [
        for (final m in members)
          if ((m.amountPaise - medianAmount).abs() * 100 <=
              medianAmount * settings.amountSpreadPct)
            m
      ];
      if (stable.length < settings.minOccurrences) continue;

      final lastSeen = members.last.date;
      final cadenceDays = cadence == Cadence.monthly
          ? settings.monthlyMaxDays
          : settings.weeklyMaxDays;
      if (istDaysBetween(lastSeen, now) >
          cadenceDays * settings.activeWithinCadences) {
        continue;
      }

      // Most common raw spelling; ties resolve alphabetically.
      final rawCounts = <String, int>{};
      for (final m in members) {
        rawCounts[m.merchant] = (rawCounts[m.merchant] ?? 0) + 1;
      }
      var display = key;
      var bestCount = -1;
      rawCounts.forEach((raw, count) {
        if (count > bestCount ||
            (count == bestCount && raw.compareTo(display) < 0)) {
          display = raw;
          bestCount = count;
        }
      });

      result.add(RecurringSeries(
        merchantKey: key,
        displayMerchant: display,
        cadence: cadence,
        medianPaise: medianAmount,
        monthlyEquivalentPaise:
            cadence == Cadence.monthly ? medianAmount : medianAmount * 52 ~/ 12,
        firstSeen: members.first.date,
        lastSeen: lastSeen,
        count: members.length,
        transactionIDs: [for (final m in members) m.id],
      ));
    }
    return result;
  }

  static (List<Insight>, Set<String>) detect({
    required List<InsightRecord> records,
    required DateTime now,
    required int monthDebitTotalPaise,
    required InsightsConfig config,
  }) {
    final settings = config.recurrence;
    final weights = config.ranker.weights;
    final found = series(records: records, now: now, config: config);
    if (found.isEmpty) return (<Insight>[], <String>{});

    final insights = <Insight>[];
    final claimed = <String>{};
    final newCutoff =
        YearMonth.fromDate(now).advancedBy(-settings.newWithinMonths);
    final denominator = monthDebitTotalPaise > 1 ? monthDebitTotalPaise : 1;

    for (final entry in found) {
      claimed.addAll(entry.transactionIDs);
      final cadenceWord =
          entry.cadence == Cadence.monthly ? 'per month' : 'per week';
      final firstMonth = YearMonth.fromDate(entry.firstSeen);

      if (firstMonth.compareTo(newCutoff) >= 0) {
        final magnitude = entry.monthlyEquivalentPaise * 1000 ~/ denominator;
        insights.add(Insight(
          id: InsightID.make(
              'recurring-new|${entry.merchantKey}|${entry.medianPaise}'),
          kind: InsightKind.recurringNew,
          headline: 'New recurring: ${entry.displayMerchant}',
          detail: '${Money.formatPaise(entry.medianPaise)} $cadenceWord'
              ' since ${firstMonth.displayName}',
          evidenceIDs: entry.transactionIDs,
          score: magnitude * (weights[InsightKind.recurringNew.name] ?? 0),
          mute: MuteMerchant(entry.merchantKey),
        ));
        continue; // a brand-new series can't also be "changed"
      }

      final sameMerchant = [
        for (final r in records)
          if (SuggestionEngine.normalize(r.merchant) == entry.merchantKey) r
      ];
      if (sameMerchant.isEmpty) continue;
      final latest =
          sameMerchant.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
      final drift = (latest.amountPaise - entry.medianPaise).abs();
      if (drift * 100 >= entry.medianPaise * settings.changedPct) {
        final magnitude = drift * 1000 ~/ denominator;
        insights.add(Insight(
          id: InsightID.make(
              'recurring-changed|${entry.merchantKey}|${latest.amountPaise}'),
          kind: InsightKind.recurringChanged,
          headline:
              '${entry.displayMerchant}: ${Money.formatPaise(latest.amountPaise)}',
          detail: 'usually ${Money.formatPaise(entry.medianPaise)} $cadenceWord',
          evidenceIDs: entry.transactionIDs,
          score: magnitude * (weights[InsightKind.recurringChanged.name] ?? 0),
          mute: MuteMerchant(entry.merchantKey),
        ));
      }
    }

    if (found.length >= 2) {
      final total =
          found.fold<int>(0, (a, s) => a + s.monthlyEquivalentPaise);
      insights.add(Insight(
        id: InsightID.make('committed|${found.length}|$total'),
        kind: InsightKind.committedSpend,
        headline: '${Money.formatPaise(total)} per month committed',
        detail: 'across ${found.length} recurring payments',
        evidenceIDs: [for (final s in found) ...s.transactionIDs],
        series: found,
        score: 0, // pinned last by the ranker
        mute: null,
      ));
    }
    return (insights, claimed);
  }

  /// Lower median of a sorted copy; must match Swift exactly.
  static int median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = List.of(values)..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }
}
```

Add the export to `lib/hisab_core.dart`, then write the Dart test group mirroring all eight Swift cases per the Global Constraints rule.

Note on Swift's `max(by:)` for `latest`: it returns the last maximal element, and Dart's `reduce((a, b) => a.date.isAfter(b.date) ? a : b)` also keeps the later element on a tie — equivalent for same-date rows.

- [ ] **Step 6: Run the Dart test to verify it passes**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: PASS, with the same expected strings the Swift test pins.

- [ ] **Step 7: Commit**

```bash
git add HisabCore hisab_flutter/packages/hisab_core
git commit -m "feat(insights): recurrence detector — new, changed, committed spend

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 6: AnomalyDetector

**Files:**
- Create: `HisabCore/Sources/HisabCore/Insights/AnomalyDetector.swift`
- Create: `hisab_flutter/packages/hisab_core/lib/src/insights/anomaly_detector.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (export)
- Test: `HisabCore/Tests/HisabCoreTests/AnomalyDetectorTests.swift`
- Test: `hisab_flutter/packages/hisab_core/test/insights_test.dart` (add a group)

**Interfaces:**
- Consumes: `InsightRecord`, `Insight`, `InsightID`, `InsightsConfig`, `ISTDay`, `SuggestionEngine.normalize`, `RecurrenceDetector.median`, `Money.formatPaise`.
- Produces: `AnomalyDetector.detect(records:now:monthDebitTotalPaise:config:) -> [Insight]`.

- [ ] **Step 1: Write the failing Swift test**

Create `HisabCore/Tests/HisabCoreTests/AnomalyDetectorTests.swift`:

```swift
import XCTest
@testable import HisabCore

final class AnomalyDetectorTests: XCTestCase {
    private let config = InsightsConfig.fallback

    private func stamp(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = iso.count > 10 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func record(_ id: String, _ iso: String, _ paise: Int64,
                        _ merchant: String) -> InsightRecord {
        InsightRecord(id: id, date: stamp(iso), amountPaise: paise, direction: .debit,
                      category: "Food", merchant: merchant)
    }

    private let now = "2026-09-15"

    func testSameDayIdenticalPaymentsAreAPossibleDuplicate() {
        let records = [record("a", "2026-09-10", 45_000, "Swiggy"),
                       record("b", "2026-09-10", 45_000, "Swiggy")]
        let insights = AnomalyDetector.detect(records: records, now: stamp(now),
                                              monthDebitTotalPaise: 90_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .possibleDuplicate)
        XCTAssertEqual(insights[0].headline, "Swiggy: ₹450.00 ×2")
        XCTAssertEqual(insights[0].detail, "2 identical payments on 10 Sep 2026")
        XCTAssertEqual(insights[0].evidenceIDs, ["a", "b"])
        XCTAssertEqual(insights[0].mute, .merchant("swiggy"))
    }

    func testDifferentMerchantsSameAmountAreNotDuplicates() {
        let records = [record("a", "2026-09-10", 45_000, "Swiggy"),
                       record("b", "2026-09-10", 45_000, "Zomato")]
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 90_000,
                                             config: config).isEmpty)
    }

    func testTimestampedPaymentsHoursApartAreNotDuplicates() {
        let records = [record("a", "2026-09-10 09:15", 45_000, "Swiggy"),
                       record("b", "2026-09-10 20:40", 45_000, "Swiggy")]
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 90_000,
                                             config: config).isEmpty)
    }

    func testTimestampedPaymentsWithinTheWindowAreDuplicates() {
        let records = [record("a", "2026-09-10 09:15", 45_000, "Swiggy"),
                       record("b", "2026-09-10 09:19", 45_000, "Swiggy")]
        let insights = AnomalyDetector.detect(records: records, now: stamp(now),
                                              monthDebitTotalPaise: 90_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .possibleDuplicate)
    }

    func testAnAmountFarAboveTheMerchantMedianIsAnOutlier() {
        var records = (1...5).map { index in
            record("p\(index)", "2026-08-0\(index)", 30_000, "Blue Tokai")
        }
        records.append(record("big", "2026-09-10", 250_000, "Blue Tokai"))
        let insights = AnomalyDetector.detect(records: records, now: stamp(now),
                                              monthDebitTotalPaise: 400_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .outlierAmount)
        XCTAssertEqual(insights[0].headline, "Blue Tokai: ₹2,500.00")
        XCTAssertEqual(insights[0].detail, "about 8× your usual ₹300.00")
        XCTAssertEqual(insights[0].evidenceIDs, ["big"])
    }

    func testTooFewPriorsMeansNoOutlier() {
        var records = (1...4).map { index in
            record("p\(index)", "2026-08-0\(index)", 30_000, "Blue Tokai")
        }
        records.append(record("big", "2026-09-10", 250_000, "Blue Tokai"))
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 400_000,
                                             config: config).isEmpty)
    }

    func testASmallMultipleBelowTheRupeeFloorIsNotAnOutlier() {
        var records = (1...5).map { index in
            record("p\(index)", "2026-08-0\(index)", 10_000, "Chaiwala")
        }
        records.append(record("big", "2026-09-10", 40_000, "Chaiwala"))
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 90_000,
                                             config: config).isEmpty)
    }

    func testAnythingOlderThanTheLookbackIsIgnored() {
        let records = [record("a", "2026-06-10", 45_000, "Swiggy"),
                       record("b", "2026-06-10", 45_000, "Swiggy")]
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 90_000,
                                             config: config).isEmpty)
    }
}
```

- [ ] **Step 2: Run the Swift test to verify it fails**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter AnomalyDetectorTests`
Expected: FAIL — "cannot find 'AnomalyDetector' in scope".

- [ ] **Step 3: Implement in Swift**

Create `HisabCore/Sources/HisabCore/Insights/AnomalyDetector.swift`:

```swift
import Foundation

/// Two conservative signals over a short window: payments that look
/// accidentally repeated, and amounts far above what this merchant usually
/// costs. Both stay silent unless there's enough history to be sure.
public enum AnomalyDetector {
    public static func detect(records: [InsightRecord], now: Date,
                              monthDebitTotalPaise: Int64,
                              config: InsightsConfig) -> [Insight] {
        let settings = config.anomaly
        let weights = config.ranker.weights
        let debits = records.filter { $0.direction == .debit }
        let recent = debits.filter {
            $0.date <= now && ISTDay.daysBetween($0.date, now) <= settings.lookbackDays
        }
        guard !recent.isEmpty else { return [] }

        var insights: [Insight] = []
        let denominator = max(monthDebitTotalPaise, 1)

        // Possible duplicates: same merchant, same amount, same IST day.
        var buckets: [String: [InsightRecord]] = [:]
        for row in recent {
            let key = SuggestionEngine.normalize(row.merchant)
            guard !key.isEmpty else { continue }
            buckets["\(key)|\(ISTDay.string(row.date))|\(row.amountPaise)", default: []].append(row)
        }
        for bucketKey in buckets.keys.sorted() {
            let members = (buckets[bucketKey] ?? []).sorted { $0.id < $1.id }
            guard members.count >= 2 else { continue }
            // When every row carries a clock time, insist they're minutes apart;
            // date-only statements can't support that test, so day equality stands.
            if members.allSatisfy({ hasClockTime($0.date) }) {
                let times = members.map(\.date).sorted()
                var close = false
                for index in 1..<times.count
                where times[index].timeIntervalSince(times[index - 1])
                    <= Double(settings.duplicateWindowMinutes * 60) {
                    close = true
                }
                guard close else { continue }
            }
            let sample = members[0]
            let merchantKey = SuggestionEngine.normalize(sample.merchant)
            let magnitude = sample.amountPaise * 1000 / denominator
            insights.append(Insight(
                id: InsightID.make("duplicate|\(members.map(\.id).joined(separator: ","))"),
                kind: .possibleDuplicate,
                headline: "\(sample.merchant): \(Money.formatPaise(sample.amountPaise))"
                    + " ×\(members.count)",
                detail: "\(members.count) identical payments on \(dayLabel(sample.date))",
                evidenceIDs: members.map(\.id),
                score: magnitude * (weights[InsightKind.possibleDuplicate.rawValue] ?? 0),
                mute: .merchant(merchantKey)))
        }

        // Outliers: this merchant has history, and this payment dwarfs it.
        for row in recent.sorted(by: { $0.id < $1.id }) {
            let key = SuggestionEngine.normalize(row.merchant)
            guard !key.isEmpty else { continue }
            let priors = debits.filter {
                SuggestionEngine.normalize($0.merchant) == key && $0.date < row.date
            }
            guard priors.count >= settings.minPriors else { continue }
            let typical = RecurrenceDetector.median(priors.map(\.amountPaise))
            guard typical > 0,
                  row.amountPaise >= typical * Int64(settings.outlierMultiple),
                  row.amountPaise >= settings.outlierMinPaise else { continue }
            let magnitude = row.amountPaise * 1000 / denominator
            insights.append(Insight(
                id: InsightID.make("outlier|\(row.id)"),
                kind: .outlierAmount,
                headline: "\(row.merchant): \(Money.formatPaise(row.amountPaise))",
                detail: "about \(row.amountPaise / typical)× your usual \(Money.formatPaise(typical))",
                evidenceIDs: [row.id],
                score: magnitude * (weights[InsightKind.outlierAmount.rawValue] ?? 0),
                mute: .merchant(key)))
        }
        return insights
    }

    /// Statement rows without a time parse to IST midnight; payment-app rows
    /// (GPay) carry a real clock time.
    static func hasClockTime(_ date: Date) -> Bool {
        let comps = YearMonth.istCalendar.dateComponents([.hour, .minute, .second], from: date)
        return (comps.hour ?? 0) != 0 || (comps.minute ?? 0) != 0 || (comps.second ?? 0) != 0
    }

    static func dayLabel(_ date: Date) -> String {
        let day = YearMonth.istCalendar.dateComponents([.day], from: date).day ?? 1
        return "\(day) \(YearMonth(date: date).displayName)"
    }
}
```

- [ ] **Step 4: Run the Swift test to verify it passes**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter AnomalyDetectorTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Implement in Dart and mirror the tests**

Create `hisab_flutter/packages/hisab_core/lib/src/insights/anomaly_detector.dart` as a direct port:

```dart
/// Possible duplicates and amount outliers. Port of AnomalyDetector.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../suggestion_engine.dart';
import '../year_month.dart';
import 'insight.dart';
import 'insights_config.dart';
import 'recurrence_detector.dart';

class AnomalyDetector {
  static List<Insight> detect({
    required List<InsightRecord> records,
    required DateTime now,
    required int monthDebitTotalPaise,
    required InsightsConfig config,
  }) {
    final settings = config.anomaly;
    final weights = config.ranker.weights;
    final debits = [
      for (final r in records)
        if (r.direction == Direction.debit) r
    ];
    final recent = [
      for (final r in debits)
        if (!r.date.isAfter(now) &&
            istDaysBetween(r.date, now) <= settings.lookbackDays)
          r
    ];
    if (recent.isEmpty) return const [];

    final insights = <Insight>[];
    final denominator = monthDebitTotalPaise > 1 ? monthDebitTotalPaise : 1;

    final buckets = <String, List<InsightRecord>>{};
    for (final row in recent) {
      final key = SuggestionEngine.normalize(row.merchant);
      if (key.isEmpty) continue;
      buckets
          .putIfAbsent(
              '$key|${istDayString(row.date)}|${row.amountPaise}', () => [])
          .add(row);
    }
    for (final bucketKey in buckets.keys.toList()..sort()) {
      final members = buckets[bucketKey]!..sort((a, b) => a.id.compareTo(b.id));
      if (members.length < 2) continue;
      if (members.every((m) => hasClockTime(m.date))) {
        final times = [for (final m in members) m.date]..sort();
        var close = false;
        for (var i = 1; i < times.length; i++) {
          if (times[i].difference(times[i - 1]).inSeconds <=
              settings.duplicateWindowMinutes * 60) {
            close = true;
          }
        }
        if (!close) continue;
      }
      final sample = members.first;
      final merchantKey = SuggestionEngine.normalize(sample.merchant);
      final magnitude = sample.amountPaise * 1000 ~/ denominator;
      insights.add(Insight(
        id: InsightID.make(
            'duplicate|${members.map((m) => m.id).join(',')}'),
        kind: InsightKind.possibleDuplicate,
        headline: '${sample.merchant}: ${Money.formatPaise(sample.amountPaise)}'
            ' ×${members.length}',
        detail:
            '${members.length} identical payments on ${dayLabel(sample.date)}',
        evidenceIDs: [for (final m in members) m.id],
        score: magnitude * (weights[InsightKind.possibleDuplicate.name] ?? 0),
        mute: MuteMerchant(merchantKey),
      ));
    }

    final ordered = List.of(recent)..sort((a, b) => a.id.compareTo(b.id));
    for (final row in ordered) {
      final key = SuggestionEngine.normalize(row.merchant);
      if (key.isEmpty) continue;
      final priors = [
        for (final d in debits)
          if (SuggestionEngine.normalize(d.merchant) == key &&
              d.date.isBefore(row.date))
            d
      ];
      if (priors.length < settings.minPriors) continue;
      final typical =
          RecurrenceDetector.median([for (final p in priors) p.amountPaise]);
      if (typical <= 0) continue;
      if (row.amountPaise < typical * settings.outlierMultiple ||
          row.amountPaise < settings.outlierMinPaise) {
        continue;
      }
      final magnitude = row.amountPaise * 1000 ~/ denominator;
      insights.add(Insight(
        id: InsightID.make('outlier|${row.id}'),
        kind: InsightKind.outlierAmount,
        headline: '${row.merchant}: ${Money.formatPaise(row.amountPaise)}',
        detail: 'about ${row.amountPaise ~/ typical}× your usual '
            '${Money.formatPaise(typical)}',
        evidenceIDs: [row.id],
        score: magnitude * (weights[InsightKind.outlierAmount.name] ?? 0),
        mute: MuteMerchant(key),
      ));
    }
    return insights;
  }

  /// Statement rows without a time land on IST midnight; payment-app rows
  /// carry a real clock time.
  static bool hasClockTime(DateTime date) {
    final c = istClock(date);
    return c.hour != 0 || c.minute != 0 || c.second != 0;
  }

  static String dayLabel(DateTime date) =>
      '${istClock(date).day} ${YearMonth.fromDate(date).displayName}';
}
```

Add the export to `lib/hisab_core.dart`, then write the Dart test group mirroring all eight Swift cases.

- [ ] **Step 6: Run the Dart test to verify it passes**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add HisabCore hisab_flutter/packages/hisab_core
git commit -m "feat(insights): anomaly detector — possible duplicates and outliers

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 7: InsightsEngine — collisions, suppression, ranking

**Files:**
- Create: `HisabCore/Sources/HisabCore/Insights/InsightsEngine.swift`
- Create: `hisab_flutter/packages/hisab_core/lib/src/insights/insights_engine.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (export)
- Test: `HisabCore/Tests/HisabCoreTests/InsightsEngineTests.swift`
- Test: `hisab_flutter/packages/hisab_core/test/insights_test.dart` (add a group)

**Interfaces:**
- Consumes: all three detectors, `CompleteMonths`, `InsightsInput`, `Suppressions`, `InsightsResult`, `InsightsConfig`.
- Produces: `InsightsEngine.generate(input:config:suppressions:) -> InsightsResult`. This is the single entry point both apps call; nothing else in the app layer touches a detector.

- [ ] **Step 1: Write the failing Swift test**

Create `HisabCore/Tests/HisabCoreTests/InsightsEngineTests.swift`. Build one dataset that trips several detectors at once and assert the orchestration rules:

```swift
import XCTest
@testable import HisabCore

final class InsightsEngineTests: XCTestCase {
    private let config = InsightsConfig.fallback

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func record(_ id: String, _ iso: String, _ paise: Int64,
                        _ category: String, _ merchant: String) -> InsightRecord {
        InsightRecord(id: id, date: day(iso), amountPaise: paise, direction: .debit,
                      category: category, merchant: merchant)
    }

    /// Jun–Aug complete, "now" mid-September: August is the latest complete month.
    private var periods: [DatePeriod] {
        [DatePeriod(start: day("2026-01-01"), end: day("2026-08-31"))]
    }
    private var now: Date { day("2026-09-15") }

    /// A rent series (recurring), a Food trend, and a duplicate pair.
    private var dataset: [InsightRecord] {
        var rows: [InsightRecord] = []
        for (index, month) in ["06", "07", "08"].enumerated() {
            rows.append(record("rent\(index)", "2026-\(month)-05", 1_500_000, "Housing", "Landlord"))
            rows.append(record("food\(index)", "2026-\(month)-12", 100_000, "Food", "Swiggy"))
        }
        rows.append(record("foodspike", "2026-08-20", 300_000, "Food", "Swiggy"))
        rows.append(record("dup1", "2026-08-25", 45_000, "Food", "Zomato"))
        rows.append(record("dup2", "2026-08-25", 45_000, "Food", "Zomato"))
        return rows
    }

    private func generate(_ suppressions: Suppressions = Suppressions()) -> InsightsResult {
        InsightsEngine.generate(
            input: InsightsInput(records: dataset, documentPeriods: periods, now: now),
            config: config, suppressions: suppressions)
    }

    func testCommittedSpendIsAlwaysTheLastCard() {
        let result = generate()
        XCTAssertFalse(result.cards.isEmpty)
        XCTAssertEqual(result.cards.last?.kind, .committedSpend)
        XCTAssertEqual(result.cards.filter { $0.kind == .committedSpend }.count, 1)
    }

    func testCardsAreCappedAtMaxCards() {
        XCTAssertLessThanOrEqual(generate().cards.count, config.ranker.maxCards)
    }

    func testHigherWeightedKindsOutrankTrends() {
        let cards = generate().cards
        guard let duplicateIndex = cards.firstIndex(where: { $0.kind == .possibleDuplicate }),
              let trendIndex = cards.firstIndex(where: { $0.kind == .trend }) else {
            return XCTFail("expected both a duplicate and a trend card")
        }
        XCTAssertLessThan(duplicateIndex, trendIndex)
    }

    func testDismissedIDsAreRemovedButStillReportedInAllIDs() {
        let first = generate().cards[0]
        let result = generate(Suppressions(dismissedIDs: [first.id]))
        XCTAssertFalse(result.cards.contains { $0.id == first.id })
        XCTAssertTrue(result.allIDs.contains(first.id),
                      "allIDs must list every generated id so the app can prune")
    }

    func testMutingAMerchantSilencesItsCards() {
        let result = generate(Suppressions(mutedMerchants: ["zomato"]))
        XCTAssertFalse(result.cards.contains { $0.kind == .possibleDuplicate })
    }

    func testMutingACategorySilencesItsTrend() {
        let result = generate(Suppressions(mutedCategories: ["Food"]))
        XCTAssertFalse(result.cards.contains { $0.kind == .trend })
    }

    func testAnOutlierOnARecurringPaymentIsSuppressed() {
        // Landlord has 3 priors below minPriors, so build a longer series that
        // also spikes: the recurrence card owns it, no outlier card appears.
        var rows: [InsightRecord] = []
        for index in 1...6 {
            rows.append(record("g\(index)", "2026-0\(index)-05", 200_000, "Bills", "Gym"))
        }
        rows.append(record("spike", "2026-08-05", 900_000, "Bills", "Gym"))
        let result = InsightsEngine.generate(
            input: InsightsInput(records: rows, documentPeriods: periods, now: now),
            config: config, suppressions: Suppressions())
        XCTAssertFalse(result.cards.contains { $0.kind == .outlierAmount })
    }

    func testWithoutACompleteMonthNoTrendCardsAppear() {
        let partial = [DatePeriod(start: day("2026-08-15"), end: day("2026-09-14"))]
        let result = InsightsEngine.generate(
            input: InsightsInput(records: dataset, documentPeriods: partial, now: now),
            config: config, suppressions: Suppressions())
        XCTAssertFalse(result.cards.contains { $0.kind == .trend })
    }
}
```

- [ ] **Step 2: Run the Swift test to verify it fails**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter InsightsEngineTests`
Expected: FAIL — "cannot find 'InsightsEngine' in scope".

- [ ] **Step 3: Implement in Swift**

Create `HisabCore/Sources/HisabCore/Insights/InsightsEngine.swift`:

```swift
import Foundation

/// The single entry point the apps call: transactions in, ranked cards out.
/// Pure and stateless — insights are recomputed at every boot and import
/// rather than stored, so the only persisted state is what the user
/// dismissed or muted.
public enum InsightsEngine {
    public static func generate(input: InsightsInput, config: InsightsConfig,
                                suppressions: Suppressions) -> InsightsResult {
        let completeMonths = CompleteMonths.of(input.documentPeriods)
        let latest = CompleteMonths.latest(input.documentPeriods, notAfter: input.now)

        var monthDebitTotal: Int64 = 0
        if let month = latest {
            for row in input.records
            where row.direction == .debit && YearMonth(date: row.date) == month {
                monthDebitTotal += row.amountPaise
            }
        }

        var trends: [Insight] = []
        var concentrationIDs: Set<String> = []
        if let month = latest {
            (trends, concentrationIDs) = TrendDetector.detect(
                records: input.records, month: month, completeMonths: completeMonths,
                monthDebitTotalPaise: monthDebitTotal, config: config)
        }
        let (recurrences, claimedIDs) = RecurrenceDetector.detect(
            records: input.records, now: input.now,
            monthDebitTotalPaise: monthDebitTotal, config: config)
        let anomalies = AnomalyDetector.detect(
            records: input.records, now: input.now,
            monthDebitTotalPaise: monthDebitTotal, config: config)

        // One event, one card: a recurring payment or a trend's dominant
        // purchase is already explained — don't also call it unusual.
        let explained = claimedIDs.union(concentrationIDs)
        let deduped = anomalies.filter { insight in
            guard insight.kind == .outlierAmount else { return true }
            return !insight.evidenceIDs.contains { explained.contains($0) }
        }

        let everything = trends + recurrences + deduped
        let allIDs = Set(everything.map(\.id))

        let surviving = everything.filter { insight in
            guard !suppressions.dismissedIDs.contains(insight.id) else { return false }
            switch insight.mute {
            case .merchant(let key): return !suppressions.mutedMerchants.contains(key)
            case .category(let name): return !suppressions.mutedCategories.contains(name)
            case nil: return true
            }
        }

        let committed = surviving.filter { $0.kind == .committedSpend }
        let ranked = surviving
            .filter { $0.kind != .committedSpend }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.id < rhs.id : lhs.score > rhs.score
            }

        let budget = config.ranker.maxCards - (committed.isEmpty ? 0 : 1)
        var perKind: [InsightKind: Int] = [:]
        var cards: [Insight] = []
        for insight in ranked {
            guard cards.count < budget else { break }
            let used = perKind[insight.kind] ?? 0
            guard used < config.ranker.maxPerType else { continue }
            perKind[insight.kind] = used + 1
            cards.append(insight)
        }
        cards.append(contentsOf: committed.prefix(1))
        return InsightsResult(cards: cards, allIDs: allIDs)
    }
}
```

- [ ] **Step 4: Run the Swift test to verify it passes**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter InsightsEngineTests`
Expected: PASS (8 tests). If `testAnOutlierOnARecurringPaymentIsSuppressed` fails because the Gym series doesn't qualify (amount spread), adjust the fixture amounts — not the collision rule.

- [ ] **Step 5: Implement in Dart and mirror the tests**

Create `hisab_flutter/packages/hisab_core/lib/src/insights/insights_engine.dart` as a direct port:

```dart
/// The single entry point the apps call. Port of InsightsEngine.swift.
library;

import '../domain.dart';
import '../year_month.dart';
import 'anomaly_detector.dart';
import 'complete_months.dart';
import 'insight.dart';
import 'insights_config.dart';
import 'recurrence_detector.dart';
import 'trend_detector.dart';

class InsightsEngine {
  static InsightsResult generate({
    required InsightsInput input,
    required InsightsConfig config,
    required Suppressions suppressions,
  }) {
    final completeMonths = CompleteMonths.of(input.documentPeriods);
    final latest = CompleteMonths.latest(input.documentPeriods, input.now);

    var monthDebitTotal = 0;
    if (latest != null) {
      for (final row in input.records) {
        if (row.direction == Direction.debit &&
            YearMonth.fromDate(row.date) == latest) {
          monthDebitTotal += row.amountPaise;
        }
      }
    }

    var trends = <Insight>[];
    var concentrationIDs = <String>{};
    if (latest != null) {
      (trends, concentrationIDs) = TrendDetector.detect(
        records: input.records,
        month: latest,
        completeMonths: completeMonths,
        monthDebitTotalPaise: monthDebitTotal,
        config: config,
      );
    }
    final (recurrences, claimedIDs) = RecurrenceDetector.detect(
      records: input.records,
      now: input.now,
      monthDebitTotalPaise: monthDebitTotal,
      config: config,
    );
    final anomalies = AnomalyDetector.detect(
      records: input.records,
      now: input.now,
      monthDebitTotalPaise: monthDebitTotal,
      config: config,
    );

    // One event, one card.
    final explained = {...claimedIDs, ...concentrationIDs};
    final deduped = [
      for (final insight in anomalies)
        if (insight.kind != InsightKind.outlierAmount ||
            !insight.evidenceIDs.any(explained.contains))
          insight
    ];

    final everything = [...trends, ...recurrences, ...deduped];
    final allIDs = {for (final i in everything) i.id};

    final surviving = [
      for (final insight in everything)
        if (!suppressions.dismissedIDs.contains(insight.id) &&
            _passesMute(insight, suppressions))
          insight
    ];

    final committed = [
      for (final i in surviving)
        if (i.kind == InsightKind.committedSpend) i
    ];
    final ranked = [
      for (final i in surviving)
        if (i.kind != InsightKind.committedSpend) i
    ]..sort((l, r) =>
        l.score == r.score ? l.id.compareTo(r.id) : r.score.compareTo(l.score));

    final budget = config.ranker.maxCards - (committed.isEmpty ? 0 : 1);
    final perKind = <InsightKind, int>{};
    final cards = <Insight>[];
    for (final insight in ranked) {
      if (cards.length >= budget) break;
      final used = perKind[insight.kind] ?? 0;
      if (used >= config.ranker.maxPerType) continue;
      perKind[insight.kind] = used + 1;
      cards.add(insight);
    }
    if (committed.isNotEmpty) cards.add(committed.first);
    return InsightsResult(cards: cards, allIDs: allIDs);
  }

  static bool _passesMute(Insight insight, Suppressions suppressions) {
    final mute = insight.mute;
    return switch (mute) {
      MuteMerchant(:final merchantKey) =>
        !suppressions.mutedMerchants.contains(merchantKey),
      MuteCategory(:final category) =>
        !suppressions.mutedCategories.contains(category),
      null => true,
    };
  }
}
```

Add the export to `lib/hisab_core.dart`, then write the Dart test group mirroring all eight Swift cases.

- [ ] **Step 6: Run both full core suites**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test`
Expected: all tests pass (168 before this feature, plus the new ones).

Run: `cd hisab_flutter/packages/hisab_core && dart test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add HisabCore hisab_flutter/packages/hisab_core
git commit -m "feat(insights): engine orchestration, collision rules, ranking

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 8: Cross-platform parity fixture

**Files:**
- Create: `HisabCore/Tests/HisabCoreTests/Fixtures/insights-parity.json`
- Create: `HisabCore/Tests/HisabCoreTests/InsightsParityTests.swift`
- Modify: `hisab_flutter/packages/hisab_core/test/insights_test.dart` (add a group)
- Run: `tool/sync_assets.sh` (copies the fixture into the Dart test tree)

**Interfaces:**
- Consumes: `InsightsEngine.generate`, `InsightsConfig.fallback`.
- Produces: the committed fixture, which is the contract both platforms assert. Nothing downstream imports from this task.

The fixture is the same guard the content hashes use: one input, one expected output, asserted by both languages. If a future change alters copy or ordering on one platform only, this fails loudly.

- [ ] **Step 1: Write the fixture input**

Create `HisabCore/Tests/HisabCoreTests/Fixtures/insights-parity.json` with `expected` deliberately empty — step 3 fills it:

```json
{
  "now": "2026-09-15T00:00:00Z",
  "periods": [
    {"start": "2026-01-01T00:00:00Z", "end": "2026-08-31T18:29:59Z"}
  ],
  "records": [
    {"id": "rent-06", "date": "2026-06-05T00:00:00Z", "amountPaise": 1500000, "direction": "debit", "category": "Housing", "merchant": "Landlord"},
    {"id": "rent-07", "date": "2026-07-05T00:00:00Z", "amountPaise": 1500000, "direction": "debit", "category": "Housing", "merchant": "Landlord"},
    {"id": "rent-08", "date": "2026-08-05T00:00:00Z", "amountPaise": 1500000, "direction": "debit", "category": "Housing", "merchant": "Landlord"},
    {"id": "net-07", "date": "2026-07-09T00:00:00Z", "amountPaise": 64900, "direction": "debit", "category": "Subscriptions", "merchant": "Netflix"},
    {"id": "net-08", "date": "2026-08-09T00:00:00Z", "amountPaise": 64900, "direction": "debit", "category": "Subscriptions", "merchant": "Netflix"},
    {"id": "net-09", "date": "2026-09-09T00:00:00Z", "amountPaise": 64900, "direction": "debit", "category": "Subscriptions", "merchant": "Netflix"},
    {"id": "food-06", "date": "2026-06-12T00:00:00Z", "amountPaise": 100000, "direction": "debit", "category": "Food", "merchant": "Swiggy"},
    {"id": "food-07", "date": "2026-07-12T00:00:00Z", "amountPaise": 100000, "direction": "debit", "category": "Food", "merchant": "Swiggy"},
    {"id": "food-08a", "date": "2026-08-12T00:00:00Z", "amountPaise": 100000, "direction": "debit", "category": "Food", "merchant": "Swiggy"},
    {"id": "food-08b", "date": "2026-08-22T00:00:00Z", "amountPaise": 220000, "direction": "debit", "category": "Food", "merchant": "Swiggy"},
    {"id": "dup-1", "date": "2026-08-25T00:00:00Z", "amountPaise": 45000, "direction": "debit", "category": "Food", "merchant": "Zomato"},
    {"id": "dup-2", "date": "2026-08-25T00:00:00Z", "amountPaise": 45000, "direction": "debit", "category": "Food", "merchant": "Zomato"},
    {"id": "salary-08", "date": "2026-08-01T00:00:00Z", "amountPaise": 9000000, "direction": "credit", "category": "Income", "merchant": "Employer"}
  ],
  "expected": []
}
```

Note the period end (`2026-08-31T18:29:59Z`) is the last second of 31 August in IST, so August is complete and September is not.

- [ ] **Step 2: Write the Swift parity test**

Create `HisabCore/Tests/HisabCoreTests/InsightsParityTests.swift`:

```swift
import XCTest
@testable import HisabCore

/// One fixture, two languages. Set INSIGHTS_GT_OUT to regenerate the
/// `expected` block (same pattern as SamplesGroundTruthDump).
final class InsightsParityTests: XCTestCase {
    private struct Fixture: Codable {
        struct Row: Codable {
            let id: String
            let date: String
            let amountPaise: Int64
            let direction: String
            let category: String
            let merchant: String
        }
        struct Period: Codable {
            let start: String
            let end: String
        }
        struct Expected: Codable, Equatable {
            let id: String
            let kind: String
            let headline: String
            let detail: String
            let score: Int64
        }
        let now: String
        let periods: [Period]
        let records: [Row]
        var expected: [Expected]
    }

    private func parse(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testFixtureOutputIsStable() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "insights-parity",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures"))
        var fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let input = InsightsInput(
            records: fixture.records.map {
                InsightRecord(id: $0.id, date: parse($0.date), amountPaise: $0.amountPaise,
                              direction: $0.direction == "credit" ? .credit : .debit,
                              category: $0.category, merchant: $0.merchant)
            },
            documentPeriods: fixture.periods.map {
                DatePeriod(start: parse($0.start), end: parse($0.end))
            },
            now: parse(fixture.now))

        let result = InsightsEngine.generate(input: input, config: .fallback,
                                             suppressions: Suppressions())
        let actual = result.cards.map {
            Fixture.Expected(id: $0.id, kind: $0.kind.rawValue, headline: $0.headline,
                             detail: $0.detail, score: $0.score)
        }

        if let out = ProcessInfo.processInfo.environment["INSIGHTS_GT_OUT"] {
            fixture.expected = actual
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(fixture).write(to: URL(fileURLWithPath: out))
            print("wrote \(actual.count) expected insights to \(out)")
            return
        }

        XCTAssertFalse(fixture.expected.isEmpty,
                       "fixture has no expected output — regenerate with INSIGHTS_GT_OUT")
        XCTAssertEqual(actual, fixture.expected)
    }
}
```

- [ ] **Step 3: Generate, review, and commit the expected block**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && INSIGHTS_GT_OUT=/tmp/insights-parity.json swift test --filter InsightsParityTests`

Then **read `/tmp/insights-parity.json` and check every card by hand** before trusting it: the Netflix series should be `recurringNew` (first seen July, within 2 months of September), the Food category should show a `trend` card for August, the Zomato pair a `possibleDuplicate`, and a `committedSpend` card should close the list with rent + Netflix. If a card is missing or the copy reads wrong, fix the detector — not the fixture.

Once it reads correctly, copy it over the source fixture and re-sync:

```bash
cp /tmp/insights-parity.json HisabCore/Tests/HisabCoreTests/Fixtures/insights-parity.json
tool/sync_assets.sh
```

- [ ] **Step 4: Run the Swift test in assert mode**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd HisabCore && swift test --filter InsightsParityTests`
Expected: PASS.

- [ ] **Step 5: Write the Dart parity test**

Add to `hisab_flutter/packages/hisab_core/test/insights_test.dart`:

```dart
  group('Insights parity', () {
    test('the shared fixture produces Swift-identical cards', () {
      final fixture = jsonDecode(
              File('test/fixtures/insights-parity.json').readAsStringSync())
          as Map<String, dynamic>;

      final input = InsightsInput(
        records: [
          for (final r in fixture['records'] as List)
            InsightRecord(
              id: r['id'] as String,
              date: DateTime.parse(r['date'] as String),
              amountPaise: r['amountPaise'] as int,
              direction: r['direction'] == 'credit'
                  ? Direction.credit
                  : Direction.debit,
              category: r['category'] as String,
              merchant: r['merchant'] as String,
            )
        ],
        documentPeriods: [
          for (final p in fixture['periods'] as List)
            DatePeriod(DateTime.parse(p['start'] as String),
                DateTime.parse(p['end'] as String))
        ],
        now: DateTime.parse(fixture['now'] as String),
      );

      final result = InsightsEngine.generate(
          input: input,
          config: InsightsConfig.fallback,
          suppressions: const Suppressions());

      final expected = fixture['expected'] as List;
      expect(result.cards.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i] as Map<String, dynamic>;
        expect(result.cards[i].id, e['id']);
        expect(result.cards[i].kind.name, e['kind']);
        expect(result.cards[i].headline, e['headline']);
        expect(result.cards[i].detail, e['detail']);
        expect(result.cards[i].score, e['score']);
      }
    });
  });
```

Add `import 'dart:convert';` and `import 'dart:io';` at the top of the file if not already present.

- [ ] **Step 6: Run the Dart test to verify it passes**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/insights_test.dart`
Expected: PASS. **A failure here means the two engines disagree** — fix the port, never the fixture.

- [ ] **Step 7: Commit**

```bash
git add HisabCore hisab_flutter/packages/hisab_core
git commit -m "test(insights): cross-platform parity fixture

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 9: iOS suppression store and record projection

**Files:**
- Create: `Hisab/Services/InsightStore.swift`
- Modify: `Hisab/Services/Queries.swift` (add two projections, after `analytics`)

**Interfaces:**
- Consumes: `InsightRecord`, `Suppressions`, `MuteTarget`, `DatePeriod` from HisabCore; `StoredTransaction`, `StoredMatch`, `StoredDocument`, `CategoryRule` from the app.
- Produces: `InsightStore.suppressions`, `InsightStore.dismiss(_:)`, `InsightStore.mute(_:)`, `InsightStore.prune(keeping:)`, `InsightStore.resetForDebug()`; `Queries.insightRecords(_:matches:rules:) -> [InsightRecord]` and `Queries.insightPeriods(_:) -> [DatePeriod]`.

Note: this repo has no iOS app test target — app-layer code is verified by the build plus the simulator run in Task 13. Do not add a test target for this task.

- [ ] **Step 1: Write the suppression store**

Create `Hisab/Services/InsightStore.swift`:

```swift
import Foundation
import HisabCore

/// What the user has dismissed or muted on the insight strip. Device
/// preference, not financial data — UserDefaults, same tier as the
/// suggestion prompt's schedule.
enum InsightStore {
    static let dismissedKey = "insights.dismissed"
    static let mutedMerchantsKey = "insights.mutedMerchants"
    static let mutedCategoriesKey = "insights.mutedCategories"

    private static func set(_ key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private static func insert(_ value: String, into key: String) {
        var current = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !current.contains(value) { current.append(value) }
        UserDefaults.standard.set(current, forKey: key)
    }

    static var suppressions: Suppressions {
        Suppressions(dismissedIDs: set(dismissedKey),
                     mutedMerchants: set(mutedMerchantsKey),
                     mutedCategories: set(mutedCategoriesKey))
    }

    static func dismiss(_ id: String) {
        insert(id, into: dismissedKey)
    }

    static func mute(_ target: MuteTarget) {
        switch target {
        case .merchant(let key): insert(key, into: mutedMerchantsKey)
        case .category(let name): insert(name, into: mutedCategoriesKey)
        }
    }

    /// Drops dismissals for insights that no longer generate, so the stored
    /// set can't grow without bound as months roll by.
    static func prune(keeping live: Set<String>) {
        let stored = set(dismissedKey)
        let kept = stored.intersection(live)
        guard kept.count != stored.count else { return }
        UserDefaults.standard.set(Array(kept).sorted(), forKey: dismissedKey)
    }

    static func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: dismissedKey)
        UserDefaults.standard.removeObject(forKey: mutedMerchantsKey)
        UserDefaults.standard.removeObject(forKey: mutedCategoriesKey)
    }
}
```

- [ ] **Step 2: Add the projections to Queries**

In `Hisab/Services/Queries.swift`, insert directly after the `analytics(txns:matches:rules:)` function:

```swift
    /// Insight input: the same counted rows analytics uses, carrying the row
    /// id so a card can point back at its evidence.
    static func insightRecords(_ txns: [StoredTransaction], matches: [StoredMatch],
                               rules: [CategoryRule]) -> [InsightRecord] {
        let selfTransfers = selfTransferUUIDs(in: txns)
        return visible(txns, matches: matches)
            .filter { !selfTransfers.contains($0.uuid) }
            .map { txn in
                InsightRecord(id: txn.uuid.uuidString,
                              date: txn.date,
                              amountPaise: txn.amountPaise,
                              direction: txn.direction,
                              category: effectiveCategory(of: txn, rules: rules,
                                                          selfTransfers: []),
                              merchant: txn.counterparty.isEmpty ? txn.narration
                                                                 : txn.counterparty)
            }
    }

    static func insightPeriods(_ documents: [StoredDocument]) -> [DatePeriod] {
        documents.map(\.period)
    }
```

- [ ] **Step 3: Verify the app still builds**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); xcodegen generate && xcodebuild -project Hisab.xcodeproj -scheme Hisab -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`. (`xcodegen generate` is required whenever files are added under `Hisab/` — new sources are invisible to the project otherwise.)

- [ ] **Step 4: Commit**

```bash
git add Hisab/Services
git commit -m "feat(insights): iOS suppression store and record projection

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 10: iOS insight strip, evidence sheet, dashboard mount

**Files:**
- Create: `Hisab/Views/Components/InsightStrip.swift`
- Create: `Hisab/Views/InsightEvidenceSheet.swift`
- Modify: `Hisab/Views/DashboardView.swift`

**Interfaces:**
- Consumes: `Insight`, `InsightKind`, `RecurringSeries`, `InsightsEngine`, `InsightsConfig`, `InsightsInput` from HisabCore; `InsightStore`, `Queries.insightRecords`, `Queries.insightPeriods` from Task 9.
- Produces: `InsightStrip(insights:onOpen:onDismiss:onMute:)` and `InsightEvidenceSheet(insight:transactions:)`, both used only by `DashboardView`.

- [ ] **Step 1: Build the strip and card views**

Create `Hisab/Views/Components/InsightStrip.swift`:

```swift
import SwiftUI
import HisabCore

/// The "For you" strip: at most five neutral observations, furniture rather
/// than notification — no badges, no unread counts, no entrance animation.
struct InsightStrip: View {
    let insights: [Insight]
    let onOpen: (Insight) -> Void
    let onDismiss: (Insight) -> Void
    let onMute: (Insight) -> Void

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("For you")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HisabTheme.primaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(insights) { insight in
                            InsightCard(insight: insight,
                                        onOpen: { onOpen(insight) },
                                        onDismiss: { onDismiss(insight) },
                                        onMute: { onMute(insight) })
                                .containerRelativeFrame(.horizontal, count: 1,
                                                        span: 1, spacing: 12) { width, _ in
                                    width * 0.85
                                }
                        }
                    }
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

private struct InsightCard: View {
    let insight: Insight
    let onOpen: () -> Void
    let onDismiss: () -> Void
    let onMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(caption)
                Spacer()
                if insight.kind != .committedSpend {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accent)

            Text(insight.headline)
                .font(.headline)
                .foregroundStyle(HisabTheme.primaryText)
            Text(insight.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(HisabTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            if insight.mute != nil {
                Button("Don't show insights like this", action: onMute)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption). \(insight.headline). \(insight.detail)")
        .accessibilityAddTraits(.isButton)
    }

    private var caption: String {
        switch insight.kind {
        case .trend: "TREND"
        case .recurringNew, .recurringChanged: "RECURRING"
        case .committedSpend: "COMMITTED"
        case .possibleDuplicate, .outlierAmount: "UNUSUAL"
        }
    }

    private var icon: String {
        switch insight.kind {
        // Display-only: the core copy starts with "up "/"down ", pinned by
        // the parity fixture, so the arrow can't drift from the sentence.
        case .trend: insight.detail.hasPrefix("down") ? "arrow.down.right" : "arrow.up.right"
        case .recurringNew, .recurringChanged: "arrow.triangle.2.circlepath"
        case .committedSpend: "calendar"
        case .possibleDuplicate: "doc.on.doc"
        case .outlierAmount: "exclamationmark.triangle"
        }
    }

    private var accent: Color {
        switch insight.kind {
        case .trend: insight.detail.hasPrefix("down") ? HisabTheme.hara : HisabTheme.khataRed
        case .recurringNew, .recurringChanged: HisabTheme.primaryText
        case .committedSpend, .possibleDuplicate, .outlierAmount: HisabTheme.sona
        }
    }
}
```

- [ ] **Step 2: Build the evidence sheet**

Create `Hisab/Views/InsightEvidenceSheet.swift`:

```swift
import SwiftUI
import HisabCore

/// Every card answers "show me why": the rows behind the number, or for the
/// committed-spend card, the recurring series that make it up.
struct InsightEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let insight: Insight
    let transactions: [StoredTransaction]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(insight.headline).font(.headline)
                    Text(insight.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                if insight.kind == .committedSpend {
                    Section("Recurring payments") {
                        ForEach(insight.series, id: \.merchantKey) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayMerchant)
                                Text("\(Money.formatPaise(entry.medianPaise)) "
                                     + (entry.cadence == .monthly ? "per month" : "per week")
                                     + " · since \(YearMonth(date: entry.firstSeen).displayName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Section("Transactions") {
                        ForEach(evidence, id: \.uuid) { txn in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(txn.counterparty.isEmpty ? txn.narration : txn.counterparty)
                                        .lineLimit(1)
                                    Text(txn.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.formatPaise(txn.amountPaise))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Why this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var evidence: [StoredTransaction] {
        let wanted = Set(insight.evidenceIDs)
        return transactions
            .filter { wanted.contains($0.uuid.uuidString) }
            .sorted { $0.date > $1.date }
    }
}
```

- [ ] **Step 3: Mount the strip on the dashboard**

In `Hisab/Views/DashboardView.swift`:

1. Add state, next to the existing `@State` properties:

```swift
    @State private var openInsight: Insight?
    @State private var suppressionsVersion = 0
```

2. In `content`, compute the result and insert the strip as the first element of the populated `VStack`, immediately after `MonthChipRow`:

```swift
        let insightResult = InsightsEngine.generate(
            input: InsightsInput(
                records: Queries.insightRecords(storedTxns, matches: matchRows,
                                                rules: Queries.rules(from: ruleRows)),
                documentPeriods: Queries.insightPeriods(storedDocs),
                now: Date()),
            config: InsightsConfig.bundled(),
            suppressions: InsightStore.suppressions)
```

and inside the `VStack(spacing: 16)`:

```swift
                InsightStrip(insights: insightResult.cards,
                             onOpen: { openInsight = $0 },
                             onDismiss: { insight in
                                 InsightStore.dismiss(insight.id)
                                 suppressionsVersion += 1
                             },
                             onMute: { insight in
                                 if let target = insight.mute { InsightStore.mute(target) }
                                 suppressionsVersion += 1
                             })
                    .id(suppressionsVersion)
```

`suppressionsVersion` exists only to re-run the body after a UserDefaults write, which SwiftUI cannot observe on its own.

3. Attach the sheet next to the existing `.sheet(isPresented: $showImport)`:

```swift
            .sheet(item: $openInsight) { insight in
                InsightEvidenceSheet(insight: insight, transactions: storedTxns)
            }
```

4. Prune stale dismissals inside the existing `.task`, at the end of the closure:

```swift
                InsightStore.prune(keeping: insightResultIDsForPruning)
```

To make that available, hoist the generated ids into state: add `@State private var liveInsightIDs: Set<String> = []`, set it in `content` via `.onAppear { liveInsightIDs = insightResult.allIDs }` on the `VStack`, and prune with `InsightStore.prune(keeping: liveInsightIDs)`. Guard the prune with `if !liveInsightIDs.isEmpty` so an empty first render can't wipe the set.

5. Add `--reset-insights` to the debug launch arguments handled in `.task`, alongside the existing ones:

```swift
                if args.contains("--reset-insights") { InsightStore.resetForDebug() }
```

- [ ] **Step 4: Build and check it renders**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); xcodegen generate && xcodebuild -project Hisab.xcodeproj -scheme Hisab -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

Then boot a simulator, install, and launch with `--seed-demo --reset-insights`. Expected: the dashboard shows a "For you" strip. If it is empty, that is a legitimate outcome for the current demo data — Task 13 extends the demo set so it never is. Do not tune thresholds to force cards.

- [ ] **Step 5: Commit**

```bash
git add Hisab/Views
git commit -m "feat(insights): iOS For-you strip, evidence sheet, dashboard mount

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 11: Android suppression store, projection, and config wiring

**Files:**
- Create: `hisab_flutter/lib/services/insight_store.dart`
- Modify: `hisab_flutter/lib/services/queries.dart` (add two projections)
- Modify: `hisab_flutter/lib/state.dart` (carry the config and current suppressions)
- Modify: `hisab_flutter/lib/main.dart` (load the config asset and initial suppressions)
- Test: `hisab_flutter/test/services_test.dart` (add a projection test)

**Interfaces:**
- Consumes: `InsightRecord`, `Suppressions`, `MuteTarget`, `InsightsConfig`, `DatePeriod`.
- Produces: `InsightStore.load()`, `.dismiss(String)`, `.mute(MuteTarget)`, `.prune(Set<String>)`, `.resetForDebug()`; `Queries.insightRecords(txns, matches, ruleList)`, `Queries.insightPeriods(documents)`; `AppState.insightsConfig` and `AppState.suppressions`.

- [ ] **Step 1: Write the failing projection test**

Add to `hisab_flutter/test/services_test.dart`, inside the existing `main()`:

```dart
  test('insightRecords carries row ids and excludes matched bank rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.storedDocuments).insert(StoredDocumentsCompanion.insert(
          id: 'doc-1',
          sourceRaw: 'gpay',
          filename: 'demo.csv',
          fileSha256: 'hash-1',
          periodStartMs: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
          periodEndMs: DateTime.utc(2026, 8, 31).millisecondsSinceEpoch,
        ));
    await db.into(db.storedTransactions).insert(StoredTransactionsCompanion.insert(
          id: 'txn-1',
          uuid: 'uuid-1',
          documentId: 'doc-1',
          sourceRaw: 'gpay',
          dateMs: DateTime.utc(2026, 8, 12).millisecondsSinceEpoch,
          amountPaise: 45000,
          direction: 'debit',
          counterparty: 'Swiggy',
          narration: 'UPI payment',
          contentHash: 'ch-1',
        ));

    final txns = await db.select(db.storedTransactions).get();
    final records = Queries.insightRecords(txns, const [], const []);
    expect(records.length, 1);
    expect(records.first.id, 'uuid-1');
    expect(records.first.merchant, 'Swiggy');
    expect(records.first.amountPaise, 45000);

    final docs = await db.select(db.storedDocuments).get();
    expect(Queries.insightPeriods(docs).length, 1);
  });
```

Adjust the companion field names to whatever `storage/database.dart` actually declares — read it first rather than guessing; the existing tests in this file show the correct shape.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd hisab_flutter && flutter test test/services_test.dart`
Expected: FAIL — `insightRecords` is not defined.

- [ ] **Step 3: Add the projections**

In `hisab_flutter/lib/services/queries.dart`, after `analytics`:

```dart
  /// Insight input: the same counted rows analytics uses, carrying the row
  /// id so a card can point back at its evidence.
  static List<InsightRecord> insightRecords(List<StoredTransaction> txns,
      List<StoredMatche> matches, List<CategoryRule> ruleList) {
    final selfTransfers = selfTransferUuids(txns);
    return [
      for (final txn in visible(txns, matches))
        if (!selfTransfers.contains(txn.uuid))
          InsightRecord(
            id: txn.uuid,
            date: dateOf(txn),
            amountPaise: txn.amountPaise,
            direction: directionOf(txn),
            category: effectiveCategory(txn, ruleList, selfTransfers),
            merchant:
                txn.counterparty.isEmpty ? txn.narration : txn.counterparty,
          )
    ];
  }

  static List<DatePeriod> insightPeriods(List<StoredDocument> documents) => [
        for (final doc in documents)
          DatePeriod(
              DateTime.fromMillisecondsSinceEpoch(doc.periodStartMs,
                  isUtc: true),
              DateTime.fromMillisecondsSinceEpoch(doc.periodEndMs, isUtc: true))
      ];
```

- [ ] **Step 4: Write the suppression store**

Create `hisab_flutter/lib/services/insight_store.dart`:

```dart
/// What the user dismissed or muted on the insight strip. Device
/// preference, not financial data — SharedPreferences, the same tier as
/// the suggestion prompt's schedule. Mirrors InsightStore.swift.
library;

import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InsightStore {
  static const dismissedKey = 'insights.dismissed';
  static const mutedMerchantsKey = 'insights.mutedMerchants';
  static const mutedCategoriesKey = 'insights.mutedCategories';

  static Future<Suppressions> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Suppressions(
      dismissedIDs: (prefs.getStringList(dismissedKey) ?? const []).toSet(),
      mutedMerchants:
          (prefs.getStringList(mutedMerchantsKey) ?? const []).toSet(),
      mutedCategories:
          (prefs.getStringList(mutedCategoriesKey) ?? const []).toSet(),
    );
  }

  static Future<void> _insert(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(key) ?? [];
    if (!current.contains(value)) {
      current.add(value);
      await prefs.setStringList(key, current);
    }
  }

  static Future<void> dismiss(String id) => _insert(dismissedKey, id);

  static Future<void> mute(MuteTarget target) => switch (target) {
        MuteMerchant(:final merchantKey) =>
          _insert(mutedMerchantsKey, merchantKey),
        MuteCategory(:final category) => _insert(mutedCategoriesKey, category),
      };

  /// Drops dismissals for insights that no longer generate.
  static Future<void> prune(Set<String> live) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(dismissedKey) ?? const [];
    final kept = [
      for (final id in stored)
        if (live.contains(id)) id
    ];
    if (kept.length != stored.length) {
      await prefs.setStringList(dismissedKey, kept);
    }
  }

  static Future<void> resetForDebug() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(dismissedKey);
    await prefs.remove(mutedMerchantsKey);
    await prefs.remove(mutedCategoriesKey);
  }
}
```

- [ ] **Step 5: Carry the config and suppressions in AppState**

In `hisab_flutter/lib/state.dart`, extend `AppState`:

```dart
  final InsightsConfig insightsConfig;

  /// Refreshed from InsightStore whenever the user dismisses or mutes.
  Suppressions suppressions;
```

and the constructor:

```dart
  AppState({
    required this.db,
    required this.importService,
    required this.ruleset,
    required this.insightsConfig,
    this.suppressions = const Suppressions(),
  }) {
    snapshots = _combine();
  }
```

In `hisab_flutter/lib/main.dart`, load the asset and the stored suppressions before constructing `AppState`:

```dart
  final insightsConfig = InsightsConfig.fromJsonString(
      await rootBundle.loadString('assets/insights/insights-config.json'));
  final suppressions = await InsightStore.load();
```

and pass `insightsConfig: insightsConfig, suppressions: suppressions` into the `AppState(...)` call. Add `import 'services/insight_store.dart';`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd hisab_flutter && flutter test test/services_test.dart`
Expected: PASS (5 tests).

Run: `cd hisab_flutter && flutter analyze`
Expected: no errors or warnings (pre-existing `unintended_html_in_doc_comment` infos are fine).

- [ ] **Step 7: Commit**

```bash
git add hisab_flutter/lib hisab_flutter/test
git commit -m "feat(insights): Android suppression store, projection, config wiring

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 12: Android insight strip, evidence sheet, dashboard mount

**Files:**
- Create: `hisab_flutter/lib/widgets/insight_strip.dart`
- Create: `hisab_flutter/lib/widgets/insight_evidence_sheet.dart`
- Modify: `hisab_flutter/lib/screens/dashboard_screen.dart`

**Interfaces:**
- Consumes: `InsightsEngine`, `Insight`, `InsightKind`, `RecurringSeries`, `AppState.insightsConfig`, `AppState.suppressions`, `InsightStore`, `Queries.insightRecords`, `Queries.insightPeriods`.
- Produces: `InsightStrip` and `showInsightEvidence(...)`, used only by `DashboardScreen`.

- [ ] **Step 1: Build the strip widget**

Create `hisab_flutter/lib/widgets/insight_strip.dart`:

```dart
/// The "For you" strip — mirrors InsightStrip.swift. Furniture, not
/// notification: no badges, no counts, no entrance animation.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../theme.dart';

class InsightStrip extends StatelessWidget {
  final List<Insight> insights;
  final void Function(Insight) onOpen;
  final void Function(Insight) onDismiss;
  final void Function(Insight) onMute;

  const InsightStrip({
    super.key,
    required this.insights,
    required this.onOpen,
    required this.onDismiss,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width * 0.85;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('For you',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: insights.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SizedBox(
              width: width,
              child: _InsightCard(
                insight: insights[index],
                onOpen: () => onOpen(insights[index]),
                onDismiss: () => onDismiss(insights[index]),
                onMute: () => onMute(insights[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final Insight insight;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onMute;

  const _InsightCard({
    required this.insight,
    required this.onOpen,
    required this.onDismiss,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$_caption. ${insight.headline}. ${insight.detail}',
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onOpen,
          onLongPress: insight.mute == null ? null : () => _showMute(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icon, size: 14, color: _accent),
                    const SizedBox(width: 4),
                    Text(_caption,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _accent)),
                    const Spacer(),
                    if (insight.kind != InsightKind.committedSpend)
                      GestureDetector(
                        onTap: onDismiss,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.close,
                              size: 14, color: Colors.black45),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(insight.headline,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(insight.detail,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMute(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: const Text("Don't show insights like this"),
          onTap: () {
            Navigator.pop(sheetContext);
            onMute();
          },
        ),
      ),
    );
  }

  String get _caption => switch (insight.kind) {
        InsightKind.trend => 'TREND',
        InsightKind.recurringNew ||
        InsightKind.recurringChanged =>
          'RECURRING',
        InsightKind.committedSpend => 'COMMITTED',
        InsightKind.possibleDuplicate ||
        InsightKind.outlierAmount =>
          'UNUSUAL',
      };

  // Display-only: core copy starts with "up "/"down ", pinned by the parity
  // fixture, so the arrow can't drift from the sentence.
  bool get _isDrop => insight.detail.startsWith('down');

  IconData get _icon => switch (insight.kind) {
        InsightKind.trend =>
          _isDrop ? Icons.south_east : Icons.north_east,
        InsightKind.recurringNew || InsightKind.recurringChanged => Icons.repeat,
        InsightKind.committedSpend => Icons.calendar_month,
        InsightKind.possibleDuplicate => Icons.copy_all,
        InsightKind.outlierAmount => Icons.warning_amber,
      };

  Color get _accent => switch (insight.kind) {
        InsightKind.trend =>
          _isDrop ? HisabTheme.hara : HisabTheme.khataRed,
        InsightKind.recurringNew || InsightKind.recurringChanged =>
          HisabTheme.ink,
        InsightKind.committedSpend ||
        InsightKind.possibleDuplicate ||
        InsightKind.outlierAmount =>
          HisabTheme.sona,
      };
}
```

- [ ] **Step 2: Build the evidence sheet**

Create `hisab_flutter/lib/widgets/insight_evidence_sheet.dart`:

```dart
/// "Show me why" for a card — mirrors InsightEvidenceSheet.swift.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../services/queries.dart';
import '../storage/database.dart';

void showInsightEvidence(
    BuildContext context, Insight insight, List<StoredTransaction> txns) {
  final wanted = insight.evidenceIDs.toSet();
  final rows = [
    for (final txn in txns)
      if (wanted.contains(txn.uuid)) txn
  ]..sort((a, b) => b.dateMs.compareTo(a.dateMs));

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(insight.headline,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(insight.detail,
                style: const TextStyle(color: Colors.black54)),
            const Divider(height: 28),
            if (insight.kind == InsightKind.committedSpend)
              for (final entry in insight.series)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.displayMerchant),
                  subtitle: Text('${Money.formatPaise(entry.medianPaise)} '
                      '${entry.cadence == Cadence.monthly ? 'per month' : 'per week'}'
                      ' · since ${YearMonth.fromDate(entry.firstSeen).displayName}'),
                )
            else
              for (final txn in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      txn.counterparty.isEmpty ? txn.narration : txn.counterparty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(istDayString(dateOf(txn))),
                  trailing: Text(Money.formatPaise(txn.amountPaise),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 3: Mount it on the dashboard**

In `hisab_flutter/lib/screens/dashboard_screen.dart`:

1. Add the imports for `insight_strip.dart`, `insight_evidence_sheet.dart`, and `../services/insight_store.dart`.
2. In `_body(Snapshot data)`, after `final merchants = ...`, compute:

```dart
    final state = AppScope.of(context);
    final insights = InsightsEngine.generate(
      input: InsightsInput(
        records: Queries.insightRecords(data.txns, data.matches, ruleList),
        documentPeriods: Queries.insightPeriods(data.documents),
        now: DateTime.now(),
      ),
      config: state.insightsConfig,
      suppressions: state.suppressions,
    );
```

3. Insert into the `ListView` children, right after the month-chip `SizedBox` and its `SizedBox(height: 8)`:

```dart
        InsightStrip(
          insights: insights.cards,
          onOpen: (insight) =>
              showInsightEvidence(context, insight, data.txns),
          onDismiss: (insight) async {
            await InsightStore.dismiss(insight.id);
            final refreshed = await InsightStore.load();
            if (mounted) setState(() => state.suppressions = refreshed);
          },
          onMute: (insight) async {
            final target = insight.mute;
            if (target == null) return;
            await InsightStore.mute(target);
            final refreshed = await InsightStore.load();
            if (mounted) setState(() => state.suppressions = refreshed);
          },
        ),
        if (insights.cards.isNotEmpty) const SizedBox(height: 8),
```

4. Prune stale dismissals once per launch. Add to `_DashboardScreenState`:

```dart
  bool _pruned = false;
```

and at the end of the `insights` computation in `_body`:

```dart
    if (!_pruned && insights.allIDs.isNotEmpty) {
      _pruned = true;
      InsightStore.prune(insights.allIDs);
    }
```

- [ ] **Step 4: Verify**

Run: `cd hisab_flutter && flutter analyze`
Expected: no errors or warnings.

Run: `cd hisab_flutter && flutter test --exclude-tags samples`
Expected: PASS.

Run: `J=$(~/.claude/scripts/cpu-gate.sh); cd hisab_flutter && flutter build apk --debug`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add hisab_flutter/lib
git commit -m "feat(insights): Android For-you strip, evidence sheet, dashboard mount

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
```

---

### Task 13: Demo data that always produces cards, then end-to-end verification

**Files:**
- Modify: `Hisab/Resources/demo-gpay.csv`, `Hisab/Resources/demo-hdfc.csv`
- Modify: `hisab_flutter/assets/demo/demo-gpay.csv`, `hisab_flutter/assets/demo/demo-hdfc.csv` (identical content)
- Modify: `Hisab/Services/DemoData.swift`, `hisab_flutter/lib/services/demo_data.dart` (shift demo dates to the present)
- Modify: `README.md` (one feature line)
- Modify: `docs/superpowers/specs/2026-09-18-spending-insights-design.md` (status line)
- Test: `HisabCore/Tests/HisabCoreTests/` — none; verification is the two device runs below

**Interfaces:**
- Consumes: everything built so far.
- Produces: nothing downstream. This task closes the feature.

**Why the date shift:** the demo statements carry fixed 2026 dates. Recurrence needs a series that is *active now*, and anomalies only look back 35 days, so a frozen demo set stops producing cards as months pass — and the Play pre-launch robots and any reviewer would see an empty strip. Shifting the demo months forward at load time fixes that permanently.

- [ ] **Step 1: Shift demo dates to the present, iOS**

In `Hisab/Services/DemoData.swift`, add a rewrite step applied to each CSV's text before it is handed to the import service:

```swift
    /// The demo statements carry fixed dates. Slide every month forward so
    /// the newest demo month is the last complete month relative to today —
    /// otherwise the demo set silently stops producing insights as time passes.
    static func shiftToPresent(_ csv: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let pattern = try! NSRegularExpression(pattern: "\\d{4}-\\d{2}-\\d{2}")
        let full = NSRange(csv.startIndex..., in: csv)
        var dates: [Date] = []
        pattern.enumerateMatches(in: csv, range: full) { match, _, _ in
            if let range = match.flatMap({ Range($0.range, in: csv) }),
               let date = formatter.date(from: String(csv[range])) {
                dates.append(date)
            }
        }
        guard let newest = dates.max() else { return csv }

        let target = YearMonth(date: Date()).advanced(by: -1)
        let source = YearMonth(date: newest)
        let shift = (target.year * 12 + target.month) - (source.year * 12 + source.month)
        guard shift != 0 else { return csv }

        var result = ""
        var cursor = csv.startIndex
        pattern.enumerateMatches(in: csv, range: full) { match, _, _ in
            guard let range = match.flatMap({ Range($0.range, in: csv) }),
                  let date = formatter.date(from: String(csv[range])) else { return }
            result += csv[cursor..<range.lowerBound]
            result += formatter.string(from: shifted(date, byMonths: shift))
            cursor = range.upperBound
        }
        result += csv[cursor...]
        return result
    }

    /// Same day-of-month in the shifted month, clamped to its length.
    private static func shifted(_ date: Date, byMonths shift: Int) -> Date {
        let cal = YearMonth.istCalendar
        let day = cal.component(.day, from: date)
        let month = YearMonth(date: date).advanced(by: shift)
        var comps = DateComponents()
        comps.year = month.year
        comps.month = month.month
        comps.day = 1
        let first = cal.date(from: comps)!
        let length = cal.range(of: .day, in: .month, for: first)?.count ?? 28
        comps.day = min(day, length)
        return cal.date(from: comps)!
    }
```

Then change `load` so each CSV is read, shifted, written to a temporary file, and imported from there rather than from the bundle URL directly. Keep the existing `overrideSource:` arguments unchanged.

- [ ] **Step 2: Shift demo dates to the present, Android**

Port the same two functions into `hisab_flutter/lib/services/demo_data.dart` as `shiftToPresent(String csv)` and `_shifted(DateTime, int)`, using `RegExp(r'\d{4}-\d{2}-\d{2}')`, `istDayString`, and `YearMonth.advancedBy`. Apply it to each asset string before `importBytes`.

- [ ] **Step 3: Extend the demo statements so every card kind appears**

Edit the four CSVs (iOS and Flutter copies must stay byte-identical — `tool/sync_assets.sh` does not cover demo data, so copy by hand and diff). Across the newest three demo months, ensure:

| Card kind | What to add |
|---|---|
| `recurringNew` | A ₹649 "Netflix" debit on the 9th of each of the last three demo months |
| `recurringChanged` | A ₹1,500 "Gym Membership" debit on the 3rd of each of the last six demo months, with the newest one at ₹1,800 |
| `committedSpend` | Satisfied automatically once two series exist (Netflix + Gym) |
| `trend` | "Swiggy" debits totalling ~₹1,000/month in the two older months and ~₹2,500 in the newest complete month, all categorized Food Delivery by the bundled ruleset |
| `possibleDuplicate` | Two identical ₹450 "Zomato" debits on the same day in the newest complete month |
| `outlierAmount` | Six "Blue Tokai" debits of ~₹300 across the older months, then one ₹2,500 in the newest complete month |

Keep the running balances consistent — the synthetic CSV parser validates the balance chain, and a broken chain will make the demo import fail outright.

- [ ] **Step 4: Verify end to end on iOS**

```bash
J=$(~/.claude/scripts/cpu-gate.sh)
xcodegen generate
xcodebuild -project Hisab.xcodeproj -scheme Hisab -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Boot a simulator, install the built app, and launch with `--seed-demo --reset-insights`. Confirm by eye:
- the "For you" strip renders at most five cards, committed-spend last;
- at least one card of each kind appears across the strip;
- tapping a card opens the evidence sheet listing the right transactions;
- dismissing a card removes it and it does not return after relaunch;
- long-pressing offers the mute action and muting silences that merchant/category.

Capture a screenshot of the dashboard for the record.

- [ ] **Step 5: Verify end to end on Android**

```bash
J=$(~/.claude/scripts/cpu-gate.sh)
cd hisab_flutter
flutter build apk --release --target-platform android-arm64 --dart-define=SEED_DEMO=true
```

Start the `Medium_Phone_API_36.1` emulator (not `Pixel_9_Pro` — its disk is nearly full), install the APK, and run the same five checks. If `adb` misbehaves, `adb kill-server && adb start-server`. Capture `adb exec-out screencap -p > /tmp/android-insights.png`.

Compare the two screenshots: the same cards, in the same order, with the same copy. Any difference in wording or ordering is a parity bug — fix the core, not the UI.

- [ ] **Step 6: Update the docs**

In `README.md`, add one bullet to the feature list, in the existing voice:

```markdown
- **Spending insights** — neutral, on-device observations at the top of the dashboard: category trends against your own average, new or changed recurring payments, committed monthly spend, and possible duplicate charges. Every card opens the transactions behind it.
```

In `docs/superpowers/specs/2026-09-18-spending-insights-design.md`, change the status line to `Status: implemented (2026-09-21)`.

- [ ] **Step 7: Run everything CI runs**

```bash
J=$(~/.claude/scripts/cpu-gate.sh)
tool/sync_assets.sh --check
cd HisabCore && swift test
cd ../hisab_flutter/packages/hisab_core && dart test
cd ../.. && flutter test --exclude-tags samples
cd packages/hisab_pdf && flutter test
```

Expected: every suite passes and `--check` reports no drift. Fix any drift by running `tool/sync_assets.sh` and committing the result.

- [ ] **Step 8: Commit and open the PR**

```bash
git add -A
git commit -m "feat(insights): demo data that always produces cards, docs

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0156QLRwiceqjHcj59oBkgfF"
gh auth switch -u VedantS01
git push -u origin feat/insights
gh pr create --repo VedantS01/hisab --base main --head feat/insights \
  --title "Spending insights: proactive dashboard cards on both platforms" \
  --body-file <the PR body: what, why, the parity story, the five manual checks>
gh auth switch -u vedantsab00
```

---

## Self-Review

Checked against `docs/superpowers/specs/2026-09-18-spending-insights-design.md`:

| Spec section | Covered by |
|---|---|
| Pure `generateInsights(input, config, suppressed)` | Task 7 |
| Complete-month rule | Task 3, enforced in Tasks 4 and 7 |
| Content-derived insight ids | Task 2 (pinned digests) |
| TrendDetector incl. concentration annotation | Task 4 |
| RecurrenceDetector: new / changed / committed | Task 5 |
| AnomalyDetector: duplicates + outliers | Task 6 |
| Ranking, caps, variety guard, collision rules | Task 7 |
| Dismiss / mute / prune | Tasks 9 (iOS) and 11 (Android) |
| "For you" strip, card anatomy, evidence tap-through | Tasks 10 and 12 |
| Bundled config JSON + sync + CI drift check | Task 1, re-checked in Task 13 |
| Cross-platform parity fixture | Task 8 |
| Demo data producing every card type | Task 13 |
| Zero network, no notifications | Global Constraints; nothing in any task adds a dependency |

**Three deliberate deviations from the spec, to be reflected back into it:**

1. **Scores are integers, not floats.** The spec said "magnitude × weight × recency"; this plan drops the recency factor (every detector already bounds its own window, so everything emitted is current) and uses integer permille arithmetic so ordering can never diverge between Swift and Dart.
2. **Tap-through opens an evidence sheet, not the filtered Transactions tab.** The spec described driving the Transactions tab; a self-contained sheet delivers the same "show me why" without plumbing tab-selection state through both apps, and works identically on each.
3. **The committed-spend card is neither dismissible nor mutable.** The spec left it mutable via overflow; with a single pinned summary card there is no sensible mute target, so it simply has `mute: nil`.

Also added, not in the spec: `activeWithinCadences` (a series goes stale after two missed cadences, so cancelled subscriptions stop counting as committed spend) and the demo-data date shift in Task 13.

**Type consistency check:** `InsightRecord`, `Insight`, `RecurringSeries`, `Suppressions`, `InsightsResult`, `MuteTarget`, `InsightKind`, `Cadence` are defined once in Task 2 and used with identical field names in Tasks 4–12. `RecurrenceDetector.median` is defined in Task 5 and reused by Task 6. `CompleteMonths.of`/`.latest` from Task 3 are used only in Task 7. `TrendDetector.detect` and `RecurrenceDetector.detect` both return a tuple whose second element feeds the collision rule in Task 7.

