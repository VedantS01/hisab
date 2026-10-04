import SwiftUI
import UserNotifications
import HisabCore

/// How to wire a bank's SMS alerts into Hisab, told honestly.
///
/// Every claim on this screen is one the app can keep. `AppShortcutsProvider`
/// does put "Add Transaction Alert" into the Shortcuts app and Siri on install
/// — but it does NOT put Hisab in the share sheet, and no app can install a
/// Shortcuts automation on the user's behalf. So this screen walks the user
/// through building both themselves, step by step, naming the exact trigger and
/// options. Discovering after the fact that the share sheet was never there
/// would undermine every other claim the screen makes.
struct CaptureSetupView: View {
    @State private var enabled = CapturePrefs.isEnabled
    @State private var authorization: UNAuthorizationStatusBox = .unknown
    @State private var testResult: String?

    /// B3: an inline sample, not a bundled resource. The point is for the user
    /// to watch the real parser succeed before trusting it, and a constant
    /// serves that exactly as well as a file would. It carries a UPI ref so the
    /// test shows the path most alerts now take: straight into the ledger.
    private static let sample =
        "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. UPI Ref No 627775786529"

    var body: some View {
        List {
            Section {
                Text("Hisab reads the text of a bank or UPI alert you hand it: the amount, who it went to, the UPI ID, the last digits of the account and the bank reference.")
                    .font(.subheadline)
                // M-5: `MemoStore.expire` spares merged memos on purpose —
                // their details are what stop the same alert being captured
                // again — so a flat "deleted after 45 days" was a promise the
                // app does not keep.
                Text("It is kept on this phone, in Hisab's own store, and nothing is sent anywhere. An alert that carries a bank reference — a UPI or IMPS ref, a NEFT UTR — goes into your ledger right away and is confirmed when the statement arrives. One without stays a memo, a label rather than a ledger entry, until its statement arrives; a memo's real output is a categorization rule. A memo Hisab never matched to a statement is deleted after \(PendingMemo.expiryDays) days; one it did match is kept, so the same alert is not captured twice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What this does")
            }

            Section {
                Toggle("Capture bank alerts", isOn: $enabled)
                    .tint(HisabTheme.khataRed)
                    .onChange(of: enabled) { _, newValue in
                        Task {
                            await CaptureNotifier.setEnabled(newValue)
                            await refreshAuthorization()
                        }
                    }
                if enabled, authorization == .denied {
                    Label("Notifications are off for Hisab, so it cannot ask you what an unknown payment was. Turn them on in iOS Settings › Notifications › Hisab.",
                          systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(HisabTheme.khataRed)
                }
            } footer: {
                Text("With this off, the Shortcuts action still runs but declines the alert and stores nothing.")
            }

            Section {
                step(1, "Open Shortcuts › Automation › New Automation.")
                step(2, "Choose the Message trigger.")
                step(3, "Set “Sender contains” to your bank's sender ID (HDFCBK, IDFCFB, and so on). One automation per sender.")
                step(4, "Choose Run Immediately, and turn Notify When Run off.")
                step(5, "Add exactly one action: Hisab › Add Transaction Alert.")
                step(6, "Set its Alert Text to the Shortcut Input (the message body).")
                step(7, "Leave Note empty. Anything you put there is saved word for word, so it is for a short note of your own — never the message body.")
            } header: {
                Text("Step 1 — the automation")
            } footer: {
                Text("Apple's richer Notification trigger — which would catch a banking app's own push alerts, not just SMS — needs iOS 27. On this phone the Message trigger is what there is, and whether it passes the message body through is undocumented, which is why step 2 exists.")
            }

            Section {
                step(1, "In Shortcuts, tap + to create a new shortcut.")
                step(2, "Turn on “Show in Share Sheet”, and set it to receive Text.")
                step(3, "Add one action: Hisab › Add Transaction Alert, with Shortcut Input as the text.")
                step(4, "Name it something like “Log to Hisab”.")
            } header: {
                Text("Step 2 — the share-sheet fallback")
            } footer: {
                Text("Hisab does NOT appear in the share sheet on its own; iOS only offers a shortcut you have built. Once this exists you can select any alert's text, share it, and tap “Log to Hisab” — which works whatever the Message trigger does.")
            }

            Section {
                Button("Test it") { runTest() }
                    .tint(HisabTheme.khataRed)
                Text(Self.sample)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let testResult {
                    Text(testResult)
                        .font(.subheadline)
                        .accessibilityIdentifier("capture-test-result")
                }
            } header: {
                Text("Check the parser")
            } footer: {
                Text("Runs the reader on a sample alert and shows what it got out. Nothing is stored.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(HisabTheme.background)
        .navigationTitle("Capture setup")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("capture-setup")
        .task {
            enabled = CapturePrefs.isEnabled
            await refreshAuthorization()
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(HisabTheme.sona.opacity(0.25), in: Circle())
            Text(text).font(.subheadline)
        }
    }

    /// The same decisions `CaptureService` makes, minus the writes.
    private func runTest() {
        let now = Date()
        guard let alert = try? CaptureService.extractor?.extract(Self.sample) else {
            // What capture falls back to without the extractor: 1.3.0's
            // parser, which never adds anything to the ledger.
            guard let memo = AlertParser.parse(text: Self.sample, receivedAt: now) else {
                testResult = "Could not read that alert. Nothing was stored."
                return
            }
            testResult = "The on-device reader isn't available, so this is the basic parser's reading. "
                + Self.reading(amountPaise: memo.amountPaise, direction: memo.direction, payee: memo.payee,
                               vpa: memo.vpa, accountTail: memo.accountTail, date: memo.date, ref: nil)
                + " It would be kept as a memo."
            return
        }
        let memo = AlertCapture.memo(from: alert, receivedAt: now)
        let row = AlertCapture.ledgerRow(from: alert, receivedAt: now)
        guard memo != nil || row != nil, let amount = alert.amountPaise, let direction = alert.direction else {
            testResult = "Could not read that alert. Nothing was stored."
            return
        }
        let payee = memo?.payee ?? row.flatMap { $0.counterparty.isEmpty ? nil : $0.counterparty }
        testResult = Self.reading(amountPaise: amount, direction: direction, payee: payee, vpa: alert.vpa,
                                  accountTail: alert.ownAccountTail,
                                  date: AlertCapture.date(alert.dateISO, receivedAt: now), ref: alert.ref)
            + (row != nil ? " It has a bank reference, so it would go into your ledger right away."
                          : " It has no bank reference, so it would be kept as a memo until the statement arrives.")
    }

    private static func reading(amountPaise: Int64, direction: Direction, payee: String?, vpa: String?,
                                accountTail: String?, date: Date, ref: String?) -> String {
        var parts = ["\(Money.formatPaise(amountPaise)) \(direction == .debit ? "out" : "in")"]
        if let payee { parts.append("\(direction == .debit ? "to" : "from") \(payee)") }
        parts.append("on \(ISTStamp.day(date))")
        // Only when it adds something: this sample's payee IS its VPA, because
        // the alert names no merchant, and printing it twice reads like a bug.
        if let vpa, vpa != payee?.lowercased() { parts.append("UPI \(vpa)") }
        if let accountTail { parts.append("a/c ••\(accountTail)") }
        if let ref { parts.append("ref \(ref)") }
        return "Read: " + parts.joined(separator: ", ") + "."
    }

    private func refreshAuthorization() async {
        authorization = UNAuthorizationStatusBox(await CaptureNotifier.authorizationStatus())
    }
}

/// The three authorization states the capture UI distinguishes. `.provisional`
/// and `.ephemeral` count as allowed only so this never accuses iOS of blocking
/// something it has not; `CaptureNotifier.considerNotifying` is stricter about
/// what it will actually send on.
enum UNAuthorizationStatusBox: Equatable {
    case unknown, denied, allowed

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .allowed
        default: self = .unknown
        }
    }
}
