import Foundation

/// What the subtitle ribbon and transcript show for a foreign-language line.
public enum SubtitleMode: String, CaseIterable, Sendable {
    case both, translation, original
    public var label: String { switch self { case .both: return "Both"; case .translation: return "Translation"; case .original: return "Original" } }
    /// The text to show, given a line and its (optional) translation. A line with no translation is always shown as heard.
    public func visible(original: String, translation: String?) -> (original: String?, translation: String?) {
        let t = (translation?.isEmpty ?? true) ? nil : translation
        switch self {
        case .both: return (original, t)
        case .translation: return t == nil ? (original, nil) : (nil, t)
        case .original: return (original, nil)
        }
    }
}

/// The user's word list: names and jargon that recognition or translation tends to get wrong.
/// One entry per line. "heard => Correct" replaces text; a single term fixes its spelling/capitals and is kept as-is when translating.
public struct WordList: Equatable, Sendable {
    public struct Entry: Equatable, Sendable { public var heard: String, written: String }
    public let entries: [Entry]

    public init(_ text: String) {
        entries = text.split(whereSeparator: \.isNewline).compactMap { raw -> Entry? in
            let parts = raw.components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { return Entry(heard: parts[0], written: parts[1]) }
            if parts.count == 1, !parts[0].isEmpty { return Entry(heard: parts[0], written: parts[0]) }
            return nil
        }
    }

    public var terms: [String] { entries.map(\.written) }

    public func apply(to text: String) -> String {
        var out = text
        for e in entries {
            var pattern = NSRegularExpression.escapedPattern(for: e.heard)
            // Whole words only for alphabetic scripts; CJK has no spaces between words.
            if e.heard.first.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) ?? false { pattern = "(?<![\\p{L}\\p{N}])" + pattern }
            if e.heard.last.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) ?? false { pattern += "(?![\\p{L}\\p{N}])" }
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: e.written))
        }
        return out
    }
}

/// Without headphones the microphone also hears the call from the speakers, so the same sentence would appear twice.
/// A microphone line that mostly repeats something the call just said is an echo.
public struct EchoFilter: Sendable {
    private var heard: [(tokens: Set<String>, at: Date)] = []
    public var window: TimeInterval = 15
    public var threshold = 0.7
    public init() {}

    public mutating func noteCallLine(_ text: String, at: Date = Date()) {
        heard.removeAll { at.timeIntervalSince($0.at) > window }
        heard.append((Set(WER.tokens(text)), at))
        if heard.count > 40 { heard.removeFirst(heard.count - 40) }
    }

    public func isEcho(_ micText: String, at: Date = Date()) -> Bool {
        let mine = Set(WER.tokens(micText))
        guard mine.count >= 3 else { return false }
        let recent = heard.filter { at.timeIntervalSince($0.at) <= window }.reduce(into: Set<String>()) { $0.formUnion($1.tokens) }
        return Double(mine.intersection(recent).count) / Double(mine.count) >= threshold
    }
}

extension Segment {
    /// "Mine": notes are written from the translations, so they come out in the reader's language.
    /// "Meeting": notes are written from what was actually said.
    public static func forNotes(_ segments: [Segment], inMyLanguage: Bool) -> [Segment] {
        guard inMyLanguage else { return segments }
        return segments.map { s in
            var s = s
            // An interpreted line's own text is already in the user's language.
            if s.interpreted != true, let t = s.translation, !t.isEmpty { s.text = t }
            return s
        }
    }
}
