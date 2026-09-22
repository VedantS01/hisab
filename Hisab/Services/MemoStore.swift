import Foundation
import SwiftData
import HisabCore

/// SwiftData shim for pending memos. Deliberately logic-free.
@MainActor
enum MemoStore {
    /// False when this alert was already captured — the dedup guard that stops
    /// Android's notification *updates* producing a second memo.
    @discardableResult
    static func insert(_ memo: PendingMemo, into ctx: ModelContext) -> Bool {
        let hash = memo.captureHash
        let existing = FetchDescriptor<StoredPendingMemo>(
            predicate: #Predicate { $0.captureHash == hash })
        // A thrown fetch must not be read as "not found": with unique-attribute
        // upsert behind this guard, inserting on a failed lookup can overwrite a
        // memo the user already categorized. Declining one capture is the cheaper
        // error.
        guard let found = try? ctx.fetch(existing) else { return false }
        if !found.isEmpty { return false }
        ctx.insert(StoredPendingMemo(memo: memo))
        try? ctx.save()
        return true
    }

    /// Unmerged, unlabelled memos, newest first.
    static func pending(_ ctx: ModelContext) -> [StoredPendingMemo] {
        let descriptor = FetchDescriptor<StoredPendingMemo>(
            predicate: #Predicate { $0.mergedTxnUUID == nil && $0.assignedCategory == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        return (try? ctx.fetch(descriptor)) ?? []
    }

    static func all(_ ctx: ModelContext) -> [StoredPendingMemo] {
        (try? ctx.fetch(FetchDescriptor<StoredPendingMemo>())) ?? []
    }

    static func find(hash: String, in ctx: ModelContext) -> StoredPendingMemo? {
        let descriptor = FetchDescriptor<StoredPendingMemo>(
            predicate: #Predicate { $0.captureHash == hash })
        return (try? ctx.fetch(descriptor))?.first
    }

    static func assign(category: String, to memo: StoredPendingMemo, in ctx: ModelContext) {
        memo.assignedCategory = category
        try? ctx.save()
    }

    static func expire(now: Date, in ctx: ModelContext) {
        for memo in all(ctx)
        where memo.mergedTxnUUID == nil
            && PendingMemo.isExpired(capturedAt: memo.capturedAt, now: now) {
            ctx.delete(memo)
        }
        try? ctx.save()
    }
}
