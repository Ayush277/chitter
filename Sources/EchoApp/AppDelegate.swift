import EchoCore
import AppKit
import EchoAudio
import Carbon.HIToolbox
import EchoVoice
import SwiftUI
import EchoUI
import EchoNet
import EchoNotes
import EchoLang

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var session: SessionController!
    private var startItem: NSMenuItem!
    private var interpretItem: NSMenuItem!
    let callWatcher = CallWatcher()
    let settingsModel = SettingsModel()
    let ledgerModel = LedgerModel()
    let onboardingModel = OnboardingModel()
    var settingsWindow: HostedWindow!, ledgerWindow: HostedWindow!, onboardingWindow: HostedWindow!

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)      // the theme is black only; menus and alerts follow
        session = SessionController()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.setAccessibilityLabel("Chitter")
        let menu = NSMenu()
        startItem = NSMenuItem(title: "Start listening", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(startItem)
        menu.addItem(NSMenuItem(title: L("Privacy Ledger…"), action: #selector(openLedger), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Settings…"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L("Welcome tour"), action: #selector(openWelcome), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Live transcript panel  (⌃⌥L)", action: #selector(toggleLivePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Notes  (⌃⌥N)", action: #selector(openNotes), keyEquivalent: ""))
        interpretItem = NSMenuItem(title: "Interpret my voice", action: #selector(toggleInterpret), keyEquivalent: "")
        menu.addItem(interpretItem)
        menu.addItem(NSMenuItem(title: L("Try the sample meeting"), action: #selector(playSample), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit Chitter"), action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        settingsModel.onSubtitleModeChange = { [weak self] mode in self?.session.ribbonModel.mode = mode; self?.session.livePanel.model.mode = mode }
        settingsModel.onInterpretModeChange = { [weak self] in
            Task { @MainActor in
                guard let self, let problem = await self.session.interpreter.reconfigure() else { return }
                self.interpretItem.state = .off; self.settingsModel.voiceMessage = problem
            }
        }
        settingsModel.micProvider = { AudioDevices.microphones() }
        settingsModel.voiceProvider = { SpeechPlayer.voices(for: $0) }
        settingsModel.previewVoice = { [weak self] language in self?.previewVoice(language) }
        settingsModel.requestPersonalVoice = { await SpeechPlayer.requestPersonalVoice() }
        settingsModel.setupProvider = { Self.interpreterSetup() }
        session.wireInterpreter()
        let health: () async -> [EngineHealth] = { [weak self] in await self?.engineHealth() ?? [] }
        settingsModel.healthProvider = health
        settingsModel.onAccessibilityChange = { [weak self] on in self?.session.ribbonModel.accessibilityMode = on; self?.session.notesVM.accessibilityMode = on }
        session.notesVM.accessibilityMode = Prefs.accessibilityMode
        onboardingModel.loadHealth = health
        onboardingModel.requestAudio = { await Self.probeSystemAudio() }
        onboardingModel.playSample = { [weak self] in Task { await self?.session.playSample() } }
        onboardingModel.finish = { [weak self] in Prefs.onboarded = true; self?.onboardingWindow.close() }
        settingsWindow = HostedWindow(title: "Chitter Settings", size: NSSize(width: 660, height: 500)) { [unowned self] in AnyView(SettingsView(model: self.settingsModel)) }
        ledgerWindow = HostedWindow(title: "Privacy Ledger", size: NSSize(width: 900, height: 520)) { [unowned self] in AnyView(LedgerView(model: self.ledgerModel)) }
        onboardingWindow = HostedWindow(title: "Welcome to Chitter", size: NSSize(width: 600, height: 520)) { [unowned self] in AnyView(OnboardingView(model: self.onboardingModel, settings: self.settingsModel)) }
        callWatcher.onStart = { [weak self] info in Task { @MainActor in self?.session.callStarted(info) } }
        callWatcher.onEnd = { [weak self] in Task { @MainActor in self?.session.callEnded() } }
        callWatcher.start()      // polls Core Audio every 2 s (cheap); the Prefs toggle decides whether to act
        if ProcessInfo.processInfo.environment["CHITTER_BENCH_EXIT"] != nil { exit(0) }   // cold-start benchmark
        if !Prefs.onboarded { onboardingWindow.show() }
        session.onStateChange = { [weak self] in self?.refresh() }
        refresh()
        // QA: `--snapshot-ui <folder>` draws every window with demo data into PNGs, then quits.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-ui"), i + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[i + 1]
            Task { await self.snapshotDemo(into: dir); NSApp.terminate(nil) }
        }
        // QA: `--listen <seconds>` runs a real meeting on live system audio, then quits and prints where it was saved.
        if let i = CommandLine.arguments.firstIndex(of: "--listen"), i + 1 < CommandLine.arguments.count, let secs = Double(CommandLine.arguments[i + 1]) {
            Task {
                await self.session.start(title: "QA live check")
                print("listening: \(self.session.status)"); fflush(stdout)
                self.session.livePanel.show()
                try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                if let dir = CommandLine.arguments.firstIndex(of: "--snapshot").map({ CommandLine.arguments[$0 + 1] }) { self.snapshot(into: dir) }
                let saved = self.session.meeting?.dir.path ?? ""
                self.session.stop()
                try? await Task.sleep(nanoseconds: 30_000_000_000)      // final notes
                print("saved: \(saved)"); fflush(stdout)
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--sample") { Task { await self.session.playSample() } }   // used by QA scripts
        Hotkeys.shared.register(keyCode: kVK_ANSI_R, id: 1) { [weak self] in MainActor.assumeIsolated { self?.session.toggleListening() } }
        Hotkeys.shared.register(keyCode: kVK_ANSI_N, id: 3) { [weak self] in MainActor.assumeIsolated { self?.openNotes() } }
        Hotkeys.shared.register(keyCode: kVK_ANSI_L, id: 4) { [weak self] in MainActor.assumeIsolated { self?.session.livePanel.toggle() } }
        Hotkeys.shared.register(keyCode: kVK_ANSI_S, id: 2) { [weak self] in MainActor.assumeIsolated { self?.session.toggleRibbon() } }
    }

    @MainActor func refresh() {
        let listening = session.isListening
        let name = listening ? "waveform.circle.fill" : "waveform.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: listening ? "Chitter, listening" : "Chitter, idle")
        startItem.title = listening ? L("Stop listening  (⌃⌥R)") : L("Start listening  (⌃⌥R)")
    }

    /// QA: draws Chitter's own views into PNG files (no screen recording needed, nothing else on screen is captured).
    @MainActor func save<V: View>(_ view: V, _ size: NSSize, _ name: String, into dir: String) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color.black))
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size), styleMask: [.titled], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = host; w.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        w.orderOut(nil)
    }

    @MainActor func snapshot(into dir: String) {
        for tab in ["languages", "interpreting", "words", "engines"] {
            settingsModel.tab = tab
            save(SettingsView(model: settingsModel), NSSize(width: 730, height: 560), "settings-\(tab).png", into: dir)
        }
        save(session.livePanel.snapshotView(), NSSize(width: 340, height: 480), "live-panel.png", into: dir)
    }

    /// Demo content only (a throwaway meeting folder), so no real meeting ever appears in these pictures.
    @MainActor func snapshotDemo(into dir: String) async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chitter-demo-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let lines = [Segment(id: 1, start: 3, end: 7, text: "Hemos decidido lanzar el viernes.", translation: "We have decided to launch on Friday.", language: "es"),
                     Segment(id: 2, start: 10, end: 14, text: "Maria wird den Testbericht bis Donnerstag schicken.", translation: "Maria will send the test report by Thursday.", language: "de", speaker: 2),
                     Segment(id: 3, start: 19, end: 22, text: "Great, let us review the budget next Monday.", translation: "Genial, revisemos el presupuesto el lunes.", language: "en", speaker: 1, interpreted: true)]
        let notes = NotesResult(notes: ExtractiveNotes.generate(lines.map { var s = $0; s.text = s.interpreted == true ? s.text : (s.translation ?? s.text); return s }),
                                provider: "demo", validShare: 1, attempts: [])
        if let m = try? store.create(title: "Demo: launch planning") {
            lines.forEach(m.append)
            if let data = try? JSONEncoder().encode(notes.notes) { m.saveNotes(json: data, markdown: NotesValidator.markdown(notes.notes)) }
            m.finish()
        }
        let vm = NotesViewModel(store: store, index: nil, engineLabel: { "demo" }, generate: { _ in notes })
        vm.load(); vm.click(notes.notes.decisions.first?.lines ?? [1])
        session.livePanel.model.lines = lines
        settingsModel.healthProvider = { [weak self] in await self?.engineHealth() ?? [] }
        settingsModel.refreshHealth(); settingsModel.refreshInterpreting()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        snapshot(into: dir)
        save(NotesView(vm: vm), NSSize(width: 1180, height: 640), "notes.png", into: dir)
        let ribbon = RibbonModel(); ribbon.fadeAfter = 120
        ribbon.show(original: lines[0].text, translation: lines[0].translation, speaker: 0, isFinal: true)
        save(ribbon.previewView().frame(maxWidth: .infinity, maxHeight: .infinity), NSSize(width: 760, height: 160), "ribbon.png", into: dir)
        onboardingModel.step = 1
        save(OnboardingView(model: onboardingModel, settings: settingsModel), NSSize(width: 600, height: 520), "welcome.png", into: dir)
        save(LedgerView(model: ledgerModel), NSSize(width: 900, height: 420), "ledger.png", into: dir)
        let knot = KnotModel(); knot.active = true; knot.level = 0.05; knot.state = "Listening…"; knot.route = "Routing to BlackHole 2ch"
        save(VoiceKnotView(m: knot).frame(maxWidth: .infinity, maxHeight: .infinity), NSSize(width: 260, height: 190), "interpreter.png", into: dir)
    }

    @MainActor @objc func toggleLivePanel() { session.livePanel.toggle() }

    private let previewPlayer = SpeechPlayer()
    @MainActor func previewVoice(_ language: String) {
        let samples = ["en": "This is how I will sound in your call.", "es": "Así sonaré en tu llamada.", "fr": "Voici ma voix pendant l'appel.",
                       "de": "So klinge ich in deinem Anruf.", "it": "Ecco come suonerò nella chiamata.", "pt": "É assim que vou soar na chamada.",
                       "zh": "我在通话中听起来是这样的。", "ja": "通話ではこのような声になります。", "ko": "통화에서는 이런 목소리로 들립니다.", "ru": "Так я буду звучать в звонке."]
        let player = previewPlayer
        Task { let b = await player.synthesize(samples[String(language.prefix(2))] ?? samples["en"]!, language: language); await player.play(b, deviceID: nil) }
    }

    /// What interpreting needs, each with how to fix it.
    static func interpreterSetup() -> [EngineHealth] {
        let mic = MicRecorder.authorization() == .authorized
        let keys = CGPreflightListenEventAccess()
        let bh = BlackHoleInstaller.isInstalled
        var out = [
            EngineHealth(name: "Virtual microphone", detail: bh ? "BlackHole 2ch is installed" : "Not installed. Turn on “Interpret my voice” from the menu to install it.", level: bh ? .ok : .warn),
            EngineHealth(name: "Microphone access", detail: mic ? "Allowed" : "Allow Chitter in System Settings → Privacy & Security → Microphone", level: mic ? .ok : .warn),
        ]
        if !Prefs.handsFree {
            out.append(EngineHealth(name: "Right ⌥ key", detail: keys ? "Chitter can see the key" : "Allow Chitter in System Settings → Privacy & Security → Input Monitoring, then reopen Chitter", level: keys ? .ok : .warn))
        }
        if bh, let current = AudioDevices.defaultInput(), let d = AudioDevices.all().first(where: { $0.id == current }) {
            let stuck = d.name.localizedCaseInsensitiveContains("BlackHole")
            out.append(EngineHealth(name: "System microphone", detail: stuck ? "It is set to BlackHole, so apps can't hear your real voice. Change it in System Settings → Sound → Input." : d.name, level: stuck ? .warn : .ok))
        }
        return out
    }

    @MainActor @objc func openLedger() { ledgerWindow.show() }
    @MainActor @objc func openSettings() { settingsWindow.show() }
    @MainActor @objc func openWelcome() { onboardingModel.step = 0; onboardingWindow.show() }

    /// Briefly starts the system-audio tap so macOS shows its permission prompt at the moment the user reaches this step.
    static func probeSystemAudio() async -> String? {
        let tap = SystemAudioTap()
        do { try tap.start { _ in }; try? await Task.sleep(nanoseconds: 600_000_000); tap.stop(); return nil }
        catch { return "\(error)" }
    }

    func engineHealth() async -> [EngineHealth] {
        var out: [EngineHealth] = []
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            out.append(EngineHealth(name: "Speech", detail: Prefs.preferWhisper ? "WhisperKit" : "Apple on-device", level: .ok))
            let notes = await AppleFoundationProvider().isAvailable()
            out.append(EngineHealth(name: "Notes · Apple model", detail: notes ? "ready" : "Apple Intelligence is off or unsupported", level: notes ? .ok : .warn))
            let st = await AppleTranslator.status(from: Prefs.sourceLanguage == "auto" ? "es" : Prefs.sourceLanguage, to: Prefs.targetLanguage)
            out.append(EngineHealth(name: "Translation · Apple", detail: st == .installed ? "language pack installed" : "download the language pack in System Settings", level: st == .installed ? .ok : .warn))
        }
        #else
        out.append(EngineHealth(name: "Speech", detail: "WhisperKit", level: .ok))
        #endif
        let ollama = await OpenAIClient.isReachable(.ollama)
        out.append(EngineHealth(name: "Ollama (local)", detail: ollama ? "running" : "not running (optional)", level: ollama ? .ok : .warn))
        let keys = LLMEndpoint.presets.filter { $0.keychainAccount.flatMap { Keychain.get(account: $0) } != nil }.map(\.name)
        out.append(EngineHealth(name: "Cloud providers", detail: keys.isEmpty ? "none added — fine" : keys.joined(separator: ", "), level: .ok))
        out.append(EngineHealth(name: "Offline fallback", detail: "always available", level: .ok))
        out.append(EngineHealth(name: "Virtual mic", detail: BlackHoleInstaller.isInstalled ? "BlackHole 2ch found" : "BlackHole not installed (interpreting only)", level: BlackHoleInstaller.isInstalled ? .ok : .warn))
        return out
    }

    @MainActor @objc func openNotes() { session.notesWindow.hideFromScreenShare = Prefs.hideNotesFromScreenShare; session.notesWindow.show() }
    @MainActor @objc func playSample() { Task { await session.playSample() } }
    @MainActor @objc func toggleInterpret() {
        let i = session.interpreter
        if i.enabled { i.disable(); interpretItem.state = .off; return }
        Task {
            await session.prepareTranslators()
            if !BlackHoleInstaller.isInstalled { await offerBlackHole() }
            if let problem = await i.enable() { let a = NSAlert(); a.messageText = "Can't interpret yet"; a.informativeText = problem; a.runModal() }
            else { interpretItem.state = .on }
        }
    }

    /// F12: install only on first use, only after the user agrees; failure → manual guide, rest of the app unaffected.
    @MainActor func offerBlackHole() async {
        let a = NSAlert()
        a.messageText = "Install the BlackHole virtual microphone?"
        a.informativeText = "Interpretation plays translated speech into your call through BlackHole 2ch, a free open-source audio driver. Chitter will download it from existential.audio, check its checksum, and ask for your admin password once. You can skip this — you'll just hear the translation on your own speakers."
        a.addButton(withTitle: "Install"); a.addButton(withTitle: "Skip")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try await BlackHoleInstaller.install() }
        catch {
            let f = NSAlert(); f.messageText = "BlackHole wasn't installed"
            f.informativeText = "\(error)\n\n" + BlackHoleInstaller.manualGuide; f.runModal()
        }
    }
    @MainActor @objc func toggle() { session.toggleListening() }
    @MainActor @objc func quit() { session.interpreter.shutdown(); NSApp.terminate(nil) }
    @MainActor func applicationWillTerminate(_ n: Notification) { session.interpreter.shutdown() }
}
