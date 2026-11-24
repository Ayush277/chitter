import AppKit
import EchoCore
import EchoAudio
import EchoVoice
import EchoASR
import EchoUI
import EchoLang
import EchoNet
import EchoNotes

/// Wires capture → resample → ASR → ribbon (+ transcript). Later phases extend this with
/// language ID, translation, records and notes.
@MainActor
final class SessionController: ObservableObject {
    let ribbonModel = RibbonModel()
    lazy var ribbon = RibbonPanel(model: ribbonModel)
    @Published var isListening = false
    @Published var status = "Idle"
    @Published var lines: [Segment] = []

    private let tap = SystemAudioTap()
    let translators = TranslatorChain([])
    lazy var interpreter = Interpreter(translators: translators)
    let dub = DubQueue()
    private var detectedLanguage: String?
    private var lastPartialTranslate = Date.distantPast
    private var engine: ASREngine?
    private var consumer: Task<Void, Never>?
    private var feeder: FileFeeder?
    private var started = Date()
    let store = MeetingStore()
    lazy var index: SearchIndex? = try? SearchIndex(path: SearchIndex.defaultPath())
    private(set) var meeting: MeetingHandle?
    private var lastSpeech = Date()
    private var watchdog: Task<Void, Never>?
    let notesEngine = NotesEngine(providers: NotesProviders.defaultChain())
    private var notesTask: Task<Void, Never>?
    private var notesLineCount = 0
    private var forcedLanguage: String?
    lazy var notesVM = NotesViewModel(store: store, index: index,
        engineLabel: { [notesEngine] in await notesEngine.activeProviderName() },
        generate: { [notesEngine] in await notesEngine.generate($0) })
    lazy var notesWindow = NotesWindowController(vm: notesVM)

    var onStateChange: (() -> Void)?

    func toggleListening() { if isListening { stop() } else { Task { await start() } } }

    private(set) var autoStarted = false

    func start(fixture: FileFeeder? = nil, language: String? = nil, title: String = "Meeting", auto: Bool = false) async {
        guard !isListening else { return }
        autoStarted = auto
        status = "Starting…"; onStateChange?()
        await configureTranslators()
        forcedLanguage = language
        let auto = language == nil && Prefs.sourceLanguage == "auto"
        let code = language ?? (auto ? "en" : Prefs.sourceLanguage)
        // Auto language = Whisper detects the language of every utterance, so a call can switch languages mid-way.
        let engine = auto ? ASRFactory.makeMultilingual() : ASRFactory.make(preferWhisper: Prefs.preferWhisper)
        self.engine = engine
        ribbonModel.accessibilityMode = Prefs.accessibilityMode
        started = Date(); lines = []; lastSpeech = Date()
        meeting = try? store.create(title: title, sourceLanguage: Prefs.sourceLanguage == "auto" ? nil : Prefs.sourceLanguage,
                                    targetLanguage: Prefs.targetLanguage)
        await NetworkGateway.shared.setMeeting(meeting?.info.id)
        watchdog = Task { [weak self] in   // auto-end after N minutes without speech (default 10)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                if Date().timeIntervalSince(self.lastSpeech) > Prefs.autoEndMinutes * 60 { self.stop(); return }
            }
        }
        ribbon.present()

        let startEngine: (String) async -> Bool = { [weak self] c in
            guard let self else { return false }
            let locale = await self.locale(for: c)
            self.detectedLanguage = c
            do { try await engine.start(locale: locale) } catch { self.status = "\(error)"; self.onStateChange?(); return false }
            self.consumer = Task { [weak self] in for await r in engine.results { await self?.handle(r) } }
            return true
        }
        guard await startEngine(code) else { return }

        let sink: @Sendable ([Float]) -> Void = { [weak engine] s in engine?.append(s) }
        do {
            if let fixture { feeder = fixture; fixture.start(onChunk: sink, onDone: { [weak self] in Task { @MainActor in self?.sampleFinished() } }) }
            else { try tap.start(onSamples: sink) }
        } catch { status = "\(error)"; onStateChange?(); return }
        isListening = true; status = "Listening…"; onStateChange?()
        notesLineCount = 0
        notesTask = Task { [weak self] in   // live notes: roughly every 60 s of new speech
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.writeNotes()
            }
        }
    }

    /// F18: plays the bundled sample meeting through the real pipeline.
    func playSample() async {
        guard !isListening else { return }
        let dir = Bundle.main.resourceURL?.appendingPathComponent("Fixtures")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Fixtures")
        var samples: [Float] = []
        for n in ["sample1", "sample2", "sample3"] {
            guard let s = try? AudioFile.loadSamples(url: dir.appendingPathComponent("\(n).wav")) else { continue }
            samples += s + [Float](repeating: 0, count: 16_000)
        }
        guard !samples.isEmpty else { status = "Sample audio is missing from this build."; onStateChange?(); return }
        await start(fixture: FileFeeder(samples: samples), language: "en")
        if let id = meeting?.info.id { notesWindow.show(selecting: id) }
    }

    private func sampleFinished() {
        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); if isListening { stop() } }
    }

    func writeNotes() async {
        guard let m = meeting, lines.count > notesLineCount || !lines.isEmpty else { return }
        notesLineCount = lines.count
        let r = await notesEngine.generate(lines)
        if let data = try? JSONEncoder().encode(r.notes) { m.saveNotes(json: data, markdown: NotesValidator.markdown(r.notes)) }
    }

    private func locale(for code: String) async -> Locale {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !Prefs.preferWhisper, let l = await AppleSpeechEngine.supportedLocale(for: code) { return l }
        #endif
        return Locale(identifier: code)
    }

    func prepareTranslators() async { await configureTranslators() }

    private func configureTranslators() async {
        var chain: [Translator] = []
        #if compiler(>=6.2)
        if #available(macOS 26, *) { chain.append(AppleTranslator()); chain.append(AppleModelTranslator()) }
        #endif
        if await OpenAIClient.isReachable(.ollama) {
            chain.append(LLMTranslator(endpoint: .ollama, apiKey: { nil }))
        }
        await translators.setTranslators(chain)
    }

    private func handle(_ r: ASRResult) {
        let id = lines.count + 1
        let lang = r.language ?? detectedLanguage
        ribbonModel.show(original: r.text, translation: nil, speaker: 0, isFinal: r.isFinal)
        let target = Prefs.targetLanguage
        let wantsTranslation = lang.map { Lang.base($0) != Lang.base(target) } ?? false
        lastSpeech = Date()
        if r.isFinal {
            let seg = Segment(id: id, start: r.start, end: r.end, text: r.text, language: lang)
            lines.append(seg); meeting?.append(seg)
        }
        guard wantsTranslation, r.isFinal || Date().timeIntervalSince(lastPartialTranslate) > 1.2 else { return }
        if !r.isFinal { lastPartialTranslate = Date() }
        Task { [weak self] in
            guard let self, let t = await self.translators.translate(r.text, from: lang, to: target) else { return }
            if r.isFinal && Prefs.dubForeignSpeech { await self.dub.enqueue(t, language: target) }
            await MainActor.run {
                self.ribbonModel.setTranslation(t)
                if r.isFinal, let i = self.lines.firstIndex(where: { $0.id == id }) { self.lines[i].translation = t; self.meeting?.append(self.lines[i]) }
            }
        }
    }

    func stop() {
        tap.stop(); feeder?.stop()
        let e = engine
        Task { await e?.finish() }
        consumer?.cancel()
        watchdog?.cancel(); notesTask?.cancel()
        Task { await dub.stop() }
        if let m = meeting {
            m.finish()
            index?.index(meetingID: m.info.id, segments: m.loadSegments())
            let id = m.info.id
            Task { @MainActor in
                await self.writeNotes()                       // final notes at meeting end
                await NetworkGateway.shared.setMeeting(nil)
                self.notesVM.reloadList(); if self.notesVM.selectedID == id { self.notesVM.load() }
            }
        }
        ribbon.dismiss()
        isListening = false; status = "Idle"; onStateChange?()
    }

    /// A call began in some app or browser (CallWatcher). Start unless the user is already listening.
    func callStarted(_ info: CallInfo) {
        guard Prefs.autoStartOnCalls, !isListening else { return }
        let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"
        Task { await start(title: "\(info.app.replacingOccurrences(of: " (browser call)", with: "")) call \(f.string(from: Date()))", auto: true) }
    }
    /// The call's mic has been closed for the grace period. Only auto-started sessions are ended automatically.
    func callEnded() { if isListening && autoStarted { stop() } }

    func toggleRibbon() { ribbon.isPresented ? ribbon.dismiss() : ribbon.present() }
}
