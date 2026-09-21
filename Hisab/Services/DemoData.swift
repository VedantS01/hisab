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
            //
            // The save in the middle is load-bearing. `eraseExisting` only
            // *marks* the demo documents deleted; the transaction rows go at
            // save time, through the cascade. `recomputeMatches` fetches all
            // transactions and re-pairs them — so if that fetch ever returned
            // the pending-deleted demo rows, it would match a live user bank
            // row against a dying demo app row, and `Queries.visible` would
            // hide the user's row for good. Committing first removes the
            // dependency on SwiftData's pending-change semantics, and matches
            // what DocumentListSheet already does on the manual delete path.
            let affected = eraseExisting(from: context)
            try context.save()
            for month in affected {
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

    /// Demo documents created **before** this release, when the demo was
    /// imported straight from the bundle and identified by the SHA-256 of that
    /// file's bytes rather than by the `demo-<source>` slot key.
    ///
    /// Without this, an upgrading user's existing demo is invisible to
    /// `eraseExisting`: nothing erases it, and the import guard doesn't fire
    /// either (no document carries the hash `demo-gpay` yet), so "Load demo
    /// data" lands a *second*, overlapping demo set on top of the first. That
    /// is a regression this release would otherwise introduce for every user
    /// who has ever tapped the button.
    ///
    /// The match is three-way — filename, source, **and** an exact content
    /// hash — and the hash is the part that makes it safe. A statement the
    /// user imported themselves can only be caught by it if their file is
    /// byte-identical to a demo CSV Hisab itself bundles, in which case it *is*
    /// the demo and replacing it is the right answer. Matching on the filename
    /// alone would not be safe: a user is free to call their own export
    /// `demo-hdfc.csv`, and deleting a real statement is far worse than the
    /// bug being fixed here.
    ///
    /// Every value below is the SHA-256 of a `Hisab/Resources/demo-*.csv` blob
    /// in this repository's history, so the set is complete by construction —
    /// a shipped bundle has no other way to exist. It also fails closed: a
    /// build whose demo CSV isn't listed keeps the old behaviour rather than
    /// having something guessed at on its behalf. Appending a new demo CSV
    /// means appending its hash here *before* that build ships.
    static let legacyDemoFileHashes: [String: Set<String>] = [
        Source.gpay.rawValue: [
            // 4a56866 / 4303599 — the 1.0 and 1.1 bundle
            "685c6763aa3797963835f05460ad20fa0ae0c7c80584e5612cf38b0e2e9b26e0",
            // eb17975 / a86b2a1 — the seven-month set this release ships
            "6a990aa55e096ac103af3b2a218ac8fe247b04479c26f5ba72bfe8e38bbd89ca",
        ],
        Source.hdfc.rawValue: [
            "d3a73cdd913a54bb8940b2c44b8fd9467c23f92458b824f8b33174d5d5d00cdd",  // 4a56866
            "ea8df42571b0fa4260ffe2c950b84661fa64f0200b69f70a90ec1b0ab9d81535",  // 4303599
            "72b2d33b18bf57b0dea00be8664fa58989b464003407ad9d21d40d2ff367897f",  // eb17975
            "eae0547ae6836e63ef93a9e3ee25c774c8ba679af4fdfee156716a47744d0976",  // a86b2a1
        ],
        Source.idfc.rawValue: [
            "a4648979cfea04f768425b663d23c23be6e22e4d3f2cc27c1131be300df32c34",  // 4303599
            "d6097fd584227a48c2079623a4bfb3c2a245811e89c09f8b01f601801abf6154",  // eb17975 / a86b2a1
        ],
    ]

    /// True only for a document this app's own demo loader created under the
    /// pre-1.2 byte-hash identity. See `legacyDemoFileHashes`.
    static func isLegacyDemo(_ document: StoredDocument) -> Bool {
        let source = document.source.rawValue
        guard document.filename == "demo-\(source).csv",
              let known = legacyDemoFileHashes[source] else { return false }
        return known.contains(document.fileSHA256)
    }

    #if DEBUG
    /// Replays the pre-1.2 demo import: the bundled CSVs exactly as they sit
    /// in the app, unshifted, identified by the SHA-256 of their bytes and
    /// erasing nothing first. That is what `DemoData.load` did before this
    /// release, so it puts the store in the state an upgrading user arrives
    /// in — which is the only way to test that `eraseExisting` now cleans it
    /// up. Debug-only, reached solely through `--seed-legacy-demo`.
    ///
    /// Any demo already present is cleared first, so the result is exactly one
    /// demo under the old identity however the store got here. Without that the
    /// harness would inherit whatever the previous test left behind and seed
    /// *two* demos, which is the very thing under test.
    @discardableResult
    static func loadLegacyForTesting(into context: ModelContext) -> Bool {
        guard let gpayURL = Bundle.main.url(forResource: "demo-gpay", withExtension: "csv"),
              let hdfcURL = Bundle.main.url(forResource: "demo-hdfc", withExtension: "csv"),
              let idfcURL = Bundle.main.url(forResource: "demo-idfc", withExtension: "csv") else {
            return false
        }
        let service = ImportService(context: context)
        do {
            let affected = eraseExisting(from: context)
            try context.save()
            for month in affected {
                Queries.recomputeMatches(context, month: month)
            }
            try context.save()
            for (url, source) in [(gpayURL, Source.gpay), (hdfcURL, .hdfc), (idfcURL, .idfc)] {
                _ = try service.importFile(at: url, password: nil, overrideSource: source)
            }
            return true
        } catch {
            return false
        }
    }
    #endif

    /// Removes the demo documents and everything hanging off them, returning
    /// the months they covered.
    ///
    /// "The demo documents" means both identities: this release's
    /// `demo-<source>` slot key and the pre-1.2 byte hash (`isLegacyDemo`).
    /// Everything below is identity-agnostic once a document is in the list —
    /// matches go by uuid, transactions by cascade — so an upgrading user's
    /// old demo is cleaned by exactly the same path as a current one.
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
            .filter { slotKeys.contains($0.fileSHA256) || isLegacyDemo($0) }
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
