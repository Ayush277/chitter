import SwiftUI
import AppKit
import EchoCore
import EchoNet
import EchoLang

public struct EngineHealth: Identifiable, Sendable {
    public enum Level: Sendable { case ok, warn, bad }
    public var id: String { name }
    public var name: String, detail: String, level: Level
    public init(name: String, detail: String, level: Level) { self.name = name; self.detail = detail; self.level = level }
}

@MainActor
public final class SettingsModel: ObservableObject {
    @Published public var sourceLanguage = Prefs.sourceLanguage { didSet { Prefs.sourceLanguage = sourceLanguage } }
    @Published public var targetLanguage = Prefs.targetLanguage { didSet { Prefs.targetLanguage = targetLanguage } }
    @Published public var speakLanguage = Prefs.speakLanguage { didSet { Prefs.speakLanguage = speakLanguage } }
    @Published public var interpretTarget = Prefs.interpretTarget { didSet { Prefs.interpretTarget = interpretTarget } }
    @Published public var accessibilityMode = Prefs.accessibilityMode { didSet { Prefs.accessibilityMode = accessibilityMode; onAccessibilityChange?(accessibilityMode) } }
    @Published public var autoStart = Prefs.autoStartOnCalls { didSet { Prefs.autoStartOnCalls = autoStart } }
    @Published public var captionMe = Prefs.captionMyVoice { didSet { Prefs.captionMyVoice = captionMe } }
    @Published public var dub = Prefs.dubForeignSpeech { didSet { Prefs.dubForeignSpeech = dub } }
    @Published public var preferWhisper = Prefs.preferWhisper { didSet { Prefs.preferWhisper = preferWhisper } }
    @Published public var hideNotes = Prefs.hideNotesFromScreenShare { didSet { Prefs.hideNotesFromScreenShare = hideNotes } }
    @Published public var autoEnd = Prefs.autoEndMinutes { didSet { Prefs.autoEndMinutes = autoEnd } }
    @Published public var customURL = Prefs.customBaseURL { didSet { Prefs.customBaseURL = customURL } }
    @Published public var customModel = Prefs.customModel { didSet { Prefs.customModel = customModel } }
    @Published public var keyDrafts: [String: String] = [:]
    @Published public var savedKeys: Set<String> = []
    @Published public var health: [EngineHealth] = []
    @Published public var storagePath = MeetingStore.defaultRoot.path
    public var onAccessibilityChange: ((Bool) -> Void)?
    public var healthProvider: () async -> [EngineHealth] = { [] }

    public init() { refreshKeys() }
    public func refreshKeys() { savedKeys = Set((LLMEndpoint.presets.compactMap(\.keychainAccount) + ["custom"]).filter { Keychain.get(account: $0) != nil }) }
    public func refreshHealth() { Task { health = await healthProvider() } }

    /// What leaves the Mac for each provider (spec §11: say exactly what is sent before first use).
    public static func disclosure(for provider: String) -> String {
        "\(provider) will receive the meeting transcript as text (never audio) to write notes and translations. Your key stays in the macOS Keychain. Every request is listed in the Privacy Ledger. Free tiers may rate-limit; Chitter then falls back to the next provider."
    }
    public func saveKey(account: String, provider: String) -> Bool {
        guard let k = keyDrafts[account], !k.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        Prefs.disclosed.insert(provider)
        let ok = Keychain.set(k.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
        keyDrafts[account] = ""; refreshKeys(); return ok
    }
    public func removeKey(account: String) { Keychain.delete(account: account); refreshKeys() }
}

public struct SettingsView: View {
    @ObservedObject var m: SettingsModel
    @ObservedObject var packs: PackModel
    @MainActor public init(model: SettingsModel) { m = model; packs = PackModel() }
    @MainActor public init(model: SettingsModel, packs: PackModel) { m = model; self.packs = packs }
    static let languages: [(String, String)] = [("en", "English"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("it", "Italiano"), ("pt", "Português"),
                                                ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"), ("ru", "Русский")]
    public var body: some View {
        TabView {
            languagesTab.tabItem { Label("Languages", systemImage: "globe") }
            enginesTab.tabItem { Label("Engines", systemImage: "gearshape.2") }
            hotkeysTab.tabItem { Label("Hotkeys", systemImage: "keyboard") }
            storageTab.tabItem { Label("Storage", systemImage: "folder") }
            privacyTab.tabItem { Label("Privacy", systemImage: "lock.shield") }
            accessibilityTab.tabItem { Label("Accessibility", systemImage: "accessibility") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 460).padding()
        .onAppear { m.refreshHealth() }
    }

    func langPicker(_ title: String, _ sel: Binding<String>, auto: Bool = false) -> some View {
        Picker(title, selection: sel) {
            if auto { Text("Detect automatically").tag("auto") }
            ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
        }
    }

    var languagesTab: some View {
        Form {
            Section("Calls") {
                Toggle("Start automatically when a call begins (Zoom, Teams, Meet in any browser…)", isOn: $m.autoStart)
                Toggle("Speak other people's foreign speech aloud in my language", isOn: $m.dub)
                Toggle("Also caption my own voice (microphone; use headphones)", isOn: $m.captionMe)
            }
            Section("Subtitles") {
                langPicker("Language being spoken", $m.sourceLanguage, auto: true)
                langPicker("Show translation in", $m.targetLanguage)
            }
            LanguagePackSection(model: packs, settings: m)
            Section("Interpreting (hold right ⌥)") {
                langPicker("I speak", $m.speakLanguage)
                langPicker("Say it in", $m.interpretTarget)
            }
        }.formStyle(.grouped)
    }

    var enginesTab: some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) {
            Text("Engines in use").font(.headline)
            ForEach(m.health) { h in
                HStack(spacing: 8) {
                    Circle().fill(color(h.level)).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(h.name).bold(); Text(h.detail).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityLabel("\(h.name): \(h.detail), \(label(h.level))")
            }
            Toggle("Use WhisperKit instead of Apple speech recognition (lower latency in my tests)", isOn: $m.preferWhisper)
            Divider()
            Text("Optional cloud providers (bring your own key)").font(.headline)
            Text("Off until you add a key. Order: Apple on-device → Ollama → these → offline fallback.").font(.caption).foregroundStyle(.secondary)
            ForEach(LLMEndpoint.presets, id: \.name) { e in keyRow(e.name, account: e.keychainAccount ?? e.name.lowercased()) }
            GroupBox("Custom OpenAI-compatible endpoint") {
                VStack(alignment: .leading) {
                    TextField("Base URL (e.g. https://api.openai.com/v1)", text: $m.customURL)
                    TextField("Model", text: $m.customModel)
                    keyRow("Custom endpoint", account: "custom")
                }
            }
        }.padding() }
    }

    func keyRow(_ provider: String, account: String) -> some View {
        HStack {
            Text(provider).frame(width: 120, alignment: .leading)
            if m.savedKeys.contains(account) {
                Text("Key saved in Keychain ✓").foregroundStyle(Tokens.translationText(dark: false).color)
                Button("Remove") { m.removeKey(account: account) }
            } else {
                SecureField("API key", text: Binding(get: { m.keyDrafts[account] ?? "" }, set: { m.keyDrafts[account] = $0 }))
                Button("Save") {
                    let a = NSAlert(); a.messageText = "Send text to \(provider)?"; a.informativeText = SettingsModel.disclosure(for: provider)
                    a.addButton(withTitle: "Use \(provider)"); a.addButton(withTitle: "Cancel")
                    if a.runModal() == .alertFirstButtonReturn { _ = m.saveKey(account: account, provider: provider) }
                }.accessibilityLabel("Save \(provider) key")
            }
        }
    }

    var hotkeysTab: some View {
        Form {
            LabeledContent("Toggle subtitles", value: "⌃⌥S"); LabeledContent("Hold to interpret", value: "Right ⌥")
            LabeledContent("Open Notes", value: "⌃⌥N"); LabeledContent("Start / stop meeting", value: "⌃⌥R")
            Text("Hotkeys are fixed in v0.1. Customisation is on the roadmap.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    var storageTab: some View {
        Form {
            LabeledContent("Meetings are stored in") { Text(m.storagePath).textSelection(.enabled).font(.system(.caption, design: .monospaced)) }
            Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: m.storagePath)) }
            Stepper("End a meeting after \(Int(m.autoEnd)) min of silence", value: $m.autoEnd, in: 1...120)
            Text("Plain Markdown, JSON and audio files — drop the folder into Obsidian. Excluded from Time Machine; readable only by you.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    var privacyTab: some View {
        Form {
            Toggle("Hide the Notes window from screen sharing and recordings", isOn: $m.hideNotes)
            Text("No telemetry, no accounts, no Chitter servers. Open the Privacy Ledger from the menu to see every network request.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    var accessibilityTab: some View {
        Form {
            Toggle("Large, high-contrast captions (≥ 28 pt)", isOn: $m.accessibilityMode)
            Text("Also enlarges the transcript in the Notes window. Every control is VoiceOver-labelled and the Notes window works from the keyboard alone (⌘F search, Tab through notes to pull their thread).").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    var aboutTab: some View {
        VStack(spacing: 8) {
            Text("Chitter").font(.system(size: 28, design: .serif).weight(.bold))
            Text("Catch every word. Keep what matters.").foregroundStyle(.secondary)
            Text("Version 0.1.0").font(.caption)
            Text("Uses WhisperKit (MIT). BlackHole (GPL) is downloaded on request, never bundled.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func color(_ l: EngineHealth.Level) -> Color { switch l { case .ok: return Tokens.verdigris.color; case .warn: return Tokens.weld.color; case .bad: return Tokens.madder.color } }
    func label(_ l: EngineHealth.Level) -> String { switch l { case .ok: return "healthy"; case .warn: return "limited"; case .bad: return "unavailable" } }
}
