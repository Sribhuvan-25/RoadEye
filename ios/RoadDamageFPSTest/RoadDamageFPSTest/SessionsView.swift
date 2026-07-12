import SwiftUI

/// "Past Sessions" — lists saved drives; tapping one shows its defects with
/// crop, class, location, and measured size. Everything is read from the
/// on-device SessionStore, no network.
struct SessionsView: View {
    @State private var sessions: [SessionSummary] = []

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("No sessions yet. Record a drive to see defects here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { s in
                NavigationLink(destination: SessionDetailView(session: s)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateString(s.startedEpoch)).font(.headline)
                        Text("\(s.defectCount) defects · \(Int(s.durationS))s")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in
                idx.map { sessions[$0].sessionID }.forEach(SessionStore.delete)
                sessions = SessionStore.listSessions()
            }
        }
        .navigationTitle("Past Sessions")
        .onAppear { sessions = SessionStore.listSessions() }
    }

    private func dateString(_ epoch: Double) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }
}

struct SessionDetailView: View {
    let session: SessionSummary
    @State private var records: [DefectRecord] = []

    var body: some View {
        List(records) { r in
            HStack(spacing: 12) {
                cropImage(r)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.className).font(.headline)
                    if let d = r.dimensions {
                        Text(String(format: "%.2f × %.2f m · %.2f m²", d.widthM, d.lengthM, d.areaM2))
                            .font(.subheadline)
                    }
                    if let loc = r.location {
                        Text(String(format: "%.5f, %.5f", loc.lat, loc.lon))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(String(format: "conf %.0f%%", r.confidence * 100))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("\(records.count) defects")
        .onAppear { records = SessionStore.loadRecords(session.sessionID) }
    }

    @ViewBuilder
    private func cropImage(_ r: DefectRecord) -> some View {
        if let name = r.cropFilename,
           let ui = UIImage(contentsOfFile:
                SessionStore.cropURL(sessionID: session.sessionID, filename: name).path) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            Rectangle().fill(.gray.opacity(0.3))
        }
    }
}
