import Testing
import Foundation
@testable import EchoLang

struct Fail: Translator { let name = "fail"; func translate(_ t: String, from: String?, to: String) async throws -> String { throw TranslationError.unavailable("x") } }
struct Upper: Translator { let name = "upper"; func translate(_ t: String, from: String?, to: String) async throws -> String { t.uppercased() } }

@Test func chainFallsThroughToNextProvider() async {
    let c = TranslatorChain([Fail(), Upper()])
    #expect(await c.translate("hola", from: "es", to: "en") == "HOLA")
    #expect(await c.lastUsed == "upper")
}
@Test func chainReturnsNilWhenAllFail() async {
    #expect(await TranslatorChain([Fail()]).translate("hola", from: "es", to: "en") == nil)
}
@Test func chainSkipsSameLanguage() async {
    #expect(await TranslatorChain([Upper()]).translate("hi", from: "en-US", to: "en") == nil)
}
@Test func textLanguageIDGetsFiveLanguages() {
    let samples = ["en": "Welcome everyone to the weekly planning meeting.", "es": "Buenos días a todos, vamos a revisar el calendario.",
                   "fr": "Bonjour à tous, nous allons examiner le calendrier.", "ja": "皆さん、おはようございます。今日は進捗について話し合います。",
                   "zh": "大家好，今天我们来讨论一下项目的进度。"]
    for (code, text) in samples { #expect(TextLanguageID.detect(text)?.language.hasPrefix(code) == true) }
}
@Test func langBase() { #expect(Lang.base("zh-Hans") == "zh"); #expect(Lang.base("en_US") == "en") }

#if compiler(>=6.2) && canImport(FoundationModels)
@available(macOS 26, *)
@Test func appleModelTranslatorTranslatesWhenAvailable() async throws {
    // Runs only where Apple Intelligence is enabled; otherwise it must fail cleanly so the chain falls through.
    do {
        let out = try await AppleModelTranslator().translate("Buenos días a todos", from: "es", to: "en")
        #expect(out.lowercased().contains("good morning") || out.lowercased().contains("hello"))
    } catch is TranslationError { /* unavailable here: fine, chain moves on */ }
}
#endif
