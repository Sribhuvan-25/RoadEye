import Foundation
import UIKit

/// Saves and lists per-session archives on disk. Each session is a folder in
/// Documents/sessions/<id>/ holding defects.json (the reviewable records),
/// summary.json (the header for the list screen), and defect crop JPEGs.
enum SessionStore {
    static var root: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func sessionDir(_ id: String) -> URL {
        let dir = root.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(
        id: String, startedEpoch: Double, durationS: TimeInterval,
        records: [DefectRecord], crops: [Int: UIImage]
    ) {
        let dir = sessionDir(id)
        for (trackID, image) in crops {
            guard let rec = records.first(where: { $0.trackID == trackID }),
                  let name = rec.cropFilename,
                  let data = image.jpegData(compressionQuality: 0.85) else { continue }
            try? data.write(to: dir.appendingPathComponent(name))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        if let d = try? enc.encode(records) {
            try? d.write(to: dir.appendingPathComponent("defects.json"))
        }
        let summary = SessionSummary(sessionID: id, startedEpoch: startedEpoch,
                                     durationS: durationS, defectCount: records.count)
        if let d = try? enc.encode(summary) {
            try? d.write(to: dir.appendingPathComponent("summary.json"))
        }
    }

    static func listSessions() -> [SessionSummary] {
        let dec = JSONDecoder()
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { d -> SessionSummary? in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("summary.json")),
                  let s = try? dec.decode(SessionSummary.self, from: data) else { return nil }
            return s
        }.sorted { $0.startedEpoch > $1.startedEpoch }
    }

    static func loadRecords(_ id: String) -> [DefectRecord] {
        let url = sessionDir(id).appendingPathComponent("defects.json")
        guard let data = try? Data(contentsOf: url),
              let recs = try? JSONDecoder().decode([DefectRecord].self, from: data)
        else { return [] }
        return recs
    }

    static func cropURL(sessionID: String, filename: String) -> URL {
        sessionDir(sessionID).appendingPathComponent(filename)
    }

    static func delete(_ id: String) {
        try? FileManager.default.removeItem(at: sessionDir(id))
    }
}
