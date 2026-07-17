import Foundation

/// Minimal OpenRouter chat client -- Swift port of report/openrouter.py.
/// Same endpoint, model default, temperature 0, and max_tokens cap as the
/// Python harness, so a report generated on-device matches one generated
/// by the reference pipeline. The API key is supplied by the caller (the
/// app reads it from the Keychain; the macOS test harness from .env).
enum OpenRouterClient {
    static let apiURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let defaultModel = "anthropic/claude-sonnet-4.5"

    enum ClientError: LocalizedError {
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .http(let code, let detail): return "OpenRouter HTTP \(code): \(detail)"
            case .badResponse: return "Unexpected OpenRouter response"
            }
        }
    }

    static func complete(systemPrompt: String, userContent: String, apiKey: String,
                         model: String = defaultModel, maxTokens: Int = 2000) async throws -> String {
        var req = URLRequest(url: apiURL, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/Sribhuvan-25/Road-Analysis", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("RoadEye Inspection Report", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ClientError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ClientError.badResponse
        }
        return content
    }
}
