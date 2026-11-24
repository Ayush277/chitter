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

@Test func callDetectorRecognisesAppsAndBrowsersButNotIdleOrSelf() {
    let zoom = AudioProcess(pid: 10, bundleID: "us.zoom.xos", isRunningInput: true, isRunningOutput: true)
    #expect(CallDetector.classify([zoom], ownPID: 1)?.app == "Zoom")
    let chrome = AudioProcess(pid: 11, bundleID: "com.google.Chrome.helper", isRunningInput: true, isRunningOutput: true)
    #expect(CallDetector.classify([chrome], ownPID: 1)?.app.contains("Chrome") == true)
    let idle = AudioProcess(pid: 12, bundleID: "us.zoom.xos", isRunningInput: false, isRunningOutput: true)
    #expect(CallDetector.classify([idle], ownPID: 1) == nil, "output only (e.g. watching a video) is not a call")
    let dictation = AudioProcess(pid: 13, bundleID: "com.apple.assistantd", isRunningInput: true, isRunningOutput: false)
    #expect(CallDetector.classify([dictation], ownPID: 1) == nil)
    let me = AudioProcess(pid: 99, bundleID: "com.google.Chrome", isRunningInput: true, isRunningOutput: false)
    #expect(CallDetector.classify([me], ownPID: 99) == nil, "Chitter never detects itself")
}

final class Events: @unchecked Sendable { var started = 0, ended = 0; var live: CallInfo? }
@Test func callWatcherStartsOnceAndEndsOnlyAfterGracePeriod() {
    let ev = Events()
    ev.live = CallInfo(app: "Zoom", bundleID: "us.zoom.xos")
    let w = CallWatcher(interval: 2, graceSeconds: 8, probe: { ev.live })
    w.onStart = { _ in ev.started += 1 }; w.onEnd = { ev.ended += 1 }
    w.tick(); w.tick(); w.tick()
    #expect(ev.started == 1 && w.isCallActive)
    ev.live = nil                                   // someone mutes for a moment…
    w.tick(); w.tick(); w.tick()
    #expect(ev.ended == 0 && w.isCallActive)
    ev.live = CallInfo(app: "Zoom", bundleID: "us.zoom.xos"); w.tick()   // …and un-mutes
    #expect(ev.started == 1 && ev.ended == 0)
    ev.live = nil
    for _ in 0..<4 { w.tick() }                     // 4 ticks × 2 s = 8 s of silence → meeting over
    #expect(ev.ended == 1 && !w.isCallActive)
    ev.live = CallInfo(app: "Teams", bundleID: "com.microsoft.teams2"); w.tick()
    #expect(ev.started == 2)
}
