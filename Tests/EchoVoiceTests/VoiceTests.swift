import Testing
import Foundation
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
