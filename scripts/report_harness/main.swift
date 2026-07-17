import Foundation

/// macOS CLI harness for the app's Report/ sources (compiled together by
/// scripts/test_swift_report.sh). Lets the Swift report pipeline be verified
/// on the Mac -- payload parity vs the Python builder, prompt sync, validator
/// behavior, and a real OpenRouter call -- without an iOS device build.

func loadRecords(_ path: String) -> [DefectRecord] {
    guard let data = FileManager.default.contents(atPath: path),
          let recs = try? JSONDecoder().decode([DefectRecord].self, from: data) else {
        FileHandle.standardError.write("cannot load/decode \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return recs
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: report_harness payload <fixture> <sessionID> [durationS]")
    exit(2)
}

switch args[1] {
case "payload":
    let records = loadRecords(args[2])
    let duration = args.count > 4 ? Double(args[4]) : nil
    let payload = ReportPayload.build(records: records, sessionID: args[3],
                                      startedEpoch: nil, durationS: duration)
    print(ReportPayload.jsonString(payload))
case "prompt":
    print(ReportPrompt.text)
case "validator-test":
    let records = loadRecords(args[2])
    let payload = ReportPayload.build(records: records, sessionID: args[3],
                                      startedEpoch: nil, durationS: 45.5)
    let good = """
    # Road Inspection Report
    Session swift-001, 45.5 seconds surveyed.

    ## Executive Summary
    6 defects: 2 severe, 1 moderate, 3 low. Total measured area 1.81 m².

    ## Severity Overview
    | Severity | Count | Classes present |
    |---|---|---|
    | severe | 2 | Crack, Pothole |
    | moderate | 1 | Pothole |
    | low | 3 | Manhole, Crack, Pothole |

    ## Defects
    **Defect #9 — Crack — severe** Size 0.15 × 4.25 m, area 0.64 m². Location 37.775231, -122.418773. Confidence 48.3%.
    **Defect #6 — Pothole — severe** Size 0.8 × 0.7 m, area 0.5 m². Location 37.77512, -122.419015. Confidence 81.2%.
    **Defect #2 — Pothole — moderate** Size 0.45 × 0.4 m, area 0.18 m². Location 37.7749, -122.4194. Confidence 77%.
    **Defect #12 — Manhole — low** Size 0.66 × 0.64 m, area 0.42 m². Location 37.77531, -122.41862. Confidence 90.5%.
    **Defect #4 — Crack — low** Size 0.1 × 0.7 m, area 0.07 m². Location 37.77498, -122.41928. Confidence 44%.
    **Defect #15 — Pothole — low** Not measured. Location not recorded. Confidence 51%.

    ## Recommended Actions
    Severe (2): schedule repair. Moderate (1): maintenance queue. Low (3): log only.

    ## Limitations and Data Caveats
    Dimensions via IPM, pending field validation. 1 unmeasured, 1 unlocated.
    """
    let bad = good.replacingOccurrences(of: "area 0.64 m²", with: "area 9.87 m²")
        + "\nEstimated repair cost: 3100 dollars.\n"
    let missing = good.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.contains("#15") }.joined(separator: "\n")

    let g = ReportValidator.validate(report: good, payload: payload)
    let b = ReportValidator.validate(report: bad, payload: payload)
    let m = ReportValidator.validate(report: missing, payload: payload)
    print("GOOD: \(g.count) problem(s)"); g.forEach { print("  - \($0)") }
    print("BAD: \(b.count) problem(s)"); b.forEach { print("  - \($0)") }
    print("MISSING: \(m.count) problem(s)"); m.forEach { print("  - \($0)") }
    let ok = g.isEmpty && !b.isEmpty && !m.isEmpty
    print(ok ? "PASS" : "FAIL")
    exit(ok ? 0 : 1)
case "generate":
    let records = loadRecords(args[2])
    guard let key = envAPIKey() else {
        FileHandle.standardError.write("no OPENROUTER_API_KEY in env or .env\n".data(using: .utf8)!)
        exit(1)
    }
    let result = try await ReportGenerator.generate(
        records: records, sessionID: args[3], startedEpoch: nil,
        durationS: args.count > 4 ? Double(args[4]) : nil, apiKey: key)
    if result.problems.isEmpty {
        print(result.text)
    } else {
        FileHandle.standardError.write(
            "validation problems: \(result.problems)\n".data(using: .utf8)!)
        print(result.text)
        exit(1)
    }
default:
    print("unknown subcommand \(args[1])")
    exit(2)
}

func envAPIKey() -> String? {
    if let k = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !k.isEmpty {
        return k
    }
    for path in [".env", "report/.env"] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "OPENROUTER_API_KEY" {
                return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
        }
    }
    return nil
}
