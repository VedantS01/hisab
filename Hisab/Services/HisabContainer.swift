import Foundation
import SwiftData

/// The process's single ModelContainer.
///
/// App Intents run inside the app's process, so an intent that built its own
/// container would put two containers over one store file. SwiftData resolves
/// a unique-attribute collision by upserting — last write wins across every
/// property — which means a racing insert of an already-categorized
/// `StoredPendingMemo` could silently revert `assignedCategory`. One container
/// makes that unrepresentable, and keeps a foreground UI in step with a memo
/// captured while it is open.
enum HisabContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: HisabSchema.schema)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
