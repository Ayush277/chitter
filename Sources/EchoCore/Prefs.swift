import Foundation

/// Plain UserDefaults-backed settings. Secrets never live here (see Keychain).
public enum Prefs {
    public static let d = UserDefaults.standard
    public static var sourceLanguage: String { get { d.string(forKey: "sourceLanguage") ?? "auto" } set { d.set(newValue, forKey: "sourceLanguage") } }
    public static var targetLanguage: String {
        get { d.string(forKey: "targetLanguage") ?? (Locale.current.language.languageCode?.identifier ?? "en") }
        set { d.set(newValue, forKey: "targetLanguage") }
    }
    /// The language you speak when interpreting (default: system language) and the one spoken into the call.
    public static var speakLanguage: String {
        get { d.string(forKey: "speakLanguage") ?? (Locale.current.language.languageCode?.identifier ?? "en") }
        set { d.set(newValue, forKey: "speakLanguage") }
    }
    public static var interpretTarget: String {
        get { d.string(forKey: "interpretTarget") ?? (speakLanguage == "en" ? "es" : "en") }
        set { d.set(newValue, forKey: "interpretTarget") }
    }
    public static var accessibilityMode: Bool { get { d.bool(forKey: "accessibilityMode") } set { d.set(newValue, forKey: "accessibilityMode") } }
    public static var preferWhisper: Bool { get { d.bool(forKey: "preferWhisper") } set { d.set(newValue, forKey: "preferWhisper") } }
    public static var autoEndMinutes: Double { get { d.object(forKey: "autoEndMinutes") as? Double ?? 10 } set { d.set(newValue, forKey: "autoEndMinutes") } }
    public static var hideNotesFromScreenShare: Bool { get { d.object(forKey: "hideNotes") as? Bool ?? true } set { d.set(newValue, forKey: "hideNotes") } }
}

extension Prefs {
    /// Also caption your own microphone during a meeting (the system-audio tap only hears the other people).
    public static var captionMyVoice: Bool { get { d.object(forKey: "captionMyVoice") as? Bool ?? true } set { d.set(newValue, forKey: "captionMyVoice") } }
    /// Start subtitles automatically when a call begins in any app or browser, and wrap up when it ends.
    public static var autoStartOnCalls: Bool { get { d.object(forKey: "autoStartOnCalls") as? Bool ?? true } set { d.set(newValue, forKey: "autoStartOnCalls") } }
    /// Speak other people's foreign-language speech aloud in your language (voice-over).
    public static var dubForeignSpeech: Bool { get { d.object(forKey: "dubForeignSpeech") as? Bool ?? true } set { d.set(newValue, forKey: "dubForeignSpeech") } }
    public static var onboarded: Bool { get { d.bool(forKey: "onboarded") } set { d.set(newValue, forKey: "onboarded") } }
    public static var consentAcknowledged: Bool { get { d.bool(forKey: "consentAck") } set { d.set(newValue, forKey: "consentAck") } }
    public static var customBaseURL: String { get { d.string(forKey: "custom.baseURL") ?? "" } set { d.set(newValue, forKey: "custom.baseURL") } }
    public static var customModel: String { get { d.string(forKey: "custom.model") ?? "" } set { d.set(newValue, forKey: "custom.model") } }
    public static var disclosed: Set<String> {
        get { Set(d.stringArray(forKey: "disclosedProviders") ?? []) }
        set { d.set(Array(newValue), forKey: "disclosedProviders") }
    }
}

extension Prefs {
    public static var subtitleMode: SubtitleMode {
        get { SubtitleMode(rawValue: d.string(forKey: "subtitleMode") ?? "") ?? .both }
        set { d.set(newValue.rawValue, forKey: "subtitleMode") }
    }
    /// Write notes in my language (from the translations) instead of the meeting's own language.
    public static var notesInMyLanguage: Bool { get { d.object(forKey: "notesInMyLanguage") as? Bool ?? true } set { d.set(newValue, forKey: "notesInMyLanguage") } }
    public static var wordListText: String { get { d.string(forKey: "wordList") ?? "" } set { d.set(newValue, forKey: "wordList") } }
    public static var wordList: WordList { WordList(wordListText) }
    /// Interpret without holding a key: each sentence is sent after a short pause.
    public static var handsFree: Bool { get { d.bool(forKey: "handsFree") } set { d.set(newValue, forKey: "handsFree") } }
    /// While speaking a translation into the call, make BlackHole the system microphone, then switch back.
    public static var switchSystemMic: Bool { get { d.object(forKey: "switchSystemMic") as? Bool ?? true } set { d.set(newValue, forKey: "switchSystemMic") } }
    /// Core Audio UID of the microphone Chitter listens through ("" = system default).
    public static var micDeviceUID: String { get { d.string(forKey: "micDeviceUID") ?? "" } set { d.set(newValue, forKey: "micDeviceUID") } }
}

/// Localised string lookup. Keys are the English text (same convention as Localizable.xcstrings).
public func L(_ key: String) -> String { NSLocalizedString(key, bundle: .main, value: key, comment: "") }
