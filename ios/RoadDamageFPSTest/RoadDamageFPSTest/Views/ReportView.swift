import SwiftUI

/// Inspection report for one saved session: generates via OpenRouter on
/// demand (key from Keychain, set in Settings), persists report.md beside
/// defects.json, and renders/shares the saved markdown. The one screen in
/// the app that touches the network.
struct ReportView: View {
    let session: SessionSummary

    @State private var reportText: String?
    @State private var generating = false
    @State private var errorText: String?

    private var reportURL: URL {
        SessionStore.sessionDir(session.sessionID).appendingPathComponent("report.md")
    }

    var body: some View {
        Group {
            if let text = reportText {
                ScrollView {
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else if generating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Generating report...").foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("No report yet for this session.")
                        .foregroundStyle(.secondary)
                    if KeychainStore.load() == nil {
                        Text("Save an OpenRouter API key in Settings first.")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Button("Generate Report") { Task { await generate() } }
                            .buttonStyle(.borderedProminent)
                    }
                    if let e = errorText {
                        Text(e).font(.caption).foregroundStyle(.red)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Inspection Report")
        .toolbar {
            if let text = reportText {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Regenerate") {
                        reportText = nil
                        Task { await generate() }
                    }
                    .disabled(generating)
                }
            }
        }
        .onAppear {
            reportText = try? String(contentsOf: reportURL, encoding: .utf8)
        }
    }

    private func generate() async {
        guard let key = KeychainStore.load() else {
            errorText = "No API key in Keychain."
            return
        }
        generating = true
        errorText = nil
        defer { generating = false }
        do {
            let records = SessionStore.loadRecords(session.sessionID)
            let result = try await ReportGenerator.generate(
                records: records, sessionID: session.sessionID,
                startedEpoch: session.startedEpoch, durationS: session.durationS,
                apiKey: key)
            guard result.problems.isEmpty else {
                errorText = "Report failed validation: \(result.problems.joined(separator: "; "))"
                return
            }
            try result.text.write(to: reportURL, atomically: true, encoding: .utf8)
            reportText = result.text
        } catch {
            errorText = error.localizedDescription
        }
    }
}
