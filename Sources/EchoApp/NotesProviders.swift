import Foundation
import EchoCore
import EchoNet
import EchoNotes

/// Default chain (spec §5.1): Apple on-device model → Ollama → user-added API keys → extractive (inside NotesEngine).
enum NotesProviders {
    static func defaultChain() -> [LLMProvider] {
        var chain: [LLMProvider] = []
        #if compiler(>=6.2)
        if #available(macOS 26, *) { chain.append(AppleFoundationProvider()) }
        #endif
        chain.append(OpenAICompatibleProvider(endpoint: .ollama))
        for e in LLMEndpoint.presets {
            let acct = e.keychainAccount
            chain.append(OpenAICompatibleProvider(endpoint: e, apiKey: { acct.flatMap { Keychain.get(account: $0) } }))
        }
        if let custom = customEndpoint() {
            let acct = custom.keychainAccount
            chain.append(OpenAICompatibleProvider(endpoint: custom, apiKey: { acct.flatMap { Keychain.get(account: $0) } }))
        }
        return chain
    }
    /// User-configured OpenAI-compatible endpoint (Settings → Engines).
    static func customEndpoint() -> LLMEndpoint? {
        guard let url = UserDefaults.standard.string(forKey: "custom.baseURL"), !url.isEmpty,
              let model = UserDefaults.standard.string(forKey: "custom.model"), !model.isEmpty else { return nil }
        return LLMEndpoint(name: "Custom endpoint", baseURL: url, model: model, keychainAccount: "custom",
                           isLocal: url.contains("127.0.0.1") || url.contains("localhost"))
    }
}
