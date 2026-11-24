import Foundation
import EchoCore

/// Offline fallback: no model, no network. Scores sentences by word frequency and uses patterns for
/// decisions and action items. Always produces valid line references.
public enum ExtractiveNotes {
    static let stop: Set<String> = ["the","a","an","and","or","but","to","of","in","on","for","with","is","are","was","were","be","been","we","i","you","it","that","this","will","so","at","by","as","not","have","has","had","do","does","also","then","there","their","they","our","let","let's","lets","today","about","from","what","which","who","would","should","could","need","needs","can","because","before","after","next"]

    public static func generate(_ segments: [Segment]) -> Notes {
        let lines = segments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return Notes(generatedBy: "Extractive") }
        // Word frequencies
        var freq: [String: Int] = [:]
        for l in lines { for w in words(l.text) where !stop.contains(w) && w.count > 3 { freq[w, default: 0] += 1 } }
        func score(_ t: String) -> Double {
            let ws = words(t).filter { !stop.contains($0) && $0.count > 3 }
            return ws.isEmpty ? 0 : Double(ws.reduce(0) { $0 + (freq[$1] ?? 0) }) / Double(ws.count)
        }
        let top = lines.sorted { score($0.text) > score($1.text) }.prefix(3).sorted { $0.id < $1.id }
        let summary = top.map { clean($0.text) }.joined(separator: " ")
        let topics = freq.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(5).map { $0.key.capitalized }

        let decisionRE = try! NSRegularExpression(pattern: #"\b(decided|agreed|we will|we'll|the decision|conclude[ds]?|let's go with|move the|moved to|approved)\b"#, options: .caseInsensitive)
        let actionRE = try! NSRegularExpression(pattern: #"\b(will|needs? to|has to|must|should|owns?|responsible|follow up|please)\b"#, options: .caseInsensitive)
        let ownerRE = try! NSRegularExpression(pattern: #"\b([A-Z][a-z]{1,15})\s+(?:will|needs? to|has to|must|owns|should)\b"#)
        let ownRE2 = try! NSRegularExpression(pattern: #"\b([A-Z][a-z]{1,15})\s+owns\b"#)
        let dueRE = try! NSRegularExpression(pattern: #"\bby\s+((?:next\s+|the\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|end of (?:the )?(?:day|week|month)|(?:the\s+)?(?:first|second|third|\d+(?:st|nd|rd|th)?)\s+of\s+\w+|\w+\s+\d{1,2}(?:st|nd|rd|th)?))"#, options: .caseInsensitive)

        var decisions: [Decision] = [], actions: [ActionItem] = []
        for l in lines {
            for sentence in sentences(l.text) {
                let r = NSRange(sentence.startIndex..., in: sentence)
                if decisionRE.firstMatch(in: sentence, range: r) != nil { decisions.append(Decision(text: clean(sentence), lines: [l.id])) }
                else if actionRE.firstMatch(in: sentence, range: r) != nil {
                    let owner = [ownerRE, ownRE2].lazy.compactMap { $0.firstMatch(in: sentence, range: r) }.first
                        .flatMap { Range($0.range(at: 1), in: sentence).map { String(sentence[$0]) } }
                    let due = dueRE.firstMatch(in: sentence, range: r).flatMap { Range($0.range(at: 1), in: sentence).map { String(sentence[$0]) } }
                    if owner != nil || due != nil { actions.append(ActionItem(text: clean(sentence), owner: owner, due: due, lines: [l.id])) }
                }
            }
        }
        return Notes(summary: summary, topics: topics, decisions: Array(decisions.prefix(8)), actions: Array(actions.prefix(12)),
                     glossary: [], generatedBy: "Extractive (offline)")
    }

    static func words(_ s: String) -> [String] { s.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init) }
    static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func sentences(_ s: String) -> [String] {
        var out: [String] = []
        s.enumerateSubstrings(in: s.startIndex..., options: .bySentences) { sub, _, _, _ in if let sub, !sub.trimmingCharacters(in: .whitespaces).isEmpty { out.append(sub) } }
        return out.isEmpty ? [s] : out
    }
}
