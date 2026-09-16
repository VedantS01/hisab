import XCTest
@testable import HisabCore

final class FormatFingerprintTests: XCTestCase {
    private var table: NormalizedTable {
        NormalizedTable(rows: [
            ["CANARA BANK", ""],
            ["Date", "Narration", "Amount", "Balance"],
            ["01/04/2026", "SALARY ACME CORP 987654", "100.00", "900.00"],
            ["02/04/2026", "POS COFFEE 4413", "150.00", "850.00"],
        ], container: "csv")
    }

    func testNoBodyCellValueEverAppearsInFingerprint() throws {
        let fp = FormatFingerprint.make(table: table)
        let encoded = try String(data: JSONEncoder().encode(fp), encoding: .utf8)!
        let everything = encoded + fp.emailBody(appVersion: "1.1.0")
        for secret in ["SALARY", "ACME", "987654", "COFFEE", "4413", "01/04/2026", "100.00"] {
            XCTAssertFalse(everything.contains(secret), "leaked body value: \(secret)")
        }
    }

    func testHeaderAndShapesAreCaptured() {
        let fp = FormatFingerprint.make(table: table)
        XCTAssertEqual(fp.container, "csv")
        XCTAssertEqual(fp.headerRow, ["Date", "Narration", "Amount", "Balance"])
        XCTAssertEqual(fp.columnCount, 4)
        XCTAssertEqual(fp.rowCount, 2)
        XCTAssertEqual(fp.cellShapes[0], "NN/NN/NNNN")
        XCTAssertEqual(fp.cellShapes[2], "NNN.NN")
        XCTAssertEqual(fp.bankNameGuess, "Canara")
    }

    func testHeaderlessTableStillFingerprints() {
        let headerless = NormalizedTable(rows: [
            ["01/04/2026", "POS X", "100.00", "900.00"],
        ], container: "txt")
        let fp = FormatFingerprint.make(table: headerless)
        XCTAssertEqual(fp.headerRow, [])
        XCTAssertEqual(fp.rowCount, 1)
        XCTAssertFalse(fp.emailBody(appVersion: "1.1.0").contains("POS X"))
    }

    func testMailtoURLTargetsSupportAddressWithEncodedBody() throws {
        let fp = FormatFingerprint.make(table: table)
        let url = try XCTUnwrap(fp.mailtoURL(appVersion: "1.1.0"))
        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "vedantsaboo2001@gmail.com")
        let items = components.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "subject" }?.value, "Hisab format request")
        XCTAssertEqual(items.first { $0.name == "body" }?.value, fp.emailBody(appVersion: "1.1.0"))
    }

    func testEmailBodyNamesAppVersionAndContainer() {
        let body = FormatFingerprint.make(table: table).emailBody(appVersion: "1.1.0")
        XCTAssertTrue(body.contains("Hisab format request (v1.1.0)"))
        XCTAssertTrue(body.contains("csv"))
        XCTAssertTrue(body.contains("Date | Narration | Amount | Balance"))
    }
}
