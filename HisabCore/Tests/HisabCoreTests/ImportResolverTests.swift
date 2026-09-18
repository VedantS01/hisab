import XCTest
@testable import HisabCore

final class ImportResolverTests: XCTestCase {
    private let sbiSpec = FormatSpec(
        id: "test-sbi",
        sourceID: "bank:sbi",
        bankName: "State Bank of India",
        headerPatterns: ["date": "^txn date$", "narration": "^description$",
                         "reference": "ref no", "debit": "^debit$",
                         "credit": "^credit$", "balance": "^balance$"],
        dateFormats: ["dd/MM/yyyy"],
        signConvention: "debitCredit")

    private func resolver(specs: [FormatSpec] = []) -> ImportResolver {
        ImportResolver(registry: .live, specs: specs)
    }

    private let sbiCSV = """
    Txn Date,Description,Ref No./Cheque No.,Debit,Credit,Balance
    01/04/2026,POS COFFEE,R1,100.00,,900.00
    02/04/2026,SALARY,R2,,50.00,950.00
    """

    // Pinned exactly so the Dart twin can assert the identical list.
    func testSupportedFormatNamesListsParsersThenSpecBanksDeduped() {
        XCTAssertEqual(ImportResolver.live().supportedFormatNames,
                       ["Google Pay", "Paytm", "BHIM UPI", "HDFC Bank",
                        "IDFC First Bank", "Axis Bank", "Bank of Baroda",
                        "ICICI Bank", "Kotak Mahindra Bank",
                        "Punjab National Bank", "State Bank of India"])
    }

    func testCodeParserWinsFirst() throws {
        let url = Bundle.module.url(forResource: "idfc-fixture", withExtension: "xlsx",
                                    subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        guard case .parsed(let doc) = resolver().resolve(data: data, filename: "s.xlsx",
                                                         password: nil) else {
            return XCTFail("expected code-parser parse")
        }
        XCTAssertEqual(doc.source, .idfc)
    }

    func testSpecParsesWhenNoCodeParserMatches() {
        guard case .parsed(let doc) = resolver(specs: [sbiSpec])
            .resolve(data: Data(sbiCSV.utf8), filename: "sbi.csv", password: nil) else {
            return XCTFail("expected spec parse")
        }
        XCTAssertEqual(doc.source, Source(rawValue: "bank:sbi"))
        XCTAssertEqual(doc.transactions.count, 2)
    }

    func testInferenceCatchesUnknownBankAndSlugsTheGuess() {
        let csv = """
        CANARA BANK
        Date,Narration,Debit,Credit,Balance
        01/04/2026,POS COFFEE SHOP,100.00,,900.00
        02/04/2026,SALARY CREDIT ACME,,50.00,950.00
        03/04/2026,UPI GROCER PAY,200.00,,750.00
        """
        guard case .parsed(let doc) = resolver()
            .resolve(data: Data(csv.utf8), filename: "unknown.csv", password: nil) else {
            return XCTFail("expected inference parse")
        }
        XCTAssertEqual(doc.source, Source(rawValue: "bank:canara"))
        XCTAssertEqual(doc.transactions.count, 3)
    }

    func testGarbageIsUnsupportedWithFingerprint() {
        guard case .unsupported(let fp) = resolver()
            .resolve(data: Data([0x00, 0x01]), filename: "x.xlsx", password: nil) else {
            return XCTFail("expected unsupported")
        }
        XCTAssertEqual(fp.container, "xlsx")
        XCTAssertEqual(fp.rowCount, 0)
    }

    func testChainBreakOnMatchingSpecIsUnverified() {
        let tampered = sbiCSV.replacingOccurrences(of: "950.00", with: "999.00")
        guard case .unverified(let fp, let detail) = resolver(specs: [sbiSpec])
            .resolve(data: Data(tampered.utf8), filename: "sbi.csv", password: nil) else {
            return XCTFail("expected unverified")
        }
        XCTAssertEqual(fp.container, "csv")
        XCTAssertFalse(detail.isEmpty)
    }
}
