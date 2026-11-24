import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Chitter")
        item.button?.setAccessibilityLabel("Chitter")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Chitter", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc func quit() { NSApp.terminate(nil) }
}
