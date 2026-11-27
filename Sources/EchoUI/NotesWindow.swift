import SwiftUI
import AppKit
import EchoCore
import EchoNotes

enum ExportKind { case markdown, srt, docx }

@MainActor
enum Exports {
    static func save(_ vm: NotesViewModel, _ kind: ExportKind) {
        guard let id = vm.selectedID, let h = vm.store.open(id) else { return }
        let panel = NSSavePanel()
        let base = h.info.title.replacingOccurrences(of: "/", with: "-")
        let data: Data
        switch kind {
        case .markdown: panel.nameFieldStringValue = "\(base).md"; data = Data(vm.markdown().utf8)
        case .srt: panel.nameFieldStringValue = "\(base).srt"; data = Data(Exporter.srt(segments: vm.segments).utf8)
        case .docx: panel.nameFieldStringValue = "\(base).docx"
            data = Exporter.docx(info: h.info, segments: vm.segments, notes: vm.notes.map { n in NotesValidator.markdown(n) })
        }
        panel.begin { r in if r == .OK, let url = panel.url { try? data.write(to: url) } }
    }
}

/// Window that shows meeting content. Hidden from screen sharing by default (F17).
@MainActor
public final class NotesWindowController {
    private var window: NSWindow?
    private let vm: NotesViewModel
    public var hideFromScreenShare = true { didSet { if let w = window { ScreenShareSafety.apply(to: w, hidden: hideFromScreenShare) } } }

    public init(vm: NotesViewModel) { self.vm = vm }

    public func show(selecting id: String? = nil) {
        vm.reloadList()
        if let id { vm.selectedID = id }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Chitter — Notes"
            w.contentView = NSHostingView(rootView: NotesView(vm: vm))
            w.isReleasedWhenClosed = false
            NeonWindow.apply(to: w)
            w.center()
            window = w
        }
        ScreenShareSafety.apply(to: window!, hidden: hideFromScreenShare)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
