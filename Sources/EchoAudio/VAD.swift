import Foundation

public enum SpeechActivity: Sendable { case started, ended }

/// Energy-based voice activity detector with hysteresis. Feed 16 kHz mono samples.
public struct EnergyVAD: Sendable {
    public var startThreshold: Float
    public var endThreshold: Float
    public var hangoverSeconds: Double
    public private(set) var isSpeaking = false
    private var silentFor: Double = 0
    private let sampleRate: Double

    public init(startThreshold: Float = 0.012, endThreshold: Float = 0.006,
                hangoverSeconds: Double = 0.6, sampleRate: Double = 16_000) {
        self.startThreshold = startThreshold; self.endThreshold = endThreshold
        self.hangoverSeconds = hangoverSeconds; self.sampleRate = sampleRate
    }

    public static func rms(_ s: [Float]) -> Float {
        guard !s.isEmpty else { return 0 }
        var acc: Float = 0
        for x in s { acc += x * x }
        return (acc / Float(s.count)).squareRoot()
    }

    /// Returns a transition if the chunk changed state.
    public mutating func process(_ chunk: [Float]) -> SpeechActivity? {
        let level = Self.rms(chunk)
        let dur = Double(chunk.count) / sampleRate
        if !isSpeaking {
            if level >= startThreshold { isSpeaking = true; silentFor = 0; return .started }
        } else {
            if level < endThreshold {
                silentFor += dur
                if silentFor >= hangoverSeconds { isSpeaking = false; silentFor = 0; return .ended }
            } else { silentFor = 0 }
        }
        return nil
    }
}
