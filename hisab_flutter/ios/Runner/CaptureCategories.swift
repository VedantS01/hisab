import Flutter
import UserNotifications

/// One notification category per captured memo, so its buttons can name the
/// categories ranked for it ("Food", "Shopping", "Transport") plus "Later".
/// flutter_local_notifications only registers categories once, at
/// initialize, and replaces the whole set when it does; the Swift app (1.x)
/// registered them per notification, and this keeps that behaviour.
enum CaptureCategories {
    /// Enough for a day's worth of unanswered banners; older categories
    /// belong to banners long since dismissed.
    private static let keep = 30

    static func register(with messenger: FlutterBinaryMessenger) {
        FlutterMethodChannel(name: "hisab/notify_categories", binaryMessenger: messenger)
            .setMethodCallHandler { call, result in
                guard call.method == "set",
                      let args = call.arguments as? [String: Any],
                      let id = args["id"] as? String,
                      let actions = args["actions"] as? [[String: String]] else {
                    return result(FlutterMethodNotImplemented)
                }
                set(id: id, actions: actions) { result(nil) }
            }
    }

    /// Adds (or replaces) category [id]. Every action foregrounds the app, so
    /// the answer is written by the app's own engine and database connection.
    private static func set(id: String, actions: [[String: String]], done: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            let category = UNNotificationCategory(
                identifier: id,
                actions: actions.compactMap { action in
                    guard let actionId = action["id"], let title = action["title"] else { return nil }
                    return UNNotificationAction(identifier: actionId, title: title, options: [.foreground])
                },
                intentIdentifiers: [],
                options: [])
            let others = existing.filter { $0.identifier != id }
                .sorted { $0.identifier < $1.identifier }
                .suffix(keep - 1)
            center.setNotificationCategories(Set(others).union([category]))
            DispatchQueue.main.async(execute: done)
        }
    }
}
