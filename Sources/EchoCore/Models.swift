import Foundation

/// One line of a transcript. `id` is the 1-based line number (L1, L2, …) used by notes to cite sources.
public struct Segment: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var translation: String?
    public var language: String?
    public var speaker: Int
    public var isFinal: Bool
    public var confidence: Float?

    public init(id: Int, start: TimeInterval, end: TimeInterval, text: String, translation: String? = nil,
                language: String? = nil, speaker: Int = 0, isFinal: Bool = true, confidence: Float? = nil) {
        self.id = id; self.start = start; self.end = end; self.text = text; self.translation = translation
        self.language = language; self.speaker = speaker; self.isFinal = isFinal; self.confidence = confidence
    }
}

/// Output of any speech recognizer.
public struct ASRResult: Sendable, Equatable {
    public var text: String
    public var isFinal: Bool
    public var start: TimeInterval
    public var end: TimeInterval
    public var language: String?
    public init(text: String, isFinal: Bool, start: TimeInterval, end: TimeInterval, language: String? = nil) {
        self.text = text; self.isFinal = isFinal; self.start = start; self.end = end; self.language = language
    }
}

public struct MeetingInfo: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var sourceLanguage: String?
    public var targetLanguage: String?
    public var tags: [String]
    public init(id: String, title: String, startedAt: Date, endedAt: Date? = nil,
                sourceLanguage: String? = nil, targetLanguage: String? = nil, tags: [String] = []) {
        self.id = id; self.title = title; self.startedAt = startedAt; self.endedAt = endedAt
        self.sourceLanguage = sourceLanguage; self.targetLanguage = targetLanguage; self.tags = tags
    }
}

public enum AudioFormatSpec {
    public static let sampleRate: Double = 16_000
}
