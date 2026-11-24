import Testing
import Foundation
@testable import EchoCore

func tempStore() -> MeetingStore { MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("chitter-\(UUID())")) }

@Test func meetingFolderHasValidFilesAndPermissions() throws {
    let store = tempStore()
    let h = try store.create(title: "Weekly Planning!")
    h.append(Segment(id: 1, start: 0, end: 2, text: "Hello there"))
    h.append(Segment(id: 2, start: 2, end: 4, text: "Second line"))
    h.append(Segment(id: 1, start: 0, end: 2, text: "Hello there", translation: "Hola"))   // supersedes line 1
    h.finish()
    let segs = h.loadSegments()
    #expect(segs.count == 2 && segs[0].translation == "Hola")
    #expect(h.info.endedAt != nil)
    #expect(store.list().first?.id == h.info.id)
    #expect(h.info.id.hasSuffix("weekly-planning"))
    let perms = try FileManager.default.attributesOfItem(atPath: h.dir.path)[.posixPermissions] as? Int
    #expect(perms == 0o700)
    let tperms = try FileManager.default.attributesOfItem(atPath: h.transcriptURL.path)[.posixPermissions] as? Int
    #expect(tperms == 0o600)
}
@Test func tornFinalLineAfterCrashIsSkipped() throws {
    let h = try tempStore().create()
    h.append(Segment(id: 1, start: 0, end: 1, text: "ok"))
    let fh = try FileHandle(forWritingTo: h.transcriptURL); try fh.seekToEnd(); fh.write(Data("{\"id\":2,\"te".utf8)); try fh.close()
    #expect(h.loadSegments().count == 1)
}
@Test func searchFindsExactAndFuzzy() throws {
    let idx = try SearchIndex(path: ":memory:")
    idx.index(meetingID: "m1", segments: [Segment(id: 1, start: 0, end: 1, text: "Maria will send the budget report"),
                                          Segment(id: 2, start: 1, end: 2, text: "The release moves to March")])
    idx.index(meetingID: "m2", segments: [Segment(id: 1, start: 0, end: 1, text: "Nothing relevant here")])
    #expect(idx.search("budget").first?.lineID == 1)
    #expect(idx.search("budget").first?.fuzzy == false)
    let fz = idx.search("Marria")                       // misspelling → edit distance 1
    #expect(fz.contains { $0.meetingID == "m1" && $0.lineID == 1 })
    #expect(idx.search("xylophone").isEmpty)
    idx.remove(meetingID: "m1"); #expect(idx.search("budget").isEmpty)
}
@Test func srtAndMarkdownFormat() {
    let segs = [Segment(id: 1, start: 1.5, end: 3.25, text: "Hi", translation: "Hola")]
    #expect(Exporter.srt(segments: segs).contains("00:00:01,500 --> 00:00:03,250"))
    let md = Exporter.markdown(info: MeetingInfo(id: "x", title: "T", startedAt: Date()), segments: segs)
    #expect(md.contains("# T") && md.contains("> Hola"))
}
@Test func docxIsAValidZipWithDocumentXML() throws {
    let data = Exporter.docx(info: MeetingInfo(id: "x", title: "T & Co", startedAt: Date()), segments: [Segment(id: 1, start: 0, end: 1, text: "Hi <b>")])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).docx"); try data.write(to: url)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-p", url.path, "word/document.xml"]
    let pipe = Pipe(); p.standardOutput = pipe; try p.run(); p.waitUntilExit()
    let xml = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(p.terminationStatus == 0 && xml.contains("T &amp; Co") && xml.contains("Hi &lt;b&gt;"))
    #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF43926)
}
@Test func keychainRoundTrip() {
    let acct = "test-\(UUID())"
    #expect(Keychain.set("s3cret", account: acct, service: "app.chitter.mac.tests"))
    #expect(Keychain.get(account: acct, service: "app.chitter.mac.tests") == "s3cret")
    #expect(Keychain.delete(account: acct, service: "app.chitter.mac.tests"))
    #expect(Keychain.get(account: acct, service: "app.chitter.mac.tests") == nil)
}

@Test func committerSpeaksFinishedSentencesEarlyAndNeverTwice() {
    var c = PhraseCommitter()
    #expect(c.update(partial: "Good morning everyone") == nil)                       // no finished sentence yet
    #expect(c.update(partial: "Good morning everyone. Today we") == "Good morning everyone.")
    #expect(c.update(partial: "Good morning everyone. Today we will review") == nil) // nothing new complete
    #expect(c.update(partial: "Good morning everyone. Today we will review it. Then") == "Today we will review it.")
    #expect(c.finish(final: "Good morning everyone. Today we will review it. Then we vote.") == "Then we vote.")
    #expect(c.committed.isEmpty)                                                     // ready for the next utterance
}
@Test func committerHandlesRevisionsAndShortUtterances() {
    var c = PhraseCommitter()
    #expect(c.finish(final: "Just one sentence.") == "Just one sentence.")           // nothing committed → speak all
    _ = c.update(partial: "Hello there. How")
    #expect(c.update(partial: "Hi there. How are") == nil)                           // earlier words revised: wait for final
    #expect(c.finish(final: "Hi there. How are you?") == "Hi there. How are you?")   // disagreement → speak the final once
    var d = PhraseCommitter()
    _ = d.update(partial: "你好。今天")
    #expect(d.update(partial: "你好。今天我们开会。然后") == "今天我们开会。")         // CJK terminators work
}
