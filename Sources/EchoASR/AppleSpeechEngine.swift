import Foundation
import AVFoundation
import EchoCore
#if compiler(>=6.2)
import Speech

@available(macOS 26, *)
public final class AppleSpeechEngine: ASREngine, @unchecked Sendable {
    public let name = "Apple SpeechAnalyzer"
    public let results: AsyncStream<ASRResult>
    private let cont: AsyncStream<ASRResult>.Continuation
    private var analyzer: SpeechAnalyzer?
    private var inputCont: AsyncStream<AnalyzerInput>.Continuation?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var consumer: Task<Void, Never>?
    private var samplesFed = 0

    public init() {
        var c: AsyncStream<ASRResult>.Continuation!
        results = AsyncStream { c = $0 }
        cont = c
    }

    /// Nearest Apple-supported locale for a language code such as "zh" or "en".
    public static func supportedLocale(for code: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: code))
    }

    public static func isLocaleSupported(_ locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    public func start(locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else { throw ASRError.unavailable("Speech recognition isn't available on this Mac.") }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        // Download the on-device model on first use (free, handled by the OS).
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await req.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        if let format { converter = AVAudioConverter(from: AudioFormatHelper.mono16k, to: format) }
        try? await analyzer.prepareToAnalyze(in: format)   // preload models so the first words aren't delayed
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputCont = builder
        let cont = self.cont
        consumer = Task {
            do {
                for try await r in transcriber.results {
                    let text = String(r.text.characters)
                    guard !text.isEmpty else { continue }
                    let start = r.range.start.seconds, end = r.range.end.seconds
                    cont.yield(ASRResult(text: text, isFinal: r.isFinal,
                                         start: start.isFinite ? start : 0, end: end.isFinite ? end : 0,
                                         language: locale.language.languageCode?.identifier))
                }
            } catch { }
            cont.finish()
        }
        try await analyzer.start(inputSequence: stream)
    }

    public func append(_ samples: [Float]) {
        guard let inputCont, !samples.isEmpty else { return }
        let src = AudioFormatHelper.mono16k
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        var out = inBuf
        if let format, let converter, format != src {
            let ratio = format.sampleRate / src.sampleRate
            guard let o = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(samples.count) * ratio) + 64) else { return }
            var supplied = false
            converter.convert(to: o, error: nil) { _, st in
                if supplied { st.pointee = .noDataNow; return nil }
                supplied = true; st.pointee = .haveData; return inBuf
            }
            out = o
        }
        inputCont.yield(AnalyzerInput(buffer: out))
    }

    public func finish() async {
        inputCont?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await consumer?.value
    }
}
#endif

enum AudioFormatHelper {
    static let mono16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
}
