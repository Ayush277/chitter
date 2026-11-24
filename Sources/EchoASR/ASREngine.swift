import Foundation
import EchoCore

public enum ASRError: Error, CustomStringConvertible {
    case unavailable(String)
    public var description: String { if case .unavailable(let s) = self { return s }; return "ASR error" }
}

/// A streaming speech recognizer. Feed 16 kHz mono Float32 samples; read partial + final results.
public protocol ASREngine: AnyObject, Sendable {
    var name: String { get }
    var results: AsyncStream<ASRResult> { get }
    func start(locale: Locale) async throws
    func append(_ samples: [Float])
    func finish() async
}

public enum ASRFactory {
    /// Apple SpeechAnalyzer on macOS 26+ when this build has the SDK for it, otherwise WhisperKit.
    public static func makeDefault(whisperModel: String = "base") -> ASREngine {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return AppleSpeechEngine() }
        #endif
        return WhisperKitEngine(model: whisperModel)
    }
    /// Per-utterance language detection: right for calls where different people speak different languages.
    public static func makeMultilingual(whisperModel: String = "base") -> ASREngine { WhisperKitEngine(model: whisperModel, autodetect: true) }
    public static func make(preferWhisper: Bool, whisperModel: String = "base") -> ASREngine {
        preferWhisper ? WhisperKitEngine(model: whisperModel) : makeDefault(whisperModel: whisperModel)
    }
}
