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

        guard let (direction, directionAt) = directionMatch(in: lower) else { return nil }
        guard let amountPaise = amount(in: lower), amountPaise > 0 else { return nil }
        let vpa = self.vpa(in: lower)
        let extracted = payee(in: collapsed, lower: lower, direction: direction,
                              from: directionAt)
        guard let payee = extracted ?? vpa.map({ String($0.split(separator: "@")[0]) }),
              !payee.isEmpty else { return nil }

        return PendingMemo(amountPaise: amountPaise,
                           direction: direction,
                           payee: payee,
                           vpa: vpa,
                           accountTail: accountTail(in: lower),
                           date: date(in: lower) ?? receivedAt,
                           capturedAt: receivedAt)
    }

    /// Exactly one direction must be present, and we need its position so payee
    /// extraction can start at the transaction clause rather than at the top of
    /// the message. Both directions means a summary or an ad; neither means a
    /// balance notice.
    private static func directionMatch(in lower: String) -> (Direction, String.Index)? {
        func earliest(_ words: [String]) -> String.Index? {
            var best: String.Index?
            for word in words {
                guard let found = lower.range(of: word) else { continue }
                if best == nil || found.lowerBound < best! { best = found.lowerBound }
            }
            return best
        }
        let debit = earliest(debitWords)
        let credit = earliest(creditWords)
        if let debit, credit == nil { return (.debit, debit) }
        if let credit, debit == nil { return (.credit, credit) }
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
        let pattern = #"([a-z0-9][a-z0-9._-]{1,})@([a-z]{2,})(?![a-z0-9-])(?!\.[a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let whole = Range(match.range, in: lower) else { return nil }
        return String(lower[whole])
    }

    private static let debitLeadIns = [" to vpa ", " vpa ", " to ", " at ", " towards "]
    private static let creditLeadIns = [" from ", " by "]

    /// Words that end a payee. Compared as whole TOKENS, never as substrings —
    /// that is what stops "SRI BALAJI STORES" being cut at "bal".
    private static let payeeStopTokens: Set<String> = [
        "on", "ref", "refno", "upi", "a/c", "ac", "acct", "account",
        "avl", "bal", "not", "info", "txn", "id", "utr", "dated", "date", "via",
    ]

    /// Characters that end a payee outright.
    private static let payeeTerminators: Set<Character> = [
        ".", ",", "|", ";", "(", ")", "!", "?", "*", "#",
    ]

    /// Extracts the payee from the clause that follows the direction keyword.
    ///
    /// Anchoring at `start` (the direction keyword's position) is deliberate: a
    /// leading disclaimer such as "write to us at ..." would otherwise hijack the
    /// " to " lead-in. There is intentionally NO whole-message fallback — an alert
    /// that phrases the payee before the direction word is declined instead.
    /// Declining costs one uncaptured alert; guessing costs a wrong rule.
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
        for word in words {
            if payeeStopTokens.contains(word.lowercased()) { break }
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
