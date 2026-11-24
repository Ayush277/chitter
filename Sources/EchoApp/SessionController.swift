import AppKit
import EchoCore
import EchoAudio
import EchoASR
import EchoUI

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
    private var engine: ASREngine?
    private var consumer: Task<Void, Never>?
    private var feeder: FileFeeder?
    private var started = Date()

    var onStateChange: (() -> Void)?

    func toggleListening() { if isListening { stop() } else { Task { await start() } } }

    func start(fixture: URL? = nil) async {
        guard !isListening else { return }
        status = "Starting…"; onStateChange?()
        let engine = ASRFactory.makeDefault()
        self.engine = engine
        do {
            try await engine.start(locale: Locale.current)
        } catch {
            status = "\(error)"; onStateChange?(); return
        }
        started = Date(); lines = []
        ribbon.present()
        let sink: @Sendable ([Float]) -> Void = { [weak engine] s in engine?.append(s) }
        do {
            if let fixture { feeder = try FileFeeder(url: fixture); feeder?.start(onChunk: sink) }
            else { try tap.start(onSamples: sink) }
        } catch {
            status = "\(error)"; onStateChange?(); return
        }
        isListening = true; status = "Listening…"; onStateChange?()
        consumer = Task { [weak self] in
            for await r in engine.results { await self?.handle(r) }
        }
    }

    private func handle(_ r: ASRResult) {
        let id = lines.count + 1
        ribbonModel.show(original: r.text, translation: nil, speaker: 0, isFinal: r.isFinal)
        if r.isFinal { lines.append(Segment(id: id, start: r.start, end: r.end, text: r.text, language: r.language)) }
    }

    func stop() {
        tap.stop(); feeder?.stop()
        let e = engine
        Task { await e?.finish() }
        consumer?.cancel()
        ribbon.dismiss()
        isListening = false; status = "Idle"; onStateChange?()
    }

    func toggleRibbon() { ribbon.isPresented ? ribbon.dismiss() : ribbon.present() }
}
