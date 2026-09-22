# Near-Real-Time Transaction Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture bank/UPI transaction alerts within seconds of a payment, and when Hisab cannot categorize one, ask the user immediately — turning the answer into a categorization rule that fixes that payee forever, past and future.

**Architecture:** Alerts become `PendingMemo` rows, never ledger transactions (they carry no UTR, so they cannot join content-hash dedup or balance-chain validation). A memo's durable output is a `StoredCategoryRule`. Android captures via `NotificationListenerService`; iOS exposes one trigger-agnostic App Intent reachable from a Shortcuts automation *or* the share sheet. Parsing lives in the two parity-pinned cores.

**Tech Stack:** Swift 6 / SwiftData / App Intents / UserNotifications (iOS 18 target); Flutter / drift / `notification_listener_service` (Android); pure-Swift `HisabCore` + pure-Dart `hisab_core` with shared JSON parity fixtures.

**Spec:** `docs/superpowers/specs/2026-09-22-realtime-capture-design.md`

## Global Constraints

- **Zero network.** No networking dependency may be added, ever. No sockets, no analytics, no remote config. `mailto:` only. This is load-bearing for both store listings.
- **Memos are never ledger entries.** `PendingMemo` must not appear in month buckets, analytics, insights, reconciliation or self-transfer detection.
- **`READ_SMS` must never be added to the Android manifest.** Play's permitted uses are default SMS/Phone/Assistant handler only; expense tracking is absent from the exception table; the exception route requires an APK published before 2019-01-01. Adding it gets the app removed.
- **Raw alert text is never persisted.** Only parsed fields reach storage.
- **Money is integer paise.** Never floating point. Display via `Money.formatPaise` / Dart equivalent.
- **Two cores stay behaviourally identical**, pinned by fixtures under `HisabCore/Tests/HisabCoreTests/Fixtures/` and synced to Dart by `tool/sync_assets.sh`. Run `tool/sync_assets.sh` after touching any fixture; CI runs `--check`.
- **Timezone is Asia/Kolkata** for every date derivation. Use `YearMonth.istCalendar` in Swift; the Dart twin's existing IST helpers in Dart.
- **Capture is off by default** and reversible in one tap.
- **Version: 1.3.0.** iOS `MARKETING_VERSION: "1.3.0"`, `CURRENT_PROJECT_VERSION: 4`; Flutter `version: 1.3.0+3`.
- **CPU discipline:** before any build or test suite, run `J=$(~/.claude/scripts/cpu-gate.sh)` and cap parallelism to `$J` (never above 5).

## File Structure

**Core — new, mirrored in both languages:**

| Swift | Dart | Responsibility |
|---|---|---|
| `HisabCore/Sources/HisabCore/Capture/PendingMemo.swift` | `hisab_flutter/packages/hisab_core/lib/src/capture/pending_memo.dart` | The memo value type, `captureHash`, `RuleKey` |
| `HisabCore/Sources/HisabCore/Capture/AlertParser.swift` | `.../capture/alert_parser.dart` | Alert text → `PendingMemo?` |
| `HisabCore/Sources/HisabCore/Capture/MemoMerger.swift` | `.../capture/memo_merger.dart` | Memo → statement row matching |

**iOS app — new:** `Hisab/Services/MemoStore.swift`, `Hisab/Services/CapturePrefs.swift`, `Hisab/Services/CaptureNotifier.swift`, `Hisab/Intents/AddTransactionAlertIntent.swift`, `Hisab/Views/MemoReviewSheet.swift`, `Hisab/Views/NeedsReviewSection.swift`, `Hisab/Views/CaptureSetupView.swift`.
**iOS app — modified:** `Hisab/Models/StoredModels.swift` (add `StoredPendingMemo`), `Hisab/HisabApp.swift` (schema + URL routing), `Hisab/Views/DashboardView.swift` (needs-review + health), `Hisab/Views/SettingsView.swift` (capture toggle), `Hisab/Services/ImportService.swift` (merge on import), `project.yml` (URL scheme, document types, version).

**Android/Flutter — new:** `hisab_flutter/lib/services/memo_store.dart`, `capture_prefs.dart`, `capture_notifier.dart`, `notification_capture.dart`, `hisab_flutter/lib/widgets/memo_review_sheet.dart`, `needs_review_section.dart`, `hisab_flutter/lib/screens/capture_setup_screen.dart`, `hisab_flutter/assets/capture/allowlist.json`.
**Android/Flutter — modified:** `lib/storage/database.dart` (new table + **migration**), `lib/state.dart`, `lib/main.dart`, `lib/screens/dashboard_screen.dart`, `lib/services/import_service.dart`, `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`.

---

### Task 1: `PendingMemo` and `captureHash` (Swift)

The value type every later task consumes, plus the dedup identity. Built first and alone because a wrong `captureHash` produces duplicate memos that train rules on phantom payments.

**Files:**
- Create: `HisabCore/Sources/HisabCore/Capture/PendingMemo.swift`
- Test: `HisabCore/Tests/HisabCoreTests/PendingMemoTests.swift`

**Interfaces:**
- Consumes: `Direction` (`HisabCore/Sources/HisabCore/Domain.swift:51`, cases `debit`/`credit`), `SuggestionEngine.normalize(_:)` (`SuggestionEngine.swift:35`), `YearMonth.istCalendar`.
- Produces: `PendingMemo` (fields below), `PendingMemo.captureHash`, `PendingMemo.istDayString(_:)`, `RuleKey`, `RuleKeyKind`, `PendingMemo.ruleKey`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import HisabCore

final class PendingMemoTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    func testCaptureHashIgnoresTimeOfDay() {
        // An Android notification *update* arrives seconds later. It must not
        // produce a second memo, so the hash keys on the day, not the instant.
        let morning = PendingMemo(amountPaise: 45_000, direction: .debit,
                                  payee: "VEDANT SABOO", vpa: "vedant@okaxis",
                                  accountTail: "1234",
                                  date: date("2026-09-22 09:15"),
                                  capturedAt: date("2026-09-22 09:15"))
        let seconds_later = PendingMemo(amountPaise: 45_000, direction: .debit,
                                        payee: "VEDANT SABOO", vpa: "vedant@okaxis",
                                        accountTail: "1234",
                                        date: date("2026-09-22 09:15"),
                                        capturedAt: date("2026-09-22 09:16"))
        XCTAssertEqual(morning.captureHash, seconds_later.captureHash)
    }

    func testCaptureHashSeparatesDirection() {
        // A refund reuses the payee and amount; it is a different movement.
        let debit = PendingMemo(amountPaise: 45_000, direction: .debit,
                                payee: "SWIGGY", vpa: nil, accountTail: nil,
                                date: date("2026-09-22 09:15"),
                                capturedAt: date("2026-09-22 09:15"))
        let credit = PendingMemo(amountPaise: 45_000, direction: .credit,
                                 payee: "SWIGGY", vpa: nil, accountTail: nil,
                                 date: date("2026-09-22 09:15"),
                                 capturedAt: date("2026-09-22 09:15"))
        XCTAssertNotEqual(debit.captureHash, credit.captureHash)
    }

    func testPayeeNormalizedMatchesSuggestionEngine() {
        // Rule patterns must match what the existing rule store already holds.
        let memo = PendingMemo(amountPaise: 1, direction: .debit,
                               payee: "BLUE TOKAI COFFEE ROASTERS PVT", vpa: nil,
                               accountTail: nil, date: date("2026-09-22 09:15"),
                               capturedAt: date("2026-09-22 09:15"))
        XCTAssertEqual(memo.payeeNormalized, "blue tokai coffee")
    }

    func testRuleKeyPrefersVPAOverUnstableDisplayName() {
        // The whole point: "VEDANT SABOO" varies per statement, the VPA does not.
        let withVPA = PendingMemo(amountPaise: 1, direction: .debit,
                                  payee: "VEDANT SABOO", vpa: "Vedant@OkAxis",
                                  accountTail: nil, date: date("2026-09-22 09:15"),
                                  capturedAt: date("2026-09-22 09:15"))
        XCTAssertEqual(withVPA.ruleKey, RuleKey(pattern: "vedant@okaxis", kind: .vpa))

        let withoutVPA = PendingMemo(amountPaise: 1, direction: .debit,
                                     payee: "Blue Tokai", vpa: nil,
                                     accountTail: nil, date: date("2026-09-22 09:15"),
                                     capturedAt: date("2026-09-22 09:15"))
        XCTAssertEqual(withoutVPA.ruleKey, RuleKey(pattern: "blue tokai", kind: .merchant))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HisabCore --filter PendingMemoTests`
Expected: FAIL — cannot find `PendingMemo` in scope.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import CryptoKit

/// A transaction alert Hisab captured but has NOT admitted to the ledger.
///
/// Alerts carry no UTR, so they cannot join content-hash dedup or
/// balance-chain validation — the two properties that make Hisab's numbers
/// trustworthy. A memo's durable output is a categorization *rule*; the
/// statement remains the single source of truth. See the design spec.
public struct PendingMemo: Sendable, Equatable, Codable {
    public var amountPaise: Int64
    public var direction: Direction
    /// As it appeared in the alert, for display.
    public var payee: String
    /// VPA in full (`name@handle`), lowercased, when the alert carried one.
    public var vpa: String?
    /// Trailing digits of the account the alert named, e.g. "1234".
    public var accountTail: String?
    /// The transaction's own date (the alert's, or capture time if absent).
    public var date: Date
    public var capturedAt: Date
    public var note: String?

    public init(amountPaise: Int64, direction: Direction, payee: String,
                vpa: String?, accountTail: String?, date: Date,
                capturedAt: Date, note: String? = nil) {
        self.amountPaise = amountPaise
        self.direction = direction
        self.payee = payee
        self.vpa = vpa?.lowercased()
        self.accountTail = accountTail
        self.date = date
        self.capturedAt = capturedAt
        self.note = note
    }

    /// Cluster key shared with the suggestion engine so a rule written here
    /// matches patterns the rule store already contains.
    public var payeeNormalized: String { SuggestionEngine.normalize(payee) }

    /// `yyyy-MM-dd` in IST. Day granularity is deliberate: Android fires on
    /// notification *updates*, and a timestamp would defeat the dedup guard.
    public static func istDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Stable identity. Two captures of one payment collapse; a refund of the
    /// same amount to the same payee stays distinct (direction is in the key).
    public var captureHash: String {
        let canonical = [
            String(amountPaise),
            direction.rawValue,
            payeeNormalized,
            vpa ?? "",
            Self.istDayString(date),
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public var ruleKey: RuleKey {
        if let vpa, vpa.count >= 3 { return RuleKey(pattern: vpa, kind: .vpa) }
        return RuleKey(pattern: payeeNormalized, kind: .merchant)
    }
}

public enum RuleKeyKind: String, Codable, Sendable {
    case vpa, merchant
}

/// What a rule written from a memo should match on. The VPA is preferred
/// because personal-name payees render inconsistently across statements
/// ("VEDANT SABOO", "Vedant S", "UPI/1234/VEDANT") while `name@handle` does
/// not — and UPI narrations carry the VPA verbatim, so the longest-match
/// matcher will pick it.
public struct RuleKey: Equatable, Sendable, Codable {
    public var pattern: String
    public var kind: RuleKeyKind

    public init(pattern: String, kind: RuleKeyKind) {
        self.pattern = pattern
        self.kind = kind
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path HisabCore --filter PendingMemoTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add HisabCore/Sources/HisabCore/Capture/PendingMemo.swift HisabCore/Tests/HisabCoreTests/PendingMemoTests.swift
git commit -m "feat(capture): PendingMemo with day-granular capture hash and VPA-preferring rule key"
```

---

### Task 2: `AlertParser` (Swift)

Turns alert text into a memo, and — more importantly — declines to guess. A false memo is worse than a missed one: it trains a rule on a payment that never happened.

**Files:**
- Create: `HisabCore/Sources/HisabCore/Capture/AlertParser.swift`
- Test: `HisabCore/Tests/HisabCoreTests/AlertParserTests.swift`

**Interfaces:**
- Consumes: `PendingMemo` (Task 1), `Money.signedPaise(fromDecimalString:)` (`Money.swift:17`), `Direction`, `YearMonth.istCalendar`.
- Produces: `AlertParser.parse(text: String, receivedAt: Date) -> PendingMemo?`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import HisabCore

final class AlertParserTests: XCTestCase {
    private func at(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }
    private let now = "2026-09-22 14:30"

    func testParsesHDFCStyleUPIDebit() {
        let text = "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. Ref 123456789012. Not you? Call 18002586161"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.amountPaise, 45_000)
        XCTAssertEqual(memo?.direction, .debit)
        XCTAssertEqual(memo?.vpa, "vedant@okaxis")
        XCTAssertEqual(memo?.accountTail, "1234")
        XCTAssertEqual(PendingMemo.istDayString(memo!.date), "2026-09-22")
    }

    func testParsesLakhGroupedAmount() {
        let text = "INR 1,23,456.78 debited from A/c no. XX9876 towards BLUE TOKAI COFFEE on 21/09/2026"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.amountPaise, 12_345_678)
        XCTAssertEqual(memo?.payee, "BLUE TOKAI COFFEE")
        XCTAssertEqual(PendingMemo.istDayString(memo!.date), "2026-09-21")
    }

    func testParsesCreditAsCredit() {
        // Misreading a credit as spending would corrupt every downstream number.
        let text = "₹2,000 credited to your account XX1234 from RAHUL on 22Sep26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.direction, .credit)
        XCTAssertEqual(memo?.amountPaise, 200_000)
    }

    func testFallsBackToReceivedAtWhenAlertHasNoDate() {
        let text = "Rs 99.00 debited from a/c XX1234 to ZEPTO"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(PendingMemo.istDayString(memo!.date), "2026-09-22")
    }

    func testRejectsTextWithBothDirections() {
        // "credited"+"debited" in one message is a statement summary or an
        // ad, not a single movement. Guessing here is how you corrupt a ledger.
        let text = "Your a/c XX1234: Rs.500.00 debited and Rs.500.00 credited on 22-09-26"
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testRejectsTextWithNoDirection() {
        let text = "Your a/c XX1234 balance is Rs.12,345.67 as on 22-09-26"
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testRejectsTextWithNoCurrencyAmount() {
        // An account number must never be mistaken for an amount.
        let text = "Payment debited from a/c XX1234 to VEDANT"
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testDoesNotMistakeEmailForVPA() {
        // An email has a dotted domain; a VPA handle does not.
        let text = "Rs.450.00 debited from a/c XX1234 to SWIGGY. Queries: help@swiggy.in"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertNil(memo?.vpa)
        XCTAssertEqual(memo?.payee, "SWIGGY")
    }

    func testRejectsPromotionalText() {
        // Rejected on direction: "Spend" is not "spent". Named for what it is.
        let text = "Get a personal loan instantly! Spend more and earn rewards."
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testDoesNotReadADottedDateAsAnAmount() {
        // The fallback two-decimal pattern would happily read "22.09" out of
        // "22.09.26" and report a ₹22.09 payment. A wrong number in the user's
        // own data is the one failure this product cannot absorb.
        let text = "Payment debited on 22.09.26 to ZEPTO"
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testStillReadsAGenuineTwoDecimalAmountWithoutACurrencyMarker() {
        // The dotted-date guard must not swallow this.
        let text = "Debited 450.00 from a/c XX1234 to ZEPTO on 22-09-26"
        XCTAssertEqual(AlertParser.parse(text: text, receivedAt: at(now))?.amountPaise,
                       45_000)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HisabCore --filter AlertParserTests`
Expected: FAIL — cannot find `AlertParser` in scope.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Reads a bank/UPI transaction alert into a `PendingMemo`, or declines.
///
/// Every rule here is deliberately conservative. `nil` means "this was not
/// confidently a single money movement", and callers drop the alert silently.
/// A false memo trains a categorization rule on a payment that never
/// happened, which is far worse than missing one.
public enum AlertParser {
    private static let debitWords = ["debited", "spent", "withdrawn", "paid", "sent", "purchase"]
    private static let creditWords = ["credited", "received", "refund", "deposited"]

    public static func parse(text: String, receivedAt: Date) -> PendingMemo? {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let lower = collapsed.lowercased()

        guard let direction = direction(in: lower) else { return nil }
        guard let amountPaise = amount(in: lower), amountPaise > 0 else { return nil }
        let vpa = self.vpa(in: lower)
        guard let payee = payee(in: collapsed) ?? vpa.map({ String($0.split(separator: "@")[0]) }),
              !payee.isEmpty else { return nil }

        return PendingMemo(amountPaise: amountPaise,
                           direction: direction,
                           payee: payee,
                           vpa: vpa,
                           accountTail: accountTail(in: lower),
                           date: date(in: lower) ?? receivedAt,
                           capturedAt: receivedAt)
    }

    /// Exactly one direction must be present. Both means a summary or an ad;
    /// neither means a balance notice.
    private static func direction(in lower: String) -> Direction? {
        let debit = debitWords.contains { lower.contains($0) }
        let credit = creditWords.contains { lower.contains($0) }
        if debit && !credit { return .debit }
        if credit && !debit { return .credit }
        return nil
    }

    /// Requires a currency marker, or failing that two decimal places. Without
    /// this an account number or a phone number becomes an amount.
    private static func amount(in lower: String) -> Int64? {
        // A currency marker makes the amount unambiguous.
        if let paise = firstAmount(#"(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
                                   in: lower) {
            return paise
        }
        // Without a marker, demand two decimals AND reject anything sitting
        // inside a longer dotted run: "22.09.26" is a date, and reading ₹22.09
        // out of it would put a number the user never spent into their data.
        return firstAmount(#"(?<![0-9.])([0-9][0-9,]*\.[0-9]{2})(?![0-9.])"#, in: lower)
    }

    private static func firstAmount(_ pattern: String, in lower: String) -> Int64? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let captured = Range(match.range(at: 1), in: lower) else { return nil }
        return Money.signedPaise(fromDecimalString: String(lower[captured]))
    }

    /// A VPA handle has no dot; an email domain does. That single distinction
    /// keeps support addresses out of the rule key.
    private static func vpa(in lower: String) -> String? {
        let pattern = #"([a-z0-9][a-z0-9._-]{1,})@([a-z]{2,})(?![a-z0-9._-]*\.)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let whole = Range(match.range, in: lower) else { return nil }
        return String(lower[whole])
    }

    private static let payeeLeadIns = [" to vpa ", " to ", " at ", " towards ", " vpa "]
    private static let payeeStops = [" on ", " ref", " upi", " a/c", " ac ", " avl", " bal",
                                     " not you", ".", ",", "-", "|", ";"]

    /// Takes the segment after a lead-in, cut at the first stop word. Preserves
    /// original case: the payee is shown to the user.
    private static func payee(in text: String) -> String? {
        let lower = text.lowercased()
        for leadIn in payeeLeadIns {
            guard let found = lower.range(of: leadIn) else { continue }
            var segment = String(text[found.upperBound...])
            let segmentLower = segment.lowercased()
            var cut = segment.endIndex
            for stop in payeeStops {
                if let stopRange = segmentLower.range(of: stop), stopRange.lowerBound < cut {
                    cut = stopRange.lowerBound
                }
            }
            segment = String(segment[..<cut])
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func accountTail(in lower: String) -> String? {
        let pattern = #"(?:a/c|acct|account|ac)\s*(?:no\.?)?\s*[x*]*([0-9]{3,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let captured = Range(match.range(at: 1), in: lower) else { return nil }
        return String(lower[captured])
    }

    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                 "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    /// `22-09-26`, `22/09/2026`, `22Sep26`, `22-Sep-2026`. A two-digit year is
    /// 2000-based: these alerts are never historical.
    private static func date(in lower: String) -> Date? {
        if let numeric = try? NSRegularExpression(pattern: #"([0-9]{2})[-/]([0-9]{2})[-/]([0-9]{2,4})"#) {
            let range = NSRange(lower.startIndex..., in: lower)
            if let match = numeric.firstMatch(in: lower, range: range),
               let d = capturedInt(match, 1, lower), let m = capturedInt(match, 2, lower),
               let y = capturedInt(match, 3, lower) {
                return makeDate(day: d, month: m, year: y)
            }
        }
        if let named = try? NSRegularExpression(pattern: #"([0-9]{1,2})[- ]?([a-z]{3})[- ]?([0-9]{2,4})"#) {
            let range = NSRange(lower.startIndex..., in: lower)
            if let match = named.firstMatch(in: lower, range: range),
               let d = capturedInt(match, 1, lower),
               let monthRange = Range(match.range(at: 2), in: lower),
               let m = months[String(lower[monthRange])],
               let y = capturedInt(match, 3, lower) {
                return makeDate(day: d, month: m, year: y)
            }
        }
        return nil
    }

    private static func capturedInt(_ match: NSTextCheckingResult, _ index: Int,
                                    _ source: String) -> Int? {
        guard let range = Range(match.range(at: index), in: source) else { return nil }
        return Int(source[range])
    }

    private static func makeDate(day: Int, month: Int, year: Int) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year < 100 ? 2000 + year : year
        components.hour = 12
        return YearMonth.istCalendar.date(from: components)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path HisabCore --filter AlertParserTests`
Expected: PASS, 11 tests.

- [ ] **Step 5: Run the whole Swift suite for regressions**

Run: `J=$(~/.claude/scripts/cpu-gate.sh); swift test --package-path HisabCore -j "$J"`
Expected: PASS. Nothing existing should change.

- [ ] **Step 6: Commit**

```bash
git add HisabCore/Sources/HisabCore/Capture/AlertParser.swift HisabCore/Tests/HisabCoreTests/AlertParserTests.swift
git commit -m "feat(capture): conservative alert parser that declines rather than guesses"
```

---

### Task 3: `MemoMerger` (Swift)

Retires a memo when its statement row finally arrives, carrying the user's note across. Conservative on purpose: a wrong merge silently attaches a note to the wrong payment.

**Files:**
- Create: `HisabCore/Sources/HisabCore/Capture/MemoMerger.swift`
- Test: `HisabCore/Tests/HisabCoreTests/MemoMergerTests.swift`

**Interfaces:**
- Consumes: `PendingMemo` (Task 1), `Direction`, `YearMonth.istCalendar`.
- Produces: `MemoMergeCandidate` (`id: UUID, date: Date, amountPaise: Int64, direction: Direction, narration: String`), `MemoMerger.merge(memos:candidates:) -> [String: UUID]` keyed by `captureHash`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import HisabCore

final class MemoMergerTests: XCTestCase {
    private func day(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)!
    }

    private func memo(_ amount: Int64, _ payee: String, _ vpa: String?,
                      _ date: String) -> PendingMemo {
        PendingMemo(amountPaise: amount, direction: .debit, payee: payee, vpa: vpa,
                    accountTail: nil, date: day(date), capturedAt: day(date))
    }

    func testMergesOnVPAPresentInNarration() {
        let m = memo(45_000, "VEDANT SABOO", "vedant@okaxis", "2026-09-22")
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: day("2026-09-22"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "UPI-VEDANT SABOO-VEDANT@OKAXIS-HDFC-123456")
        XCTAssertEqual(MemoMerger.merge(memos: [m], candidates: [candidate]), [m.captureHash: id])
    }

    func testMergesWithinThreeDays() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: day("2026-09-25"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertEqual(MemoMerger.merge(memos: [m], candidates: [candidate]), [m.captureHash: id])
    }

    func testDoesNotMergeBeyondThreeDays() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-26"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testDoesNotMergeOnAmountMismatch() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-22"),
                                           amountPaise: 45_001, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testDoesNotMergeOnPayeeMismatch() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-22"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "SWIGGY INSTAMART")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testOneCandidateServesOnlyOneMemo() {
        // Two identical-looking memos, one real row: the second must stay pending
        // rather than both claiming the same transaction.
        let a = memo(45_000, "ZEPTO", nil, "2026-09-20")
        let b = memo(45_000, "ZEPTO", nil, "2026-09-21")
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: day("2026-09-21"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        let merged = MemoMerger.merge(memos: [a, b], candidates: [candidate])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[a.captureHash], id,
                       "memos are claimed oldest-first, deterministically")
        XCTAssertNil(merged[b.captureHash], "the second memo stays pending")
    }

    func testPicksNearestDateAmongCandidates() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let near = UUID(), far = UUID()
        let candidates = [
            MemoMergeCandidate(id: far, date: day("2026-09-25"), amountPaise: 45_000,
                               direction: .debit, narration: "ZEPTO MARKETPLACE"),
            MemoMergeCandidate(id: near, date: day("2026-09-22"), amountPaise: 45_000,
                               direction: .debit, narration: "ZEPTO MARKETPLACE"),
        ]
        XCTAssertEqual(MemoMerger.merge(memos: [m], candidates: candidates), [m.captureHash: near])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HisabCore --filter MemoMergerTests`
Expected: FAIL — cannot find `MemoMerger` in scope.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A statement row a memo might turn out to be.
public struct MemoMergeCandidate: Sendable, Equatable {
    public var id: UUID
    public var date: Date
    public var amountPaise: Int64
    public var direction: Direction
    public var narration: String

    public init(id: UUID, date: Date, amountPaise: Int64, direction: Direction,
                narration: String) {
        self.id = id
        self.date = date
        self.amountPaise = amountPaise
        self.direction = direction
        self.narration = narration
    }
}

/// Retires memos against imported statement rows.
///
/// The triple gate — exact amount, same direction, within ±3 days, and a
/// payee or VPA that actually appears in the narration — is intentionally
/// strict. An unmerged memo simply expires; a wrongly merged one silently
/// moves the user's note onto somebody else's payment.
public enum MemoMerger {
    public static let windowDays = 3

    /// `captureHash -> transaction id`. Each candidate is claimed at most once.
    public static func merge(memos: [PendingMemo],
                             candidates: [MemoMergeCandidate]) -> [String: UUID] {
        // Deterministic order so two runs (and two languages) agree.
        let ordered = memos.sorted {
            $0.date == $1.date ? $0.captureHash < $1.captureHash : $0.date < $1.date
        }
        var claimed = Set<UUID>()
        var result: [String: UUID] = [:]

        for memo in ordered {
            let matches = candidates
                .filter { !claimed.contains($0.id) && matches(memo: memo, candidate: $0) }
                .sorted { lhs, rhs in
                    let l = abs(lhs.date.timeIntervalSince(memo.date))
                    let r = abs(rhs.date.timeIntervalSince(memo.date))
                    return l == r ? lhs.id.uuidString < rhs.id.uuidString : l < r
                }
            guard let best = matches.first else { continue }
            claimed.insert(best.id)
            result[memo.captureHash] = best.id
        }
        return result
    }

    private static func matches(memo: PendingMemo, candidate: MemoMergeCandidate) -> Bool {
        guard memo.amountPaise == candidate.amountPaise,
              memo.direction == candidate.direction else { return false }
        let days = YearMonth.istCalendar.dateComponents([.day],
                                                        from: min(memo.date, candidate.date),
                                                        to: max(memo.date, candidate.date)).day ?? .max
        guard days <= windowDays else { return false }

        let narration = candidate.narration.lowercased()
        if let vpa = memo.vpa, narration.contains(vpa) { return true }
        let key = memo.payeeNormalized
        return !key.isEmpty && narration.contains(key.split(separator: " ")[0])
    }
}
```

Note on the payee fallback: matching on the *first* normalized token keeps
`ZEPTO` matching `ZEPTO MARKETPLACE`, where a full three-token key would not.
The amount-plus-window gate is what keeps that loose enough to work without
being loose enough to be wrong.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path HisabCore --filter MemoMergerTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add HisabCore/Sources/HisabCore/Capture/MemoMerger.swift HisabCore/Tests/HisabCoreTests/MemoMergerTests.swift
git commit -m "feat(capture): conservative memo-to-statement merger"
```

---

### Task 4: Dart core twins

The Swift sources are the executable specification; these must behave identically. Dart already has `istDayString`, `istDaysBetween` (`src/year_month.dart`) and `SuggestionEngine.normalize` (`src/suggestion_engine.dart:39`) — reuse them rather than reimplementing, or the two cores will drift on dates.

**Files:**
- Create: `hisab_flutter/packages/hisab_core/lib/src/capture/pending_memo.dart`
- Create: `hisab_flutter/packages/hisab_core/lib/src/capture/alert_parser.dart`
- Create: `hisab_flutter/packages/hisab_core/lib/src/capture/memo_merger.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (add three exports, alphabetically among the `src/` entries)
- Test: `hisab_flutter/packages/hisab_core/test/capture_test.dart`

**Interfaces:**
- Consumes: `Direction` (`src/domain.dart`), `Money.signedPaiseFromDecimalString` (check the exact Dart name in `src/money.dart` before use), `SuggestionEngine.normalize`, `istDayString`, `istDaysBetween`.
- Produces: `PendingMemo`, `RuleKey`, `RuleKeyKind`, `AlertParser.parse(String text, DateTime receivedAt)`, `MemoMergeCandidate`, `MemoMerger.merge(...)` — same semantics as Tasks 1–3.

- [ ] **Step 1: Read the Swift sources as the specification**

Read `HisabCore/Sources/HisabCore/Capture/{PendingMemo,AlertParser,MemoMerger}.swift` in full. Port them, do not reinvent them. In particular keep: the day-granular hash, the exactly-one-direction rule, the currency-marker-or-two-decimals amount rule, the no-dot VPA rule, the first-token payee fallback in the merger, and every ordering tie-break.

- [ ] **Step 2: Confirm the real Dart names before writing code**

Run: `grep -n "signedPaise\|class Money" hisab_flutter/packages/hisab_core/lib/src/money.dart`
Run: `grep -n "String istDayString\|int istDaysBetween" hisab_flutter/packages/hisab_core/lib/src/year_month.dart`
Use whatever those print. Do not assume the Swift spelling carries over.

- [ ] **Step 3: Write the failing Dart tests**

Port every test case from `PendingMemoTests`, `AlertParserTests` and `MemoMergerTests` into `capture_test.dart`, same names and same expectations. All 22 cases.

**The two regex engines are the likeliest source of divergence in this whole feature.** Two patterns need explicit verification, not assumption:
- the VPA pattern's trailing `(?![a-z0-9._-]*\.)`, against the email test case;
- the fallback amount pattern's `(?<![0-9.])…(?![0-9.])`, against both the dotted-date rejection and the genuine-two-decimal cases. Dart's `RegExp` does support lookbehind, but confirm it on this exact pattern rather than trusting that.

If either engine cannot express a pattern identically, do not quietly rewrite one side — report it, because the parity fixture is what makes the two cores trustworthy and a silent divergence defeats it.

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/capture_test.dart`
Expected: FAIL — the capture library does not exist.

- [ ] **Step 5: Implement the three files and the exports**

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/capture_test.dart`
Expected: PASS, 22 tests.

- [ ] **Step 7: Run the whole Dart core suite**

Run: `cd hisab_flutter/packages/hisab_core && dart test`
Expected: PASS. No existing test changes.

- [ ] **Step 8: Commit**

```bash
git add hisab_flutter/packages/hisab_core/lib/src/capture hisab_flutter/packages/hisab_core/lib/hisab_core.dart hisab_flutter/packages/hisab_core/test/capture_test.dart
git commit -m "feat(capture): Dart twins for memo, alert parser and merger"
```

---

### Task 5: Cross-platform parity fixture

Mirrored unit tests prove each core works. Only a shared fixture proves they agree. This is the same discipline as `insights-parity*.json`, and it is what caught drift last time.

**Files:**
- Create: `HisabCore/Tests/HisabCoreTests/Fixtures/alert-parity.json`
- Create: `HisabCore/Tests/HisabCoreTests/AlertParityTests.swift`
- Modify: `hisab_flutter/packages/hisab_core/test/capture_test.dart` (add the fixture group)
- Modify: `tool/sync_assets.sh` — **no change needed**; it already copies all of `Fixtures/` to `packages/hisab_core/test/fixtures`. Verify, don't assume.

**Interfaces:**
- Consumes: `AlertParser.parse`, `PendingMemo.captureHash`, `PendingMemo.ruleKey` (Tasks 1–4).
- Produces: `alert-parity.json` as the single source of truth for parser agreement.

- [ ] **Step 1: Write the fixture**

One JSON file, an array of cases. Each case pins the *whole* parse outcome so nothing can drift on one platform only:

```json
{
  "receivedAt": "2026-09-22T14:30:00+05:30",
  "cases": [
    {
      "name": "hdfc-upi-debit",
      "text": "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. Ref 123456789012. Not you? Call 18002586161",
      "expected": {
        "amountPaise": 45000,
        "direction": "debit",
        "payee": "vedant@okaxis",
        "payeeNormalized": "vedant okaxis",
        "vpa": "vedant@okaxis",
        "accountTail": "1234",
        "dateISO": "2026-09-22",
        "captureHash": "<fill from the Swift run>",
        "rulePattern": "vedant@okaxis",
        "ruleKind": "vpa"
      }
    },
    {
      "name": "lakh-grouped-merchant",
      "text": "INR 1,23,456.78 debited from A/c no. XX9876 towards BLUE TOKAI COFFEE on 21/09/2026",
      "expected": {
        "amountPaise": 12345678,
        "direction": "debit",
        "payee": "BLUE TOKAI COFFEE",
        "payeeNormalized": "blue tokai coffee",
        "vpa": null,
        "accountTail": "9876",
        "dateISO": "2026-09-21",
        "captureHash": "<fill from the Swift run>",
        "rulePattern": "blue tokai coffee",
        "ruleKind": "merchant"
      }
    },
    {
      "name": "credit-not-debit",
      "text": "₹2,000 credited to your account XX1234 from RAHUL on 22Sep26",
      "expected": {
        "amountPaise": 200000,
        "direction": "credit",
        "payee": "your account XX1234 from RAHUL",
        "payeeNormalized": "your account xx",
        "vpa": null,
        "accountTail": "1234",
        "dateISO": "2026-09-22",
        "captureHash": "<fill from the Swift run>",
        "rulePattern": "your account xx",
        "ruleKind": "merchant"
      }
    },
    {
      "name": "no-date-falls-back-to-received",
      "text": "Rs 99.00 debited from a/c XX1234 to ZEPTO",
      "expected": {
        "amountPaise": 9900,
        "direction": "debit",
        "payee": "ZEPTO",
        "payeeNormalized": "zepto",
        "vpa": null,
        "accountTail": "1234",
        "dateISO": "2026-09-22",
        "captureHash": "<fill from the Swift run>",
        "rulePattern": "zepto",
        "ruleKind": "merchant"
      }
    },
    {
      "name": "email-is-not-a-vpa",
      "text": "Rs.450.00 debited from a/c XX1234 to SWIGGY. Queries: help@swiggy.in",
      "expected": {
        "amountPaise": 45000,
        "direction": "debit",
        "payee": "SWIGGY",
        "payeeNormalized": "swiggy",
        "vpa": null,
        "accountTail": "1234",
        "dateISO": "2026-09-22",
        "captureHash": "<fill from the Swift run>",
        "rulePattern": "swiggy",
        "ruleKind": "merchant"
      }
    }
  ],
  "rejected": [
    "Your a/c XX1234: Rs.500.00 debited and Rs.500.00 credited on 22-09-26",
    "Your a/c XX1234 balance is Rs.12,345.67 as on 22-09-26",
    "Payment debited from a/c XX1234 to VEDANT",
    "Get a personal loan instantly! Spend more and earn rewards."
  ]
}
```

**On the `credit-not-debit` case:** the expected `payee` there is ugly because
the lead-in is `" to "` and the stop list does not cut at `from`. Do not
"fix" it by special-casing in the parser. Record what the parser actually
does, and if the ugliness matters, raise it as a finding — a fixture that
lies about behaviour is worse than one that pins something imperfect. The
`credited`-direction assertion is what this case exists to protect.

- [ ] **Step 2: Write the Swift parity test**

Follow the shape of `HisabCore/Tests/HisabCoreTests/InsightsParityTests.swift` (read it first). For each case: parse, then assert every expected field including `captureHash`, `rulePattern` and `ruleKind`. For each entry in `rejected`: assert `parse` returns nil. Support an env-gated regeneration dump for the `captureHash` values, exactly as `INSIGHTS_GT_OUT` does.

- [ ] **Step 3: Fill in the hashes from the Swift run, then verify**

Run the Swift test with the regeneration env var set, inspect the diff, then run clean.
Run: `swift test --package-path HisabCore --filter AlertParityTests`
Expected: PASS.

- [ ] **Step 4: Sync the fixture to Dart and assert it there**

Run: `tool/sync_assets.sh`
Then add a group to `capture_test.dart` loading `test/fixtures/alert-parity.json` (see `insights_test.dart:886` for the existing load pattern) and asserting the identical fields.

- [ ] **Step 5: Run both suites**

Run: `swift test --package-path HisabCore --filter AlertParityTests`
Run: `cd hisab_flutter/packages/hisab_core && dart test test/capture_test.dart`
Expected: both PASS on byte-identical expectations.

- [ ] **Step 6: Verify the fixture actually discriminates**

Temporarily change one digit of an `amountPaise` in the fixture and confirm **both** suites fail. Revert. A parity fixture nobody has seen fail is not known to be wired up — this step is not optional.

- [ ] **Step 7: Run the sync check**

Run: `tool/sync_assets.sh --check`
Expected: exit 0, no drift.

- [ ] **Step 8: Commit**

```bash
git add HisabCore/Tests/HisabCoreTests/Fixtures/alert-parity.json HisabCore/Tests/HisabCoreTests/AlertParityTests.swift hisab_flutter/packages/hisab_core/test/fixtures/alert-parity.json hisab_flutter/packages/hisab_core/test/capture_test.dart
git commit -m "test(capture): pin alert parsing across both cores"
```

---

### Task 6: Move iOS onto an explicit Info.plist

A prerequisite for both the deep-link scheme (Task 10) and share-sheet import (Task 17). The target currently sets `GENERATE_INFOPLIST_FILE: YES` and configures everything through `INFOPLIST_KEY_*` build settings. **`CFBundleURLTypes` and `CFBundleDocumentTypes` have no `INFOPLIST_KEY_*` equivalent** — they are arrays of dictionaries — so they cannot be expressed that way at all. Isolated as its own task because botching it silently drops the launch screen or the orientation lock, which looks like an unrelated UI bug later.

**Files:**
- Modify: `project.yml` (target `Hisab`)
- Create: `Hisab/Info.plist` (generated by xcodegen from the `info:` block — do not hand-write it)

**Interfaces:**
- Produces: a real `Info.plist` carrying every setting the `INFOPLIST_KEY_*` entries carried, plus URL scheme `hisab`.

- [ ] **Step 1: Record the current behaviour before changing anything**

Run the gate, then `make gen`, then `make build`. Then dump the built app's Info.plist and note these four keys, which must survive: `UILaunchScreen`, `UISupportedInterfaceOrientations`, `CFBundleDisplayName`, `ITSAppUsesNonExemptEncryption`.

Run: `plutil -p "$(find ~/Library/Developer/Xcode/DerivedData -name 'Hisab.app' -maxdepth 6 | head -1)/Info.plist" | head -40`

- [ ] **Step 2: Replace the INFOPLIST_KEY settings with an `info:` block**

In `project.yml`, under `targets.Hisab`, remove `GENERATE_INFOPLIST_FILE`, `INFOPLIST_KEY_UILaunchScreen_Generation`, `INFOPLIST_KEY_UISupportedInterfaceOrientations`, `INFOPLIST_KEY_CFBundleDisplayName` and `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`, and add:

```yaml
    info:
      path: Hisab/Info.plist
      properties:
        CFBundleDisplayName: Hisab
        ITSAppUsesNonExemptEncryption: false
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        CFBundleURLTypes:
          - CFBundleURLName: com.vedants.hisab.deeplink
            CFBundleTypeRole: Editor
            CFBundleURLSchemes:
              - hisab
```

Leave every other build setting untouched.

- [ ] **Step 3: Regenerate and confirm nothing regressed**

Run: `make gen`
Run: `plutil -p Hisab/Info.plist`
Expected: all four preserved keys present, plus `CFBundleURLTypes`.

- [ ] **Step 4: Build and launch in the simulator**

Run the gate, then `make build`.
Expected: BUILD SUCCEEDED, app launches portrait-locked with a launch screen and the name "Hisab".

- [ ] **Step 5: Verify the scheme is actually registered**

Boot the simulator app, then run:
`xcrun simctl openurl booted "hisab://memo/unknown"`
Expected: Hisab comes to the foreground. It will not route anywhere yet — Task 10 adds that. Foregrounding is the whole assertion here; if the app does not come forward, the scheme is not registered and every later deep-link test would fail for this reason instead of its own.

- [ ] **Step 6: Commit**

Stage `project.yml` and `Hisab/Info.plist`; commit as
`build(ios): explicit Info.plist and hisab:// URL scheme`

---

### Task 7: iOS memo persistence with dedup

**Files:**
- Modify: `Hisab/Models/StoredModels.swift` (append `StoredPendingMemo`, add `HisabSchema`)
- Modify: `Hisab/HisabApp.swift:9` (use the shared schema)
- Create: `Hisab/Services/MemoStore.swift`
- Create: `Hisab/Services/CapturePrefs.swift`
- Modify: `HisabCore/Sources/HisabCore/Capture/PendingMemo.swift` (expiry helper)
- Test: `HisabCore/Tests/HisabCoreTests/PendingMemoTests.swift`

**Note on testability:** the app target has no unit-test target. Anything worth testing must live in `HisabCore`; `MemoStore` stays a thin SwiftData shim. If you find yourself writing a condition in `MemoStore`, move it to the core and test it there.

**Interfaces:**
- Consumes: `PendingMemo`, `MemoMerger`, `RuleKey` (Tasks 1–3).
- Produces: `StoredPendingMemo`, `HisabSchema.schema`, `MemoStore.insert(_:into:) -> Bool`, `MemoStore.pending(_:)`, `MemoStore.all(_:)`, `MemoStore.find(hash:in:)`, `MemoStore.assign(category:to:in:)`, `MemoStore.expire(now:in:)`, `CapturePrefs.isEnabled`, `CapturePrefs.lastCaptureAt`, `CapturePrefs.notificationsSentToday(now:)`, `CapturePrefs.recordNotification(now:)`, `PendingMemo.expiryDays`, `PendingMemo.isExpired(capturedAt:now:)`.

- [ ] **Step 1: Write the failing expiry test**

Add to `PendingMemoTests`:

```swift
func testExpiryBoundaryIsInclusiveAt45Days() {
    let captured = date("2026-08-01 10:00")
    let day45 = YearMonth.istCalendar.date(byAdding: .day, value: 45, to: captured)!
    let day46 = YearMonth.istCalendar.date(byAdding: .day, value: 46, to: captured)!
    XCTAssertFalse(PendingMemo.isExpired(capturedAt: captured, now: day45))
    XCTAssertTrue(PendingMemo.isExpired(capturedAt: captured, now: day46))
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path HisabCore --filter PendingMemoTests`
Expected: FAIL — no `isExpired`.

- [ ] **Step 3: Add the expiry helper to the core**

```swift
public extension PendingMemo {
    /// Memos are a labelling channel, not storage. Statements arrive monthly;
    /// 45 days leaves buffer for a late import without unbounded growth.
    static let expiryDays = 45

    static func isExpired(capturedAt: Date, now: Date) -> Bool {
        let days = YearMonth.istCalendar.dateComponents([.day], from: capturedAt, to: now).day ?? 0
        return days > expiryDays
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --package-path HisabCore --filter PendingMemoTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Add the SwiftData model and shared schema**

Append to `Hisab/Models/StoredModels.swift`, following the existing style (defaulted properties; `@Attribute(.unique)` on the identity, the same pattern `StoredTransaction.contentHash` uses at line 34):

```swift
@Model
final class StoredPendingMemo {
    @Attribute(.unique) var captureHash: String = ""
    var amountPaise: Int64 = 0
    var directionRaw: String = ""
    var payee: String = ""
    var payeeNormalized: String = ""
    var vpa: String?
    var accountTail: String?
    var date: Date = Date.distantPast
    var capturedAt: Date = Date.distantPast
    var note: String?
    var assignedCategory: String?
    var mergedTxnUUID: UUID?
    var notifiedAt: Date?

    init(memo: PendingMemo) {
        self.captureHash = memo.captureHash
        self.amountPaise = memo.amountPaise
        self.directionRaw = memo.direction.rawValue
        self.payee = memo.payee
        self.payeeNormalized = memo.payeeNormalized
        self.vpa = memo.vpa
        self.accountTail = memo.accountTail
        self.date = memo.date
        self.capturedAt = memo.capturedAt
        self.note = memo.note
    }

    var direction: Direction { Direction(rawValue: directionRaw) ?? .debit }

    var asMemo: PendingMemo {
        PendingMemo(amountPaise: amountPaise, direction: direction, payee: payee,
                    vpa: vpa, accountTail: accountTail, date: date,
                    capturedAt: capturedAt, note: note)
    }
}

/// One definition of the store's shape. The App Intent opens its own
/// container, and two drifting schema lists would corrupt the store.
enum HisabSchema {
    static let schema = Schema([
        StoredDocument.self, StoredTransaction.self, StoredCategoryRule.self,
        StoredMatch.self, PinnedMonth.self, StoredPendingMemo.self,
    ])
}
```

Raw alert text is deliberately absent. Do not add it.

**Before replacing the list in `HisabApp.swift`, read line 9 and confirm the existing models match the five named above.** Do not trust this plan's recollection of it.

- [ ] **Step 6: Write `MemoStore`**

```swift
import Foundation
import SwiftData
import HisabCore

/// SwiftData shim for pending memos. Deliberately logic-free.
@MainActor
enum MemoStore {
    /// False when this alert was already captured — the dedup guard that stops
    /// Android's notification *updates* producing a second memo.
    @discardableResult
    static func insert(_ memo: PendingMemo, into ctx: ModelContext) -> Bool {
        let hash = memo.captureHash
        let existing = FetchDescriptor<StoredPendingMemo>(
            predicate: #Predicate { $0.captureHash == hash })
        if let found = try? ctx.fetch(existing), !found.isEmpty { return false }
        ctx.insert(StoredPendingMemo(memo: memo))
        try? ctx.save()
        return true
    }

    /// Unmerged, unlabelled memos, newest first.
    static func pending(_ ctx: ModelContext) -> [StoredPendingMemo] {
        let descriptor = FetchDescriptor<StoredPendingMemo>(
            predicate: #Predicate { $0.mergedTxnUUID == nil && $0.assignedCategory == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        return (try? ctx.fetch(descriptor)) ?? []
    }

    static func all(_ ctx: ModelContext) -> [StoredPendingMemo] {
        (try? ctx.fetch(FetchDescriptor<StoredPendingMemo>())) ?? []
    }

    static func find(hash: String, in ctx: ModelContext) -> StoredPendingMemo? {
        let descriptor = FetchDescriptor<StoredPendingMemo>(
            predicate: #Predicate { $0.captureHash == hash })
        return (try? ctx.fetch(descriptor))?.first
    }

    static func assign(category: String, to memo: StoredPendingMemo, in ctx: ModelContext) {
        memo.assignedCategory = category
        try? ctx.save()
    }

    static func expire(now: Date, in ctx: ModelContext) {
        for memo in all(ctx)
        where memo.mergedTxnUUID == nil
            && PendingMemo.isExpired(capturedAt: memo.capturedAt, now: now) {
            ctx.delete(memo)
        }
        try? ctx.save()
    }
}
```

- [ ] **Step 7: Write `CapturePrefs`**

Device preferences, never SwiftData — the tier rule `InsightStore` already follows, because these describe this device rather than the user's financial history.

```swift
import Foundation
import HisabCore

/// Capture is a property of this device, not of the user's ledger.
enum CapturePrefs {
    private static let enabledKey = "capture.enabled"
    private static let lastCaptureKey = "capture.lastCaptureAt"
    private static let notifyCountKey = "capture.notifyCount"
    private static let notifyDayKey = "capture.notifyDay"

    /// Off by default. The user opts in.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var lastCaptureAt: Date? {
        get { UserDefaults.standard.object(forKey: lastCaptureKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCaptureKey) }
    }

    /// Notifications sent today, so a heavy UPI day cannot spam. Resets when
    /// the IST day changes.
    static func notificationsSentToday(now: Date) -> Int {
        let today = PendingMemo.istDayString(now)
        guard UserDefaults.standard.string(forKey: notifyDayKey) == today else { return 0 }
        return UserDefaults.standard.integer(forKey: notifyCountKey)
    }

    static func recordNotification(now: Date) {
        let today = PendingMemo.istDayString(now)
        let count = notificationsSentToday(now: now) + 1
        UserDefaults.standard.set(today, forKey: notifyDayKey)
        UserDefaults.standard.set(count, forKey: notifyCountKey)
    }
}
```

- [ ] **Step 8: Build**

Run the gate, then `make build`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 9: Commit**

Stage the core file, its test, `StoredModels.swift`, `HisabApp.swift`, `MemoStore.swift`, `CapturePrefs.swift`; commit as
`feat(ios): pending-memo persistence with dedup and capture prefs`

---

### Task 8: iOS App Intent and Shortcuts/Siri exposure

The trigger-agnostic ingestion point. One intent serves the Shortcuts automation path *and* the share-sheet path, which is what makes the undocumented Message-trigger behaviour a non-blocker rather than a dependency.

**Files:**
- Create: `Hisab/Intents/AddTransactionAlertIntent.swift`
- Create: `Hisab/Intents/HisabShortcuts.swift`
- Create: `Hisab/Services/CaptureNotifier.swift` (stub here, filled in Task 9)

**Interfaces:**
- Consumes: `AlertParser.parse`, `MemoStore.insert`, `CapturePrefs.lastCaptureAt`, `HisabSchema.schema`, `Money.formatPaise`.
- Produces: `AddTransactionAlertIntent`, `HisabShortcuts`, `CaptureNotifier.considerNotifying(memo:in:)`.

- [ ] **Step 1: Write the intent**

```swift
import AppIntents
import SwiftData
import HisabCore

/// Ingests one transaction alert from anywhere: a Shortcuts automation, the
/// share sheet, or Siri. Deliberately source-agnostic — Apple's richer
/// Notification trigger is iOS 27 only, and the iOS 17+ Message trigger's
/// body input is undocumented, so the design must not depend on either.
struct AddTransactionAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Transaction Alert"
    static var description = IntentDescription(
        "Reads a bank or UPI alert and files it for categorization. Nothing leaves your phone.")

    /// Never open the app: an automation must be able to run silently.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alert Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try ModelContainer(for: HisabSchema.schema)
        let ctx = container.mainContext

        guard var memo = AlertParser.parse(text: text, receivedAt: Date()) else {
            return .result(dialog: "No transaction found in that text.")
        }
        memo.note = note

        let inserted = MemoStore.insert(memo, into: ctx)
        CapturePrefs.lastCaptureAt = Date()

        guard inserted else {
            return .result(dialog: "Already logged \(Money.formatPaise(memo.amountPaise)).")
        }
        CaptureNotifier.considerNotifying(memo: memo, in: ctx)
        return .result(dialog: "Logged \(Money.formatPaise(memo.amountPaise)) to \(memo.payee).")
    }
}
```

**On the container:** App Intents run inside the app's process, so when Hisab
is already running this opens a *second* `ModelContainer` over the same store
file. Prefer reusing the app's container if one is reachable; if you keep a
separate one, verify by capturing an alert while the app is in the
foreground and confirming the memo appears in the UI without a relaunch. If
it does not, the two contexts are not seeing each other's writes and the
container must be shared — a stale foreground UI is exactly how the 1.2
dismiss/mute bug presented.

- [ ] **Step 2: Add the shortcut provider**

```swift
import AppIntents

/// Surfaces the intent in the Shortcuts app and Siri without setup.
struct HisabShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTransactionAlertIntent(),
                    phrases: ["Add a transaction alert to \(.applicationName)",
                              "Log a payment in \(.applicationName)"],
                    shortTitle: "Add Alert",
                    systemImageName: "indianrupeesign.circle")
    }
}
```

- [ ] **Step 3: Add the `CaptureNotifier` stub**

```swift
import Foundation
import SwiftData
import HisabCore

@MainActor
enum CaptureNotifier {
    /// Filled in by Task 9.
    static func considerNotifying(memo: PendingMemo, in ctx: ModelContext) {}
}
```

- [ ] **Step 4: Build**

Run the gate, then `make gen`, then `make build`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Verify the intent is actually exposed and dedup works end to end**

Install to the simulator, open the Shortcuts app, confirm "Add Transaction Alert" appears under Hisab. Run it with:
`Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis`
Expected dialog: `Logged ₹450.00 to vedant@okaxis.`
Run it a second time with identical text.
Expected dialog: `Already logged ₹450.00.` — the dedup guard proving itself through the real store, not a unit test.

- [ ] **Step 6: Commit**

Stage `Hisab/Intents`, `Hisab/Services/CaptureNotifier.swift`; commit as
`feat(ios): trigger-agnostic App Intent for alert capture`

---

### Task 9: Notification policy in the core

The cap and the quiet-hours hold are real logic, and the iOS app target cannot unit-test anything. So the decision lives in `HisabCore` (and gets a Dart twin in Task 14), and the app only obeys it.

**Files:**
- Create: `HisabCore/Sources/HisabCore/Capture/NotificationPolicy.swift`
- Create: `HisabCore/Sources/HisabCore/Capture/CategoryRanker.swift`
- Test: `HisabCore/Tests/HisabCoreTests/NotificationPolicyTests.swift`

**Interfaces:**
- Consumes: `PendingMemo`, `SpendRecord` (`SuggestionEngine.swift:5`), `Categorizer.uncategorized` / `.miscellaneous` / `.selfTransfer`, `YearMonth.istCalendar`.
- Produces:
  - `NotificationDecision` — `.send`, `.hold(until: Date)`, `.suppress`
  - `NotificationPolicy.dailyCap` (10), `NotificationPolicy.quietStartHour` (22), `NotificationPolicy.quietEndHour` (8)
  - `NotificationPolicy.decide(now: Date, sentToday: Int) -> NotificationDecision`
  - `CategoryRanker.topCategories(records: [SpendRecord], now: Date, limit: Int) -> [String]`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import HisabCore

final class NotificationPolicyTests: XCTestCase {
    private func at(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    func testSendsDuringWakingHoursUnderTheCap() {
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 14:30"), sentToday: 3), .send)
    }

    func testSuppressesAtTheDailyCap() {
        // A heavy UPI day must not turn into 40 notifications.
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 14:30"),
                                                 sentToday: NotificationPolicy.dailyCap),
                       .suppress)
    }

    func testHoldsLateNightUntilMorning() {
        // Hisab must never wake anyone. 23:10 -> 08:00 next day.
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 23:10"), sentToday: 0),
                       .hold(until: at("2026-09-23 08:00")))
    }

    func testHoldsEarlyMorningUntilSameDayEight() {
        // 02:30 is still "last night" -> 08:00 the SAME day, not the next.
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 02:30"), sentToday: 0),
                       .hold(until: at("2026-09-22 08:00")))
    }

    func testSendsExactlyAtEightAndHoldsExactlyAtTwentyTwo() {
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 08:00"), sentToday: 0), .send)
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 22:00"), sentToday: 0),
                       .hold(until: at("2026-09-23 08:00")))
    }
}

final class CategoryRankerTests: XCTestCase {
    private func day(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)!
    }

    private func record(_ category: String, _ date: String,
                        _ direction: Direction = .debit) -> SpendRecord {
        SpendRecord(merchant: "m", amountPaise: 100, date: day(date),
                    direction: direction, effectiveCategory: category)
    }

    func testRanksByCountAndExcludesNonCategories() {
        let now = day("2026-09-22")
        let records = [
            record("Food Delivery", "2026-09-20"), record("Food Delivery", "2026-09-19"),
            record("Food Delivery", "2026-09-18"),
            record("Transport", "2026-09-20"), record("Transport", "2026-09-19"),
            record("Shopping", "2026-09-20"),
            record("Groceries", "2026-09-20"),
            // These three must never be offered as an answer.
            record(Categorizer.uncategorized, "2026-09-20"),
            record(Categorizer.miscellaneous, "2026-09-20"),
            record(Categorizer.selfTransfer, "2026-09-20"),
        ]
        XCTAssertEqual(CategoryRanker.topCategories(records: records, now: now, limit: 3),
                       ["Food Delivery", "Transport", "Groceries"],
                       "count desc, then alphabetical: Groceries before Shopping")
    }

    func testIgnoresRecordsOlderThanNinetyDaysAndCredits() {
        let now = day("2026-09-22")
        let records = [
            record("Food Delivery", "2026-01-01"),
            record("Transport", "2026-09-20", .credit),
            record("Shopping", "2026-09-20"),
        ]
        XCTAssertEqual(CategoryRanker.topCategories(records: records, now: now, limit: 3),
                       ["Shopping"])
    }

    func testReturnsFewerThanLimitWhenNotEnoughHistory() {
        XCTAssertEqual(CategoryRanker.topCategories(records: [], now: day("2026-09-22"), limit: 3),
                       [])
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path HisabCore --filter NotificationPolicyTests`
Run: `swift test --package-path HisabCore --filter CategoryRankerTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum NotificationDecision: Equatable, Sendable {
    case send
    /// Held so Hisab never wakes anyone; deliver at this instant instead.
    case hold(until: Date)
    /// Today's budget is spent. The needs-review inbox still carries the memo,
    /// so nothing is lost — only the interruption is dropped.
    case suppress
}

/// When Hisab may interrupt the user about an uncategorized payment.
public enum NotificationPolicy {
    public static let dailyCap = 10
    public static let quietStartHour = 22
    public static let quietEndHour = 8

    public static func decide(now: Date, sentToday: Int) -> NotificationDecision {
        if sentToday >= dailyCap { return .suppress }
        let hour = YearMonth.istCalendar.component(.hour, from: now)
        guard hour >= quietStartHour || hour < quietEndHour else { return .send }

        // Before 08:00 the hold lands today; from 22:00 it lands tomorrow.
        let base = hour < quietEndHour
            ? now
            : YearMonth.istCalendar.date(byAdding: .day, value: 1, to: now) ?? now
        var components = YearMonth.istCalendar.dateComponents([.year, .month, .day], from: base)
        components.hour = quietEndHour
        components.minute = 0
        components.second = 0
        guard let until = YearMonth.istCalendar.date(from: components) else { return .send }
        return .hold(until: until)
    }
}

/// The categories worth offering as one-tap answers on a notification.
public enum CategoryRanker {
    public static let windowDays = 90

    /// Highest debit *count* over the trailing window. Count, not spend: the
    /// question is "what does this user usually buy", and one large payment
    /// should not outrank a habit. Excluded: the two non-answers and self
    /// transfers. Ties break alphabetically so the buttons are deterministic.
    public static func topCategories(records: [SpendRecord], now: Date,
                                     limit: Int) -> [String] {
        let excluded: Set<String> = [Categorizer.uncategorized,
                                     Categorizer.miscellaneous,
                                     Categorizer.selfTransfer]
        let windowStart = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var counts: [String: Int] = [:]
        for record in records
        where record.direction == .debit
            && record.date >= windowStart
            && record.date <= now
            && !excluded.contains(record.effectiveCategory) {
            counts[record.effectiveCategory, default: 0] += 1
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --package-path HisabCore --filter NotificationPolicyTests`
Run: `swift test --package-path HisabCore --filter CategoryRankerTests`
Expected: PASS, 8 tests total.

- [ ] **Step 5: Commit**

Stage the two core files and the test; commit as
`feat(capture): notification policy and category ranking in the core`

---

### Task 10: iOS notification delivery and deep-link routing

This is the task most likely to *look* correct and silently do nothing — the exact failure mode that shipped in 1.2 (a write-only `@State` that `body` never read, which survived an implementation and a full code review). Every step here ends in an observation on a running app, not a passing compile.

**Files:**
- Modify: `Hisab/Services/CaptureNotifier.swift` (replace the Task 8 stub)
- Modify: `Hisab/HisabApp.swift` (notification delegate, `onOpenURL`, launch-time permission state)
- Create: `Hisab/Services/DeepLinkRouter.swift`

**Interfaces:**
- Consumes: `NotificationPolicy`, `CategoryRanker`, `MemoStore`, `CapturePrefs`, `Queries.suggestionRecords(_:)` (`Queries.swift`), `Money.formatPaise`, `Categorizer`.
- Produces: `CaptureNotifier.requestAuthorization()`, `CaptureNotifier.considerNotifying(memo:in:)`, `DeepLinkRouter` (`@Observable`, with `pendingMemoHash: String?` and `pendingTxnUUID: UUID?`), `DeepLinkRouter.handle(_ url: URL)`.

- [ ] **Step 1: Implement `CaptureNotifier`**

Notification action titles are fixed at *category registration* time, so dynamic category buttons require registering a category whose identifier encodes the titles, immediately before scheduling. That is the non-obvious part of this file.

```swift
import Foundation
import SwiftData
import UserNotifications
import HisabCore

@MainActor
enum CaptureNotifier {
    static let categoryPrefix = "MEMO_CATEGORIZE"
    static let laterActionID = "MEMO_LATER"

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Notifies only when Hisab could NOT categorize the payee — precisely the
    /// memory-decay case this feature exists for.
    static func considerNotifying(memo: PendingMemo, in ctx: ModelContext) {
        let rules = Queries.categoryRules(ctx)
        let matcher = CategoryMatcher(rules: rules)
        let auto = matcher.category(for: memo.payee)
        guard auto == Categorizer.uncategorized || auto == Categorizer.miscellaneous else {
            return
        }

        let now = Date()
        let decision = NotificationPolicy.decide(
            now: now, sentToday: CapturePrefs.notificationsSentToday(now: now))
        let fireDate: Date?
        switch decision {
        case .suppress: return
        case .send: fireDate = nil
        case .hold(let until): fireDate = until
        }

        let choices = CategoryRanker.topCategories(
            records: Queries.suggestionRecords(ctx), now: now, limit: 3)
        let categoryID = register(choices: choices)

        let content = UNMutableNotificationContent()
        content.title = "What was this?"
        content.body = "\(Money.formatPaise(memo.amountPaise)) to \(memo.payee)"
        content.categoryIdentifier = categoryID
        content.userInfo = ["captureHash": memo.captureHash]
        content.sound = .default

        var trigger: UNNotificationTrigger?
        if let fireDate {
            let interval = max(1, fireDate.timeIntervalSince(now))
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        }

        let request = UNNotificationRequest(identifier: memo.captureHash,
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        CapturePrefs.recordNotification(now: now)

        if let stored = MemoStore.find(hash: memo.captureHash, in: ctx) {
            stored.notifiedAt = now
            try? ctx.save()
        }
    }

    /// Action titles are baked in at registration, so a distinct set of choices
    /// needs a distinct category id. Registration is cheap and idempotent.
    private static func register(choices: [String]) -> String {
        let id = ([categoryPrefix] + choices).joined(separator: "|")
        var actions = choices.map {
            UNNotificationAction(identifier: "CAT|\($0)", title: $0, options: [])
        }
        actions.append(UNNotificationAction(identifier: laterActionID,
                                            title: "Later", options: []))
        let category = UNNotificationCategory(identifier: id, actions: actions,
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        return id
    }
}
```

**Known limitation to record, not to fix here:** `setNotificationCategories` *replaces* the registered set, so only the most recent choice-set stays registered. Two pending notifications with different choice-sets would leave the older one's buttons stale. Accept it for the beta and note it in the ledger; the alternative is accumulating categories forever. Do not silently paper over it.

- [ ] **Step 2: Implement `DeepLinkRouter`**

```swift
import Foundation
import Observation

/// Where a `hisab://` link wants the UI to go. Observable so SwiftUI actually
/// re-renders — a write-only value that `body` never reads is the exact bug
/// that shipped in 1.2's dismiss/mute.
@MainActor
@Observable
final class DeepLinkRouter {
    var pendingMemoHash: String?
    var pendingTxnUUID: UUID?
    var showNeedsReview = false

    /// `hisab://memo/<captureHash>` or `hisab://transaction/<uuid>`.
    /// An unrecognised or unresolvable link opens the needs-review inbox
    /// rather than failing silently.
    func handle(_ url: URL) {
        guard url.scheme == "hisab" else { return }
        let value = url.lastPathComponent
        switch url.host {
        case "memo":
            pendingMemoHash = value.isEmpty ? nil : value
            showNeedsReview = value.isEmpty
        case "transaction":
            pendingTxnUUID = UUID(uuidString: value)
            showNeedsReview = pendingTxnUUID == nil
        default:
            showNeedsReview = true
        }
    }
}
```

- [ ] **Step 3: Wire the delegate and `onOpenURL` in `HisabApp`**

Read `Hisab/HisabApp.swift` in full first. Add:
- a `UNUserNotificationCenterDelegate` (an `NSObject` subclass held by the app) whose `didReceive(_:withCompletionHandler:)` reads `response.notification.request.content.userInfo["captureHash"]`, and:
  - for an action id beginning `CAT|`, assigns that category to the memo **and** writes the rule offer state so the app can confirm on next open;
  - for `MEMO_LATER` or the default action, sets `router.pendingMemoHash` so the review sheet opens.
- `.onOpenURL { router.handle($0) }` on the root view.
- the router injected via `.environment(router)`.

**The assertion that matters:** `body` must *read* `router.pendingMemoHash`. Grep for it after writing — if the only reference is a write, the deep link will do nothing and no test will catch it.

- [ ] **Step 4: Verify notification delivery on the simulator**

Build and install. Enable capture. Run the App Intent from Shortcuts with an alert naming a payee no rule matches:
`Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis`
Expected: a notification titled "What was this?" with body `₹450.00 to vedant@okaxis`, and — on long-press — up to three category buttons plus "Later".

Then run it with a payee a rule *does* match (`to SWIGGY`).
Expected: **no notification.** If one appears, the categorized-guard is inverted, which would make the feature intolerable in daily use.

- [ ] **Step 5: Verify the deep link routes**

Run: `xcrun simctl openurl booted "hisab://memo/<the captureHash from step 4>"`
Expected: the review sheet opens on that memo.
Run: `xcrun simctl openurl booted "hisab://memo/deadbeef"`
Expected: the needs-review inbox opens — not a blank screen, not a crash.

- [ ] **Step 6: Verify a notification tap routes**

Tap the notification body (not a button).
Expected: Hisab opens with the review sheet on that memo. This is the single most important interaction in the feature and cannot be verified by any automated test in this project.

- [ ] **Step 7: Commit**

Stage `CaptureNotifier.swift`, `DeepLinkRouter.swift`, `HisabApp.swift`; commit as
`feat(ios): failure notifications with category actions and deep-link routing`

---

### Task 11: iOS review sheet, rule offer, inbox and health

**Files:**
- Create: `Hisab/Views/MemoReviewSheet.swift`
- Create: `Hisab/Views/NeedsReviewSection.swift`
- Create: `Hisab/Views/CaptureSetupView.swift`
- Modify: `Hisab/Views/DashboardView.swift` (mount the section and the health warning)
- Modify: `Hisab/Views/SettingsView.swift` (capture toggle, last-captured line, link to setup)

**Interfaces:**
- Consumes: `MemoStore`, `CapturePrefs`, `DeepLinkRouter`, `RuleKey`, `Queries.categoryRules`, `StoredCategoryRule`, `Money.formatPaise`, `CategoryRanker`.
- Produces: `MemoReviewSheet(memo:)`, `NeedsReviewSection()`, `CaptureSetupView()`.

- [ ] **Step 1: Add the blast-radius count to the core**

The count shown in the rule offer must be real, and counting is logic — so it belongs in the core, not in a view.

Add to `HisabCore/Sources/HisabCore/Capture/PendingMemo.swift` (or a new `RuleImpact.swift`):

```swift
/// How many existing rows a proposed rule would change.
public enum RuleImpact {
    public struct Row: Sendable {
        public var text: String
        public var hasOverride: Bool
        public var currentCategory: String
        public init(text: String, hasOverride: Bool, currentCategory: String) {
            self.text = text
            self.hasOverride = hasOverride
            self.currentCategory = currentCategory
        }
    }

    /// Rows a new `pattern` would newly categorize. Rows the user categorized
    /// by hand are excluded — a rule must never override an explicit choice.
    public static func affectedCount(pattern: String, rows: [Row]) -> Int {
        let needle = pattern.lowercased()
        guard !needle.isEmpty else { return 0 }
        return rows.filter {
            !$0.hasOverride
                && $0.text.lowercased().contains(needle)
                && ($0.currentCategory == Categorizer.uncategorized
                    || $0.currentCategory == Categorizer.miscellaneous)
        }.count
    }
}
```

with tests covering: a match counted; an override-bearing row excluded; an already-categorized row excluded; an empty pattern returning 0.

- [ ] **Step 2: Run the core tests**

Run: `swift test --package-path HisabCore --filter RuleImpact`
Expected: PASS, 4 tests.

- [ ] **Step 3: Build `MemoReviewSheet`**

Shows amount (`Money.formatPaise`), payee, capture time, account tail, a note field, and a category picker seeded with `CategoryRanker.topCategories` followed by the rest alphabetically. On choosing a category:
1. `MemoStore.assign(category:to:in:)`
2. compute `RuleImpact.affectedCount` for `memo.asMemo.ruleKey.pattern` over the projected rows
3. offer: *"Always categorize `<pattern>` as `<category>`" — with, when the count is above zero, "This will also update N past transactions."*
4. on accept, insert a `StoredCategoryRule(pattern:category:sortOrder:)` following the exact pattern at `Hisab/Views/SuggestionPrompt.swift:63`

Recategorization needs no backfill: `Queries.category(of:rules:)` derives category at read time, so every matching past row changes the moment the rule lands. Do not write a migration loop.

- [ ] **Step 4: Build `NeedsReviewSection` and the health warning**

Section on the dashboard, shown only when `MemoStore.pending(ctx)` is non-empty: a count and the memos, each opening `MemoReviewSheet`. Feed it from `@Query` so SwiftData changes invalidate the view automatically — computing from a bare `ModelContext` fetch never refreshes (the bug that left the Transactions tab stale on device).

Health warning, shown when `CapturePrefs.isEnabled` and `lastCaptureAt` is nil or older than 3 days: *"No alerts captured in N days — capture may have stopped."* with a link to `CaptureSetupView`. This exists because both mechanisms fail silently; without it the feature can be dead for weeks unnoticed.

- [ ] **Step 5: Build `CaptureSetupView`**

Plain-language disclosure first (what is read, what is kept, that nothing leaves the device), then the enable toggle, then step-by-step iOS setup: create a Shortcuts automation on the **Message** trigger filtered to the bank's sender, whose single action is Hisab's "Add Transaction Alert", set to Run Immediately with Notify When Run off. State honestly that the richer Notification trigger needs iOS 27. Include a "Test it" button that runs the parser on a bundled sample and reports what it extracted, so the user can confirm the pipeline works before trusting it.

**Be accurate about what the app can and cannot do here.** `AppShortcutsProvider` (Task 8) puts the action in the Shortcuts app and Siri automatically, but it does **not** put Hisab in the share sheet for selected text, and an app cannot install an automation on the user's behalf. Share-sheet capture requires a *shortcut* with "Use as Quick Action → Share Sheet" enabled, which the user must create or import. So:

- The setup screen walks the user through building the automation themselves, step by step, naming the exact trigger and options.
- It also walks them through the one-time share-sheet shortcut (new shortcut → Receive text from Share Sheet → Add Transaction Alert → enable Show in Share Sheet), which is the fallback that works regardless of whether the Message trigger passes the body.
- Do **not** write copy claiming Hisab appears in the share sheet on install. It does not, and discovering that after reading the setup screen would undermine trust in everything else the screen says.

This friction is the main thing the TestFlight dogfooding is meant to measure, so record it plainly rather than hiding it.

- [ ] **Step 6: Add the Settings entries**

In `SettingsView`, a capture section: the toggle (requesting notification authorization on first enable, via `CaptureNotifier.requestAuthorization`), a "Last captured" line, and a link to `CaptureSetupView`.

- [ ] **Step 7: Build and verify on the simulator**

Run the gate, then `make gen`, then `make build`.
Then, in the running app:
- capture two alerts with unmatched payees; confirm the dashboard section shows 2
- open one, assign a category, accept the rule offer
- confirm the memo leaves the needs-review list
- confirm the blast-radius count matched what actually changed: check a previously `Uncategorized` transaction with that payee now shows the new category in the Transactions tab
- toggle capture off and on; confirm the health line updates

- [ ] **Step 8: Commit**

Stage the new views, the modified views, and the core `RuleImpact` + its test; commit as
`feat(ios): memo review, retroactive rule offer, needs-review inbox and capture health`

---

### Task 12: iOS merge on import

**Files:**
- Modify: `Hisab/Services/ImportService.swift`
- Modify: `HisabCore` — none.

**Interfaces:**
- Consumes: `MemoMerger.merge(memos:candidates:)`, `MemoMergeCandidate`, `MemoStore`.
- Produces: no new API; import now retires memos and transfers notes.

- [ ] **Step 1: Read `ImportService.swift` in full**

Find the point after transactions are inserted and saved. The merge must run *after* insertion, in the same save cycle, so a failed import does not retire memos.

- [ ] **Step 2: Add the merge step**

Project the freshly stored rows into `MemoMergeCandidate` (`id: txn.uuid`, `date`, `amountPaise`, `direction`, `narration: "\(txn.counterparty) \(txn.narration)"`), call `MemoMerger.merge` with `MemoStore.all(ctx).map(\.asMemo)` filtered to unmerged, then for each result set `mergedTxnUUID` and, when the memo carries a note and the transaction has none, copy the note across. Then `MemoStore.expire(now: Date(), in: ctx)`.

Use `"\(counterparty) \(narration)"` as the narration — the same concatenation `Queries.category(of:rules:)` uses, so VPA matching sees the same text categorization does.

- [ ] **Step 3: Verify end to end on the simulator**

- capture an alert for ₹450 to a payee, dated today
- import a synthetic statement containing a ₹450 debit to that payee on the same day
- expected: the memo disappears from needs-review, and the transaction carries the note
- then capture an alert for an amount that appears in *no* statement and import again
- expected: that memo stays pending — the merge must not claim unrelated rows

- [ ] **Step 4: Confirm memos stayed out of the numbers**

Note the dashboard month total before capturing, capture three alerts, and confirm the total is **unchanged**. Memos are a labelling channel; if they move a total, the exclusion is broken and the ledger's integrity guarantee is gone.

- [ ] **Step 5: Commit**

Stage `ImportService.swift`; commit as
`feat(ios): retire pending memos against imported statement rows`

---

### Task 13: Flutter memo table and the schema migration

**This task carries the highest blast radius in the plan.** `lib/storage/database.dart` currently declares `int get schemaVersion => 1` and **no `MigrationStrategy` at all**. Adding a table without one means every existing install opens a v1 database that lacks the new table, and the first query throws `no such table`. The feature would work perfectly on a fresh install and break the app for every current user — precisely the class of bug that fresh-install testing cannot see.

**Files:**
- Modify: `hisab_flutter/lib/storage/database.dart`
- Regenerate: `hisab_flutter/lib/storage/database.g.dart` (build_runner — never hand-edit)
- Create: `hisab_flutter/lib/services/memo_store.dart`
- Create: `hisab_flutter/lib/services/capture_prefs.dart`
- Test: `hisab_flutter/test/memo_store_test.dart`

**Interfaces:**
- Consumes: `PendingMemo`, `MemoMerger` (Task 4).
- Produces: `StoredPendingMemos` table, `MemoStore.insert`, `.pending`, `.all`, `.find`, `.assign`, `.expire`, `CapturePrefs` mirroring the Swift names.

- [ ] **Step 1: Add the table**

Mirror the SwiftData model field-for-field. Follow the existing table style in this file (text primary keys, `IntColumn` millisecond timestamps — note the existing convention is `dateMs` / `periodStartMs`, so use `dateMs` and `capturedAtMs`, **not** `DateTime` columns).

```dart
class StoredPendingMemos extends Table {
  TextColumn get captureHash => text()();
  IntColumn get amountPaise => integer()();
  TextColumn get direction => text()(); // debit | credit
  TextColumn get payee => text()();
  TextColumn get payeeNormalized => text()();
  TextColumn get vpa => text().nullable()();
  TextColumn get accountTail => text().nullable()();
  IntColumn get dateMs => integer()();
  IntColumn get capturedAtMs => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get assignedCategory => text().nullable()();
  TextColumn get mergedTxnUuid => text().nullable()();
  IntColumn get notifiedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {captureHash};
}
```

Add it to the `@DriftDatabase(tables: [...])` list.

- [ ] **Step 2: Bump the schema version and add the migration**

```dart
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  /// There was no MigrationStrategy before v2. Without this, an existing v1
  /// install opens a database with no pending-memo table and throws on the
  /// first query — a fresh install would never reveal it.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(storedPendingMemos);
          }
        },
      );
}
```

- [ ] **Step 3: Regenerate**

Run: `cd hisab_flutter && dart run build_runner build --delete-conflicting-outputs`
Expected: `database.g.dart` regenerated with `$StoredPendingMemosTable`. Do not hand-edit the generated file.

- [ ] **Step 4: Write the migration test — the one that discriminates**

```dart
// hisab_flutter/test/memo_store_test.dart
// Opens a database at schema v1, then upgrades, proving the migration runs.
// A fresh-install test would pass even with the migration missing, so this
// is the only test here that is actually load-bearing.
```

Build a v1 database using drift's test helpers (`NativeDatabase.memory()` with an explicit `schemaVersion` fixture, or drift's `SchemaVerifier` if the project adds `drift_dev`'s schema tooling), insert a transaction, then reopen at v2 and assert both that the old row survives and that a memo can be inserted. If drift's schema-verification tooling is not already available, create the v1 schema by raw SQL in the test rather than skipping this — the assertion matters more than the mechanism.

- [ ] **Step 5: Run it and watch it fail with the migration removed**

Temporarily revert the `migration` override, run the test, and confirm it FAILS with a missing-table error. Restore the override and confirm it PASSES. A migration test that has never failed is not known to test the migration.

Run: `cd hisab_flutter && flutter test test/memo_store_test.dart`

- [ ] **Step 6: Write `MemoStore` and `CapturePrefs`**

Mirror `Hisab/Services/MemoStore.swift` and `CapturePrefs.swift` method-for-method and name-for-name. `CapturePrefs` uses `SharedPreferences`, following `lib/services/insight_store.dart` exactly (read it first) — capture state is a device preference, never database data.

- [ ] **Step 7: Run the Flutter test suite**

Run: `cd hisab_flutter && flutter test`
Expected: PASS, including the existing suites.

- [ ] **Step 8: Commit**

Stage the storage, generated file, services and test; commit as
`feat(android): pending-memo table with the first real drift migration`

---

### Task 14: Dart twins for policy, ranking and rule impact

**Files:**
- Create: `hisab_flutter/packages/hisab_core/lib/src/capture/notification_policy.dart`
- Create: `.../capture/category_ranker.dart`
- Create: `.../capture/rule_impact.dart`
- Modify: `hisab_flutter/packages/hisab_core/lib/hisab_core.dart` (exports)
- Modify: `hisab_flutter/packages/hisab_core/test/capture_test.dart`

**Interfaces:**
- Produces: Dart equivalents of `NotificationDecision`, `NotificationPolicy.decide`, `CategoryRanker.topCategories`, `RuleImpact.affectedCount` with identical semantics to Tasks 9 and 11.

- [ ] **Step 1: Read the Swift sources as the specification**

`HisabCore/Sources/HisabCore/Capture/{NotificationPolicy,CategoryRanker}.swift` and the `RuleImpact` addition. Port exactly, including: the cap check *before* the quiet-hours check, the before-08:00-holds-today / from-22:00-holds-tomorrow split, count-not-spend ranking, the alphabetical tie-break, and the override exclusion.

- [ ] **Step 2: Port every test case**

All 12 cases from `NotificationPolicyTests`, `CategoryRankerTests` and the `RuleImpact` tests, same names, same expectations. Dart's `DateTime` arithmetic around the IST offset is the likeliest source of divergence — use the existing helpers in `src/year_month.dart`, not raw `DateTime` math.

- [ ] **Step 3: Run to verify they fail, implement, run to verify they pass**

Run: `cd hisab_flutter/packages/hisab_core && dart test test/capture_test.dart`

- [ ] **Step 4: Extend the parity fixture**

Add a `policy` block to `HisabCore/Tests/HisabCoreTests/Fixtures/alert-parity.json` pinning `decide` outcomes for a set of (hour, sentToday) pairs, and a `ranking` block pinning `topCategories` for a fixed record set. Assert it from both suites, then run `tool/sync_assets.sh`. Verify it discriminates by perturbing one expectation and watching both suites fail.

- [ ] **Step 5: Commit**

`feat(capture): Dart twins for notification policy, ranking and rule impact`

---

### Task 15: Android notification capture

**Files:**
- Modify: `hisab_flutter/pubspec.yaml` (add `notification_listener_service`)
- Create: `hisab_flutter/lib/services/notification_capture.dart`
- Create: `hisab_flutter/assets/capture/allowlist.json`
- Modify: `hisab_flutter/pubspec.yaml` (register `assets/capture/`)
- Modify: `hisab_flutter/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: `AlertParser.parse`, `MemoStore.insert`, `CapturePrefs`, `CaptureNotifier` (Task 16).
- Produces: `NotificationCapture.start()`, `.stop()`, `.isGranted()`, `.requestPermission()`, `CaptureAllowlist.load()`.

- [ ] **Step 1: Confirm `READ_SMS` is absent and stays absent**

Run: `grep -rn "READ_SMS\|RECEIVE_SMS\|READ_CALL_LOG" hisab_flutter/android/`
Expected: no matches. If a plugin's manifest merges one in, that plugin cannot be used — Play would remove the app. Check the merged manifest after building, not just the source.

- [ ] **Step 2: Add the dependency and verify what it pulls in**

Run: `cd hisab_flutter && flutter pub add notification_listener_service`
Then run: `cd hisab_flutter && flutter build apk --debug`
Then inspect the merged manifest for any SMS or network permission the plugin added:
`grep -rn "uses-permission" hisab_flutter/build/app/intermediates/merged_manifests/debug/AndroidManifest.xml`
Expected: `BIND_NOTIFICATION_LISTENER_SERVICE` only (as a service permission), plus what Hisab already declared. **Any INTERNET permission is a blocker** — it would contradict the zero-network promise on the store listing even if unused. Report it rather than proceeding.

- [ ] **Step 3: Write the allowlist asset**

```json
{
  "version": 1,
  "packages": [
    "com.google.android.apps.messaging",
    "com.samsung.android.messaging",
    "com.android.mms",
    "net.one97.paytm",
    "com.phonepe.app",
    "com.google.android.apps.nbu.paisa.user",
    "com.csam.icici.bank.imobile",
    "com.sbi.lotusintouch",
    "com.snapwork.hdfc",
    "com.axis.mobile",
    "com.idfcfirstbank.optimus"
  ]
}
```

Bundled as an asset so it extends without a code change, following the `FormatSpec` precedent. Only notifications from these packages are examined; everything else is ignored before parsing.

- [ ] **Step 4: Write `NotificationCapture`**

Subscribe to the plugin's event stream. For each event: check `CapturePrefs.isEnabled`; check the package is in the allowlist; concatenate title and content into one string; `AlertParser.parse`; on a memo, `MemoStore.insert` and, only when insert returned true, `CaptureNotifier.considerNotifying`. Always set `CapturePrefs.lastCaptureAt` on a *parsed* alert (not on every notification, or the health indicator would report health it does not have).

Never persist the raw notification text.

- [ ] **Step 5: Declare the service and the deep link in the manifest**

Add the notification-listener service with `BIND_NOTIFICATION_LISTENER_SERVICE` and the `android.service.notification.NotificationListenerService` intent filter per the plugin's README, and an `intent-filter` on the main activity for `hisab://` (`android:scheme="hisab"`, `VIEW` action, `BROWSABLE` + `DEFAULT` categories).

- [ ] **Step 6: Verify capture on a device or emulator**

Install, enable capture, grant notification access when deep-linked to settings. Then post a test notification containing an alert body from the allowlisted SMS package — `adb shell am broadcast` cannot post as another package, so use the emulator's SMS injection instead:
`adb emu sms send BANKSMS "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis"`
Expected: the memo appears in needs-review and a notification fires.

Then send the identical SMS again.
Expected: **no second memo** — the dedup guard holding against a real notification update, which is the reason it exists.

- [ ] **Step 7: Verify it survives process death**

Force-stop the app (`adb shell am force-stop com.vedants.hisab` — confirm the real applicationId first), then inject another SMS.
Expected: captured anyway. If it is not, the plugin does not survive process death and a thin platform channel over `NotificationListenerService` directly is required — report this rather than shipping a listener that silently stops.

- [ ] **Step 8: Commit**

`feat(android): notification-listener capture with a bundled sender allowlist`

---

### Task 16: Flutter correction loop

Mirror of Tasks 10–12 on the Flutter side. Read each Swift counterpart before writing the Dart.

**Files:**
- Create: `hisab_flutter/lib/services/capture_notifier.dart`
- Create: `hisab_flutter/lib/widgets/memo_review_sheet.dart`
- Create: `hisab_flutter/lib/widgets/needs_review_section.dart`
- Create: `hisab_flutter/lib/screens/capture_setup_screen.dart`
- Modify: `hisab_flutter/lib/screens/dashboard_screen.dart`, `lib/state.dart`, `lib/main.dart`, `lib/services/import_service.dart`, `pubspec.yaml`
- Test: `hisab_flutter/test/capture_flow_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 13–15, plus `flutter_local_notifications` for delivery with action buttons.
- Produces: `CaptureNotifier.considerNotifying`, `MemoReviewSheet`, `NeedsReviewSection`, `CaptureSetupScreen`.

- [ ] **Step 1: Add `flutter_local_notifications` and re-check permissions**

Run: `cd hisab_flutter && flutter pub add flutter_local_notifications`
Then re-run the merged-manifest permission check from Task 15 Step 2. Expected additions: `POST_NOTIFICATIONS`, and possibly `RECEIVE_BOOT_COMPLETED` / `SCHEDULE_EXACT_ALARM`. **No INTERNET.**

- [ ] **Step 2: Implement `CaptureNotifier`**

Mirror `Hisab/Services/CaptureNotifier.swift`: categorize the payee with `CategoryMatcher`, return early unless the result is `Uncategorized` or `Miscellaneous`, consult `NotificationPolicy.decide`, build up to three action buttons from `CategoryRanker.topCategories` plus "Later", and carry `captureHash` in the payload. Android action buttons are per-notification (`AndroidNotificationAction`), so unlike iOS there is **no** global-category limitation here — note the asymmetry in the ledger.

- [ ] **Step 3: Wire notification-tap and action routing**

`onDidReceiveNotificationResponse` reads the payload's `captureHash`: an action id beginning `CAT|` assigns that category; anything else opens the review sheet. Route through the app's existing navigation, and ensure the state the sheet reads is a value the widget tree actually watches — `lib/state.dart` already exposes watched streams (`db.select(...).watch()`), so add the memo stream there rather than fetching once in `initState`.

- [ ] **Step 4: Build the review sheet, inbox, health line and setup screen**

Mirror Task 11's behaviour, including the blast-radius count via `RuleImpact.affectedCount` and rule insertion following `lib/widgets/suggestion_prompt.dart`. The Android setup screen differs from iOS: a single "Grant notification access" button deep-linking to the system settings page, plus the disclosure text, plus the same "Test it" affordance. Add the health warning at the 3-day threshold, and state plainly in the setup copy that some manufacturers' battery settings can stop capture — this is the Xiaomi/Oppo/Vivo reality and users deserve to be told.

- [ ] **Step 5: Add the import merge**

Mirror Task 12 in `lib/services/import_service.dart`, using `"$counterparty $narration"` as the narration so VPA matching sees what categorization sees.

- [ ] **Step 6: Write `capture_flow_test.dart`**

Widget/unit tests for what is testable without a device: a memo assigned a category leaves the pending list; a rule insertion recategorizes a matching past row; an override-bearing row is untouched; the import merge retires a memo and transfers its note; and a memo does **not** change any analytics total.

- [ ] **Step 7: Run the suites**

Run: `cd hisab_flutter && flutter test`
Run: `cd hisab_flutter/packages/hisab_core && dart test`
Expected: PASS.

- [ ] **Step 8: Verify the upgrade path on a device**

Install the **1.2.0 release APK first**, open it so the v1 database exists, then install the 1.3.0 build over it. Expected: no crash, existing transactions intact, capture available. This is the assertion Task 13's migration exists for, and a fresh install cannot make it.

- [ ] **Step 9: Commit**

`feat(android): memo review, retroactive rule offer, inbox, health and import merge`

---

### Task 17: iOS share-sheet file import (Phase B)

Independent of capture. Cheap because Task 6 already moved the target onto a real Info.plist.

**Files:**
- Modify: `project.yml` (document types in the `info:` block)
- Modify: `Hisab/HisabApp.swift` (file URL handling)
- Modify: `Hisab/Services/ImportService.swift` if needed to accept a file URL

**Interfaces:**
- Consumes: the existing `ImportResolver` pipeline (silent format detection shipped in 1.2 — there is no source to pick).
- Produces: Hisab as a destination for PDF/CSV/XLSX/XLS/TXT from Files, Mail, Gmail and the share sheet.

- [ ] **Step 1: Declare the document types**

Add to the `info:` `properties` in `project.yml`:

```yaml
        LSSupportsOpeningDocumentsInPlace: true
        UIFileSharingEnabled: true
        CFBundleDocumentTypes:
          - CFBundleTypeName: Statement
            CFBundleTypeRole: Viewer
            LSHandlerRank: Alternate
            LSItemContentTypes:
              - com.adobe.pdf
              - public.comma-separated-values-text
              - org.openxmlformats.spreadsheetml.sheet
              - com.microsoft.excel.xls
              - public.plain-text
```

`LSHandlerRank: Alternate` is deliberate: Hisab is not claiming to be the system's PDF handler, only offering itself as a destination.

- [ ] **Step 2: Handle the incoming URL**

Extend the existing `onOpenURL` (added in Task 10) to distinguish a file URL from a `hisab://` link: a file URL goes to the import pipeline. Copy the file into the app's container before reading — an open-in-place URL is only valid for the duration of the access scope, and reading it later fails. Use `url.startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` around the copy.

- [ ] **Step 3: Verify from a real share sheet**

Build to the simulator. Put a synthetic CSV in Files, tap Share, and confirm Hisab appears. Choose it.
Expected: the import flow opens on that file and detects the format with no source picker.

Then repeat from Mail with an attachment, which is the actual user journey — a statement arrives by email.

- [ ] **Step 4: Confirm the password-protected case still prompts**

Share an encrypted HDFC PDF. Expected: the existing password prompt appears rather than a silent failure.

- [ ] **Step 5: Commit**

`feat(ios): accept statements from the share sheet and Files`

---

### Task 18: Version bump, full verification, TestFlight

**Files:**
- Modify: `project.yml` (`MARKETING_VERSION: "1.3.0"`, `CURRENT_PROJECT_VERSION: 4`)
- Modify: `hisab_flutter/pubspec.yaml` (`version: 1.3.0+3`)
- Modify: `README.md` if the feature warrants a line

- [ ] **Step 1: Full verification**

Run the gate, then in order:
- `swift test --package-path HisabCore`
- `cd hisab_flutter/packages/hisab_core && dart test`
- `cd hisab_flutter && flutter test`
- `tool/sync_assets.sh --check`
- `make gen && make build`
- `make uitest`

Every one must pass. Report any failure rather than working around it.

- [ ] **Step 2: Confirm the zero-network promise still holds**

Run: `grep -rn "http://\|https://\|Socket\|URLSession\|HttpClient\|dart:io.*Http" --include=*.swift --include=*.dart Hisab HisabCore hisab_flutter/lib hisab_flutter/packages | grep -v test | grep -v "mailto"`
Expected: no networking. Also re-check the merged Android manifest for `INTERNET`. This promise is load-bearing for both store listings.

- [ ] **Step 3: Bump versions and commit**

- [ ] **Step 4: Archive, export and upload to TestFlight**

Archive with **automatic** signing, then export with the manual distribution profile — the SPM resource bundle rejects a global `PROVISIONING_PROFILE_SPECIFIER`, so signing must switch at `exportArchive`. Reuse the export options at `~/.claude-personal/jobs/2d3c07f7/tmp/exportOptions.plist` (method `app-store-connect`, team `AQQHT55AT9`, cert `Apple Distribution: Vedant Saboo (AQQHT55AT9)`, profile `Hisab App Store`). Upload with `altool`.

Expected: `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, `UPLOAD SUCCEEDED` with a delivery UUID.

- [ ] **Step 5: Build the Android sideload APK**

Run: `cd hisab_flutter && flutter build apk --release --split-per-abi`
TestFlight covers only iOS; the Android half needs a sideload build, and OEM battery-kill behaviour cannot be evaluated on an emulator.

- [ ] **Step 6: Push and open the PR**

Branch `feat/realtime-capture`. `gh` must be switched to `VedantS01` first and switched back to `vedantsab00` after. Never push to main directly.

- [ ] **Step 7: Record the store-declaration work that is NOT code**

Notification access is a sensitive-data grant, so shipping this beyond a
sideload needs console work that cannot be done from the repo. Write these
into the PR body as an explicit handover list for Vedant:

- **Play Data safety**: declare what the notification listener reads and that
  it is processed on-device and not shared or transmitted. Play's automated
  pre-submission checks compare the binary against the declaration and will
  flag an undeclared data type before human review.
- **Prominent disclosure**: confirm the in-app disclosure on `CaptureSetupView`
  satisfies Play's requirement for a separate in-app disclosure preceding the
  grant (it is written for exactly this).
- **Both store listings** describe Hisab as having no network access. That
  remains true and the listings need no change on that point — but the
  feature descriptions should mention capture, and the iOS privacy answers
  should be re-checked against the new local notifications usage.

TestFlight itself needs none of this; it becomes blocking only at the Play
internal-track upload and the next App Store submission.

- [ ] **Step 8: Write the dogfooding checklist into the PR body**

The build exists to answer two questions: how hard is setup, and is it useful. List, for the reviewer-of-one: iOS automation setup steps, what to watch for (silent automation failure, notification action behaviour, whether the Message trigger passes the body at all), and the Android notification-access grant plus battery-manager behaviour.
