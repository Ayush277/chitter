import Foundation

/// Any OpenAI-compatible chat endpoint (Gemini, Groq, OpenRouter, Ollama, custom, OpenAI).
public struct LLMEndpoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var baseURL: String          // e.g. https://api.groq.com/openai/v1
    public var model: String
    public var keychainAccount: String? // nil → no key needed (Ollama)
    public var isLocal: Bool
    public init(name: String, baseURL: String, model: String, keychainAccount: String? = nil, isLocal: Bool = false) {
        self.name = name; self.baseURL = baseURL; self.model = model; self.keychainAccount = keychainAccount; self.isLocal = isLocal
    }
    public static let ollama = LLMEndpoint(name: "Ollama", baseURL: "http://127.0.0.1:11434/v1", model: "llama3.2", isLocal: true)
    /// Free-tier presets (limits change often; the chain falls through on 429).
    public static let presets: [LLMEndpoint] = [
        LLMEndpoint(name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-2.0-flash", keychainAccount: "gemini"),
        LLMEndpoint(name: "Groq", baseURL: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile", keychainAccount: "groq"),
        LLMEndpoint(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "meta-llama/llama-3.3-70b-instruct:free", keychainAccount: "openrouter"),
    ]
}

public struct ChatMessage: Codable, Sendable { public var role: String; public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content } }

public enum OpenAIClient {
    /// One chat completion; retries 429s with exponential backoff (decision table), then throws so the chain moves on.
    public static func complete(endpoint: LLMEndpoint, apiKey: String?, messages: [ChatMessage], json: Bool = false,
                                purpose: String, maxRetries: Int = 2, gateway: NetworkGateway = .shared) async throws -> String {
        guard let url = URL(string: endpoint.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")
        else { throw GatewayError.badResponse }
        var body: [String: Any] = ["model": endpoint.model, "messages": messages.map { ["role": $0.role, "content": $0.content] },
                                   "temperature": 0.2]
        if json { body["response_format"] = ["type": "json_object"] }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        var attempt = 0
        while true {
            do {
                let (data, _) = try await gateway.data(for: req, purpose: purpose, provider: endpoint.name, containsMeetingData: !endpoint.isLocal ? true : false)
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choice = (obj["choices"] as? [[String: Any]])?.first,
                      let msg = choice["message"] as? [String: Any], let text = msg["content"] as? String
                else { throw GatewayError.badResponse }
                return text
            } catch GatewayError.rateLimited(let after) where attempt < maxRetries {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64((after ?? pow(2, Double(attempt))) * 1_000_000_000))
            }
        }
    }

    public static func isReachable(_ endpoint: LLMEndpoint, gateway: NetworkGateway = .shared) async -> Bool {
        guard let url = URL(string: endpoint.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models") else { return false }
        return (try? await gateway.data(for: URLRequest(url: url, timeoutInterval: 2), purpose: "Check \(endpoint.name) is running",
                                        provider: endpoint.name, containsMeetingData: false)) != nil
    }
}
