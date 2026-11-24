import AVFoundation
import EchoAudio

/// Records the microphone to 16 kHz mono while push-to-talk is held.
public final class MicRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let resampler = AudioResampler()
    private var samples: [Float] = []
    private let lock = NSLock()
    public private(set) var isRecording = false
    public var onLevel: (@Sendable (Float) -> Void)?

    public init() {}

    public static func authorization() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    public static func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    public func start() throws {
        guard !isRecording else { return }
        samples = []
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in
            guard let self else { return }
            let s = self.resampler.convert(buf)
            self.lock.lock(); self.samples += s; self.lock.unlock()
            self.onLevel?(EnergyVAD.rms(s))
        }
        try engine.start(); isRecording = true
    }

    public func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0); engine.stop(); isRecording = false
        lock.lock(); defer { lock.unlock() }
        return samples
    }
}
