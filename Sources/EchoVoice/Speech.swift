import AVFoundation
import CoreAudio

/// Text-to-speech with the built-in macOS voices (free). Optionally plays into a chosen output device (BlackHole).
public final class SpeechPlayer: NSObject, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private let lock = NSLock()

    public override init() { super.init() }

    /// Renders speech to PCM buffers (no audio device involved). Used by playback and by the latency check.
    public func synthesize(_ text: String, language: String) async -> [AVAudioPCMBuffer] {
        await withCheckedContinuation { (c: CheckedContinuation<[AVAudioPCMBuffer], Never>) in
            let utt = AVSpeechUtterance(string: text)
            utt.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: String(language.prefix(2)))
            var out: [AVAudioPCMBuffer] = []; var done = false
            synth.write(utt) { buf in
                guard let pcm = buf as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 { if !done { done = true; c.resume(returning: out) } }
                else { out.append(pcm) }
            }
        }
    }

    /// Plays buffers to `deviceID` (nil = system output). Returns when finished.
    public func play(_ buffers: [AVAudioPCMBuffer], deviceID: AudioDeviceID?) async {
        guard let first = buffers.first else { return }
        let engine = AVAudioEngine(); let node = AVAudioPlayerNode()
        engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: first.format)
        if let deviceID, let au = engine.outputNode.audioUnit {
            var d = deviceID
            AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &d, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        setEngine(engine)
        do { try engine.start() } catch { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            for (i, b) in buffers.enumerated() {
                if i == buffers.count - 1 { node.scheduleBuffer(b, completionCallbackType: .dataPlayedBack) { _ in c.resume() } }
                else { node.scheduleBuffer(b, completionHandler: nil) }
            }
            node.play()
        }
        engine.stop()
    }

    private func setEngine(_ e: AVAudioEngine) { lock.lock(); engine = e; lock.unlock() }
    public func stop() { lock.lock(); engine?.stop(); lock.unlock() }
}
