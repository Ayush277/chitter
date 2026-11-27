import Testing
import Foundation
import AVFoundation
@testable import EchoVoice

@Test func installerChecksumIsPinnedAndVerified() throws {
    #expect(BlackHoleInstaller.sha256.count == 64)
    let f = FileManager.default.temporaryDirectory.appendingPathComponent("bh-\(UUID()).pkg")
    try Data("not the real installer".utf8).write(to: f)
    #expect(throws: BlackHoleInstaller.InstallError.self) { try BlackHoleInstaller.verify(file: f) }
    // a matching checksum passes
    let good = try BlackHoleInstaller.sha256Hex(of: f)
    try BlackHoleInstaller.verify(file: f, expected: good)
    // known vector: sha256("abc")
    try Data("abc".utf8).write(to: f)
    #expect(try BlackHoleInstaller.sha256Hex(of: f) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
@Test func installerOnlyDownloadsFromOfficialHost() {
    #expect(BlackHoleInstaller.url.host == "existential.audio" && BlackHoleInstaller.url.scheme == "https")
    #expect(BlackHoleInstaller.manualGuide.contains("brew install --cask blackhole-2ch"))
}
@Test func micRouterIsNoOpWithoutBlackHoleOrRestoresCleanly() {
    let r = MicRouter()
    if AudioDevices.blackHole() == nil { #expect(!r.routeToBlackHole()) }   // never touches the system if the driver is absent
    r.restore(); #expect(!r.isRouted)
}
@Test func ttsProducesAudioBuffers() async {
    let bufs = await SpeechPlayer().synthesize("Hello from Chitter", language: "en-US")
    #expect(!bufs.isEmpty && bufs.reduce(0) { $0 + Int($1.frameLength) } > 4_000)
}

@Test func dubQueueSpeaksFasterWhenBehindButCapsIt() {
    #expect(DubQueue.rate(forBacklog: 0) == DubQueue.rate(forBacklog: 1))
    #expect(DubQueue.rate(forBacklog: 3) > DubQueue.rate(forBacklog: 1))
    #expect(DubQueue.rate(forBacklog: 50) <= 0.65)
}
@Test func dubQueueDropsOldestWhenFarBehind() async {
    let q = DubQueue()
    await q.stop()
    for i in 0..<10 { await q.enqueue("Line \(i)", language: "en-US") }
    #expect(await q.dropped >= 6)                   // maxBacklog is 3, so older lines are dropped, never spoken late
    await q.stop()
}
@Test func picksTheBestInstalledVoice() {
    let v = SpeechPlayer.bestVoice(for: "en-US")
    #expect(v != nil)
    let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
    if let v, let top = all.map(\.quality.rawValue).max() { #expect(v.quality.rawValue >= top || !v.language.hasPrefix("en")) }
}
@Test func recorderNeverRecordsFromTheLoopbackDriver() {
    let devs = [AudioDevice(id: 1, name: "BlackHole 2ch", hasInput: true, hasOutput: true),
                AudioDevice(id: 2, name: "MacBook Pro Microphone", hasInput: true, hasOutput: false),
                AudioDevice(id: 3, name: "USB Mic", hasInput: true, hasOutput: false)]
    let uid: (AudioDeviceID) -> String = { "uid\($0)" }
    #expect(AudioDevices.recordingDevice(preferredUID: "uid3", devices: devs, uidOf: uid, systemDefault: 2) == 3)
    #expect(AudioDevices.recordingDevice(preferredUID: "", devices: devs, uidOf: uid, systemDefault: 2) == nil)   // default is fine
    #expect(AudioDevices.recordingDevice(preferredUID: "", devices: devs, uidOf: uid, systemDefault: 1) == 2)
    #expect(AudioDevices.recordingDevice(preferredUID: "gone", devices: devs, uidOf: uid, systemDefault: 1) == 2)
}
