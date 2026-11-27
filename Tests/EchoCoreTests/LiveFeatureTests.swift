import Testing
import Foundation
@testable import EchoCore

@Test func subtitleModeChoosesWhatToShow() {
    #expect(SubtitleMode.both.visible(original: "hola", translation: "hello") == ("hola", "hello"))
    #expect(SubtitleMode.translation.visible(original: "hola", translation: "hello") == (nil, "hello"))
    #expect(SubtitleMode.translation.visible(original: "hi", translation: nil) == ("hi", nil))      // same language: never blank
    #expect(SubtitleMode.original.visible(original: "hola", translation: "hello") == ("hola", nil))
}
@Test func wordListReplacesWholeWordsOnly() {
    let w = WordList("chit her => Chitter\nAyush\n\n  => broken\nart => ART")
    #expect(w.terms == ["Chitter", "Ayush", "ART"])
    #expect(w.apply(to: "ayush built chit her for art class, not a cartoon") == "Ayush built Chitter for ART class, not a cartoon")
}
@Test func wordListWorksWithoutSpacesInCJKAndEscapesSymbols() {
    #expect(WordList("支付回调 => 支付回調").apply(to: "支付回调还是超时") == "支付回調还是超时")
    #expect(WordList("c plus plus => C++ $1").apply(to: "I like c plus plus") == "I like C++ $1")
}
@Test func echoFilterDropsOnlyRepeatsOfRecentCallAudio() {
    var f = EchoFilter(); let t = Date()
    f.noteCallLine("We need to finish the testing before Friday.", at: t)
    #expect(f.isEcho("we need to finish the testing before friday", at: t.addingTimeInterval(2)))
    #expect(!f.isEcho("I can send the report tomorrow morning", at: t.addingTimeInterval(2)))
    #expect(!f.isEcho("we need to finish the testing before friday", at: t.addingTimeInterval(60)))   // too old
    #expect(!f.isEcho("the testing", at: t))                                                          // too short to judge
}
@Test func notesInMyLanguageUseTranslationsButKeepOwnInterpretedWords() {
    let segs = [Segment(id: 1, start: 0, end: 1, text: "Hola", translation: "Hello", language: "es"),
                Segment(id: 2, start: 1, end: 2, text: "I agree", translation: "Estoy de acuerdo", language: "en", speaker: 1, interpreted: true)]
    #expect(Segment.forNotes(segs, inMyLanguage: true).map(\.text) == ["Hello", "I agree"])
    #expect(Segment.forNotes(segs, inMyLanguage: false).map(\.text) == ["Hola", "I agree"])
}
@Test func oldTranscriptLinesWithoutInterpretedFlagStillLoad() throws {
    let old = #"{"id":1,"start":0,"end":1,"text":"hi","speaker":0,"isFinal":true}"#
    #expect(try JSONDecoder().decode(Segment.self, from: Data(old.utf8)).interpreted == nil)
}
