import Testing
import Foundation
import EchoCore
import EchoNotes
@testable import EchoUI

/// Body-text pairs must meet WCAG AA (4.5:1), including every neon colour used as text.
@Test func bodyTextPairsMeetAA() {
    let backgrounds: [(String, Tokens.Hex)] = [("black", Tokens.black), ("surface", Tokens.surface), ("raised", Tokens.raised)]
    let texts: [(String, Tokens.Hex)] = [("text", Tokens.text), ("dim", Tokens.textDim), ("cyan", Tokens.cyan), ("magenta", Tokens.magenta),
        ("mint", Tokens.mint), ("yellow", Tokens.yellow), ("red", Tokens.red), ("violet", Tokens.violet), ("orange", Tokens.orange)]
    for (bn, bg) in backgrounds {
        for (tn, fg) in texts { #expect(fg.contrast(with: bg) >= 4.5, "\(tn) on \(bn) = \(fg.contrast(with: bg))") }
    }
}
/// Filled neon buttons, chips and speaker badges carry black labels.
@Test func blackLabelsOnNeonFillsMeetAA() {
    for fill in Tokens.speakerThreads + [Tokens.red] { #expect(Tokens.black.contrast(with: fill) >= 4.5) }
}
@Test func speakerThreadsAreDistinctAndWrap() {
    #expect(Set(Tokens.speakerThreads.map { "\($0.r)\($0.g)\($0.b)" }).count == 6)
    #expect(Tokens.speakerInitial(0) == "A" && Tokens.speakerInitial(27) == "B")
}

@MainActor @Test func pullTheThreadHoverClickAndPin() {
    let store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID())"))
    let vm = NotesViewModel(store: store, index: nil, engineLabel: { "x" }, generate: { _ in
        NotesResult(notes: Notes(), provider: "x", validShare: 1, attempts: []) })
    vm.hover([3, 4]); #expect(vm.activeLines == [3, 4])
    vm.hover(nil); #expect(vm.activeLines.isEmpty)
    vm.click([7]); #expect(vm.pinned && vm.activeLines == [7] && vm.scrollTarget == 7)
    vm.hover(nil); #expect(vm.activeLines == [7], "pinned highlight survives hover-out")
    vm.clearPin(); #expect(vm.activeLines.isEmpty && !vm.pinned)
}

@Test func localizableCatalogIsCompleteForEnglishAndStubbedForOthers() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Localizable.xcstrings")
    let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    #expect(obj["sourceLanguage"] as? String == "en")
    let strings = obj["strings"] as! [String: [String: Any]]
    #expect(strings.count > 60)
    for (key, entry) in strings {
        let loc = entry["localizations"] as! [String: [String: [String: String]]]
        #expect(loc["en"]?["stringUnit"]?["value"] == key, "English must equal the key: \(key)")
        for lang in ["es", "zh-Hans", "ja", "ko"] {
            #expect(loc[lang]?["stringUnit"]?["state"] == "needs_review", "\(lang) stub for \(key) must be marked needs_review")
        }
    }
}
@Test func accessibilityRibbonTextIsAtLeast28pt() {
    // Spec F15: Accessibility mode enlarges ribbon text to ≥ 28 pt. The ribbon uses 28 / 34 pt in that mode.
    let src = try! String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/EchoUI/Ribbon.swift"), encoding: .utf8)
    #expect(src.contains("big ? 28 : 15") && src.contains("big ? 34 : 20"))
}
