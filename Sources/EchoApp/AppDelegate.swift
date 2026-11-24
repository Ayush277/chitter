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
        menu.addItem(NSMenuItem(title: "Open Notes  (⌃⌥N)", action: #selector(openNotes), keyEquivalent: ""))
        interpretItem = NSMenuItem(title: "Interpret my voice  (hold right ⌥)", action: #selector(toggleInterpret), keyEquivalent: "")
        menu.addItem(interpretItem)
        menu.addItem(NSMenuItem(title: L("Try the sample meeting"), action: #selector(playSample), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit Chitter"), action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
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
        if CommandLine.arguments.contains("--sample") { Task { await self.session.playSample() } }   // used by QA scripts
        Hotkeys.shared.register(keyCode: kVK_ANSI_R, id: 1) { [weak self] in MainActor.assumeIsolated { self?.session.toggleListening() } }
        Hotkeys.shared.register(keyCode: kVK_ANSI_N, id: 3) { [weak self] in MainActor.assumeIsolated { self?.openNotes() } }
        Hotkeys.shared.register(keyCode: kVK_ANSI_S, id: 2) { [weak self] in MainActor.assumeIsolated { self?.session.toggleRibbon() } }
    }

    @MainActor func refresh() {
        let listening = session.isListening
        let name = listening ? "waveform.circle.fill" : "waveform.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: listening ? "Chitter, listening" : "Chitter, idle")
        startItem.title = listening ? L("Stop listening  (⌃⌥R)") : L("Start listening  (⌃⌥R)")
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
