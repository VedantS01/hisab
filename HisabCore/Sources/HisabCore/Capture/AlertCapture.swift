import Foundation

/// What capture stores from one extracted alert.
///
/// - A **memo**, the labelling channel, when the alert names someone to label:
///   a payee or a VPA. A counterparty that is only an account number would
///   normalize to the same rule key for every transfer, so it gets no memo.
/// - A **ledger row** when the alert carries a payment-rail reference (UPI
///   RRN, IMPS ref, NEFT/RTGS UTR). The reference is what lets the row join
///   content-hash dedup (a second alert for the same payment collapses into it)
///   and reconcile against the statement row that later confirms it. Alerts
///   without one stay memos, as in 1.3.0: nothing unreferenced enters the ledger.
///
/// Pure, so both cores pin it with one fixture (`alert-capture.json`).
public enum AlertCapture {
    public static func memo(from alert: ExtractedAlert, receivedAt: Date) -> PendingMemo? {
        guard alert.isTransaction, let direction = alert.direction,
              let amount = alert.amountPaise, amount > 0,
              let payee = nonEmpty(alert.payee) ?? nonEmpty(alert.vpa) else { return nil }
        return PendingMemo(amountPaise: amount, direction: direction, payee: payee,
                           vpa: nonEmpty(alert.vpa), accountTail: nonEmpty(alert.ownAccountTail),
                           date: date(alert.dateISO, receivedAt: receivedAt), capturedAt: receivedAt)
    }

    public static func ledgerRow(from alert: ExtractedAlert, receivedAt: Date) -> ParsedTransaction? {
        guard alert.isTransaction, let direction = alert.direction,
              let amount = alert.amountPaise, amount > 0,
              let reference = nonEmpty(alert.ref) else { return nil }
        let counterparty = nonEmpty(alert.payee) ?? nonEmpty(alert.vpa)
            ?? nonEmpty(alert.counterpartyAccountTail).map { "A/c \($0)" } ?? ""
        // Rules match "counterparty narration": carrying the VPA here lets a
        // VPA rule learned from a memo categorize the ledger row too.
        return ParsedTransaction(date: date(alert.dateISO, receivedAt: receivedAt), amountPaise: amount,
                                 direction: direction, counterparty: counterparty,
                                 reference: reference, narration: nonEmpty(alert.vpa) ?? "")
    }

    /// The transaction's IST day. `yyyy-MM-dd` as written; `--MM-dd` (no year
    /// in the alert) in the latest year that does not put it after the day the
    /// alert arrived; absent or impossible (29 Feb in a common year) falls back
    /// to the arrival time.
    public static func date(_ iso: String?, receivedAt: Date) -> Date {
        guard let iso else { return receivedAt }
        let cal = YearMonth.istCalendar
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        if iso.hasPrefix("--"), parts.count == 4, let month = Int(parts[2]), let day = Int(parts[3]) {
            let received = cal.dateComponents([.year, .month, .day], from: receivedAt)
            let year = received.year ?? 2000
            let isLater = (month, day) > (received.month ?? 0, received.day ?? 0)
            return ist(year: isLater ? year - 1 : year, month: month, day: day) ?? receivedAt
        }
        if parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
            return ist(year: year, month: month, day: day) ?? receivedAt
        }
        return receivedAt
    }

    /// Midnight IST of a valid calendar day, or nil. Calendar silently rolls
    /// 29 Feb 2025 into 1 Mar, so the components are checked on the way back.
    static func ist(year: Int, month: Int, day: Int) -> Date? {
        let cal = YearMonth.istCalendar
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let back = cal.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day ? date : nil
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
