import Foundation
import SwiftData
import HisabCore

/// Imports the two bundled synthetic statements (a GPay-side and a bank-side view of the
/// same three months) so the app is explorable before any real statement is uploaded.
@MainActor
enum DemoData {
    @discardableResult
    static func load(into context: ModelContext) -> Bool {
        guard let gpayURL = Bundle.main.url(forResource: "demo-gpay", withExtension: "csv"),
              let hdfcURL = Bundle.main.url(forResource: "demo-hdfc", withExtension: "csv") else {
            return false
        }
        let service = ImportService(context: context)
        do {
            _ = try service.importFile(at: gpayURL, password: nil, overrideSource: .gpay)
            _ = try service.importFile(at: hdfcURL, password: nil, overrideSource: .hdfc)
            return true
        } catch {
            return false
        }
    }
}
