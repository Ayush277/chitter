import Foundation
import WhisperKit

/// On-device spoken-language ID from the first seconds of audio (Whisper `tiny`, ~40 MB, downloaded on demand).
public final class AudioLanguageDetector: @unchecked Sendable {
    private var pipe: WhisperKit?
    private let model: String
    public init(model: String = "tiny") { self.model = model }

    public func prepare() async throws {
        var cfg = WhisperKitConfig(model: model); cfg.verbose = false; cfg.logLevel = .none
        pipe = try await WhisperKit(cfg)
    }

    /// Returns a language code ("en", "zh", …) and probability.
    /// Pass `candidates` (the user's languages) to avoid look-alike mistakes such as Spanish → Latin.
    public func detect(_ samples: [Float], candidates: [String] = []) async -> (language: String, probability: Float)? {
        guard let pipe, samples.count >= 8_000 else { return nil }
        guard let r = try? await pipe.detectLangauge(audioArray: samples) else { return nil }
        if !candidates.isEmpty,
           let best = r.langProbs.filter({ candidates.contains($0.key) }).max(by: { $0.value < $1.value }) {
            return (best.key, best.value)
        }
        return (r.language, r.langProbs[r.language] ?? 0)
    }
}
