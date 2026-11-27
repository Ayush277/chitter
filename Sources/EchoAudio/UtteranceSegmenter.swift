import Foundation

/// Hands-free interpreting: cuts a live microphone stream into utterances, ending one after a pause.
public struct UtteranceSegmenter: Sendable {
    private var vad: EnergyVAD
    private var preRoll: [Float] = []
    private var current: [Float] = []
    private var voiced = 0
    private let rate = 16_000
    public var minVoicedSeconds = 0.35
    public var maxSeconds = 20.0

    public init(pauseSeconds: Double = 1.0) { vad = EnergyVAD(hangoverSeconds: pauseSeconds) }

    /// Feed 16 kHz mono chunks. Returns a finished utterance when the speaker pauses (or talks for `maxSeconds`).
    public mutating func feed(_ chunk: [Float]) -> [Float]? {
        let activity = vad.process(chunk)
        if vad.isSpeaking || activity == .ended || !current.isEmpty {
            if current.isEmpty { current = preRoll; preRoll = [] }
            current += chunk
            if EnergyVAD.rms(chunk) >= vad.endThreshold { voiced += chunk.count }
        } else {
            preRoll += chunk
            if preRoll.count > rate * 3 / 10 { preRoll.removeFirst(preRoll.count - rate * 3 / 10) }
        }
        guard activity == .ended || Double(current.count) / Double(rate) >= maxSeconds else { return nil }
        let out = current, spoken = Double(voiced) / Double(rate)
        current = []; voiced = 0
        return spoken >= minVoicedSeconds ? out : nil      // coughs and clicks are ignored
    }

    public mutating func reset() {
        current = []; preRoll = []; voiced = 0
        vad = EnergyVAD(hangoverSeconds: vad.hangoverSeconds)
    }
}
