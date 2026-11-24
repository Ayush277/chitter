import Foundation

/// Lets voice-over start before an utterance ends: as the live (partial) transcript grows, every sentence that is
/// followed by more text is "committed" once and handed out to be translated and spoken. When the utterance
/// finishes, only the not-yet-committed remainder is returned, so nothing is spoken twice or skipped.
public struct PhraseCommitter: Sendable {
    public private(set) var committed = ""
    static let terminators: Set<Character> = [".", "?", "!", "。", "！", "？", "…"]
    public init() {}

    /// New complete sentence(s) to speak now, if any.
    public mutating func update(partial: String) -> String? {
        guard partial.hasPrefix(committed) else { return nil }          // the recogniser revised earlier words: wait for the final
        // last terminator that is followed by more text, i.e. the sentence is surely finished
        var cut: String.Index?
        for i in partial.indices where Self.terminators.contains(partial[i]) {
            let after = partial.index(after: i)
            if after < partial.endIndex, !partial[after...].allSatisfy({ $0 == " " || Self.terminators.contains($0) }) { cut = after }
        }
        guard let cut else { return nil }
        let candidate = String(partial[..<cut])
        guard candidate.count > committed.count else { return nil }
        let new = String(candidate.dropFirst(committed.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        committed = candidate
        return new.isEmpty ? nil : new
    }

    /// The part of the final text that hasn't been spoken yet. Resets for the next utterance.
    public mutating func finish(final: String) -> String? {
        defer { committed = "" }
        let text = final.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !committed.isEmpty else { return text.isEmpty ? nil : text }
        let c = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        // common prefix length between what we spoke and the final text
        var n = 0
        for (a, b) in zip(c, text) { if a == b { n += 1 } else { break } }
        if Double(n) >= Double(c.count) * 0.8 {                         // final agrees with what was committed
            let rest = String(text.dropFirst(max(n, min(c.count, text.count)))).trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
        return text                                                     // the recogniser changed its mind: speak the final once
    }
}
