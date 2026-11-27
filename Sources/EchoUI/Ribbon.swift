import SwiftUI
import AppKit
import EchoCore

/// What the ribbon is showing right now.
@MainActor
public final class RibbonModel: ObservableObject {
    @Published public var original = ""
    @Published public var translation = ""
    @Published public var speaker = 0
    @Published public var isFinal = false
    @Published public var visible = false
    @Published public var accessibilityMode = false
    @Published public var mode: SubtitleMode = .both
    @Published public var hovering = false
    private var hideTask: Task<Void, Never>?
    public var fadeAfter: TimeInterval = 3

    public init() {}

    public func show(original: String, translation: String?, speaker: Int, isFinal: Bool) {
        self.original = original
        if let translation { self.translation = translation } else if isFinal || original.isEmpty { self.translation = "" }
        self.speaker = speaker; self.isFinal = isFinal; visible = true
        hideTask?.cancel()
        hideTask = Task { [fadeAfter] in
            try? await Task.sleep(nanoseconds: UInt64(fadeAfter * 1_000_000_000))
            if !Task.isCancelled { self.visible = false }
        }
    }
    public func setTranslation(_ t: String) { translation = t }
    public func clear() { hideTask?.cancel(); visible = false; original = ""; translation = "" }
}

struct RibbonView: View {
    @ObservedObject var model: RibbonModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let big = model.accessibilityMode
        let thread = Tokens.thread(model.speaker)
        let shown = model.mode.visible(original: model.original, translation: model.translation)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Tokens.speakerInitial(model.speaker))
                    .font(.system(size: big ? 18 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Tokens.ink.color)
                    .frame(width: big ? 28 : 18, height: big ? 28 : 18)
                    .background(Circle().fill(thread.color))
                    .accessibilityHidden(true)
                if let original = shown.original {
                    Text(original)
                        .font(.system(size: big ? 28 : 15))
                        .foregroundStyle(Tokens.textLight.color.opacity(0.7))
                        .lineLimit(2)
                }
            }
            if let translation = shown.translation {
                Text(translation)
                    .font(.system(size: big ? 34 : 20, weight: .medium, design: .serif))
                    .foregroundStyle(Tokens.textLight.color)
                    .lineLimit(3)
            }
            GeometryReader { g in
                Rectangle().fill(thread.color)
                    .frame(width: g.size.width * (model.isFinal ? 1 : 0.4), height: 2)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.isFinal)
            }.frame(height: 2)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tokens.ink.color.opacity(0.88)))
        .frame(maxWidth: big ? 1100 : 820)
        .opacity(model.visible ? (model.hovering ? 0.15 : 1) : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.visible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live subtitle: \(shown.original ?? ""). \(shown.translation ?? "")")
    }
}

/// Floating, non-activating panel. Click-through by default; goes transparent while the pointer is over it;
/// hold ⌘ over it to drag. Position is remembered per display.
@MainActor
public final class RibbonPanel {
    public let model: RibbonModel
    private let panel: NSPanel
    private var timer: Timer?
    private var moveObserver: NSObjectProtocol?

    public init(model: RibbonModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 160),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        let host = NSHostingView(rootView: RibbonView(model: model))
        host.frame = panel.contentView!.bounds; host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setAccessibilityLabel("Chitter subtitles")
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() }
        }
    }

    public func present() {
        place()
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    public func dismiss() { timer?.invalidate(); panel.orderOut(nil); model.clear() }
    public var isPresented: Bool { panel.isVisible }

    private func tick() {
        let inside = panel.frame.contains(NSEvent.mouseLocation) && model.visible
        if inside != model.hovering { model.hovering = inside }
        panel.ignoresMouseEvents = !(inside && NSEvent.modifierFlags.contains(.command))
    }

    private var displayKey: String {
        let id = (panel.screen ?? NSScreen.main)?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "ribbon.origin.\(id?.intValue ?? 0)"
    }
    private func savePosition() {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: displayKey)
    }
    private func place() {
        guard let screen = NSScreen.main else { return }
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if let s = UserDefaults.standard.string(forKey: "ribbon.origin.\(id?.intValue ?? 0)") {
            panel.setFrameOrigin(NSPointFromString(s))
        } else {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 80))
        }
    }
}
