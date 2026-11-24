import Testing
import Foundation
import EchoCore
@testable import EchoNotes

let sample: [Segment] = [
    Segment(id: 1, start: 0, end: 5, text: "Let's start with the launch date. I think we should move the release to the first of March because testing is not finished."),
    Segment(id: 2, start: 5, end: 10, text: "Agreed. I will ask the design team to finish the onboarding screens by next Wednesday. Also, Priya needs to update the privacy policy before launch."),
    Segment(id: 3, start: 10, end: 15, text: "Great. We decided to move the release to March first. Daniel will follow up with design by Friday, and Priya owns the privacy policy."),
]

struct Mock: LLMProvider {
    var name = "mock"; var maxInputChars = 24_000; var available = true
    var reply: @Sendable (String) throws -> String
    func isAvailable() async -> Bool { available }
    func complete(system: String, user: String, json: Bool) async throws -> String { try reply(user) }
}

@Test func extractiveFindsDecisionsAndActionsWithValidLines() {
    let n = ExtractiveNotes.generate(sample)
    #expect(!n.summary.isEmpty && !n.topics.isEmpty)
    #expect(n.decisions.contains { $0.text.contains("March") })
    #expect(n.actions.contains { $0.owner == "Daniel" && $0.due == "Friday" })
    let (_, share) = NotesValidator.sanitize(n, validIDs: Set(sample.map(\.id)))
    #expect(share == 1)
}
@Test func sanitizeDropsInvalidLineReferences() {
    let n = Notes(summary: "s", decisions: [Decision(text: "ok", lines: [1]), Decision(text: "ghost", lines: [99]), Decision(text: "mixed", lines: [2, 99])],
                  actions: [ActionItem(text: "a", lines: [7])])
    let (c, share) = NotesValidator.sanitize(n, validIDs: [1, 2, 3])
    #expect(c.decisions.map(\.text) == ["ok", "mixed"] && c.decisions[1].lines == [2])
    #expect(c.actions.isEmpty)
    #expect(share == 0.25)
}
@Test func parsesFencedJSON() throws {
    let n = try NotesValidator.parse("Sure!\n```json\n{\"summary\":\"x\",\"decisions\":[{\"text\":\"d\",\"lines\":[1]}]}\n```")
    #expect(n.summary == "x" && n.decisions.count == 1 && n.actions.isEmpty)
    #expect(throws: (any Error).self) { try NotesValidator.parse("no json here") }
}
@Test func chunkingNeverSplitsLinesAndKeepsIDs() {
    let segs = (1...50).map { Segment(id: $0, start: 0, end: 1, text: String(repeating: "word ", count: 20)) }
    let parts = NotesEngine.chunks(segs, limit: 1_000)
    #expect(parts.count > 1 && parts.flatMap { $0 }.map(\.id) == Array(1...50))
}
@Test func chainFallsBackToNextThenExtractive() async {
    let bad = Mock(name: "bad", reply: { _ in throw GatewayErrorStub.boom })
    let off = Mock(name: "off", available: false, reply: { _ in "" })
    let good = Mock(name: "good", reply: { _ in "{\"summary\":\"All good\",\"decisions\":[{\"text\":\"Ship in March\",\"lines\":[1,3]}]}" })
    let r = await NotesEngine(providers: [off, bad, good]).generate(sample)
    #expect(r.provider == "good" && r.notes.decisions.first?.lines == [1, 3])
    let r2 = await NotesEngine(providers: [off, bad]).generate(sample)
    #expect(r2.provider == "Extractive (offline)" && !r2.notes.isEmpty)
}
@Test func repairPromptRetriesOnceThenFails() async {
    final class Counter: @unchecked Sendable { var n = 0 }
    let c = Counter()
    let flaky = Mock(name: "flaky", reply: { _ in c.n += 1; return c.n == 1 ? "garbage" : "{\"summary\":\"fixed\",\"decisions\":[{\"text\":\"d\",\"lines\":[2]}]}" })
    let r = await NotesEngine(providers: [flaky]).generate(sample)
    #expect(r.provider == "flaky" && r.notes.summary == "fixed" && c.n == 2)
}
@Test func mapReduceKeepsLineIDsAcrossChunks() async {
    let segs = (1...40).map { Segment(id: $0, start: 0, end: 1, text: "Line number \($0) says we agreed to ship item \($0). " + String(repeating: "filler ", count: 30)) }
    let m = Mock(name: "m", maxInputChars: 3_000, reply: { u in
        // cite the first line id present in each chunk
        let id = u.components(separatedBy: "\n").first(where: { $0.hasPrefix("L") })?.dropFirst().prefix(while: { $0.isNumber }) ?? "1"
        return u.hasPrefix("Transcript") ? "{\"summary\":\"part\",\"decisions\":[{\"text\":\"d\(id)\",\"lines\":[\(id)]}]}" : "merged summary"
    })
    let r = await NotesEngine(providers: [m]).generate(segs)
    #expect(r.notes.decisions.count > 1 && r.validShare == 1)
}
@Test func markdownIncludesLineRefs() {
    let md = NotesValidator.markdown(Notes(summary: "S", decisions: [Decision(text: "Do it", lines: [3])], actions: [ActionItem(text: "Send", owner: "Maria", due: "Fri", lines: [4])]))
    #expect(md.contains("Do it _(L3)_") && md.contains("**Maria**") && md.contains("(due Fri)"))
}
enum GatewayErrorStub: Error { case boom }
