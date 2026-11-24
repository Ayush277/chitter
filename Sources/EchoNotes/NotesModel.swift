import Foundation
import EchoCore

public struct Decision: Codable, Equatable, Sendable { public var text: String; public var lines: [Int]
    public init(text: String, lines: [Int]) { self.text = text; self.lines = lines } }
public struct ActionItem: Codable, Equatable, Sendable { public var text: String; public var owner: String?; public var due: String?; public var lines: [Int]
    public init(text: String, owner: String? = nil, due: String? = nil, lines: [Int]) { self.text = text; self.owner = owner; self.due = due; self.lines = lines } }
public struct GlossaryTerm: Codable, Equatable, Sendable { public var term: String; public var meaning: String
    public init(term: String, meaning: String) { self.term = term; self.meaning = meaning } }

/// Structured notes. Every decision/action cites transcript line IDs (L1, L2…) → "Pull the Thread".
public struct Notes: Codable, Equatable, Sendable {
    public var summary: String
    public var topics: [String]
    public var decisions: [Decision]
    public var actions: [ActionItem]
    public var glossary: [GlossaryTerm]
    public var generatedBy: String?
    public init(summary: String = "", topics: [String] = [], decisions: [Decision] = [], actions: [ActionItem] = [],
                glossary: [GlossaryTerm] = [], generatedBy: String? = nil) {
        self.summary = summary; self.topics = topics; self.decisions = decisions; self.actions = actions
        self.glossary = glossary; self.generatedBy = generatedBy
    }
    public var isEmpty: Bool { summary.isEmpty && decisions.isEmpty && actions.isEmpty }

    // Lenient decoding: LLMs omit keys.
    enum CodingKeys: String, CodingKey { case summary, topics, decisions, actions, glossary, generatedBy }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        topics = (try? c.decode([String].self, forKey: .topics)) ?? []
        decisions = (try? c.decode([Decision].self, forKey: .decisions)) ?? []
        actions = (try? c.decode([ActionItem].self, forKey: .actions)) ?? []
        glossary = (try? c.decode([GlossaryTerm].self, forKey: .glossary)) ?? []
        generatedBy = try? c.decode(String.self, forKey: .generatedBy)
    }
}

public enum NotesValidator {
    public enum Failure: Error { case notJSON, wrongShape }

    /// Extracts the first JSON object from model output (handles ```json fences and chatter).
    public static func extractJSON(_ s: String) -> Data? {
        guard let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a < b else { return nil }
        return Data(s[a...b].utf8)
    }

    public static func parse(_ raw: String) throws -> Notes {
        guard let data = extractJSON(raw) else { throw Failure.notJSON }
        guard let n = try? JSONDecoder().decode(Notes.self, from: data), !n.isEmpty else { throw Failure.wrongShape }
        return n
    }

    /// Drops items whose `lines` reference IDs that don't exist (spec §5.1) and returns the cleaned notes
    /// plus the share of cited items that were valid before cleaning.
    public static func sanitize(_ n: Notes, validIDs: Set<Int>) -> (notes: Notes, validShare: Double) {
        var total = 0, ok = 0
        var out = n
        out.decisions = n.decisions.compactMap { d in
            total += 1
            let l = d.lines.filter(validIDs.contains)
            guard !l.isEmpty, l.count == d.lines.count else { return l.isEmpty ? nil : Decision(text: d.text, lines: l) }
            ok += 1; return d
        }
        out.actions = n.actions.compactMap { a in
            total += 1
            let l = a.lines.filter(validIDs.contains)
            guard !l.isEmpty, l.count == a.lines.count else { return l.isEmpty ? nil : ActionItem(text: a.text, owner: a.owner, due: a.due, lines: l) }
            ok += 1; return a
        }
        return (out, total == 0 ? 1 : Double(ok) / Double(total))
    }

    public static func markdown(_ n: Notes) -> String {
        func refs(_ l: [Int]) -> String { l.isEmpty ? "" : " _(" + l.map { "L\($0)" }.joined(separator: ", ") + ")_" }
        var s = ""
        if !n.summary.isEmpty { s += "## Summary\n\n\(n.summary)\n\n" }
        if !n.topics.isEmpty { s += "## Topics\n\n" + n.topics.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        if !n.decisions.isEmpty { s += "## Decisions\n\n" + n.decisions.map { "- \($0.text)\(refs($0.lines))" }.joined(separator: "\n") + "\n\n" }
        if !n.actions.isEmpty {
            s += "## Action items\n\n" + n.actions.map { a in
                "- [ ] \(a.text)" + (a.owner.map { " — **\($0)**" } ?? "") + (a.due.map { " (due \($0))" } ?? "") + refs(a.lines)
            }.joined(separator: "\n") + "\n\n"
        }
        if !n.glossary.isEmpty { s += "## Glossary\n\n" + n.glossary.map { "- **\($0.term)**: \($0.meaning)" }.joined(separator: "\n") + "\n" }
        return s
    }
}
