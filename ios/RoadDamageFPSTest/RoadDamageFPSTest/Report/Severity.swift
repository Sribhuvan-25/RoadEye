import Foundation

/// Deterministic severity scoring -- Swift port of report/severity.py (the
/// canonical copy; keep thresholds and reason strings in sync). The LLM never
/// decides severity, it only narrates what this computes, so the same defect
/// always scores the same way on-device and in the Python harness.
enum Severity {
    static let levels = ["low", "moderate", "severe"]
    static let levelRank: [String: Int] = ["low": 0, "moderate": 1, "severe": 2]

    static let potholeAreaBounds: [(level: String, lower: Double)] =
        [("severe", 0.30), ("moderate", 0.10), ("low", 0.0)]
    static let crackLengthBounds: [(level: String, lower: Double)] =
        [("severe", 3.0), ("moderate", 1.0), ("low", 0.0)]

    struct Score {
        let level: String
        let reason: String
    }

    static func score(className: String, dimensions: Dimensions?) -> Score {
        let key = className.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard let dims = dimensions else {
            return Score(level: "low",
                         reason: "not measured (no camera configuration); severity unassessed")
        }

        switch key {
        case "manhole":
            return Score(level: "low",
                         reason: "manhole cover -- infrastructure, not pavement damage")
        case "pothole":
            return Score(level: boundLevel(dims.areaM2, potholeAreaBounds),
                         reason: String(format: "pothole area %.2f m²", dims.areaM2))
        case "crack":
            return Score(level: boundLevel(dims.lengthM, crackLengthBounds),
                         reason: String(format: "crack length %.2f m", dims.lengthM))
        default:
            return Score(level: "low",
                         reason: "unrecognized class '\(className)'; severity unassessed")
        }
    }

    private static func boundLevel(_ value: Double,
                                   _ bounds: [(level: String, lower: Double)]) -> String {
        for (level, lower) in bounds where value >= lower {
            return level
        }
        return "low"
    }
}
