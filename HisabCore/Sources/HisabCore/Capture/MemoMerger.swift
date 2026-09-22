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
/// The gates are deliberately strict and the pairing is deliberately global.
/// An unmerged memo expires harmlessly; a wrongly merged one silently moves
/// the user's note onto somebody else's payment.
public enum MemoMerger {
    public static let windowDays = 3

    /// `captureHash -> transaction id`. Each memo and each candidate is used
    /// at most once, and the assignment is fully determined by content.
    public static func merge(memos: [PendingMemo],
                             candidates: [MemoMergeCandidate]) -> [String: UUID] {
        struct Pair {
            let memoHash: String
            let candidateID: UUID
            let distance: Int
        }

        var pairs: [Pair] = []
        for memo in memos {
            for candidate in candidates where matches(memo: memo, candidate: candidate) {
                pairs.append(Pair(memoHash: memo.captureHash,
                                  candidateID: candidate.id,
                                  distance: dayGap(memo.date, candidate.date)))
            }
        }

        // Closest pair first. Per-memo greedy let an older memo take a nearer
        // memo's exact-date row and push that memo onto the older one's row,
        // swapping two notes between two real payments.
        pairs.sort {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.memoHash != $1.memoHash { return $0.memoHash < $1.memoHash }
            return $0.candidateID.uuidString < $1.candidateID.uuidString
        }

        var claimedMemos = Set<String>()
        var claimedCandidates = Set<UUID>()
        var result: [String: UUID] = [:]
        for pair in pairs {
            guard !claimedMemos.contains(pair.memoHash),
                  !claimedCandidates.contains(pair.candidateID) else { continue }
            claimedMemos.insert(pair.memoHash)
            claimedCandidates.insert(pair.candidateID)
            result[pair.memoHash] = pair.candidateID
        }
        return result
    }

    /// Whole IST calendar days between two instants.
    ///
    /// Truncating to the start of day is essential. `dateComponents(from:to:)`
    /// measures elapsed time and borrows across midnight, so a memo captured
    /// at 23:55 and a midnight-dated statement row four date-labels later
    /// measure as three days. Bank parsers emit date-only values and memos
    /// carry real times, so that case is the norm.
    static func dayGap(_ lhs: Date, _ rhs: Date) -> Int {
        let calendar = YearMonth.istCalendar
        let earlier = calendar.startOfDay(for: min(lhs, rhs))
        let later = calendar.startOfDay(for: max(lhs, rhs))
        return calendar.dateComponents([.day], from: earlier, to: later).day ?? .max
    }

    /// Lowercased alphanumeric tokens. Digits are kept deliberately: a numeric
    /// VPA like `9876543210@ybl` would otherwise reduce to `{ybl}`, a subset of
    /// nearly every UPI narration, making the VPA gate a match on the bank
    /// handle alone.
    static func tokens(of text: String) -> Set<String> {
        var cleaned = ""
        for character in text.lowercased() {
            cleaned.append(character.isLetter || character.isNumber ? character : " ")
        }
        return Set(cleaned.split(separator: " ").map(String.init))
    }

    private static func matches(memo: PendingMemo,
                                candidate: MemoMergeCandidate) -> Bool {
        guard memo.amountPaise == candidate.amountPaise,
              memo.direction == candidate.direction,
              dayGap(memo.date, candidate.date) <= windowDays else { return false }

        let narrationTokens = tokens(of: candidate.narration)

        // Every part of the handle must appear, so "ram@okhdfc" does not match
        // a payment to "sriram@okhdfc".
        if let vpa = memo.vpa {
            let vpaTokens = tokens(of: vpa)
            if !vpaTokens.isEmpty, vpaTokens.isSubset(of: narrationTokens) { return true }
        }

        // Whole-token match. Substring containment made this gate nearly a
        // no-op for a payee whose first token is a single initial.
        guard let first = memo.payeeNormalized.split(separator: " ").first else {
            return false
        }

        // A VPA's handle (after "@") identifies a bank shared by millions,
        // not a person -- unlike its local part, which the VPA-subset check
        // above already covers. A numeric VPA's local part vanishes under
        // SuggestionEngine.normalize (letters-only), so payeeNormalized can
        // collapse to just the handle. If it did, the fallback must not
        // fire on the handle alone: that would merge onto any stranger who
        // shares the same UPI provider, which is the common case in India,
        // not the edge case. Bank narrations that name the payee and omit
        // the VPA entirely (no handle to collide with) are unaffected.
        //
        // The handle is deliberately the substring after the LAST "@", or
        // "" when there is none -- never `split(separator:).last`, whose
        // default `omittingEmptySubsequences: true` would drop a trailing
        // empty component and return the LOCAL part for a malformed
        // "name@" VPA instead of "". An empty handle can never equal a
        // non-empty payee token (`first` is always non-empty here), so this
        // keeps the guard's behaviour otherwise unchanged; it exists only
        // so this function computes exactly what the Dart port computes.
        //
        // Deliberately untested: this line is unreachable through `matches`
        // today. `tokens()` strips "@" as a separator, so for a trailing-"@"
        // VPA, `vpaTokens` above reduces to exactly `{localPart}`. Reaching
        // this guard requires the VPA-subset check to have failed, i.e.
        // `localPart` absent from `narrationTokens` -- but that is the same
        // condition under which `narrationTokens.contains(first)` below is
        // also false (since `first == localPart` is required to hit this
        // guard at all). The two predicates collapse into one, so no
        // observable outcome depends on how `handle` is computed here, and
        // no test can be written that would fail without this fix. It is
        // still made bit-for-bit identical to the Dart port on principle:
        // the collapse depends on the VPA-subset check sitting before this
        // guard and on `tokens()` stripping "@", and if either ever changes
        // this line would go live with nothing to catch a divergence.
        if let vpa = memo.vpa {
            let handle = vpa.lastIndex(of: "@").map { String(vpa[vpa.index(after: $0)...]) } ?? ""
            if String(first) == handle { return false }
        }

        return narrationTokens.contains(String(first))
    }
}
