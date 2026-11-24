import Foundation
import EchoCore
import EchoAudio
import WhisperKit
import NaturalLanguage

/// Pseudo-streaming Whisper: re-decodes the growing current utterance about once a second (partials),
/// and emits a final when the energy VAD detects an utterance end or the utterance reaches 25 s.
public final class WhisperKitEngine: ASREngine, @unchecked Sendable {
    public let name: String
    public let results: AsyncStream<ASRResult>
    private let cont: AsyncStream<ASRResult>.Continuation
    private let model: String
    private var pipe: WhisperKit?
    private var language: String?
    private let lock = NSLock()
    private var utterance: [Float] = []
    private var utteranceStart: TimeInterval = 0
    private var total = 0
    private var vad = EchoAudio.EnergyVAD()
    private var lastDecodeAt = 0
    private var decoding = false
    private var pending: Task<Void, Never>?

    private let autodetect: Bool

    /// `autodetect: true` lets Whisper identify the language of every utterance (mixed-language calls).
    public init(model: String = "base", autodetect: Bool = false) {
        self.model = model; self.autodetect = autodetect
        self.name = "WhisperKit (\(model))"
        var c: AsyncStream<ASRResult>.Continuation!
        results = AsyncStream { c = $0 }
        cont = c
    }

    public func start(locale: Locale) async throws {
        language = autodetect ? nil : locale.language.languageCode?.identifier
        var cfg = WhisperKitConfig(model: model)
        cfg.verbose = false
        cfg.logLevel = .none
        do { pipe = try await WhisperKit(cfg) }
        catch {
            // Decision table: retry with a smaller model, then surface "offline model missing".
            if model != "tiny" { pipe = try await WhisperKit(WhisperKitConfig(model: "tiny")) }
            else { throw ASRError.unavailable("The offline speech model is missing and couldn't be downloaded. Check your connection and retry.") }
        }
        await warmUp()
    }

    /// Runs one throwaway decode so CoreML finishes specialising before the first real utterance.
    private func warmUp() async {
        guard let pipe else { return }
        var o = DecodingOptions(); o.language = language; o.withoutTimestamps = true
        _ = try? await pipe.transcribe(audioArray: [Float](repeating: 0.001, count: 16_000), decodeOptions: o)
    }

    public func append(_ samples: [Float]) {
        lock.lock()
        let activity = vad.process(samples)
        let wasSpeaking = vad.isSpeaking
        if utterance.isEmpty && (activity == .started) { utteranceStart = Double(total) / 16_000 }
        if wasSpeaking || activity == .ended || !utterance.isEmpty { utterance += samples }
        total += samples.count
        let len = utterance.count
        let dueFinal = (activity == .ended && len > 0) || len > 25 * 16_000
        let duePartial = wasSpeaking && len - lastDecodeAt >= 8_000 && len >= 11_200 && !decoding
        if dueFinal {
            let audio = utterance, start = utteranceStart
            utterance = []; lastDecodeAt = 0
            lock.unlock()
            let prev = pending
            pending = Task { await prev?.value; await self.decode(audio, start: start, final: true) }
            return
        }
        if duePartial {
            decoding = true; lastDecodeAt = len
            let audio = utterance, start = utteranceStart
            lock.unlock()
            Task { await self.decode(audio, start: start, final: false); self.endDecode() }
            return
        }
        lock.unlock()
    }

    private func endDecode() { lock.lock(); decoding = false; lock.unlock() }
    private func takeRemaining() -> ([Float], TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        let r = (utterance, utteranceStart); utterance = []; return r
    }

    /// Languages Whisper "detects" by mistake on real call audio (Spanish → Latin is the classic one).
    static let implausible: Set<String> = ["la", "nn", "sn", "yo", "haw", "mi", "ln", "jw", "su", "br", "oc", "gl", "tl", "mg", "ba", "tt"]
    static let candidates = ["es", "pt", "it", "fr", "de", "en"]

    private func decodeOnce(_ audio: [Float], language: String?) async -> (text: String, language: String?)? {
        guard let pipe else { return nil }
        var opts = DecodingOptions()
        opts.language = language
        opts.detectLanguage = language == nil
        opts.withoutTimestamps = true
        opts.skipSpecialTokens = true
        guard let res = try? await pipe.transcribe(audioArray: audio, decodeOptions: opts).first else { return nil }
        return (res.text.trimmingCharacters(in: .whitespacesAndNewlines), res.language)
    }

    private func decode(_ audio: [Float], start: TimeInterval, final: Bool) async {
        guard pipe != nil, audio.count > 4_000, var best = await decodeOnce(audio, language: language) else { return }
        // Auto-detect safeguard: if the detected language is implausible, retry the likely ones and keep the text
        // that actually reads as its language.
        if autodetect, final, let l = best.language, Self.implausible.contains(l) {
            var bestScore = -1.0
            for cand in Self.candidates {
                guard let r = await decodeOnce(audio, language: cand), !r.text.isEmpty else { continue }
                let rec = NLLanguageRecognizer(); rec.processString(r.text)
                let score = rec.languageHypotheses(withMaximum: 5)[NLLanguage(cand)] ?? 0
                if score > bestScore { bestScore = score; best = (r.text, cand) }
            }
        }
        guard !best.text.isEmpty else { return }
        cont.yield(ASRResult(text: best.text, isFinal: final, start: start, end: start + Double(audio.count) / 16_000, language: best.language))
    }

    public func finish() async {
        let (audio, start) = takeRemaining()
        await pending?.value
        if !audio.isEmpty { await decode(audio, start: start, final: true) }
        cont.finish()
    }
}
