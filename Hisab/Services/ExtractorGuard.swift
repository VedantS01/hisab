import Foundation

/// Keeps a fault in the on-device reader from costing more than one alert.
///
/// A crash inside Core ML is a signal, not an error: nothing in-process can
/// catch it, and 1.4.0 showed it can hit every extraction on a new OS. So each
/// extraction drops a marker file first and deletes it after. A marker still
/// there at the next use means the process died mid-read: the reader is
/// switched off for this build, capture falls back to `AlertParser` (memos
/// only, as in 1.3.0), and the setup screen says so and offers a report.
///
/// A file rather than UserDefaults because defaults are flushed lazily — a
/// write just before a segfault can be lost, which is exactly the case this
/// exists for. Switched off per build: an update may carry the fix, so it gets
/// a fresh chance, and "Try the reader again" gives one by hand.
enum ExtractorGuard {
    private static let marker = URL.applicationSupportDirectory.appending(path: "extractor-in-flight")
    private static let disabledBuildKey = "extractor.disabledBuild"
    private static let crashedAtKey = "extractor.crashedAt"

    private static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// When the reader died mid-read, while it is switched off for this build.
    static var crashedAt: Date? {
        recoverFromCrash()
        guard UserDefaults.standard.string(forKey: disabledBuildKey) == build else { return nil }
        return UserDefaults.standard.object(forKey: crashedAtKey) as? Date
    }

    /// Turns the reader back on for this build.
    static func reenable() {
        UserDefaults.standard.removeObject(forKey: disabledBuildKey)
        UserDefaults.standard.removeObject(forKey: crashedAtKey)
    }

    /// Runs one extraction with the marker in place.
    static func guarded<T>(_ read: () throws -> T) rethrows -> T {
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: marker) }
        return try read()
    }

    #if DEBUG
    /// Leaves the marker a crash mid-read would have left, for the UI test.
    static func leaveMarkerForTesting() {
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }
    #endif

    /// Turns a marker the previous process left behind into "switched off".
    private static func recoverFromCrash() {
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let diedAt = (try? FileManager.default.attributesOfItem(atPath: marker.path))?[.creationDate] as? Date
        try? FileManager.default.removeItem(at: marker)
        UserDefaults.standard.set(build, forKey: disabledBuildKey)
        UserDefaults.standard.set(diedAt ?? Date(), forKey: crashedAtKey)
    }
}
