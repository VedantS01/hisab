// Dart twin of PendingMemoTests.swift, AlertParserTests.swift and
// MemoMergerTests.swift (HisabCore/Tests/HisabCoreTests). Same test names,
// same expectations, same fixtures — see task-4-brief.md.
import 'dart:convert';
import 'dart:io';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

/// The IST-wall-clock instant for (year, month, day, hour, minute), built
/// the same way AlertParser._makeDate does: express the wall-clock time as
/// a UTC instant shifted by -istOffset so istClock() reads it back exactly.
DateTime _istDateTime(int year, int month, int day,
    [int hour = 0, int minute = 0]) {
  return DateTime.utc(year, month, day, hour, minute).subtract(istOffset);
}

/// "yyyy-MM-dd HH:mm" in IST.
DateTime _at(String iso) {
  final parts = iso.split(' ');
  final d = parts[0].split('-').map(int.parse).toList();
  final t = parts[1].split(':').map(int.parse).toList();
  return _istDateTime(d[0], d[1], d[2], t[0], t[1]);
}

/// "yyyy-MM-dd" in IST, midnight.
DateTime _day(String iso) {
  final d = iso.split('-').map(int.parse).toList();
  return _istDateTime(d[0], d[1], d[2]);
}

int _idCounter = 0;

/// A fresh canonical lowercase UUID-shaped string, unique per call.
String _newId() {
  _idCounter++;
  final hex = _idCounter.toRadixString(16).padLeft(12, '0');
  return '00000000-0000-4000-8000-$hex';
}

void main() {
  group('PendingMemo', () {
    test('testCaptureHashIgnoresTimeOfDay', () {
      // Two captures of the same underlying payment, with `date` values
      // minutes (or hours) apart but on the same IST calendar day — e.g. an
      // alert with no date in its text, where AlertParser falls back to
      // receivedAt, and a second capture lands later. The hash must key on
      // the day, not the instant, so these collapse to one memo.
      final morning = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'VEDANT SABOO',
        vpa: 'vedant@okaxis',
        accountTail: '1234',
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      final sameDayLater = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'VEDANT SABOO',
        vpa: 'vedant@okaxis',
        accountTail: '1234',
        date: _at('2026-09-22 23:50'),
        capturedAt: _at('2026-09-22 23:50'),
      );
      expect(morning.captureHash, sameDayLater.captureHash);
    });

    test('testCaptureHashSeparatesAcrossISTMidnight', () {
      // The other half of day granularity: `date` values only minutes apart
      // but on different IST calendar days must NOT collapse.
      final beforeMidnight = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'VEDANT SABOO',
        vpa: 'vedant@okaxis',
        accountTail: '1234',
        date: _at('2026-09-22 23:55'),
        capturedAt: _at('2026-09-22 23:55'),
      );
      final afterMidnight = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'VEDANT SABOO',
        vpa: 'vedant@okaxis',
        accountTail: '1234',
        date: _at('2026-09-23 00:05'),
        capturedAt: _at('2026-09-23 00:05'),
      );
      expect(beforeMidnight.captureHash, isNot(afterMidnight.captureHash));
    });

    test('testCaptureHashSeparatesAmountPayeeAndVPA', () {
      // captureHash IS the dedup identity — each field that feeds it must
      // move the hash when it changes.
      final baseline = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'SWIGGY',
        vpa: 'swiggy@icici',
        accountTail: '1234',
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );

      final differentAmount = PendingMemo(
        amountPaise: 45001,
        direction: Direction.debit,
        payee: 'SWIGGY',
        vpa: 'swiggy@icici',
        accountTail: '1234',
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      expect(baseline.captureHash, isNot(differentAmount.captureHash));

      final differentPayee = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'ZOMATO',
        vpa: 'swiggy@icici',
        accountTail: '1234',
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      expect(baseline.captureHash, isNot(differentPayee.captureHash));

      final differentVPA = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'SWIGGY',
        vpa: 'swiggy@hdfcbank',
        accountTail: '1234',
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      expect(baseline.captureHash, isNot(differentVPA.captureHash));
    });

    test('testCaptureHashSeparatesDirection', () {
      // A refund reuses the payee and amount; it is a different movement.
      final debit = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'SWIGGY',
        vpa: null,
        accountTail: null,
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      final credit = PendingMemo(
        amountPaise: 45000,
        direction: Direction.credit,
        payee: 'SWIGGY',
        vpa: null,
        accountTail: null,
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      expect(debit.captureHash, isNot(credit.captureHash));
    });

    test('testPayeeNormalizedMatchesSuggestionEngine', () {
      // Rule patterns must match what the existing rule store already holds.
      final memo = PendingMemo(
        amountPaise: 1,
        direction: Direction.debit,
        payee: 'BLUE TOKAI COFFEE ROASTERS PVT',
        vpa: null,
        accountTail: null,
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      expect(memo.payeeNormalized, 'blue tokai coffee');
    });

    test('testRuleKeyPrefersVPAOverUnstableDisplayName', () {
      // The whole point: "VEDANT SABOO" varies per statement, the VPA does not.
      final withVPA = PendingMemo(
        amountPaise: 1,
        direction: Direction.debit,
        payee: 'VEDANT SABOO',
        vpa: 'Vedant@OkAxis',
        accountTail: null,
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      expect(withVPA.ruleKey,
          RuleKey(pattern: 'vedant@okaxis', kind: RuleKeyKind.vpa));

      final withoutVPA = PendingMemo(
        amountPaise: 1,
        direction: Direction.debit,
        payee: 'Blue Tokai',
        vpa: null,
        accountTail: null,
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
      );
      expect(withoutVPA.ruleKey,
          RuleKey(pattern: 'blue tokai', kind: RuleKeyKind.merchant));
    });

    test('PendingMemo value equality over stored fields', () {
      // P3 fix: Swift's PendingMemo is Equatable (synthesized over stored
      // properties only); the Dart twin had no ==/hashCode and fell back to
      // reference identity. Two memos with identical stored fields must be
      // ==; changing `note` alone (a stored field excluded from every
      // computed property) must make them unequal.
      final a = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'SWIGGY',
        vpa: 'swiggy@icici',
        accountTail: '1234',
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
        note: 'lunch',
      );
      final b = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'SWIGGY',
        vpa: 'swiggy@icici',
        accountTail: '1234',
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
        note: 'lunch',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final differentNote = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'SWIGGY',
        vpa: 'swiggy@icici',
        accountTail: '1234',
        date: _at('2026-09-22 09:15'),
        capturedAt: _at('2026-09-22 09:15'),
        note: 'dinner',
      );
      expect(a, isNot(differentNote));
    });
  });

  group('AlertParser', () {
    const now = '2026-09-22 14:30';

    test('testParsesHDFCStyleUPIDebit', () {
      const text =
          'Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. Ref 123456789012. Not you? Call 18002586161';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.amountPaise, 45000);
      expect(memo?.direction, Direction.debit);
      expect(memo?.vpa, 'vedant@okaxis');
      expect(memo?.payee, 'vedant@okaxis');
      expect(memo?.accountTail, '1234');
      expect(istDayString(memo!.date), '2026-09-22');
    });

    test('testParsesLakhGroupedAmount', () {
      const text =
          'INR 1,23,456.78 debited from A/c no. XX9876 towards BLUE TOKAI COFFEE on 21/09/2026';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.amountPaise, 12345678);
      expect(memo?.payee, 'BLUE TOKAI COFFEE');
      expect(istDayString(memo!.date), '2026-09-21');
    });

    test('testParsesCreditAsCredit', () {
      // Misreading a credit as spending would corrupt every downstream number.
      const text = '₹2,000 credited to your account XX1234 from RAHUL on 22Sep26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.direction, Direction.credit);
      expect(memo?.amountPaise, 200000);
      // C2: the payee must be the sender, never the masked-account boilerplate.
      expect(memo?.payee, 'RAHUL');
    });

    test('testFallsBackToReceivedAtWhenAlertHasNoDate', () {
      const text = 'Rs 99.00 debited from a/c XX1234 to ZEPTO';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.payee, 'ZEPTO');
      expect(istDayString(memo!.date), '2026-09-22');
    });

    test('testRejectsTextWithBothDirections', () {
      // "credited"+"debited" in one message is a statement summary or an
      // ad, not a single movement. Guessing here is how you corrupt a ledger.
      const text =
          'Your a/c XX1234: Rs.500.00 debited and Rs.500.00 credited on 22-09-26';
      expect(AlertParser.parse(text, _at(now)), isNull);
    });

    test('testRejectsTextWithNoDirection', () {
      const text = 'Your a/c XX1234 balance is Rs.12,345.67 as on 22-09-26';
      expect(AlertParser.parse(text, _at(now)), isNull);
    });

    test('testRejectsTextWithNoCurrencyAmount', () {
      // An account number must never be mistaken for an amount.
      const text = 'Payment debited from a/c XX1234 to VEDANT';
      expect(AlertParser.parse(text, _at(now)), isNull);
    });

    test('testDoesNotMistakeEmailForVPA', () {
      // An email has a dotted domain; a VPA handle does not.
      const text =
          'Rs.450.00 debited from a/c XX1234 to SWIGGY. Queries: help@swiggy.in';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.vpa, isNull);
      expect(memo?.payee, 'SWIGGY');
    });

    test('testRejectsPromotionalText', () {
      // Rejected on direction: "Spend" is not "spent". Named for what it is.
      const text = 'Get a personal loan instantly! Spend more and earn rewards.';
      expect(AlertParser.parse(text, _at(now)), isNull);
    });

    test('testDoesNotReadADottedDateAsAnAmount', () {
      // The fallback two-decimal pattern would happily read "22.09" out of
      // "22.09.26" and report a ₹22.09 payment. A wrong number in the user's
      // own data is the one failure this product cannot absorb.
      const text = 'Payment debited on 22.09.26 to ZEPTO';
      expect(AlertParser.parse(text, _at(now)), isNull);
    });

    test('testStillReadsAGenuineTwoDecimalAmountWithoutACurrencyMarker', () {
      // The dotted-date guard must not swallow this.
      const text = 'Debited 450.00 from a/c XX1234 to ZEPTO on 22-09-26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.amountPaise, 45000);
      expect(memo?.payee, 'ZEPTO');
    });

    test('testReadsVPAWhenTheAlertEndsTheSentenceWithAPeriod', () {
      // Regression: a trailing sentence period must not be mistaken for a
      // dotted email domain and swallow the VPA.
      const text =
          'Rs.100.00 debited from a/c XX1234 to VPA vedant@okaxis. Thank you for using UPI.';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.vpa, 'vedant@okaxis');
      expect(memo?.payee, 'vedant@okaxis');
    });

    test('testDoesNotReadAnEmailAsAVPAEvenAtTheEndOfASentence', () {
      // An email domain dot must still block a VPA match, even when a
      // second, sentence-ending period follows immediately after it.
      const text =
          'Rs.450.00 debited from a/c XX1234 to SWIGGY. Queries: help@swiggy.in.';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.vpa, isNull);
      expect(memo?.payee, 'SWIGGY');
    });

    test('testDoesNotTruncateAMerchantNameContainingAStopWord', () {
      // C1: " bal" (intended for "Avl Bal" boilerplate) must not fire as a
      // substring inside "BALAJI" — stop words are tokens, not substrings.
      const text = 'Rs.200.00 debited from a/c XX1234 to SRI BALAJI STORES on 22-09-26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.payee, 'SRI BALAJI STORES');
    });

    test('testIgnoresALeadingDisclaimerWhenFindingThePayee', () {
      // C3: the lead-in search must anchor after the direction keyword, or
      // a leading disclaimer's " to " hijacks the match.
      const text =
          'For queries write to us at 1800123456. Rs.500.00 debited from a/c XX1234 to SWIGGY on 22-09-26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.payee, 'SWIGGY');
    });

    test('testReadsANumericVPA', () {
      const text = 'Rs.150.00 debited from a/c XX1234 to VPA 9876543210@ybl on 22-09-26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.vpa, '9876543210@ybl');
      expect(memo?.payee, '9876543210@ybl');
    });

    test('testIgnoresABoilerplatePreambleContainingADirectionWord', () {
      // N1: direction words ("sent") routinely appear in template preambles.
      // Anchoring on the amount instead of the direction word means the
      // preamble, and the disclaimer's " to ", cannot hijack the match.
      const text =
          'This SMS is sent by XYZ Bank. For queries write to us at 1800123456. Rs.500.00 debited from a/c XX1234 to SWIGGY on 22-09-26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.payee, 'SWIGGY');
    });

    test('testKeepsAMerchantNameContainingOnAsAWord', () {
      // N2: "on" only ends a payee when a date plausibly follows it, so
      // "X ON WHEELS" (a real Indian business pattern) survives intact.
      const text = 'Rs.150.00 debited from a/c XX1234 to SHOP ON WHEELS on 22-09-26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.payee, 'SHOP ON WHEELS');
    });

    test('testKeepsAMerchantNameStartingWithAFormerStopWord', () {
      // N3: a name whose first token used to be a stop token ("id") must
      // not be dropped entirely.
      const text = 'Rs.320.00 debited from a/c XX1234 to ID FRESH FOOD on 22-09-26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.payee, 'ID FRESH FOOD');
    });

    test('testStopsAtAConnectorWord', () {
      // N4: connector words like "using" must not leak into the payee and
      // fragment one merchant into two different rule keys.
      const text = 'Purchase of Rs.450.00 at SWIGGY using a/c XX1234';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.payee, 'SWIGGY');
    });

    test('testStopsAtViaInAPaidAlert', () {
      // "via UPI" is one of the commonest tails in Indian payment alerts;
      // round 3 briefly let it leak into the payee as "SWIGGY via".
      const text = 'You have paid Rs.450.00 to SWIGGY via UPI on 22-09-26';
      final memo = AlertParser.parse(text, _at(now));
      expect(memo?.payee, 'SWIGGY');
      expect(memo?.direction, Direction.debit);
      expect(memo?.amountPaise, 45000);
    });
  });

  group('MemoMerger', () {
    PendingMemo memo(int amount, String payee, String? vpa, String date) {
      return PendingMemo(
        amountPaise: amount,
        direction: Direction.debit,
        payee: payee,
        vpa: vpa,
        accountTail: null,
        date: _day(date),
        capturedAt: _day(date),
      );
    }

    PendingMemo memoAt(int amount, String payee, String? vpa, DateTime date) {
      return PendingMemo(
        amountPaise: amount,
        direction: Direction.debit,
        payee: payee,
        vpa: vpa,
        accountTail: null,
        date: date,
        capturedAt: date,
      );
    }

    test('testMergesOnVPAPresentInNarration', () {
      final m = memo(45000, 'VEDANT SABOO', 'vedant@okaxis', '2026-09-22');
      final id = _newId();
      final candidate = MemoMergeCandidate(
        id: id,
        date: _day('2026-09-22'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'UPI-VEDANT SABOO-VEDANT@OKAXIS-HDFC-123456',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]),
          {m.captureHash: id});
    });

    test('testMergesWithinThreeDays', () {
      final m = memo(45000, 'ZEPTO', null, '2026-09-22');
      final id = _newId();
      final candidate = MemoMergeCandidate(
        id: id,
        date: _day('2026-09-25'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'ZEPTO MARKETPLACE',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]),
          {m.captureHash: id});
    });

    test('testDoesNotMergeBeyondThreeDays', () {
      final m = memo(45000, 'ZEPTO', null, '2026-09-22');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-26'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'ZEPTO MARKETPLACE',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]), isEmpty);
    });

    test('testDoesNotMergeOnAmountMismatch', () {
      final m = memo(45000, 'ZEPTO', null, '2026-09-22');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-22'),
        amountPaise: 45001,
        direction: Direction.debit,
        narration: 'ZEPTO MARKETPLACE',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]), isEmpty);
    });

    test('testDoesNotMergeOnPayeeMismatch', () {
      final m = memo(45000, 'ZEPTO', null, '2026-09-22');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-22'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'SWIGGY INSTAMART',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]), isEmpty);
    });

    test('testOneCandidateServesOnlyOneMemo', () {
      // Two identical-looking memos, one real row: pairing is global and
      // greedy by distance, so the closer-dated memo wins the candidate
      // and the farther one stays pending. (Per-memo oldest-first greedy
      // claiming could instead let an older memo steal a nearer memo's
      // exact-date row — see testDoesNotSwapTwoMemosBetweenTwoCandidates.)
      final a = memo(45000, 'ZEPTO', null, '2026-09-20');
      final b = memo(45000, 'ZEPTO', null, '2026-09-21');
      final id = _newId();
      final candidate = MemoMergeCandidate(
        id: id,
        date: _day('2026-09-21'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'ZEPTO MARKETPLACE',
      );
      final merged = MemoMerger.merge(memos: [a, b], candidates: [candidate]);
      expect(merged.length, 1);
      expect(merged[b.captureHash], id,
          reason: 'the closer-dated memo claims the candidate');
      expect(merged[a.captureHash], isNull,
          reason: 'the farther memo stays pending');
    });

    test('testPicksNearestDateAmongCandidates', () {
      final m = memo(45000, 'ZEPTO', null, '2026-09-22');
      final near = _newId();
      final far = _newId();
      final candidates = [
        MemoMergeCandidate(
          id: far,
          date: _day('2026-09-25'),
          amountPaise: 45000,
          direction: Direction.debit,
          narration: 'ZEPTO MARKETPLACE',
        ),
        MemoMergeCandidate(
          id: near,
          date: _day('2026-09-22'),
          amountPaise: 45000,
          direction: Direction.debit,
          narration: 'ZEPTO MARKETPLACE',
        ),
      ];
      expect(MemoMerger.merge(memos: [m], candidates: candidates),
          {m.captureHash: near});
    });

    // MARK: - Fix round 1 (D1-D4)

    test('testDoesNotMergeAcrossFourDateLabelsWhenTimesOfDayDiffer', () {
      // D1: elapsed-time arithmetic borrows across midnight.
      // 2026-09-22 23:55 -> 2026-09-26 00:05 is four date-labels apart but
      // only 3d10m of elapsed time, so a naive elapsed-time diff reports 3
      // days and wrongly merges.
      final m = memoAt(45000, 'ZEPTO', null, _at('2026-09-22 23:55'));
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _at('2026-09-26 00:05'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'ZEPTO MARKETPLACE',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]), isEmpty,
          reason:
              'four date-labels apart must not merge, regardless of elapsed time');
    });

    test('testStillMergesThreeDateLabelsApartWhenTimesOfDayDiffer', () {
      // The other half of D1: the fix must not over-tighten. Three
      // date-labels apart still merges even with differing times of day.
      final m = memoAt(45000, 'ZEPTO', null, _at('2026-09-22 23:55'));
      final id = _newId();
      final candidate = MemoMergeCandidate(
        id: id,
        date: _at('2026-09-25 00:05'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'ZEPTO MARKETPLACE',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]),
          {m.captureHash: id});
    });

    test('testDoesNotMergeOnASingleInitialPayeeToken', () {
      // D2: raw substring containment made "M S DHONI" -> first token "m"
      // match almost any narration. Whole-token matching must decline.
      final m = memo(45000, 'M S DHONI', null, '2026-09-22');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-22'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'UPI-AMAZON PAY-AMAZON@YBL-ICICI0000123',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]), isEmpty);
    });

    test('testMergesASingleInitialPayeeOntoItsRealRow', () {
      // The other half of D2: whole-token matching must not simply disable
      // short-token matching outright.
      final m = memo(45000, 'M S DHONI', null, '2026-09-22');
      final id = _newId();
      final candidate = MemoMergeCandidate(
        id: id,
        date: _day('2026-09-22'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'UPI-M S DHONI-HDFC-123456',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]),
          {m.captureHash: id});
    });

    test('testDoesNotMergeAVPAThatIsASubstringOfAnother', () {
      // D3: "ram@okhdfc" is a literal substring of "sriram@okhdfc" but a
      // different person. Tokens must be a whole-token subset, not a
      // substring match. The payee is chosen so it doesn't independently
      // match the narration either.
      final m = memo(45000, 'RAM KUMAR', 'ram@okhdfc', '2026-09-22');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-22'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'UPI-SRIRAM-SRIRAM@OKHDFC-HDFC-99',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]), isEmpty);
    });

    test('testDoesNotSwapTwoMemosBetweenTwoCandidates', () {
      // D4: per-memo oldest-first greedy claiming lets M1 (older) steal
      // M2's exact-date candidate, pushing M2 onto M1's farther candidate
      // -- both "merge" but with swapped notes. Global closest-pair-first
      // assignment must not swap them.
      final m1 = memo(45000, 'ZEPTO', null, '2026-09-20');
      final m2 = memo(45000, 'ZEPTO', null, '2026-09-21');
      final candidateA = _newId(); // far from m1's own date, but m1's true row
      final candidateB = _newId(); // exact match for m2
      final candidates = [
        MemoMergeCandidate(
          id: candidateA,
          date: _day('2026-09-23'),
          amountPaise: 45000,
          direction: Direction.debit,
          narration: 'ZEPTO MARKETPLACE',
        ),
        MemoMergeCandidate(
          id: candidateB,
          date: _day('2026-09-21'),
          amountPaise: 45000,
          direction: Direction.debit,
          narration: 'ZEPTO MARKETPLACE',
        ),
      ];
      final merged = MemoMerger.merge(memos: [m1, m2], candidates: candidates);
      expect(merged[m2.captureHash], candidateB,
          reason: 'm2 keeps its exact-date row');
      expect(merged[m1.captureHash], candidateA,
          reason: 'm1 gets its own, farther row');
    });

    test('testDoesNotMergeANumericVPAOntoAnotherUserOfTheSameHandle', () {
      // F1 (Critical): a numeric VPA's local part vanishes under
      // SuggestionEngine.normalize (letters-only), so payeeNormalized
      // becomes just the bank handle ("ybl"). The VPA gate correctly fails
      // here (the digits are absent from the narration), but the payee
      // fallback must not then match on the handle alone -- that would
      // merge onto a stranger who happens to use the same UPI provider,
      // which is the common case, not the edge case.
      final m = memo(50000, '9876543210@ybl', '9876543210@ybl', '2026-09-20');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-22'),
        amountPaise: 50000,
        direction: Direction.debit,
        narration:
            'UPI/DR/000111222333/RAVI KUMAR/YBL/1112223334@ybl/Payment',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]), isEmpty);
    });

    test('testStillMergesAVPABearingMemoWhenTheNarrationNamesOnlyThePayee',
        () {
      // The fix must not become the blunt "return false whenever the VPA
      // gate fails": some bank narrations name the payee and omit the VPA
      // entirely. Here the payee's first token ("vedant") is not the VPA's
      // handle ("okaxis"), so the fallback must still apply.
      final m = memo(45000, 'VEDANT SABOO', 'vedant@okaxis', '2026-09-20');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-21'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'UPI/123456/VEDANT SABOO',
      );
      final merged = MemoMerger.merge(memos: [m], candidates: [candidate]);
      expect(merged[m.captureHash], candidate.id);
    });

    test('testAMalformedVPAWithNoHandleStillMergesViaTheVPAGate', () {
      // Fix round 2: this does NOT test the handle-comparison guard -- it
      // was originally written to (and named for) that, but the VPA gate
      // above the guard already returns true here: for a trailing "@" VPA,
      // tokens() strips "@" as a separator, so vpaTokens reduces to exactly
      // {"someperson"}, which is trivially a subset of a narration
      // containing "someperson". The guard is provably unreachable on this
      // input (see the comment at the guard itself, in memo_merger.dart).
      // What this test actually pins is that a malformed, handle-less VPA
      // still merges normally through the ordinary VPA-subset path.
      final m = memo(45000, 'SOMEPERSON SHOP', 'someperson@', '2026-09-20');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-21'),
        amountPaise: 45000,
        direction: Direction.debit,
        narration: 'SOMEPERSON SHOP PAYMENT',
      );
      final merged = MemoMerger.merge(memos: [m], candidates: [candidate]);
      expect(merged[m.captureHash], candidate.id);
    });

    test('testDoesNotMergeOnDirectionMismatch', () {
      final m = memo(45000, 'ZEPTO', null, '2026-09-22');
      final candidate = MemoMergeCandidate(
        id: _newId(),
        date: _day('2026-09-22'),
        amountPaise: 45000,
        direction: Direction.credit,
        narration: 'ZEPTO MARKETPLACE',
      );
      expect(MemoMerger.merge(memos: [m], candidates: [candidate]), isEmpty);
    });

    test('testTokensKeepsCombiningMarksAttached', () {
      // Swift twin: MemoMergerTests.testTokensKeepsCombiningMarksAttached.
      // राम = र + ा (combining vowel sign, U+093E) + म: two extended
      // grapheme clusters ("रा", "म") in Swift, both letters, so they
      // concatenate into one token instead of splitting at the mark.
      expect(MemoMerger.tokens('राम KIRANA'), {'राम', 'kirana'});
    });
  });

  group('Alert parity', () {
    // Swift twin: AlertParityTests.swift. Same fixture (copied here by
    // tool/sync_assets.sh) pins AlertParser.parse and MemoMerger.merge so
    // the two cores cannot silently disagree on either. See task-5-brief.md.
    final fixture = jsonDecode(
            File('test/fixtures/alert-parity.json').readAsStringSync())
        as Map<String, dynamic>;
    final receivedAt = DateTime.parse(fixture['receivedAt'] as String);

    Direction directionOf(String raw) =>
        raw == 'credit' ? Direction.credit : Direction.debit;

    for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
      test('${c['name']} parses identically to Swift', () {
        final text = c['text'] as String;
        final expected = c['expected'] as Map<String, dynamic>;
        final memo = AlertParser.parse(text, receivedAt);
        expect(memo, isNotNull, reason: '${c['name']}: expected a parse');
        expect(memo!.amountPaise, expected['amountPaise']);
        expect(memo.direction.name, expected['direction']);
        expect(memo.payee, expected['payee']);
        expect(memo.payeeNormalized, expected['payeeNormalized']);
        expect(memo.vpa, expected['vpa']);
        expect(memo.accountTail, expected['accountTail']);
        expect(istDayString(memo.date), expected['dateISO']);
        expect(memo.captureHash, expected['captureHash']);
        expect(memo.ruleKey.pattern, expected['rulePattern']);
        expect(memo.ruleKey.kind.name, expected['ruleKind']);
      });
    }

    test('rejected texts all fail to parse', () {
      for (final text in (fixture['rejected'] as List).cast<String>()) {
        expect(AlertParser.parse(text, receivedAt), isNull,
            reason: 'expected nil for rejected text: $text');
      }
    });

    for (final m
        in (fixture['merges'] as List).cast<Map<String, dynamic>>()) {
      test('${m['name']} merges identically to Swift', () {
        final memoFixtures =
            (m['memos'] as List).cast<Map<String, dynamic>>();
        final memos = [
          for (final mf in memoFixtures)
            PendingMemo(
              amountPaise: mf['amountPaise'] as int,
              direction: directionOf(mf['direction'] as String),
              payee: mf['payee'] as String,
              vpa: mf['vpa'] as String?,
              accountTail: mf['accountTail'] as String?,
              date: _day(mf['dateISO'] as String),
              capturedAt: _day(mf['dateISO'] as String),
            ),
        ];
        // Each fixture-recorded hash must match what this run computes --
        // catches drift in PendingMemo's hash algorithm independent of the
        // merge assignment itself.
        for (var i = 0; i < memos.length; i++) {
          expect(memos[i].captureHash, memoFixtures[i]['captureHash'],
              reason: '${m['name']}: memo ${memoFixtures[i]['id']} '
                  'hash differs');
        }

        final candidateFixtures =
            (m['candidates'] as List).cast<Map<String, dynamic>>();
        final candidates = [
          for (final cf in candidateFixtures)
            MemoMergeCandidate(
              id: cf['id'] as String,
              date: _day(cf['dateISO'] as String),
              amountPaise: cf['amountPaise'] as int,
              direction: directionOf(cf['direction'] as String),
              narration: cf['narration'] as String,
            ),
        ];

        final result = MemoMerger.merge(memos: memos, candidates: candidates);
        final expected =
            (m['expected'] as Map<String, dynamic>).cast<String, String>();
        expect(result, expected);
      });
    }
  });
}
