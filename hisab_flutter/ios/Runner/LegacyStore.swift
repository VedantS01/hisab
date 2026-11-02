import Flutter
import Foundation
import Security
import SwiftData

/// Reads what the Swift app (1.x) left on the phone, once, for the Dart side
/// to copy into its drift database (lib/services/legacy_migration.dart).
///
/// The @Model classes below are the Swift app's stored properties verbatim —
/// names, types, defaults, uniqueness and the cascade relationship — because
/// SwiftData opens an existing store only against the schema that wrote it.
/// Initializers and computed properties are dropped: they are not schema.
enum LegacyStore {
    static func register(with messenger: FlutterBinaryMessenger) {
        FlutterMethodChannel(name: "hisab/legacy", binaryMessenger: messenger)
            .setMethodCallHandler { call, result in
                switch call.method {
                case "export": result(export())
                case "finish": finish(); result(nil)
                default: result(FlutterMethodNotImplemented)
                }
            }
    }

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    private static var storeURL: URL { support.appendingPathComponent("default.store") }
    private static var backupDir: URL { support.appendingPathComponent("legacy-swiftdata") }
    private static let keychainService = "com.vedants.hisab.statement-password"

    /// UserDefaults keys the Swift app wrote, copied under the `flutter.`
    /// prefix shared_preferences reads. Dates become millisecond epochs.
    private static let boolKeys = ["capture.enabled"]
    private static let dateKeys = ["capture.lastCaptureAt", "capture.lastAttemptAt", "capture.lastOutcomeAt"]
    private static let intKeys = ["capture.notifyCount"]
    private static let stringKeys = ["capture.notifyDay", "capture.lastOutcome", "suggestion.lastShown"]
    private static let listKeys = ["capture.pendingRuleOffer", "suggestion.muted", "insights.dismissed",
                                   "insights.mutedMerchants", "insights.mutedCategories"]

    /// JSON of everything in the old store, or nil when there is none (a
    /// fresh install, or already migrated). Preferences are copied as a side
    /// effect, before Dart reads any, and never over a value Dart already has.
    static func export() -> String? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return nil }
        copyPreferences()
        do {
            let schema = Schema([LegacyDocument.self, LegacyTransaction.self, LegacyRule.self,
                                 LegacyMatch.self, LegacyPinnedMonth.self, LegacyMemo.self])
            let container = try ModelContainer(
                for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL, allowsSave: false))
            let ctx = ModelContext(container)
            let payload: [String: Any] = [
                "documents": try ctx.fetch(FetchDescriptor<LegacyDocument>()).map { d in [
                    "id": d.uuid.uuidString, "sourceRaw": d.sourceRaw, "filename": d.filename,
                    "fileSha256": d.fileSHA256, "periodStartMs": ms(d.periodStart),
                    "periodEndMs": ms(d.periodEnd), "importedAtMs": ms(d.importedAt),
                ] },
                "transactions": try ctx.fetch(FetchDescriptor<LegacyTransaction>()).map { t in [
                    "uuid": t.uuid.uuidString, "contentHash": t.contentHash, "sourceRaw": t.sourceRaw,
                    "dateMs": ms(t.date), "amountPaise": t.amountPaise, "direction": t.directionRaw,
                    "counterparty": t.counterparty, "reference": t.reference as Any,
                    "narration": t.narration, "categoryOverride": t.categoryOverride as Any,
                    "documentId": t.document?.uuid.uuidString as Any,
                ] },
                "rules": try ctx.fetch(FetchDescriptor<LegacyRule>()).map { r in [
                    "id": r.uuid.uuidString, "pattern": r.pattern, "category": r.category,
                    "sortOrder": r.sortOrder,
                ] },
                "matches": try ctx.fetch(FetchDescriptor<LegacyMatch>()).map { m in [
                    "appUuid": m.appUUID.uuidString, "bankUuid": m.bankUUID.uuidString,
                    "tier": m.tierRaw, "monthKey": m.monthKey,
                ] },
                "pinnedMonths": try ctx.fetch(FetchDescriptor<LegacyPinnedMonth>()).map {
                    String(format: "%04d-%02d", $0.year, $0.month)
                },
                "memos": try ctx.fetch(FetchDescriptor<LegacyMemo>()).map { m in [
                    "captureHash": m.captureHash, "amountPaise": m.amountPaise, "direction": m.directionRaw,
                    "payee": m.payee, "payeeNormalized": m.payeeNormalized, "vpa": m.vpa as Any,
                    "accountTail": m.accountTail as Any, "dateMs": ms(m.date),
                    "capturedAtMs": ms(m.capturedAt), "note": m.note as Any,
                    "assignedCategory": m.assignedCategory as Any,
                    "mergedTxnUuid": m.mergedTxnUUID?.uuidString as Any,
                    "notifiedAtMs": m.notifiedAt.map(ms) as Any,
                ] },
                "passwords": passwords(),
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return String(data: data, encoding: .utf8)
        } catch {
            // The store stays where it is; the next launch tries again.
            NSLog("hisab-legacy: could not read the Swift store (\(type(of: error)))")
            return nil
        }
    }

    /// After Dart has the data: the store moves to a backup folder (kept,
    /// not deleted, so a migration bug can never cost the user their
    /// ledger), and the old keys and Keychain items go.
    static func finish() {
        let fm = FileManager.default
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let from = support.appendingPathComponent("default.store\(suffix)")
            let to = backupDir.appendingPathComponent("default.store\(suffix)")
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.removeItem(at: to)
            try? fm.moveItem(at: from, to: to)
        }
        try? fm.removeItem(at: support.appendingPathComponent("extractor-in-flight"))
        let defaults = UserDefaults.standard
        for key in boolKeys + dateKeys + intKeys + stringKeys + listKeys
            + ["extractor.disabledBuild", "extractor.crashedAt"] {
            defaults.removeObject(forKey: key)
        }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: keychainService] as CFDictionary)
    }

    private static func copyPreferences() {
        let d = UserDefaults.standard
        func copy(_ key: String, _ value: Any?) {
            guard let value, d.object(forKey: "flutter.\(key)") == nil else { return }
            d.set(value, forKey: "flutter.\(key)")
        }
        for key in boolKeys where d.object(forKey: key) != nil { copy(key, d.bool(forKey: key)) }
        for key in dateKeys { copy(key, (d.object(forKey: key) as? Date).map(ms)) }
        for key in intKeys where d.object(forKey: key) != nil { copy(key, d.integer(forKey: key)) }
        for key in stringKeys { copy(key, d.string(forKey: key)) }
        for key in listKeys { copy(key, d.stringArray(forKey: key)) }
    }

    /// Statement passwords by source raw value.
    private static func passwords() -> [String: String] {
        var items: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecReturnAttributes as String: true,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitAll]
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let list = items as? [[String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for item in list {
            if let account = item[kSecAttrAccount as String] as? String,
               let data = item[kSecValueData as String] as? Data,
               let password = String(data: data, encoding: .utf8) {
                out[account] = password
            }
        }
        return out
    }

    private static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
}

// MARK: - The Swift app's schema (Hisab/Models/StoredModels.swift), read-only

@Model
final class StoredDocument {
    var uuid: UUID = UUID()
    var sourceRaw: String = ""
    var filename: String = ""
    var fileSHA256: String = ""
    var periodStart: Date = Date.distantPast
    var periodEnd: Date = Date.distantPast
    var importedAt: Date = Date.distantPast
    @Relationship(deleteRule: .cascade, inverse: \StoredTransaction.document)
    var transactions: [StoredTransaction]? = []
    init() {}
}

@Model
final class StoredTransaction {
    var uuid: UUID = UUID()
    @Attribute(.unique) var contentHash: String = ""
    var date: Date = Date.distantPast
    var amountPaise: Int64 = 0
    var directionRaw: String = ""
    var counterparty: String = ""
    var reference: String?
    var narration: String = ""
    var sourceRaw: String = ""
    var categoryOverride: String?
    var document: StoredDocument?
    init() {}
}

@Model
final class StoredCategoryRule {
    var uuid: UUID = UUID()
    var pattern: String = ""
    var category: String = ""
    var sortOrder: Int = 0
    init() {}
}

@Model
final class StoredMatch {
    var appUUID: UUID = UUID()
    var bankUUID: UUID = UUID()
    var tierRaw: String = ""
    var monthKey: String = ""
    init() {}
}

@Model
final class PinnedMonth {
    var year: Int = 0
    var month: Int = 0
    init() {}
}

@Model
final class StoredPendingMemo {
    @Attribute(.unique) var captureHash: String = ""
    var amountPaise: Int64 = 0
    var directionRaw: String = ""
    var payee: String = ""
    var payeeNormalized: String = ""
    var vpa: String?
    var accountTail: String?
    var date: Date = Date.distantPast
    var capturedAt: Date = Date.distantPast
    var note: String?
    var assignedCategory: String?
    var mergedTxnUUID: UUID?
    var notifiedAt: Date?
    init() {}
}

private typealias LegacyDocument = StoredDocument
private typealias LegacyTransaction = StoredTransaction
private typealias LegacyRule = StoredCategoryRule
private typealias LegacyMatch = StoredMatch
private typealias LegacyPinnedMonth = PinnedMonth
private typealias LegacyMemo = StoredPendingMemo
