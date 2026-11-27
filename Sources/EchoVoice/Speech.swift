import AVFoundation
import CoreAudio

/// Text-to-speech with the built-in macOS voices (free). Optionally plays into a chosen output device (BlackHole).
public final class SpeechPlayer: NSObject, @unchecked Sendable {
    private var engine: AVAudioEngine?
    private let lock = NSLock()

    public override init() { super.init() }

    /// Renders speech to PCM buffers (no audio device involved). Used by playback and by the latency check.
    /// Best installed voice for a language: Premium > Enhanced > default (download better ones in System Settings → Accessibility → Spoken Content).
    public static func bestVoice(for language: String, defaults: UserDefaults = .standard) -> AVSpeechSynthesisVoice? {
        let base = String(language.prefix(2))
        if let id = defaults.string(forKey: voiceKey(base)), let v = AVSpeechSynthesisVoice(identifier: id), v.language.hasPrefix(base) { return v }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) || $0.language.hasPrefix(base) }
        let exact = candidates.filter { $0.language == language }
        let pool = exact.isEmpty ? candidates : exact
        let region = Locale.current.region?.identifier ?? "US"
        func score(_ v: AVSpeechSynthesisVoice) -> Int {   // quality first, then the user's own region, then en-US
            v.quality.rawValue * 100 + (v.language.hasSuffix("-" + region) ? 10 : 0) + (v.language == "en-US" ? 5 : 0)
        }
        return pool.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: language)
    }

    public static func voiceKey(_ language: String) -> String { "voice." + String(language.prefix(2)) }

    /// Installed voices for a language, best first. Your own "Personal Voice" (made in System Settings → Accessibility)
    /// is listed once you allow it; it only speaks the languages it was recorded in.
    public static func voices(for language: String) -> [(id: String, name: String)] {
        let base = String(language.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(base) }
            .sorted { ($0.voiceTraits.contains(.isPersonalVoice) ? 10 : $0.quality.rawValue, $1.name) > ($1.voiceTraits.contains(.isPersonalVoice) ? 10 : $1.quality.rawValue, $0.name) }
            .map { v in
                let tag = v.voiceTraits.contains(.isPersonalVoice) ? " · your own voice" : (v.quality == .premium ? " · Premium" : v.quality == .enhanced ? " · Enhanced" : "")
                return (v.identifier, "\(v.name) (\(v.language))\(tag)")
            }
    }

    /// Asks macOS to let Chitter use your Personal Voice. Returns a message for the user.
    public static func requestPersonalVoice() async -> String {
        let status = await withCheckedContinuation { c in AVSpeechSynthesizer.requestPersonalVoiceAuthorization { c.resume(returning: $0) } }
        switch status {
        case .authorized:
            let mine = AVSpeechSynthesisVoice.speechVoices().filter { $0.voiceTraits.contains(.isPersonalVoice) }
            return mine.isEmpty ? "Allowed. No Personal Voice exists yet: create one in System Settings → Accessibility → Personal Voice."
                : "Allowed. Pick \(mine[0].name) in the voice menu."
        case .denied: return "macOS denied access. Allow apps to use Personal Voice in System Settings → Accessibility → Personal Voice."
        case .unsupported: return "This Mac doesn't support Personal Voice."
        default: return "Access wasn't granted."
        }
    }

    public func synthesize(_ text: String, language: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) async -> [AVAudioPCMBuffer] {
        await withCheckedContinuation { (c: CheckedContinuation<[AVAudioPCMBuffer], Never>) in
            let utt = AVSpeechUtterance(string: text)
            utt.voice = Self.bestVoice(for: language)
            utt.rate = rate
            var out: [AVAudioPCMBuffer] = []; var done = false
            let synth = AVSpeechSynthesizer()          // one per call so clips can be prepared in parallel
            synth.write(utt) { buf in
                _ = synth
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
