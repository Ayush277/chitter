import Foundation

/// Plain UserDefaults-backed settings. Secrets never live here (see Keychain).
enum Prefs {
    static let d = UserDefaults.standard
    static var sourceLanguage: String { get { d.string(forKey: "sourceLanguage") ?? "auto" } set { d.set(newValue, forKey: "sourceLanguage") } }
    static var targetLanguage: String {
        get { d.string(forKey: "targetLanguage") ?? (Locale.current.language.languageCode?.identifier ?? "en") }
        set { d.set(newValue, forKey: "targetLanguage") }
    }
    static var accessibilityMode: Bool { get { d.bool(forKey: "accessibilityMode") } set { d.set(newValue, forKey: "accessibilityMode") } }
    static var preferWhisper: Bool { get { d.bool(forKey: "preferWhisper") } set { d.set(newValue, forKey: "preferWhisper") } }
    static var autoEndMinutes: Double { get { d.object(forKey: "autoEndMinutes") as? Double ?? 10 } set { d.set(newValue, forKey: "autoEndMinutes") } }
    static var hideNotesFromScreenShare: Bool { get { d.object(forKey: "hideNotes") as? Bool ?? true } set { d.set(newValue, forKey: "hideNotes") } }
}
