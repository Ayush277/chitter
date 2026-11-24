import Foundation
import Testing
@testable import EchoAudio

@Test func ringBufferDropsOldest() {
    let r = RingBuffer(capacity: 4)
    r.write([1, 2, 3, 4, 5, 6])
    #expect(r.read(max: 10) == [3, 4, 5, 6])
}
@Test func vadDetectsStartAndEnd() {
    var v = EnergyVAD()
    #expect(v.process([Float](repeating: 0, count: 1600)) == nil)
    #expect(v.process([Float](repeating: 0.2, count: 1600)) == .started)
    var ended = false
    for _ in 0..<10 { if v.process([Float](repeating: 0, count: 1600)) == .ended { ended = true } }
    #expect(ended)
}
@Test func resamplesFixtureTo16kMono() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Fixtures/en.wav")
    let s = try AudioFile.loadSamples(url: url)
    #expect(s.count > 16_000 * 8)
}
