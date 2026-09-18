import SwiftUI
import HisabCore

/// Shown when no engine could read (or verify) a statement. Offers a
/// user-initiated email carrying only the data-free format fingerprint.
struct FormatRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let fingerprint: FormatFingerprint
    /// Non-nil when a table was read but its balance chain wouldn't close.
    let verificationDetail: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: verificationDetail == nil ? "doc.questionmark" : "exclamationmark.shield")
                    .font(.system(size: 44))
                    .foregroundStyle(HisabTheme.khataRed)
                Text(verificationDetail == nil
                     ? "Hisab can't read this statement format yet."
                     : "Couldn't verify this statement.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let verificationDetail {
                    Text("The running balance doesn't add up (\(verificationDetail)). The file may be truncated or edited — nothing was imported.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    if let bank = fingerprint.bankNameGuess {
                        Text("This looks like a \(bank) statement.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Support for new formats arrives in app updates. The request email contains only column labels and value shapes — no transactions.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Hisab reads today: \(ImportResolver.live().supportedFormatNames.joined(separator: ", ")) — plus most Indian bank statements that print a running balance.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if verificationDetail == nil,
                   let url = fingerprint.mailtoURL(appVersion: appVersion) {
                    Button {
                        openURL(url)
                        dismiss()
                    } label: {
                        Label("Request support", systemImage: "envelope")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HisabTheme.khataRed)
                }
                Button("Close") { dismiss() }
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }
}
