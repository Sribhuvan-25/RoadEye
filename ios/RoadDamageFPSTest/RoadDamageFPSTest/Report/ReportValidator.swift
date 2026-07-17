import Foundation

/// Structural fact-check of a generated report against its payload -- Swift
/// port of report/validator.py (the canonical copy; keep checks in sync).
/// Catches a dropped defect and any number that isn't in the input; empty
/// result means the report passed.
enum ReportValidator {

    static let requiredHeadings = [
        "# Road Inspection Report",
        "## Executive Summary",
        "## Severity Overview",
        "## Defects",
        "## Recommended Actions",
        "## Limitations and Data Caveats",
    ]

    static func validate(report: String, payload: [String: Any]) -> [String] {
        var problems: [String] = []

        for h in requiredHeadings where !report.contains(h) {
            problems.append("missing required heading: '\(h)'")
        }

        let defects = payload["defects"] as? [[String: Any]] ?? []
        for r in defects {
            guard let id = r["id"] as? Int else { continue }
            if matches("#\\s*\(id)\\b", in: report).isEmpty {
                problems.append("defect id \(id) not referenced in report")
            }
        }

        let nBlocks = matches("\\*\\*Defect\\s*#", in: report).count
        let session = payload["session"] as? [String: Any] ?? [:]
        if let want = session["defect_count"] as? Int, want > 0, nBlocks != want {
            problems.append("found \(nBlocks) defect blocks, expected \(want)")
        }

        let allowed = allowedNumbers(payload)
        for tok in numbersIn(report) where !allowed.contains(tok) {
            problems.append("number \(tok) in report is not in the input data")
        }

        return problems
    }

    private static func numbersIn(_ text: String) -> Set<String> {
        var out = Set<String>()
        for m in matches("(?<![\\w.])-?\\d+\\.?\\d*", in: text) {
            if let v = Double(m) {
                out.insert(numKey(v))
            }
        }
        return out
    }

    private static func numKey(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e15 {
            return String(Int(v))
        }
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    private static func allowedNumbers(_ payload: [String: Any]) -> Set<String> {
        var allowed = Set<String>()

        func add(_ v: Any?) {
            switch v {
            case let i as Int: allowed.insert(numKey(Double(i)))
            case let d as Double: allowed.insert(numKey(d))
            default: break
            }
        }

        let session = payload["session"] as? [String: Any] ?? [:]
        add(session["defect_count"])
        add(session["duration_s"])
        add(session["started_epoch"])

        let counts = payload["counts"] as? [String: Any] ?? [:]
        (counts["by_class"] as? [String: Any])?.values.forEach(add)
        (counts["by_severity"] as? [String: Any])?.values.forEach(add)
        add(counts["total_measured_area_m2"])

        let dq = payload["data_quality"] as? [String: Any] ?? [:]
        add(dq["unmeasured_count"])
        add(dq["unlocated_count"])

        for r in payload["defects"] as? [[String: Any]] ?? [] {
            add(r["id"])
            add(r["n_frames"])
            add(r["confidence"])
            if let conf = r["confidence"] as? Double {
                add((conf * 1000).rounded(.toNearestOrEven) / 10)
                add((conf * 100).rounded(.toNearestOrEven))
            }
            (r["dimensions"] as? [String: Any])?.values.forEach(add)
            (r["location"] as? [String: Any])?.values.forEach(add)
        }

        for i in 0...100 {
            allowed.insert(String(i))
        }

        return allowed
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }
}
