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
                Circle().stroke(Tokens.weld.color.opacity(0.25), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(min(1, m.level * 12)))
                    .stroke(Tokens.weld.color, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Circle().fill(m.active ? Tokens.madder.color : Tokens.woad.color).padding(14)
                Image(systemName: "mic.fill").foregroundStyle(Tokens.textLight.color)
            }.frame(width: 64, height: 64).accessibilityHidden(true)
            Text(m.state).font(.caption).foregroundStyle(Tokens.textLight.color)
            if !m.route.isEmpty { Text(m.route).font(.caption2).foregroundStyle(Tokens.textLight.color.opacity(0.75)) }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 16).fill(Tokens.ink.color.opacity(0.92)))
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

    init(translators: TranslatorChain) { self.translators = translators }

    // MARK: enable / disable
    func enable() async -> String? {
        guard await MicRecorder.requestAccess() else { return "Microphone access is needed to interpret your voice. Allow it in System Settings → Privacy & Security → Microphone." }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }   // Input Monitoring, requested only now
        installMonitors()
        enabled = true
        model.route = AudioDevices.blackHole() == nil ? "BlackHole not installed — you'll hear it locally" : "Routing to BlackHole 2ch"
        showPanel(true)
        return nil
    }
    func disable() { monitors.forEach(NSEvent.removeMonitor); monitors = []; enabled = false; router.restore(); showPanel(false) }
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
        mic.onLevel = { [weak self] l in Task { @MainActor in self?.model.level = l } }
        do { try mic.start(); model.active = true; model.state = "Listening…" }
        catch { model.state = "Mic error: \(error.localizedDescription)" }
    }

    private func endSpeaking() {
        let samples = mic.stop(); model.active = false; model.level = 0
        guard samples.count > 6_400 else { model.state = "Too short — hold the key while you talk"; return }
        model.state = "Interpreting…"
        Task { await process(samples) }
    }

    // MARK: pipeline
    func process(_ samples: [Float]) async {
        let t0 = Date()
        let from = Prefs.speakLanguage, to = Prefs.interpretTarget
        guard let text = await Self.recognize(samples, language: from), !text.isEmpty else { model.state = "Didn't catch that"; return }
        let tASR = Date().timeIntervalSince(t0)
        let translated = await translators.translate(text, from: from, to: to) ?? text
        let tTr = Date().timeIntervalSince(t0)
        let buffers = await player.synthesize(translated, language: to)
        let tTTS = Date().timeIntervalSince(t0)
        lastLatency = tTTS
        model.state = "“\(translated)”"
        let bh = AudioDevices.blackHole()
        if bh != nil { router.routeToBlackHole() }
        await player.play(buffers, deviceID: bh?.id)
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
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 130), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.isMovableByWindowBackground = true
            p.sharingType = .none
            p.contentView = NSHostingView(rootView: VoiceKnotView(m: model))
            if let f = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: f.maxX - 250, y: f.minY + 40)) }
            panel = p
        }
        show ? panel?.orderFrontRegardless() : panel?.orderOut(nil)
    }
}
