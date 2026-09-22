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
        guard let amount = amount(in: lower), amount.paise > 0 else { return nil }
        let vpa = self.vpa(in: lower)
        let extracted = payee(in: collapsed, lower: lower, direction: direction,
                              from: amount.end)
        guard let payee = extracted ?? vpa.map({ String($0.split(separator: "@")[0]) }),
              !payee.isEmpty else { return nil }

        return PendingMemo(amountPaise: amount.paise,
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

    /// The amount and where it ended. The end position anchors payee extraction:
    /// the amount is the one landmark guaranteed to sit inside the transaction
    /// clause, whereas a direction keyword ("sent", "paid") turns up in template
    /// preambles and would let a disclaimer's " to " win.
    private static func amount(in lower: String) -> (paise: Int64, end: String.Index)? {
        if let hit = firstAmount(#"(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
                                 in: lower) {
            return hit
        }
        return firstAmount(#"(?<![0-9.])([0-9][0-9,]*\.[0-9]{2})(?![0-9.])"#, in: lower)
    }

    private static func firstAmount(_ pattern: String,
                                    in lower: String) -> (paise: Int64, end: String.Index)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let whole = Range(match.range, in: lower),
              let captured = Range(match.range(at: 1), in: lower),
              let paise = Money.signedPaise(fromDecimalString: String(lower[captured]))
        else { return nil }
        return (paise, whole.upperBound)
    }

    /// A VPA handle has no dot; an email domain does. That single distinction
    /// keeps support addresses out of the rule key.
    private static func vpa(in lower: String) -> String? {
        let pattern = #"([a-z0-9][a-z0-9._-]{1,})@([a-z]{2,})(?![a-z0-9-])(?!\.[a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let whole = Range(match.range, in: lower) else { return nil }
        return String(lower[whole])
    }

    private static let debitLeadIns = [" to vpa ", " vpa ", " to ", " at ", " towards "]
    private static let creditLeadIns = [" from ", " by "]

    /// Tokens that always end a payee. Each one is boilerplate that is never a
    /// word in a merchant's name. Deliberately SHORT: a stop token that collides
    /// with a real name either truncates the payee into a generic rule key or
    /// drops the alert entirely, and both are worse than leaving a reference
    /// fragment attached.
    private static let payeeStopTokens: Set<String> = [
        "ref", "refno", "utr", "txn", "upi", "a/c", "acct", "account",
        "avl", "dated", "using", "thru", "through", "vide",
    ]

    /// `"on"` cannot be dropped — `"on <date>"` is the commonest alert tail —
    /// but it also cannot be unconditional, because "SHOP ON WHEELS" is a real
    /// name. It ends the payee only when a date plausibly follows.
    private static let contextualStopTokens: Set<String> = ["on", "dt"]

    /// Characters that end a payee outright. ":" earns its place: it is never
    /// inside a merchant name and it closes "Info:", "Queries:" and "Bal:" in
    /// one stroke, which is why several risky word-tokens could be removed.
    private static let payeeTerminators: Set<Character> = [
        ".", ",", "|", ";", ":", "(", ")", "!", "?", "*", "#",
    ]

    /// Extracts the payee from the clause that follows the amount.
    ///
    /// Anchoring at `start` (where the amount ended) is deliberate: the amount
    /// is mandatory and sits inside the transaction clause by definition, so a
    /// leading disclaimer such as "write to us at ..." — or a direction word
    /// like "sent" appearing in a preamble — cannot hijack the lead-in search.
    /// There is intentionally NO whole-message fallback — an alert that phrases
    /// the payee before the amount is declined instead. Declining costs one
    /// uncaptured alert; guessing costs a wrong rule.
    private static func payee(in text: String, lower: String, direction: Direction,
                              from start: String.Index) -> String? {
        let leadIns = direction == .credit ? creditLeadIns : debitLeadIns
        for leadIn in leadIns {
            guard let found = lower.range(of: leadIn, range: start..<lower.endIndex) else {
                continue
            }
            if let cleaned = trimToPayee(String(text[found.upperBound...])) {
                return cleaned
            }
        }
        return nil
    }

    /// Cuts the tail at the first terminator character, then at the first stop
    /// token. Tokenising before comparing is the whole point: a stop token only
    /// ends a payee when it stands alone as a word.
    private static func trimToPayee(_ tail: String) -> String? {
        var words: [String] = []
        var current = ""
        for ch in tail {
            if payeeTerminators.contains(ch) { break }
            if ch.isWhitespace {
                if !current.isEmpty { words.append(current); current = "" }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { words.append(current) }

        var kept: [String] = []
        for (index, word) in words.enumerated() {
            let token = word.lowercased()
            if payeeStopTokens.contains(token) { break }
            if contextualStopTokens.contains(token) {
                // Only boilerplate if something date-like follows.
                let next = index + 1 < words.count ? words[index + 1] : ""
                if next.first?.isNumber == true { break }
            }
            kept.append(word)
        }
        return kept.isEmpty ? nil : kept.joined(separator: " ")
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
