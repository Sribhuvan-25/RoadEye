import Foundation

/// Builds the structured JSON payload the LLM narrates -- Swift port of
/// report/payload.py (the canonical copy; keep field names, rounding, and
/// ordering in sync). Every number, count, and ordering is decided here so
/// the model has nothing to invent; parity with the Python builder is checked
/// by scripts/test_swift_report.sh against the same fixture.
enum ReportPayload {

    static func build(records: [DefectRecord], sessionID: String,
                      startedEpoch: Double?, durationS: Double?) -> [String: Any] {
        let normed = records.map(normRecord)

        let sorted = normed.enumerated().sorted { a, b in
            let ra = Severity.levelRank[a.element.severity] ?? 0
            let rb = Severity.levelRank[b.element.severity] ?? 0
            if ra != rb { return ra > rb }
            if a.element.sortSize != b.element.sortSize { return a.element.sortSize > b.element.sortSize }
            return a.offset < b.offset
        }.map(\.element)

        var byClass: [String: Int] = [:]
        var bySeverity: [String: Int] = [:]
        for r in sorted {
            byClass[r.className, default: 0] += 1
            bySeverity[r.severity, default: 0] += 1
        }

        let unmeasured = sorted.filter { $0.dimensions == nil }.count
        let unlocated = sorted.filter { !$0.hasLocation }.count
        let totalArea = round2(sorted.reduce(0.0) { $0 + ($1.dimensions?["area_m2"] ?? 0.0) })

        return [
            "session": [
                "session_id": sessionID,
                "started_epoch": startedEpoch.map { $0 as Any } ?? NSNull(),
                "duration_s": durationS.map { pyRound($0, 1) as Any } ?? NSNull(),
                "defect_count": sorted.count,
            ],
            "counts": [
                "by_class": byClass,
                "by_severity": Severity.levels.reduce(into: [String: Int]()) {
                    $0[$1] = bySeverity[$1] ?? 0
                },
                "total_measured_area_m2": totalArea,
            ],
            "data_quality": [
                "unmeasured_count": unmeasured,
                "unlocated_count": unlocated,
                "measurement_method": "inverse perspective mapping (IPM); "
                    + "dimensions pending field validation",
            ],
            "severity_scale": [
                "definition": "computed deterministically from class + measured "
                    + "size; pothole by area (m^2), crack by length (m); manhole and "
                    + "unmeasured defects are 'low' / unassessed",
                "levels": Severity.levels,
            ],
            "defects": sorted.map(\.json),
        ]
    }

    static func jsonString(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private struct NormRecord {
        let className: String
        let severity: String
        let dimensions: [String: Double]?
        let hasLocation: Bool
        let sortSize: Double
        let json: [String: Any]
    }

    private static func normRecord(_ r: DefectRecord) -> NormRecord {
        let dims: [String: Double]? = r.dimensions.map {
            [
                "width_m": round2($0.widthM),
                "length_m": round2($0.lengthM),
                "area_m2": round2($0.areaM2),
                "distance_m": pyRound($0.distanceM, 1),
            ]
        }
        let sev = Severity.score(className: r.className, dimensions: r.dimensions)

        var sortSize = 0.0
        if let d = dims {
            let area = d["area_m2"] ?? 0.0
            let length = d["length_m"] ?? 0.0
            sortSize = area != 0.0 ? area : (length != 0.0 ? length : 0.0)
        }

        var json: [String: Any] = [
            "id": r.trackID,
            "class": r.className,
            "confidence": pyRound(r.confidence, 3),
            "n_frames": r.nFrames,
            "severity": sev.level,
            "severity_reason": sev.reason,
        ]
        json["dimensions"] = dims.map { d in
            [
                "width_m": d["width_m"]!, "length_m": d["length_m"]!,
                "area_m2": d["area_m2"]!, "distance_m": d["distance_m"]!,
            ] as [String: Any]
        } ?? NSNull()
        json["location"] = r.location.map { loc in
            [
                "lat": pyRound(loc.lat, 6),
                "lon": pyRound(loc.lon, 6),
                "heading_deg": loc.heading.map { pyRound($0, 1) as Any } ?? NSNull(),
            ] as [String: Any]
        } ?? NSNull()

        return NormRecord(className: r.className, severity: sev.level,
                          dimensions: dims, hasLocation: r.location != nil,
                          sortSize: sortSize, json: json)
    }

    private static func round2(_ v: Double) -> Double { pyRound(v, 2) }

    private static func pyRound(_ v: Double, _ digits: Int) -> Double {
        let p = pow(10.0, Double(digits))
        return (v * p).rounded(.toNearestOrEven) / p
    }
}
