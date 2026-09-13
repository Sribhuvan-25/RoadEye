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
    @State private var selection: PhotoSelection?

    private struct PhotoSelection: Identifiable {
        let record: DefectRecord
        let image: UIImage
        var id: Int { record.trackID }
    }

    var body: some View {
        List(records) { r in
            HStack(spacing: 12) {
                thumbnail(r)
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
        .toolbar {
            NavigationLink("Report") { ReportView(session: session) }
        }
        .onAppear { records = SessionStore.loadRecords(session.sessionID) }
        .fullScreenCover(item: $selection) { sel in
            DefectPhotoView(image: sel.image, title: sel.record.className,
                            subtitle: photoSubtitle(sel.record))
        }
    }

    private func photoSubtitle(_ r: DefectRecord) -> String? {
        guard let d = r.dimensions else { return nil }
        return String(format: "%.2f × %.2f m · %.2f m²", d.widthM, d.lengthM, d.areaM2)
    }

    private func loadImage(_ r: DefectRecord) -> UIImage? {
        guard let name = r.cropFilename else { return nil }
        return UIImage(contentsOfFile:
            SessionStore.cropURL(sessionID: session.sessionID, filename: name).path)
    }

    /// A photo-backed thumbnail opens the full-screen viewer on tap; a
    /// missing crop (capture can silently drop one, see SessionStore.save)
    /// shows a plain non-interactive placeholder instead of a dead button.
    @ViewBuilder
    private func thumbnail(_ r: DefectRecord) -> some View {
        if let img = loadImage(r) {
            Button {
                selection = PhotoSelection(record: r, image: img)
            } label: {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            ZStack {
                Rectangle().fill(.gray.opacity(0.3))
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
