import AVFoundation
import EchoAudio

/// Records the microphone to 16 kHz mono while push-to-talk is held.
public final class MicRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let resampler = AudioResampler()
    private var samples: [Float] = []
    private let lock = NSLock()
    public private(set) var isRecording = false
    public var keepSamples = true
    public var onLevel: (@Sendable (Float) -> Void)?
    /// Called with each 16 kHz mono chunk while recording (used to caption your own voice live).
    public var onSamples: (@Sendable ([Float]) -> Void)?

    public init() {}

    public static func authorization() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    public static func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    public func start() throws {
        guard !isRecording else { return }
        samples = []
        let input = engine.inputNode
        if let device = AudioDevices.recordingDevice(preferredUID: UserDefaults.standard.string(forKey: "micDeviceUID") ?? "",
                                                     devices: AudioDevices.all(), uidOf: AudioDevices.uid, systemDefault: AudioDevices.defaultInput()),
           let unit = input.audioUnit {
            var id = device
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let fmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in
            guard let self else { return }
            let s = self.resampler.convert(buf)
            self.lock.lock()
            if self.keepSamples { self.samples += s }       // off for open-ended streams so memory doesn't grow
            self.lock.unlock()
            self.onLevel?(EnergyVAD.rms(s)); self.onSamples?(s)
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
