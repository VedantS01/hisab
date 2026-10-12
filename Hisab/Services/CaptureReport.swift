import Foundation
import UIKit
import HisabCore

/// A user-initiated email about capture, sent from the Mail app — Hisab itself
/// still opens no connection. It carries what the system check saw and, only
/// when the user is reporting a misread, the alert text they tested; the
/// user sees all of it in Mail before anything leaves the phone.
enum CaptureReport {
    static func mailtoURL(subject: String, details: [String], alertText: String? = nil) -> URL? {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        var lines = ["Hisab \(version) on \(deviceModel), iOS \(UIDevice.current.systemVersion)", ""] + details
        if let alertText {
            lines += ["", "Alert text:", alertText]
        } else {
            lines += ["", "If an alert was misread, paste its text here (you can blank out names and numbers):", ""]
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = FormatFingerprint.supportAddress
        components.queryItems = [URLQueryItem(name: "subject", value: subject),
                                 URLQueryItem(name: "body", value: lines.joined(separator: "\n"))]
        return components.url
    }

    /// "iPhone17,4", not the marketing name: it is what a crash log names.
    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
