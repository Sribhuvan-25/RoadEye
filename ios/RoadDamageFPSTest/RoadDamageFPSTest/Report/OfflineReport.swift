import Foundation

/// Builds an inspection report entirely on-device, with no network and no API
/// key. Same structure the LLM prompt asks for, composed deterministically
/// from the payload, so the app always produces a usable report -- the LLM
/// version only adds nicer prose on top of the same facts.
enum OfflineReport {

    static func build(records: [DefectRecord], sessionID: String,
                      startedEpoch: Double?, durationS: Double?) -> String {
        let payload = ReportPayload.build(records: records, sessionID: sessionID,
                                          startedEpoch: startedEpoch, durationS: durationS)
        let session = payload["session"] as? [String: Any] ?? [:]
        let counts = payload["counts"] as? [String: Any] ?? [:]
        let bySeverity = counts["by_severity"] as? [String: Int] ?? [:]
        let dq = payload["data_quality"] as? [String: Any] ?? [:]
        let defects = payload["defects"] as? [[String: Any]] ?? []
        let total = session["defect_count"] as? Int ?? defects.count

        var out = "# Road Inspection Report\n\n"
        if let d = session["duration_s"] as? Double {
            out += "Session \(sessionID) — \(fmt(d, 1)) seconds surveyed.\n\n"
        } else {
            out += "Session \(sessionID).\n\n"
        }

        out += "## Summary\n\n"
        if total == 0 {
            out += "No defects were detected in this session.\n"
            return out
        }
        let severe = bySeverity["severe"] ?? 0
        let moderate = bySeverity["moderate"] ?? 0
        if severe > 0 {
            out += "\(total) defects found; \(severe) severe "
            out += "\(severeClasses(defects))need attention first.\n\n"
        } else if moderate > 0 {
            out += "\(total) defects found; none severe, \(moderate) moderate.\n\n"
        } else {
            out += "\(total) defects found, all low severity.\n\n"
        }

        out += "## Defects\n\n"
        for r in defects {
            out += defectLine(r) + "\n\n"
        }

        out += "## Notes\n\n"
        var notes = ["Dimensions are IPM-estimated and pending field validation"]
        if let n = dq["unmeasured_count"] as? Int, n > 0 {
            notes.append("\(n) defect\(n == 1 ? "" : "s") could not be measured")
        }
        if let n = dq["unlocated_count"] as? Int, n > 0 {
            notes.append("\(n) defect\(n == 1 ? "" : "s") \(n == 1 ? "has" : "have") no GPS fix")
        }
        out += notes.joined(separator: "; ") + ".\n"
        return out
    }

    private static func severeClasses(_ defects: [[String: Any]]) -> String {
        let classes = Set(defects.compactMap { d -> String? in
            guard (d["severity"] as? String) == "severe" else { return nil }
            return d["class"] as? String
        }).sorted()
        return classes.isEmpty ? "" : "(\(classes.joined(separator: ", "))) "
    }

    private static func defectLine(_ r: [String: Any]) -> String {
        let id = r["id"] as? Int ?? 0
        let cls = r["class"] as? String ?? "Defect"
        let sev = r["severity"] as? String ?? "low"
        var line = "**#\(id) \(cls) — \(sev)** — "

        if let d = r["dimensions"] as? [String: Any],
           let w = d["width_m"] as? Double, let l = d["length_m"] as? Double,
           let a = d["area_m2"] as? Double {
            line += "\(fmt(w, 2))×\(fmt(l, 2)) m (\(fmt(a, 2)) m²)"
        } else {
            line += "not measured"
        }

        if let loc = r["location"] as? [String: Any],
           let lat = loc["lat"] as? Double, let lon = loc["lon"] as? Double {
            line += " at \(fmt(lat, 5)), \(fmt(lon, 5))"
        } else {
            line += " at no GPS fix"
        }
        return line + " — " + action(severity: sev, reason: r["severity_reason"] as? String ?? "")
    }

    private static func action(severity: String, reason: String) -> String {
        if reason.contains("unassessed") || reason.contains("manhole") {
            return "informational only"
        }
        switch severity {
        case "severe": return "schedule repair"
        case "moderate": return "monitor"
        default: return "log only"
        }
    }

    private static func fmt(_ v: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", v)
    }
}
