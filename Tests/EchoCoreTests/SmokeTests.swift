import Foundation
import Testing
@testable import EchoCore

@Test func werExactMatchIsZero() { #expect(WER.rate(reference: "Hello, world!", hypothesis: "hello world") == 0) }
@Test func werCountsSubstitution() { #expect(WER.rate(reference: "a b c d", hypothesis: "a x c d") == 0.25) }
@Test func werCJKCountsCharacters() { #expect(WER.tokens("你好世界").count == 4) }
@Test func segmentRoundTrips() throws {
    let s = Segment(id: 3, start: 1, end: 2, text: "hi", translation: "hola", language: "en", speaker: 2)
    let d = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(Segment.self, from: d) == s)
}
