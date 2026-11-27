import AppKit
import SwiftUI
import AVFoundation
import EchoCore
import EchoAudio
import EchoASR
import EchoLang
import EchoVoice
import EchoUI

@MainActor
final class KnotModel: ObservableObject {
    @Published var level: Float = 0
    @Published var state = "Hold right ⌥ to speak"
    @Published var route = ""
    @Published var active = false
}

struct VoiceKnotView: View {
    @ObservedObject var m: KnotModel
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Tokens.cyan.color.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(min(1, m.level * 12)))
                    .stroke(Tokens.cyan.color, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                    .shadow(color: Tokens.cyan.color.opacity(0.9), radius: 6)
                Circle().fill(m.active ? Tokens.magenta.color : Tokens.raised.color).padding(14)
                    .shadow(color: m.active ? Tokens.magenta.color.opacity(0.9) : .clear, radius: 10)
                Image(systemName: "mic.fill").foregroundStyle(m.active ? Tokens.black.color : Tokens.cyan.color)
            }.frame(width: 64, height: 64).accessibilityHidden(true)
            Text(m.state).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(Tokens.text.color)
            if !m.route.isEmpty { Text(m.route).font(.caption2).foregroundStyle(Tokens.textDim.color) }
        }
        .padding(12).neonCard(m.active ? Tokens.magenta.color : Tokens.cyan.color, radius: Tokens.Radius.panel, fill: Tokens.black.color.opacity(0.93))
        .padding(8)
        .accessibilityElement(children: .combine).accessibilityLabel("Interpreter. \(m.state). \(m.route)")
    }
}

/// F11: hold right ⌥ → record mic → ASR → translate → TTS → BlackHole 2ch. Restores the original mic when done / on quit.
@MainActor
final class Interpreter {
    let model = KnotModel()
    private let mic = MicRecorder(), player = SpeechPlayer(), router = MicRouter()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var optionDown = false
    private(set) var enabled = false
    var translators: TranslatorChain
    private(set) var lastLatency: Double?
    /// true while the interpreter is listening to you, so meeting captions don't transcribe the same words twice.
    var onCapture: ((Bool) -> Void)?
    /// (what you said, what was spoken into the call)
    var onInterpreted: ((String, String) -> Void)?
    private let segments = SegmenterBox()
    private var queue: Task<Void, Never>?
    private(set) var handsFree = false

    init(translators: TranslatorChain) { self.translators = translators }

    // MARK: enable / disable
    func enable() async -> String? {
        guard await MicRecorder.requestAccess() else { return "Microphone access is needed to interpret your voice. Allow it in System Settings → Privacy & Security → Microphone." }
        enabled = true
        if Prefs.handsFree {
            if let problem = startHandsFree() { enabled = false; return problem }
        } else {
            if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }   // Input Monitoring, requested only now
            installMonitors()
            model.state = "Hold right ⌥ to speak"
        }
        model.route = AudioDevices.blackHole() == nil ? "BlackHole not installed — you'll hear it locally" : "Routing to BlackHole 2ch"
        showPanel(true)
        return nil
    }
    func disable() {
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        if handsFree || optionDown { _ = mic.stop() }
        mic.onSamples = nil; segments.reset(); handsFree = false; optionDown = false
        enabled = false; model.active = false; onCapture?(false); router.restore(); showPanel(false)
    }
    /// Applies a changed setting (hold-to-talk ↔ hands-free) while interpreting is on.
    func reconfigure() async -> String? { guard enabled else { return nil }; disable(); return await enable() }

    /// No key to hold: the mic stays open and each sentence is sent after a 1-second pause.
    private func startHandsFree() -> String? {
        segments.reset()
        mic.keepSamples = false
        mic.onLevel = { [weak self] l in Task { @MainActor in self?.model.level = l } }
        mic.onSamples = { [weak self, segments] chunk in
            guard let utterance = segments.feed(chunk) else { return }
            Task { @MainActor in self?.enqueue(utterance) }
        }
        do { try mic.start() } catch { return "Couldn't open the microphone: \(error.localizedDescription)" }
        handsFree = true; model.active = true; model.state = "Hands-free: just talk"
        onCapture?(true)
        return nil
    }

    /// Utterances are interpreted strictly in the order they were spoken.
    private func enqueue(_ samples: [Float]) {
        let previous = queue
        queue = Task { [weak self] in await previous?.value; await self?.process(samples) }
    }
    func shutdown() { disable() }       // called on quit → mic restored

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] e in
            guard e.keyCode == 61 else { return }            // right ⌥
            let down = e.modifierFlags.contains(.option)
            Task { @MainActor in self?.optionChanged(down) }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in handler(e); return e }) { monitors.append(l) }
    }

    private func optionChanged(_ down: Bool) {
        guard enabled, down != optionDown else { return }
        optionDown = down
        down ? beginSpeaking() : endSpeaking()
    }

    private func beginSpeaking() {
        onCapture?(true)
        mic.keepSamples = true; mic.onSamples = nil
        mic.onLevel = { [weak self] l in Task { @MainActor in self?.model.level = l } }
        do { try mic.start(); model.active = true; model.state = "Listening…" }
        catch { model.state = "Mic error: \(error.localizedDescription)" }
    }

    private func endSpeaking() {
        let samples = mic.stop(); model.active = false; model.level = 0
        guard samples.count > 6_400 else { model.state = "Too short — hold the key while you talk"; onCapture?(false); return }
        model.state = "Interpreting…"
        enqueue(samples)
    }

    // MARK: pipeline
    func process(_ samples: [Float]) async {
        let t0 = Date()
        let from = Prefs.speakLanguage, to = Prefs.interpretTarget
        defer { if !handsFree && !optionDown { onCapture?(false) } }
        guard let heard = await Self.recognize(samples, language: from), !heard.isEmpty else { model.state = "Didn't catch that"; return }
        let text = Prefs.wordList.apply(to: heard)
        let tASR = Date().timeIntervalSince(t0)
        let result = await translators.translate(text, from: from, to: to)
        // Never send your words untranslated into the call by accident.
        guard let translated = result ?? (Lang.base(from) == Lang.base(to) ? text : nil) else { model.state = "Translation unavailable, so nothing was sent"; return }
        let tTr = Date().timeIntervalSince(t0)
        let buffers = await player.synthesize(translated, language: to)
        let tTTS = Date().timeIntervalSince(t0)
        lastLatency = tTTS
        model.state = "“\(translated)”"
        let bh = AudioDevices.blackHole()
        if bh != nil && Prefs.switchSystemMic { router.routeToBlackHole() }
        onInterpreted?(text, translated)
        segments.muted = true            // don't re-interpret our own voice if it reaches the mic
        await player.play(buffers, deviceID: bh?.id)
        segments.muted = false
        router.restore()                 // original mic comes back right after playback
        model.state = String(format: "Done in %.1fs (ASR %.1f · translate %.1f · voice %.1f)", tTTS, tASR, tTr - tASR, tTTS - tTr)
    }

    /// Batch recognition of one utterance.
    static func recognize(_ samples: [Float], language: String) async -> String? {
        let engine = ASRFactory.make(preferWhisper: Prefs.preferWhisper)
        let locale = await localeFor(language)
        do { try await engine.start(locale: locale) } catch { return nil }
        var finals: [String] = []
        let consumer = Task { for await r in engine.results where r.isFinal { finals.append(r.text) } }
        var i = 0
        while i < samples.count { engine.append(Array(samples[i..<min(i + 3_200, samples.count)])); i += 3_200 }
        for _ in 0..<12 { engine.append([Float](repeating: 0, count: 1_600)) }
        await engine.finish(); await consumer.value
        return finals.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
    static func localeFor(_ code: String) async -> Locale {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !Prefs.preferWhisper, let l = await AppleSpeechEngine.supportedLocale(for: code) { return l }
        #endif
        return Locale(identifier: code)
    }

    // MARK: HUD
    private func showPanel(_ show: Bool) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 270, height: 190), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false      // the card draws its own glow
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.isMovableByWindowBackground = true
            p.sharingType = .none
            p.contentView = NSHostingView(rootView: VoiceKnotView(m: model))
            if let f = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: f.maxX - 300, y: f.minY + 40)) }
            panel = p
        }
        show ? panel?.orderFrontRegardless() : panel?.orderOut(nil)
    }
}

/// Lets the audio thread feed the hands-free segmenter safely.
final class SegmenterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var segmenter = UtteranceSegmenter(pauseSeconds: 1.0)
    private var isMuted = false
    var muted: Bool {
        get { lock.lock(); defer { lock.unlock() }; return isMuted }
        set { lock.lock(); isMuted = newValue; segmenter.reset(); lock.unlock() }
    }
    func feed(_ chunk: [Float]) -> [Float]? { lock.lock(); defer { lock.unlock() }; return isMuted ? nil : segmenter.feed(chunk) }
    func reset() { lock.lock(); segmenter.reset(); isMuted = false; lock.unlock() }
}
