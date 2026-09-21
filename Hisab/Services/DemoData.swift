import Foundation
import SwiftData
import HisabCore

/// Imports the three bundled synthetic statements (a GPay-side and a bank-side view
/// of the same months, plus a second bank) so the app is explorable before any real
/// statement is uploaded.
@MainActor
enum DemoData {
    /// "Load demo data" produces loaded demo data *now*: any demo already
    /// present is dropped and re-imported at today's anchor. A no-op instead
    /// would leave a returning user with last month's demo, which ages out of
    /// the very windows the month shift exists to keep it inside — two cards a
    /// month on, one after that. Idempotent either way (tap it twice, get the
    /// same thing), and it only ever touches the three demo slots, never a file
    /// the user imported themselves.
    @discardableResult
    static func load(into context: ModelContext, now: Date = Date()) -> Bool {
        guard let gpayURL = Bundle.main.url(forResource: "demo-gpay", withExtension: "csv"),
              let hdfcURL = Bundle.main.url(forResource: "demo-hdfc", withExtension: "csv"),
              let idfcURL = Bundle.main.url(forResource: "demo-idfc", withExtension: "csv") else {
            return false
        }
        let service = ImportService(context: context)
        do {
            // Whatever months the outgoing demo occupied have to be reconciled
            // again once its rows are gone: a user row that was matched against
            // a demo row is now unmatched, and would otherwise stay hidden.
            for month in eraseExisting(from: context) {
                Queries.recomputeMatches(context, month: month)
            }
            try context.save()
            for (url, source) in [(gpayURL, Source.gpay), (hdfcURL, .hdfc), (idfcURL, .idfc)] {
                let bundled = try Data(contentsOf: url)
                let shifted = try shiftedCopy(of: url, data: bundled, now: now)
                defer { try? FileManager.default.removeItem(at: shifted) }
                _ = try service.importFile(at: shifted, password: nil, overrideSource: source,
                                           fileHash: fileHash(for: source))
            }
            return true
        } catch {
            return false
        }
    }

    /// Identity of a demo statement for the import pipeline's file-level
    /// duplicate check. There is exactly one demo statement per source, ever,
    /// so the identity is that slot — not the bytes. The bytes are the wrong
    /// answer twice over: `shiftToPresent` rewrites them every month, so a
    /// returning user's second tap would look like a new file; and if a later
    /// release ships different demo statements, hashing the bundle would land a
    /// second, overlapping demo set on top of the first rather than doing
    /// nothing. Same string Flutter uses, so the two platforms agree by
    /// construction rather than by coincidence.
    static func fileHash(for source: Source) -> String { "demo-\(source.rawValue)" }

    static let slotKeys = Set(
        [Source.gpay, .hdfc, .idfc].map { fileHash(for: $0) })

    /// Removes the demo documents and everything hanging off them, returning
    /// the months they covered.
    ///
    /// `StoredDocument.transactions` cascades, so the rows go with the
    /// document — but `StoredMatch` holds bare UUIDs with no relationship to
    /// either, so nothing deletes those for us. A match left pointing at a
    /// deleted row is not inert: `Queries.visible` hides any transaction whose
    /// uuid appears as a match's bank side, so a stale match would go on hiding
    /// a *user's* row (reconciliation pairs rows by month, not by document, so
    /// a user payment may well have been matched against a demo bank row).
    /// They are deleted by uuid, which is exact and independent of months.
    @discardableResult
    static func eraseExisting(from context: ModelContext) -> [YearMonth] {
        let documents = ((try? context.fetch(FetchDescriptor<StoredDocument>())) ?? [])
            .filter { slotKeys.contains($0.fileSHA256) }
        guard !documents.isEmpty else { return [] }

        let rows = documents.flatMap { $0.transactions ?? [] }
        let uuids = Set(rows.map(\.uuid))
        for match in (try? context.fetch(FetchDescriptor<StoredMatch>())) ?? []
        where uuids.contains(match.appUUID) || uuids.contains(match.bankUUID) {
            context.delete(match)
        }

        var months: Set<YearMonth> = []
        for document in documents {
            months.formUnion(document.period.months)
            for row in document.transactions ?? [] { months.insert(row.month) }
            context.delete(document)
        }
        return months.sorted()
    }

    /// Slides a bundled statement's dates into the present and writes the result
    /// to a temp file under the same name, so the import pipeline — which works
    /// from a URL — sees it as an ordinary file.
    private static func shiftedCopy(of url: URL, data: Data, now: Date) throws -> URL {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: url.lastPathComponent)
        try shiftToPresent(text, now: now).write(to: destination, atomically: true,
                                                 encoding: .utf8)
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
