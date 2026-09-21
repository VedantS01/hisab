import Foundation
import SwiftData
import HisabCore

/// Imports the three bundled synthetic statements (a GPay-side and a bank-side view
/// of the same months, plus a second bank) so the app is explorable before any real
/// statement is uploaded.
@MainActor
enum DemoData {
    @discardableResult
    static func load(into context: ModelContext) -> Bool {
        guard let gpayURL = Bundle.main.url(forResource: "demo-gpay", withExtension: "csv"),
              let hdfcURL = Bundle.main.url(forResource: "demo-hdfc", withExtension: "csv"),
              let idfcURL = Bundle.main.url(forResource: "demo-idfc", withExtension: "csv") else {
            return false
        }
        let service = ImportService(context: context)
        do {
            for (url, source) in [(gpayURL, Source.gpay), (hdfcURL, .hdfc), (idfcURL, .idfc)] {
                let shifted = try shiftedCopy(of: url)
                defer { try? FileManager.default.removeItem(at: shifted) }
                _ = try service.importFile(at: shifted, password: nil, overrideSource: source)
            }
            return true
        } catch {
            return false
        }
    }

    /// Reads a bundled statement, slides its dates into the present and writes
    /// the result to a temp file under the same name, so the import pipeline —
    /// which works from a URL and hashes the bytes — sees it as an ordinary file.
    private static func shiftedCopy(of url: URL) throws -> URL {
        let text = try String(contentsOf: url, encoding: .utf8)
        let destination = FileManager.default.temporaryDirectory
            .appending(path: url.lastPathComponent)
        try shiftToPresent(text).write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    /// The demo statements carry fixed dates. Slide every month forward so the
    /// newest demo month is the current month — which leaves the newest *complete*
    /// demo month on the last complete month relative to today. Otherwise the demo
    /// set silently stops producing insights as time passes: recurrence wants a
    /// series that is still active, and anomalies only look back 35 days.
    ///
    /// Every file is anchored on its own newest date, so the three statements must
    /// keep sharing a newest month (each ends with a `period` line in it) — that is
    /// what makes them all slide by the same number of months.
    static func shiftToPresent(_ csv: String, now: Date = Date()) -> String {
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

        let target = YearMonth(date: now)
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

    /// Same day-of-month in the shifted month, clamped to its length. The demo
    /// statements only ever use days 1–28, so the clamp never actually fires —
    /// which is deliberate: a date on the 29th–31st would land on a different
    /// day-of-month in a shorter month and pull recurrence cadences out of range.
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
}
