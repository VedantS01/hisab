import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HisabCore

struct ImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickedURL: URL?
    @State private var overrideSource: Source?
    @State private var password = ""
    @State private var needsPassword = false
    @State private var report: ImportReport?
    @State private var errorMessage: String?
    @State private var showPicker = true

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    reportView(report)
                } else {
                    form
                }
            }
            .navigationTitle("Import statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.pdf, .commaSeparatedText, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                pickedURL = url
                attemptImport()
            } else {
                dismiss()
            }
        }
    }

    private var form: some View {
        Form {
            if let url = pickedURL {
                Section("File") {
                    Text(url.lastPathComponent).font(.subheadline)
                }
                Section("Source") {
                    Picker("Source", selection: $overrideSource) {
                        Text("Auto-detect").tag(Source?.none)
                        ForEach(Source.allCases) { source in
                            Text(source.displayName).tag(Source?.some(source))
                        }
                    }
                }
                if needsPassword {
                    Section("Password") {
                        SecureField("Statement password", text: $password)
                        Text("Remembered for this source on this device.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(HisabTheme.khataRed).font(.subheadline)
                    }
                }
                Section {
                    Button("Import") { attemptImport() }
                        .tint(HisabTheme.khataRed)
                }
            } else {
                Text("Choose a file to import.").foregroundStyle(.secondary)
            }
        }
    }

    private func reportView(_ report: ImportReport) -> some View {
        VStack(spacing: 16) {
            Image(systemName: report.duplicateOfExistingFile ? "doc.on.doc" : "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(report.duplicateOfExistingFile ? .secondary : HisabTheme.hara)
            if report.duplicateOfExistingFile {
                Text("Already imported")
                    .font(.title3.weight(.semibold))
                Text("This exact file is in your bahi already — nothing new to add.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("\(report.newCount) new transaction\(report.newCount == 1 ? "" : "s")")
                    .font(.title3.weight(.semibold))
                Text("\(report.source.displayName) · \(report.totalParsed) parsed · \(report.totalParsed - report.newCount) duplicates skipped")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !report.monthsTouched.isEmpty {
                    Text("Months: \(report.monthsTouched.map(\.displayName).joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(HisabTheme.khataRed)
        }
        .padding(24)
    }

    private func attemptImport() {
        guard let url = pickedURL else { return }
        errorMessage = nil
        let service = ImportService(context: context)
        let effectivePassword = password.isEmpty
            ? overrideSource.flatMap { KeychainHelper.password(for: $0) }
            : password
        do {
            let result = try service.importFile(at: url, password: effectivePassword,
                                                overrideSource: overrideSource)
            if !password.isEmpty {
                KeychainHelper.setPassword(password, for: result.source)
            }
            report = result
        } catch ParseError.passwordRequired {
            needsPassword = true
            errorMessage = "This statement is password-protected."
        } catch ParseError.malformedRow(let line, _) {
            errorMessage = "Could not parse line \(line) — is the right source selected?"
        } catch ParseError.empty {
            errorMessage = "No transactions found in this file."
        } catch ParseError.unrecognizedFormat {
            errorMessage = "Unrecognized format. Pick the source manually."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
