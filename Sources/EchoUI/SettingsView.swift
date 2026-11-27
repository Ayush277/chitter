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
    @Published public var tab = "languages"
    @Published public var subtitleMode = Prefs.subtitleMode { didSet { Prefs.subtitleMode = subtitleMode; onSubtitleModeChange?(subtitleMode) } }
    @Published public var notesInMine = Prefs.notesInMyLanguage { didSet { Prefs.notesInMyLanguage = notesInMine } }
    @Published public var wordList = Prefs.wordListText { didSet { Prefs.wordListText = wordList } }
    @Published public var handsFree = Prefs.handsFree { didSet { Prefs.handsFree = handsFree; onInterpretModeChange?() } }
    @Published public var switchSystemMic = Prefs.switchSystemMic { didSet { Prefs.switchSystemMic = switchSystemMic } }
    @Published public var micUID = Prefs.micDeviceUID { didSet { Prefs.micDeviceUID = micUID; onInterpretModeChange?() } }
    @Published public var voiceChoice: [String: String] = [:]
    @Published public var voiceMessage = ""
    @Published public var microphones: [(uid: String, name: String)] = []
    @Published public var checks: [EngineHealth] = []
    public var onSubtitleModeChange: ((SubtitleMode) -> Void)?
    public var onInterpretModeChange: (() -> Void)?
    public var micProvider: () -> [(uid: String, name: String)] = { [] }
    public var voiceProvider: (String) -> [(id: String, name: String)] = { _ in [] }
    public var previewVoice: (String) -> Void = { _ in }
    public var requestPersonalVoice: () async -> String = { "" }
    public var setupProvider: () async -> [EngineHealth] = { [] }

    public func voice(for language: String) -> Binding<String> {
        let key = "voice." + String(language.prefix(2))
        return Binding(get: { self.voiceChoice[key] ?? Prefs.d.string(forKey: key) ?? "" },
                       set: { self.voiceChoice[key] = $0; Prefs.d.set($0.isEmpty ? nil : $0, forKey: key) })
    }
    public func refreshInterpreting() { microphones = micProvider(); Task { checks = await setupProvider() } }
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
        TabView(selection: $m.tab) {
            languagesTab.tag("languages").tabItem { Label("Languages", systemImage: "globe") }
            interpretingTab.tag("interpreting").tabItem { Label("Interpreting", systemImage: "mic") }
            wordsTab.tag("words").tabItem { Label("Words", systemImage: "character.book.closed") }
            enginesTab.tag("engines").tabItem { Label("Engines", systemImage: "gearshape.2") }
            hotkeysTab.tag("hotkeys").tabItem { Label("Hotkeys", systemImage: "keyboard") }
            storageTab.tag("storage").tabItem { Label("Storage", systemImage: "folder") }
            privacyTab.tag("privacy").tabItem { Label("Privacy", systemImage: "lock.shield") }
            accessibilityTab.tag("accessibility").tabItem { Label("Accessibility", systemImage: "accessibility") }
            aboutTab.tag("about").tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 700, height: 520).padding()
        .onAppear { m.refreshHealth() }
    }

    func langPicker(_ title: String, _ sel: Binding<String>, auto: Bool = false) -> some View {
        Picker(title, selection: sel) {
            if auto { Text("Detect automatically").tag("auto") }
            ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
        }
    }

    func name(_ code: String) -> String { Self.languages.first { $0.0 == code }?.1 ?? code }

    /// The whole language setup at a glance: what they say, what you read, what you say, what they hear.
    var languageSummary: some View {
        func chip(_ t: String, strong: Bool = false) -> some View {
            Text(t).font(.callout.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(strong ? Tokens.weld.color : Tokens.textLight.color.opacity(0.14)))
                .foregroundStyle(strong ? Tokens.ink.color : Tokens.textLight.color)
        }
        func line(_ lead: String, _ from: String, _ verb: String, _ to: String) -> some View {
            HStack(spacing: 8) {
                Text(lead).frame(width: 64, alignment: .leading); chip(from)
                Image(systemName: "arrow.right").accessibilityHidden(true)
                Text(verb); chip(to, strong: true)
            }.foregroundStyle(Tokens.textLight.color).accessibilityElement(children: .combine)
        }
        return VStack(alignment: .leading, spacing: 8) {
            line("They say", m.sourceLanguage == "auto" ? "Any language" : name(m.sourceLanguage), "Subtitles", name(m.targetLanguage))
            line("You say", name(m.speakLanguage), "They hear", name(m.interpretTarget))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.ink.color))
    }

    var interpretingTab: some View {
        Form {
            Section("Speaking") {
                Picker("How to talk", selection: $m.handsFree) {
                    Text("Hold right ⌥").tag(false); Text("Hands-free (sends after a 1-second pause)").tag(true)
                }
                langPicker("I speak", $m.speakLanguage)
                langPicker("They hear", $m.interpretTarget)
            }
            Section("Voices") {
                voiceRow("Voice they hear (\(name(m.interpretTarget)))", language: m.interpretTarget)
                voiceRow("Voice I hear (\(name(m.targetLanguage)))", language: m.targetLanguage)
                Button("Use my own voice (macOS Personal Voice)…") { Task { m.voiceMessage = await m.requestPersonalVoice(); m.voiceChoice = [:]; m.refreshInterpreting() } }
                Text(m.voiceMessage.isEmpty ? "Free and on this Mac. A Personal Voice only speaks the languages it was recorded in." : m.voiceMessage)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Microphone") {
                Picker("Chitter listens through", selection: $m.micUID) {
                    Text("System default").tag("")
                    ForEach(m.microphones, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                Toggle("Switch the system mic to BlackHole while a translation plays, then switch back", isOn: $m.switchSystemMic)
            }
            Section("Setup check") {
                ForEach(m.checks) { h in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: h.level == .ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(color(h.level)).accessibilityHidden(true)
                        VStack(alignment: .leading) { Text(h.name); Text(h.detail).font(.caption).foregroundStyle(.secondary) }
                    }.accessibilityElement(children: .combine).accessibilityLabel("\(h.name): \(h.detail), \(label(h.level))")
                }
                Button("Check again") { m.refreshInterpreting() }
                Text("In your call app, choose “BlackHole 2ch” as the microphone while you want only the translation to be heard. “Same as system” also works with the switch above on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { m.refreshInterpreting() }
    }

    func voiceRow(_ title: String, language: String) -> some View {
        HStack {
            Picker(title, selection: m.voice(for: language)) {
                Text("Best installed voice").tag("")
                ForEach(m.voiceProvider(language), id: \.id) { Text($0.name).tag($0.id) }
            }
            Button { m.previewVoice(language) } label: { Image(systemName: "play.circle.fill") }
                .buttonStyle(.borderless).accessibilityLabel("Play a sample of this voice")
        }
    }

    var wordsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Names and jargon").font(.headline)
            Text("One per line. Write a name to fix its spelling and keep it untranslated, or “heard => Correct” to fix something Chitter keeps mishearing.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $m.wordList).font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
                .accessibilityLabel("Word list, one entry per line")
            Text("Example:  Chitter\n                  chit her => Chitter").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }.padding()
    }

    var languagesTab: some View {
        Form {
            Section { languageSummary }
            Section("Calls") {
                Toggle("Start automatically when a call begins (Zoom, Teams, Meet in any browser…)", isOn: $m.autoStart)
                Toggle("Speak other people's foreign speech aloud in my language", isOn: $m.dub)
                Toggle("Also caption my own voice (microphone; use headphones)", isOn: $m.captionMe)
            }
            Section("Subtitles") {
                langPicker("Language being spoken", $m.sourceLanguage, auto: true)
                langPicker("Show translation in", $m.targetLanguage)
                Picker("Show", selection: $m.subtitleMode) { ForEach(SubtitleMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                Picker("Write notes in", selection: $m.notesInMine) {
                    Text("My language").tag(true); Text("The meeting's own language").tag(false)
                }
            }
            LanguagePackSection(model: packs, settings: m)
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
            LabeledContent("Live transcript panel", value: "⌃⌥L")
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
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func color(_ l: EngineHealth.Level) -> Color { switch l { case .ok: return Tokens.verdigris.color; case .warn: return Tokens.weld.color; case .bad: return Tokens.madder.color } }
    func label(_ l: EngineHealth.Level) -> String { switch l { case .ok: return "healthy"; case .warn: return "limited"; case .bad: return "unavailable" } }
}
