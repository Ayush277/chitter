import Foundation
import NaturalLanguage
import EchoNet

public enum TranslationError: Error, CustomStringConvertible {
    case unavailable(String)
    public var description: String { if case .unavailable(let m) = self { return m }; return "Translation failed" }
}

public protocol Translator: Sendable {
    var name: String { get }
    /// `from` may be nil to auto-detect.
    func translate(_ text: String, from: String?, to: String) async throws -> String
}

/// Extra instruction so language-model translators leave the user's names and jargon alone.
public func keepTermsInstruction(_ terms: [String]) -> String {
    terms.isEmpty ? "" : " Keep these names and terms exactly as written: " + terms.prefix(50).joined(separator: ", ") + "."
}

public enum Lang {
    /// "zh-Hans" → "zh", "en_US" → "en"
    public static func base(_ id: String) -> String {
        Locale(identifier: id).language.languageCode?.identifier ?? String(id.prefix(2))
    }
    public static func displayName(_ id: String, in ui: Locale = .current) -> String {
        ui.localizedString(forLanguageCode: base(id)) ?? id
    }
}

/// Text-based language ID (on-device NaturalLanguage). Cheap; used to confirm each sentence.
public enum TextLanguageID {
    public static func detect(_ text: String, hints: [String] = []) -> (language: String, confidence: Double)? {
        let r = NLLanguageRecognizer()
        if !hints.isEmpty { r.languageHints = Dictionary(uniqueKeysWithValues: hints.map { (NLLanguage($0), 1.0 / Double(hints.count)) }) }
        r.processString(text)
        guard let top = r.languageHypotheses(withMaximum: 1).first else { return nil }
        return (top.key.rawValue, top.value)
    }
}

#if compiler(>=6.2)
import Translation

/// Apple's on-device Translation framework (free, private). Needs the language pair downloaded
/// (System Settings → General → Language & Region → Translation Languages).
@available(macOS 26, *)
public struct AppleTranslator: Translator {
    public let name = "Apple Translation"
    public init() {}

    public static func status(from: String, to: String) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: Locale.Language(identifier: from), to: Locale.Language(identifier: to))
    }

    public func translate(_ text: String, from: String?, to: String) async throws -> String {
        let src = Locale.Language(identifier: from ?? (TextLanguageID.detect(text)?.language ?? "en"))
        let dst = Locale.Language(identifier: to)
        if Lang.base(src.minimalIdentifier) == Lang.base(dst.minimalIdentifier) { return text }
        let st = await LanguageAvailability().status(from: src, to: dst)
        guard st == .installed else {
            throw TranslationError.unavailable(st == .supported ? "Download the \(Lang.displayName(src.minimalIdentifier)) → \(Lang.displayName(to)) language pack in System Settings." : "Apple Translation doesn't support this pair.")
        }
        let session = TranslationSession(installedSource: src, target: dst)
        return try await session.translate(text).targetText
    }
}
#endif

/// Translation through any OpenAI-compatible endpoint (local Ollama or a free-tier API).
public struct LLMTranslator: Translator {
    public let name: String
    let endpoint: LLMEndpoint
    let apiKey: @Sendable () -> String?
    let keepTerms: [String]
    public init(endpoint: LLMEndpoint, apiKey: @escaping @Sendable () -> String?, keepTerms: [String] = []) {
        self.endpoint = endpoint; self.apiKey = apiKey; self.keepTerms = keepTerms; self.name = "\(endpoint.name) (LLM)"
    }
    public func translate(_ text: String, from: String?, to: String) async throws -> String {
        let sys = "You are a live interpreter. Translate the user's text into \(Lang.displayName(to, in: Locale(identifier: "en"))). Output only the translation, no notes." + keepTermsInstruction(keepTerms)
        let out = try await OpenAIClient.complete(endpoint: endpoint, apiKey: apiKey(),
            messages: [ChatMessage(role: "system", content: sys), ChatMessage(role: "user", content: text)],
            purpose: "Translate subtitle text")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Tries each translator in order; remembers failures briefly so a dead provider doesn't stall the ribbon.
public actor TranslatorChain {
    private var translators: [Translator]
    private var coolDown: [String: Date] = [:]
    private var cache: [String: String] = [:]
    public private(set) var lastUsed: String?
    public init(_ t: [Translator]) { translators = t }
    public func setTranslators(_ t: [Translator]) { translators = t; coolDown = [:]; cache = [:] }

    public func translate(_ text: String, from: String?, to: String) async -> String? {
        if let s = from, Lang.base(s) == Lang.base(to) { return nil }
        let key = "\(from ?? "?")>\(to):\(text)"
        if let hit = cache[key] { return hit }
        for t in translators {
            if let until = coolDown[t.name], until > Date() { continue }
            do {
                let out = try await t.translate(text, from: from, to: to)
                lastUsed = t.name
                if cache.count > 500 { cache.removeAll() }
                cache[key] = out
                return out
            } catch { coolDown[t.name] = Date().addingTimeInterval(30) }
        }
        return nil   // decision table: show original only
    }
}

#if compiler(>=6.2) && canImport(FoundationModels)
import FoundationModels

/// Translation with Apple's on-device language model: free, private, and needs no downloaded language packs
/// (uses the same model as the notes). Slower and less polished than a dedicated translator, so it sits after Apple Translation.
@available(macOS 26, *)
public struct AppleModelTranslator: Translator {
    public let name = "Apple on-device model"
    private let keepTerms: [String]
    public init(keepTerms: [String] = []) { self.keepTerms = keepTerms }

    /// The first call loads the model (~6 s measured); later calls take ~1.1–1.6 s. Call this when a call starts.
    public static func warmUp() async {
        guard SystemLanguageModel.default.availability == .available else { return }
        _ = try? await AppleModelTranslator().translate("Hola", from: "es", to: "en")
    }

    public func translate(_ text: String, from: String?, to: String) async throws -> String {
        guard SystemLanguageModel.default.availability == .available else { throw TranslationError.unavailable("Apple Intelligence isn't available.") }
        let target = Lang.displayName(to, in: Locale(identifier: "en"))
        let session = LanguageModelSession(instructions: "You are a live interpreter. Translate the user's text into \(target). Reply with only the translation: no quotes, no notes, no explanation." + keepTermsInstruction(keepTerms))
        let out = try await session.respond(to: text, options: GenerationOptions(temperature: 0)).content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw TranslationError.unavailable("Empty translation") }
        return out
    }
}
#endif
