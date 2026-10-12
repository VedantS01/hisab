import SwiftUI
import HisabCore

/// The setup screen's answer to "is it working?", worked out on its own.
///
/// Hisab cannot see the user's Shortcuts automations, so it checks everything
/// it can observe instead: the switch, notifications, the reader against a
/// known alert, whether the automation has handed anything over, and what
/// became of the last thing it did. Every row that is not fine says what to
/// do next.
struct CaptureCheckItem: Identifiable, Equatable {
    enum Status { case ok, info, warn, fail }
    let id: String
    let status: Status
    let title: String
    let detail: String
}

/// The reader run against the setup screen's sample alert.
enum ReaderCheck: Equatable {
    case working, misread, unavailable, crashed(Date)
}

enum CaptureSystemCheck {
    /// `reader` is nil until the sample has been run.
    static func items(enabled: Bool, notifications: UNAuthorizationStatusBox, reader: ReaderCheck?,
                      lastAttemptAt: Date?, lastOutcome: (outcome: CapturePrefs.Outcome, at: Date)?,
                      now: Date) -> [CaptureCheckItem] {
        var items = [
            enabled
                ? CaptureCheckItem(id: "enabled", status: .ok, title: "Capture is on",
                                   detail: "The Shortcuts action stores what it reads.")
                : CaptureCheckItem(id: "enabled", status: .fail, title: "Capture is off",
                                   detail: "Turn on Capture bank alerts below. Until then the automation runs but stores nothing."),
        ]
        if let reader { items.append(readerItem(reader)) }
        items.append(automationItem(lastAttemptAt: lastAttemptAt, now: now))
        if let lastOutcome { items.append(outcomeItem(lastOutcome.outcome, at: lastOutcome.at)) }
        items.append(notificationsItem(notifications))
        return items
    }

    /// Amount, direction and reference must all come back from the sample.
    @MainActor
    static func testReader(sample: String, amountPaise: Int64, ref: String) -> ReaderCheck {
        if let crashedAt = ExtractorGuard.crashedAt { return .crashed(crashedAt) }
        guard let alert = CaptureService.extract(sample) else { return .unavailable }
        return alert.amountPaise == amountPaise && alert.direction == .debit && alert.ref == ref
            ? .working : .misread
    }

    private static func readerItem(_ reader: ReaderCheck) -> CaptureCheckItem {
        switch reader {
        case .working:
            return CaptureCheckItem(id: "reader", status: .ok, title: "On-device reader works",
                                    detail: "It read the sample alert correctly.")
        case .misread:
            return CaptureCheckItem(id: "reader", status: .warn, title: "On-device reader misread the sample",
                                    detail: "Alerts still go through, but check what it logs, and report it below.")
        case .unavailable:
            return CaptureCheckItem(id: "reader", status: .warn, title: "On-device reader unavailable",
                                    detail: "Hisab is using the basic parser, which keeps alerts as memos only.")
        case .crashed(let at):
            return CaptureCheckItem(id: "reader", status: .fail, title: "On-device reader crashed",
                                    detail: "It crashed on \(ISTStamp.dayTime(at)) and is off for this version. Hisab is using the basic parser meanwhile, which keeps alerts as memos only. Report it below, or try the reader again.")
        }
    }

    private static func automationItem(lastAttemptAt: Date?, now: Date) -> CaptureCheckItem {
        guard let lastAttemptAt else {
            return CaptureCheckItem(id: "automation", status: .fail, title: "No alert has reached Hisab yet",
                                    detail: "Build the automations in steps 1 and 2. This check updates by itself when your next bank SMS or email arrives.")
        }
        let days = ISTDay.daysBetween(lastAttemptAt, now)
        if days > CaptureHealth.staleDays {
            return CaptureCheckItem(id: "automation", status: .warn, title: "No alert for \(days) days",
                                    detail: "The last one arrived \(ISTStamp.dayTime(lastAttemptAt)). Check the automations are still on in Shortcuts › Automation.")
        }
        return CaptureCheckItem(id: "automation", status: .ok, title: "The automation is reaching Hisab",
                                detail: "The last alert arrived \(ISTStamp.dayTime(lastAttemptAt)).")
    }

    private static func outcomeItem(_ outcome: CapturePrefs.Outcome, at: Date) -> CaptureCheckItem {
        let when = ISTStamp.dayTime(at)
        switch outcome {
        case .logged:
            return CaptureCheckItem(id: "outcome", status: .ok, title: "The last alert was logged", detail: when)
        case .duplicate:
            return CaptureCheckItem(id: "outcome", status: .ok, title: "The last alert was already logged",
                                    detail: "\(when). The same payment had arrived before.")
        case .notAPayment:
            return CaptureCheckItem(id: "outcome", status: .info, title: "The last message wasn't a payment",
                                    detail: "\(when). Nothing was stored. Codes and offers that mention Rs also run the automation, which is expected. If it was a payment, report it below.")
        case .noText:
            return CaptureCheckItem(id: "outcome", status: .fail, title: "The automation passed no text",
                                    detail: "\(when). In Shortcuts, set Hisab's Alert Text to Shortcut Input.")
        case .saveFailed:
            return CaptureCheckItem(id: "outcome", status: .fail, title: "The last alert couldn't be saved",
                                    detail: "\(when). Report it below if it happens again.")
        case .captureOff:
            return CaptureCheckItem(id: "outcome", status: .warn, title: "The last alert arrived while capture was off",
                                    detail: "\(when). It was not stored.")
        }
    }

    private static func notificationsItem(_ status: UNAuthorizationStatusBox) -> CaptureCheckItem {
        switch status {
        case .allowed:
            return CaptureCheckItem(id: "notifications", status: .ok, title: "Notifications are on",
                                    detail: "Hisab can ask you what an unknown payment was.")
        case .denied:
            return CaptureCheckItem(id: "notifications", status: .warn, title: "Notifications are off",
                                    detail: "Hisab can't ask what an unknown payment was. Turn them on in iOS Settings › Notifications › Hisab.")
        case .unknown:
            return CaptureCheckItem(id: "notifications", status: .info, title: "Notifications not set up yet",
                                    detail: "Turning capture on asks for them.")
        }
    }
}

struct CaptureCheckRow: View {
    let item: CaptureCheckItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .accessibilityIdentifier("check-\(item.id)")
    }

    private var symbol: String {
        switch item.status {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch item.status {
        case .ok: HisabTheme.hara
        case .info: .secondary
        case .warn: HisabTheme.sona
        case .fail: HisabTheme.khataRed
        }
    }
}
