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
