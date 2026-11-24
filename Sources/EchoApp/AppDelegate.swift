import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var session: SessionController!
    private var startItem: NSMenuItem!

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        session = SessionController()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.setAccessibilityLabel("Chitter")
        let menu = NSMenu()
        startItem = NSMenuItem(title: "Start listening", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(startItem)
        menu.addItem(NSMenuItem(title: "Open Notes  (⌃⌥N)", action: #selector(openNotes), keyEquivalent: ""))
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
    @MainActor @objc func toggle() { session.toggleListening() }
    @objc func quit() { NSApp.terminate(nil) }
}
