import SwiftUI
import AppKit
import EchoCore

@MainActor
public final class LiveTranscriptModel: ObservableObject {
    @Published public var lines: [Segment] = []
    @Published public var mode: SubtitleMode = Prefs.subtitleMode
    public init() {}
}

struct LiveTranscriptView: View {
    @ObservedObject var model: LiveTranscriptModel
    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $model.mode) { ForEach(SubtitleMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().padding(10)
                .accessibilityLabel("Live transcript shows both languages, the translation, or the original")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.lines.isEmpty { Text("Lines appear here while Chitter is listening.").font(.callout).foregroundStyle(.secondary) }
                        ForEach(model.lines) { s in row(s).id(s.id) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 12)
                }
                .onChange(of: model.lines.last?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
        .frame(minWidth: 260, minHeight: 300)
    }

    func row(_ s: Segment) -> some View {
        let shown = model.mode.visible(original: s.text, translation: s.translation)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(String(format: "%02d:%02d", Int(s.start) / 60, Int(s.start) % 60)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                if s.interpreted == true { InterpretedTag() } else if s.speaker == 1 { Text("You").font(.caption2.weight(.semibold)) }
            }
            if let o = shown.original { Text(o).font(.callout).foregroundStyle(shown.translation == nil ? .primary : .secondary) }
            if let t = shown.translation { Text(t).font(.system(.body, design: .serif)) }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

/// A narrow floating panel beside the call with the running transcript. Hidden from screen sharing.
@MainActor
public final class LiveTranscriptPanel {
    public let model = LiveTranscriptModel()
    private var panel: NSPanel?
    public init() {}

    public func snapshotView() -> some View { LiveTranscriptView(model: model) }

    public var isPresented: Bool { panel?.isVisible ?? false }
    public func toggle() { isPresented ? panel?.orderOut(nil) : show() }
    public func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 560),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
            p.title = "Chitter — Live"
            p.level = .floating; p.isFloatingPanel = true; p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.sharingType = .none
            p.contentView = NSHostingView(rootView: LiveTranscriptView(model: model))
            if let f = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: f.maxX - 356, y: f.midY - 280)) }
            panel = p
        }
        panel?.orderFrontRegardless()
    }
}
