import Foundation
import EchoCore
import EchoNet
#if compiler(>=6.2) && canImport(FoundationModels)
import FoundationModels
#endif

public protocol LLMProvider: Sendable {
    var name: String { get }
    /// Approximate input budget in characters, used to decide when to map-reduce.
    var maxInputChars: Int { get }
    func isAvailable() async -> Bool
    func complete(system: String, user: String, json: Bool) async throws -> String
}

#if compiler(>=6.2) && canImport(FoundationModels)
/// Apple's on-device model (free, private). Needs macOS 26 + Apple Intelligence enabled.
@available(macOS 26, *)
public struct AppleFoundationProvider: LLMProvider {
    public let name = "Apple on-device model"
    public let maxInputChars = 6_000      // small context window → map-reduce kicks in early
    public init() {}
    public func isAvailable() async -> Bool { SystemLanguageModel.default.availability == .available }
    public func complete(system: String, user: String, json: Bool) async throws -> String {
        let session = LanguageModelSession(instructions: system)
        return try await session.respond(to: user).content
    }
}
#endif

/// Any OpenAI-compatible endpoint: local Ollama, or a user-supplied free-tier / BYO key API.
public struct OpenAICompatibleProvider: LLMProvider {
    public let name: String
    public let maxInputChars: Int
    let endpoint: LLMEndpoint
    let apiKey: @Sendable () -> String?
    public init(endpoint: LLMEndpoint, maxInputChars: Int = 24_000, apiKey: @escaping @Sendable () -> String? = { nil }) {
        self.endpoint = endpoint; self.maxInputChars = maxInputChars; self.apiKey = apiKey; self.name = endpoint.name
    }
    public func isAvailable() async -> Bool {
        if endpoint.isLocal { return await OpenAIClient.isReachable(endpoint) }
        return !(apiKey() ?? "").isEmpty     // cloud providers need a key the user added
    }
    public func complete(system: String, user: String, json: Bool) async throws -> String {
        try await OpenAIClient.complete(endpoint: endpoint, apiKey: apiKey(),
            messages: [ChatMessage(role: "system", content: system), ChatMessage(role: "user", content: user)],
            json: json, purpose: "Generate meeting notes")
    }
}
