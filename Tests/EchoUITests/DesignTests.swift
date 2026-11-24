import Testing
import Foundation
import EchoCore
import EchoNotes
@testable import EchoUI

/// Spec §4.3: body-text pairs must meet WCAG AA (4.5:1).
@Test func bodyTextPairsMeetAA() {
    let pairs: [(String, Tokens.Hex, Tokens.Hex)] = [
        ("text-light on ink", Tokens.textLight, Tokens.ink), ("text-light on woad", Tokens.textLight, Tokens.woad),
        ("text-dark on linen", Tokens.textDark, Tokens.linen), ("text-dark on bone", Tokens.textDark, Tokens.bone),
        ("ink on weld (primary button)", Tokens.ink, Tokens.weld),
        ("verdigris on ink (translation)", Tokens.verdigris, Tokens.ink),
        ("verdigris on woad (translation)", Tokens.verdigris, Tokens.woad),
        ("verdigris-deep on linen (translation, light)", Tokens.verdigrisDeep, Tokens.linen),
        ("verdigris-deep on bone (translation, light)", Tokens.verdigrisDeep, Tokens.bone),
        ("indigo-dye links on linen", Tokens.indigoDye, Tokens.linen),
        ("weld on ink", Tokens.weld, Tokens.ink),
    ]
    for (name, a, b) in pairs { #expect(a.contrast(with: b) >= 4.5, "\(name) = \(a.contrast(with: b))") }
}
@Test func madderIsLargeTextOrNonTextOnly() {
    let c = Tokens.madder.contrast(with: Tokens.ink)
    #expect(c >= 3.0, "madder on ink must pass the large-text/non-text bar, got \(c)")
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
