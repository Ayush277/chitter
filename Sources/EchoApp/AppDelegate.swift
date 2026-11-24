import AppKit
import Carbon.HIToolbox
import EchoVoice

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var session: SessionController!
    private var startItem: NSMenuItem!
    private var interpretItem: NSMenuItem!

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        session = SessionController()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.setAccessibilityLabel("Chitter")
        let menu = NSMenu()
        startItem = NSMenuItem(title: "Start listening", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(startItem)
        menu.addItem(NSMenuItem(title: "Open Notes  (⌃⌥N)", action: #selector(openNotes), keyEquivalent: ""))
        interpretItem = NSMenuItem(title: "Interpret my voice  (hold right ⌥)", action: #selector(toggleInterpret), keyEquivalent: "")
        menu.addItem(interpretItem)
        menu.addItem(NSMenuItem(title: "Try the sample meeting", action: #selector(playSample), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Chitter", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
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
        startItem.title = listening ? "Stop listening  (⌃⌥R)" : "Start listening  (⌃⌥R)"
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
