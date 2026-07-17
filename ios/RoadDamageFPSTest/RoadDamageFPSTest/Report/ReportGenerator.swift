import Foundation

/// Ties the report flow together on-device -- mirror of report/generate.py:
/// build the precomputed payload, call the LLM with the embedded prompt,
/// validate the result, regenerate once on failure. Returns the report text;
/// the caller persists it (report.md in the session folder).
enum ReportGenerator {

    struct Result {
        let text: String
        let problems: [String]
    }

    static func generate(records: [DefectRecord], sessionID: String,
                         startedEpoch: Double?, durationS: Double?,
                         apiKey: String, model: String = OpenRouterClient.defaultModel,
                         maxAttempts: Int = 2) async throws -> Result {
        let payload = ReportPayload.build(records: records, sessionID: sessionID,
                                          startedEpoch: startedEpoch, durationS: durationS)
        let userContent = ReportPayload.jsonString(payload)

        var text = ""
        var problems: [String] = ["not attempted"]
        for _ in 1...max(1, maxAttempts) {
            text = try await OpenRouterClient.complete(
                systemPrompt: ReportPrompt.text, userContent: userContent, apiKey: apiKey)
            problems = ReportValidator.validate(report: text, payload: payload)
            if problems.isEmpty { break }
        }
        return Result(text: text, problems: problems)
    }
}
