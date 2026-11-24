import Foundation
import EchoCore

public struct NotesResult: Sendable {
    public var notes: Notes; public var provider: String; public var validShare: Double; public var attempts: [String]
    public init(notes: Notes, provider: String, validShare: Double, attempts: [String]) {
        self.notes = notes; self.provider = provider; self.validShare = validShare; self.attempts = attempts
    }
}

/// Runs the provider chain: first available + healthy provider wins; extractive fallback last (spec §5.1).
public actor NotesEngine {
    private var providers: [LLMProvider]
    public init(providers: [LLMProvider]) { self.providers = providers }
    public func setProviders(_ p: [LLMProvider]) { providers = p }

    public func activeProviderName() async -> String {
        for p in providers where await p.isAvailable() { return p.name }
        return "Extractive (offline)"
    }

    static let system = """
    You turn a meeting transcript into structured notes. The transcript lines are labelled L1, L2, ... \
    Respond with ONLY a JSON object: {"summary": string, "topics": [string], \
    "decisions": [{"text": string, "lines": [int]}], \
    "actions": [{"text": string, "owner": string|null, "due": string|null, "lines": [int]}], \
    "glossary": [{"term": string, "meaning": string}]}. \
    "lines" must contain the integer line numbers that support the item (e.g. L3 -> 3). Use only line numbers that exist. \
    Write in the language of the transcript. Do not invent facts.
    """

    public static func render(_ segs: [Segment]) -> String { segs.map { "L\($0.id): \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n") }

    /// Splits a transcript into chunks under `limit` characters, never splitting a line (so IDs stay intact).
    public static func chunks(_ segs: [Segment], limit: Int) -> [[Segment]] {
        var out: [[Segment]] = [], cur: [Segment] = [], size = 0
        for s in segs {
            let n = s.text.count + 8
            if size + n > limit, !cur.isEmpty { out.append(cur); cur = []; size = 0 }
            cur.append(s); size += n
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    public func generate(_ segments: [Segment]) async -> NotesResult {
        let valid = Set(segments.map(\.id))
        var attempts: [String] = []
        for p in providers {
            guard await p.isAvailable() else { attempts.append("\(p.name): unavailable"); continue }
            do {
                let raw = try await run(p, segments)
                let (clean, share) = NotesValidator.sanitize(raw, validIDs: valid)
                var n = clean; n.generatedBy = p.name
                attempts.append("\(p.name): ok")
                return NotesResult(notes: n, provider: p.name, validShare: share, attempts: attempts)
            } catch { attempts.append("\(p.name): \(error)") }   // 429 etc. → next provider
        }
        var n = ExtractiveNotes.generate(segments); n.generatedBy = "Extractive (offline)"
        return NotesResult(notes: n, provider: "Extractive (offline)", validShare: 1, attempts: attempts + ["Extractive: ok"])
    }

    /// One provider, with a single repair retry; map-reduce when the transcript doesn't fit.
    func run(_ p: LLMProvider, _ segs: [Segment]) async throws -> Notes {
        let budget = max(1_500, p.maxInputChars - 800)
        let parts = Self.chunks(segs, limit: budget)
        if parts.count == 1 { return try await ask(p, Self.render(parts[0]), prefix: "Transcript:") }
        // Map: notes per chunk. Reduce: merge, keeping line IDs, then ask for one overall summary from the partial summaries.
        var partials: [Notes] = []
        for c in parts { partials.append(try await ask(p, Self.render(c), prefix: "Transcript part:")) }
        var merged = Notes()
        merged.topics = Array(NSOrderedSet(array: partials.flatMap(\.topics)).array as? [String] ?? []).prefix(8).map { $0 }
        merged.decisions = partials.flatMap(\.decisions)
        merged.actions = partials.flatMap(\.actions)
        merged.glossary = partials.flatMap(\.glossary)
        let sums = partials.enumerated().map { "Part \($0.offset + 1): \($0.element.summary)" }.joined(separator: "\n")
        if let r = try? await p.complete(system: "Combine these partial meeting summaries into one concise paragraph. Output only the paragraph.", user: String(sums.prefix(budget)), json: false) {
            merged.summary = r.trimmingCharacters(in: .whitespacesAndNewlines)
        } else { merged.summary = partials.map(\.summary).joined(separator: " ") }
        return merged
    }

    func ask(_ p: LLMProvider, _ transcript: String, prefix: String) async throws -> Notes {
        let user = "\(prefix)\n\(transcript)"
        let first = try await p.complete(system: Self.system, user: user, json: true)
        if let n = try? NotesValidator.parse(first) { return n }
        // One repair attempt (spec §5.1)
        let repair = "Your previous answer was not valid JSON in the required shape. Reply with ONLY the JSON object.\n\nPrevious answer:\n\(first.prefix(2000))\n\n\(user)"
        return try NotesValidator.parse(try await p.complete(system: Self.system, user: repair, json: true))
    }
}
