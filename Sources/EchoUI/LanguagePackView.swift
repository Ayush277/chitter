import SwiftUI
import EchoCore
#if compiler(>=6.2)
import Translation
#endif

/// Drives the "download fast translation" button. Apple's Translation framework only offers a language-pack download
/// through a SwiftUI `translationTask`, which shows the system's own download sheet.
@MainActor
public final class PackModel: ObservableObject {
    @Published public var source = "es"
    @Published var configBox: Any?
    @Published public var message = ""
    public init() {}
}

public struct LanguagePackSection: View {
    @ObservedObject var model: PackModel
    @ObservedObject var settings: SettingsModel
    public init(model: PackModel, settings: SettingsModel) { self.model = model; self.settings = settings }
    public var body: some View {
        Section("Fast translation (Apple language packs)") {
            Picker("Language to translate from", selection: $model.source) {
                ForEach(SettingsView.languages, id: \.0) { Text($0.1).tag($0.0) }
            }
            #if compiler(>=6.2)
            if #available(macOS 26, *) { PackButton(model: model, target: settings.targetLanguage) }
            #endif
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary) }
            Text("Without a pack, Chitter still translates using Apple's on-device model (about 1.5–2 s per sentence). Packs are faster.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

#if compiler(>=6.2)
@available(macOS 26, *)
struct PackButton: View {
    @ObservedObject var model: PackModel
    let target: String
    var body: some View {
        Button("Download \(model.source) → \(target) pack") {
            model.message = ""
            model.configBox = TranslationSession.Configuration(source: Locale.Language(identifier: model.source), target: Locale.Language(identifier: target))
        }
        .accessibilityHint("Opens the macOS download sheet for the translation language pack")
        .translationTask(model.configBox as? TranslationSession.Configuration) { session in
            do { try await session.prepareTranslation(); model.message = "Ready: translation is now on-device and fast." }
            catch { model.message = "Couldn't prepare the pack: \(error.localizedDescription)" }
        }
    }
}
#endif
