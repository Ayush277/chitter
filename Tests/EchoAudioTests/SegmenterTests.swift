import Testing
@testable import EchoAudio

private func tone(_ seconds: Double) -> [[Float]] { Array(repeating: [Float](repeating: 0.1, count: 1_600), count: Int(seconds * 10)) }
private func quiet(_ seconds: Double) -> [[Float]] { Array(repeating: [Float](repeating: 0, count: 1_600), count: Int(seconds * 10)) }

@Test func segmenterSendsAnUtteranceAfterAOneSecondPause() {
    var s = UtteranceSegmenter(pauseSeconds: 1.0); var out: [[Float]] = []
    for c in quiet(1) + tone(2) + quiet(0.5) + tone(1) { if let u = s.feed(c) { out.append(u) } }
    #expect(out.isEmpty)                                   // a short pause doesn't split the sentence
    for c in quiet(1.5) { if let u = s.feed(c) { out.append(u) } }
    #expect(out.count == 1 && out[0].count >= 16_000 * 3)
}
@Test func segmenterIgnoresClicksAndCutsEndlessSpeech() {
    var s = UtteranceSegmenter(); var out = 0
    for c in tone(0.1) + quiet(2) { if s.feed(c) != nil { out += 1 } }
    #expect(out == 0)
    s.maxSeconds = 3
    for c in tone(7) { if s.feed(c) != nil { out += 1 } }
    #expect(out == 2)
}

// Regression: the tap list once used the key "uuid". Apple's key is "uid", so no tap was attached and nothing was captured.
@Test func tapSettingsUseApplesKeyNames() {
    #expect(SystemAudioTap.tapList(uuid: "ABC").first?.keys.sorted() == ["drift", "uid"])
}
