import Foundation

/// Turns a saved session into shareable files. GeoJSON drops straight into
/// QGIS/ArcGIS or a web map; CSV opens in a spreadsheet. Mirrors the
/// records_to_geojson output in pipeline/geo.py so both paths agree.
enum SessionExport {

    static func geoJSON(records: [DefectRecord]) -> String {
        var features: [String] = []
        for r in records {
            guard let loc = r.location else { continue }
            var props: [String] = [
                "\"track_id\": \(r.trackID)",
                "\"class\": \"\(r.className)\"",
                "\"confidence\": \(round(r.confidence * 1000) / 1000)",
                "\"severity\": \"\(Severity.score(className: r.className, dimensions: r.dimensions).level)\"",
            ]
            if let d = r.dimensions {
                props.append("\"width_m\": \(round(d.widthM * 100) / 100)")
                props.append("\"length_m\": \(round(d.lengthM * 100) / 100)")
                props.append("\"area_m2\": \(round(d.areaM2 * 100) / 100)")
                props.append("\"distance_m\": \(round(d.distanceM * 10) / 10)")
            }
            if let h = loc.heading { props.append("\"heading_deg\": \(round(h * 10) / 10)") }
            features.append("""
            {"type":"Feature","geometry":{"type":"Point","coordinates":[\(loc.lon),\(loc.lat)]},"properties":{\(props.joined(separator: ","))}}
            """.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return "{\"type\":\"FeatureCollection\",\"features\":[\(features.joined(separator: ","))]}"
    }

    static func csv(records: [DefectRecord]) -> String {
        var out = "track_id,class,severity,confidence,width_m,length_m,area_m2,distance_m,lat,lon\n"
        for r in records {
            let sev = Severity.score(className: r.className, dimensions: r.dimensions).level
            let d = r.dimensions
            let loc = r.location
            let cols: [String] = [
                "\(r.trackID)", r.className, sev,
                String(format: "%.3f", r.confidence),
                d.map { String(format: "%.2f", $0.widthM) } ?? "",
                d.map { String(format: "%.2f", $0.lengthM) } ?? "",
                d.map { String(format: "%.2f", $0.areaM2) } ?? "",
                d.map { String(format: "%.1f", $0.distanceM) } ?? "",
                loc.map { String(format: "%.6f", $0.lat) } ?? "",
                loc.map { String(format: "%.6f", $0.lon) } ?? "",
            ]
            out += cols.joined(separator: ",") + "\n"
        }
        return out
    }

    /// Write both formats into the session folder and return their URLs.
    static func writeFiles(sessionID: String, records: [DefectRecord]) -> [URL] {
        let dir = SessionStore.sessionDir(sessionID)
        var urls: [URL] = []
        let g = dir.appendingPathComponent("defects.geojson")
        let c = dir.appendingPathComponent("defects.csv")
        if (try? geoJSON(records: records).write(to: g, atomically: true, encoding: .utf8)) != nil {
            urls.append(g)
        }
        if (try? csv(records: records).write(to: c, atomically: true, encoding: .utf8)) != nil {
            urls.append(c)
        }
        return urls
    }
}
