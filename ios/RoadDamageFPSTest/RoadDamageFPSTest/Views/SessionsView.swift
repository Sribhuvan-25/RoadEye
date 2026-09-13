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
                    SessionRow(session: s)
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
    @State private var exportURLs: [URL] = []

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
                        Text(String(format: "%.1f m away", d.distanceM))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Size not measurable")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                    if let loc = r.location {
                        Text(String(format: "%.5f, %.5f", loc.lat, loc.lon))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No GPS fix")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(String(format: "conf %.0f%%", r.confidence * 100))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("\(records.count) defects")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Report") { ReportView(session: session) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportURLs = SessionExport.writeFiles(
                            sessionID: session.sessionID, records: records)
                    } label: {
                        Label("Export GeoJSON + CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(records.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { !exportURLs.isEmpty },
            set: { if !$0 { exportURLs = [] } })
        ) {
            ShareSheet(items: exportURLs)
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

/// One row in Past Sessions: when it was recorded, how many defects, and the
/// severity mix so a drive worth reviewing stands out without opening it.
private struct SessionRow: View {
    let session: SessionSummary
    @State private var counts: (severe: Int, moderate: Int, low: Int) = (0, 0, 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateString(session.startedEpoch)).font(.headline)
            Text("\(session.defectCount) defects · \(Int(session.durationS))s")
                .font(.subheadline).foregroundStyle(.secondary)
            if session.defectCount > 0 {
                HStack(spacing: 6) {
                    if counts.severe > 0 { pill("\(counts.severe) severe", .red) }
                    if counts.moderate > 0 { pill("\(counts.moderate) moderate", .orange) }
                    if counts.low > 0 { pill("\(counts.low) low", .secondary) }
                }
            }
        }
        .onAppear(perform: loadCounts)
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func loadCounts() {
        let records = SessionStore.loadRecords(session.sessionID)
        var c = (severe: 0, moderate: 0, low: 0)
        for r in records {
            switch Severity.score(className: r.className, dimensions: r.dimensions).level {
            case "severe": c.severe += 1
            case "moderate": c.moderate += 1
            default: c.low += 1
            }
        }
        counts = c
    }

    private func dateString(_ epoch: Double) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }
}

/// UIKit share sheet so exported files can go to Files, Mail, AirDrop, etc.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
