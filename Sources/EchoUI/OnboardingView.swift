import SwiftUI
import AppKit
import EchoCore

@MainActor
public final class OnboardingModel: ObservableObject {
    @Published public var step = 0
    @Published public var audioMessage = ""
    @Published public var audioDone = false
    @Published public var consent = Prefs.consentAcknowledged { didSet { Prefs.consentAcknowledged = consent } }
    @Published public var health: [EngineHealth] = []
    public var requestAudio: () async -> String? = { nil }       // returns an error message, nil = granted
    public var loadHealth: () async -> [EngineHealth] = { [] }
    public var playSample: () -> Void = {}
    public var finish: () -> Void = {}
    public let steps = ["Audio", "Language", "Notes engine", "Try a sample"]
    public init() {}

    public func next() { if step < 3 { step += 1; if step == 2 { Task { health = await loadHealth() } } } }
    public func back() { if step > 0 { step -= 1 } }
    public func allowAudio() { Task { if let e = await requestAudio() { audioMessage = e } else { audioDone = true; audioMessage = "Got it. Chitter can hear your Mac." } } }
}

/// Four threads being tied: each permission is requested only when its step is reached.
public struct OnboardingView: View {
    @ObservedObject var m: OnboardingModel
    @ObservedObject var settings: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(model: OnboardingModel, settings: SettingsModel) { m = model; self.settings = settings }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to Chitter").font(.system(size: 30, design: .rounded).weight(.bold))
            threads
            Group {
                switch m.step {
                case 0: audioStep
                case 1: languageStep
                case 2: engineStep
                default: sampleStep
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                if m.step > 0 { Button("Back") { m.back() } }
                Spacer()
                if m.step < 3 { Button("Next") { m.next() }.buttonStyle(NeonButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).disabled(m.step == 0 && !m.consent) }
                else { Button("Done") { m.finish() }.buttonStyle(NeonButtonStyle(prominent: true)).keyboardShortcut(.defaultAction) }
            }
        }
        .padding(28).frame(width: 600, height: 520)
        .neonRoot()
    }

    var threads: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule(style: .circular).fill(i <= m.step ? Tokens.cyan.color : Tokens.raised.color).frame(height: 6)
                        .shadow(color: i <= m.step ? Tokens.cyan.color.opacity(0.8) : .clear, radius: 5)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: m.step)
                    Text(LocalizedStringKey(m.steps[i])).font(.caption).foregroundStyle(i == m.step ? .primary : .secondary)
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Step \(m.step + 1) of 4: \(m.steps[m.step])")
    }

    var audioStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Let Chitter hear your Mac").font(.title2.weight(.semibold))
            Text("Chitter listens to whatever your Mac plays — Zoom, Meet, YouTube — so no bot has to join. Audio is processed on this Mac. macOS will ask for “System Audio Recording” permission.")
            Button("Allow system audio") { m.allowAudio() }.disabled(m.audioDone)
            if !m.audioMessage.isEmpty { Text(m.audioMessage).foregroundStyle(m.audioDone ? Tokens.mint.color : Tokens.red.color) }
            GroupBox {
                Toggle("I'll tell people when I'm transcribing a call. Laws differ — many places need everyone's consent — and I'm responsible for following them.", isOn: $m.consent)
                    .accessibilityHint("Required to continue")
            }
        }
    }

    var languageStep: some View {
        Form {
            Picker("Language being spoken", selection: $settings.sourceLanguage) {
                Text("Detect automatically").tag("auto")
                ForEach(SettingsView.languages, id: \.0) { Text($0.1).tag($0.0) }
            }
            Picker("Show translation in", selection: $settings.targetLanguage) { ForEach(SettingsView.languages, id: \.0) { Text($0.1).tag($0.0) } }
            Text("Language detection runs on your Mac within a few seconds.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).scrollContentBackground(.hidden)
    }

    var engineStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes engine").font(.title2.weight(.semibold))
            Text("Chitter tries these in order and uses the first one that's ready. No account or payment needed.").foregroundStyle(.secondary)
            ForEach(m.health) { h in
                HStack { Circle().fill(h.level == .ok ? Tokens.mint.color : h.level == .warn ? Tokens.yellow.color : Tokens.red.color).frame(width: 10, height: 10)
                    Text(h.name).bold(); Text(h.detail).foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
            }
            Text("You can always add a free-tier API key later in Settings → Engines.").font(.caption).foregroundStyle(.secondary)
        }
    }

    var sampleStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try it without a call").font(.title2.weight(.semibold))
            Text("Play a short sample meeting. You'll see live subtitles, then notes with every decision tied to the line it came from.")
            Button("Play the sample meeting") { m.playSample() }
            Text("Nothing left your Mac.").font(.system(.callout, design: .rounded).italic()).foregroundStyle(.secondary)
        }
    }
}

@MainActor
public final class HostedWindow {
    private var window: NSWindow?
    private let title: String, size: NSSize, make: () -> AnyView
    private let hide: Bool
    public init(title: String, size: NSSize, hideFromScreenShare: Bool = false, content: @escaping () -> AnyView) {
        self.title = title; self.size = size; self.make = content; hide = hideFromScreenShare
    }
    public func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = title; w.contentView = NSHostingView(rootView: make()); w.isReleasedWhenClosed = false; w.center()
            NeonWindow.apply(to: w)
            window = w
        }
        if hide { ScreenShareSafety.apply(to: window!, hidden: true) }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    public func close() { window?.close() }
}
