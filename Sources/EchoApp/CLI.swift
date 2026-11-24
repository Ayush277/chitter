import Foundation
import EchoCore
import EchoAudio
import EchoASR
import EchoLang
import EchoNotes
import EchoNet

/// Headless modes used by scripts/bench.sh and the phase checks.
/// `Chitter --transcribe <wav> [--whisper] [--lang en] [--model base] [--fast]`
enum CLI {
    /// `Chitter --capture-test <seconds>`: records system audio and reports duration captured + peak level.
    static func captureTest(_ args: [String]) async -> Int32 {
        let secs = args.firstIndex(of: "--capture-test").flatMap { Double(args[$0 + 1]) } ?? 5
        let tap = SystemAudioTap()
        let counter = Counter()
        do { try tap.start { counter.add($0) } } catch { print("capture failed: \(error)"); return 1 }
        try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
        tap.stop()
        let (n, peak, nonSilent) = counter.snapshot()
        let out: [String: Any] = ["requested_seconds": secs, "captured_seconds": Double(n) / 16_000, "peak": peak, "non_silent_seconds": Double(nonSilent) / 16_000]
        print(String(decoding: try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), as: UTF8.self))
        return 0
    }

    /// `Chitter --detect-language <wav>`
    static func detectLanguage(_ args: [String]) async -> Int32 {
        guard let i = args.firstIndex(of: "--detect-language"), i + 1 < args.count else { return 2 }
        do {
            let samples = Array(try AudioFile.loadSamples(url: URL(fileURLWithPath: args[i + 1])).prefix(16_000 * 5))
            let d = AudioLanguageDetector(); try await d.prepare()
            let t0 = Date(); let r = await d.detect(samples, candidates: ["en", "es", "zh", "ja", "fr", "ko", "de", "pt", "it", "ru"])
            print("{\"language\":\"\(r?.language ?? "?")\",\"probability\":\(r?.probability ?? 0),\"seconds\":\(Date().timeIntervalSince(t0))}")
            return 0
        } catch { print("error: \(error)"); return 1 }
    }

    /// `Chitter --translate "text" <from> <to>`
    static func translate(_ args: [String]) async -> Int32 {
        guard let i = args.firstIndex(of: "--translate"), i + 3 < args.count else { return 2 }
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let st = await AppleTranslator.status(from: args[i + 2], to: args[i + 3])
            print("pair status: \(st)")
            do { print(try await AppleTranslator().translate(args[i + 1], from: args[i + 2], to: args[i + 3])) } catch { print("error: \(error)") }
        }
        #endif
        return 0
    }

    /// `Chitter --notes <file.txt>` — one transcript line per text line. Prints notes JSON + which provider ran.
    static func notes(_ args: [String]) async -> Int32 {
        guard let i = args.firstIndex(of: "--notes"), i + 1 < args.count,
              let text = try? String(contentsOfFile: args[i + 1], encoding: .utf8) else { return 2 }
        let segs = text.split(separator: "\n").enumerated().map { Segment(id: $0.offset + 1, start: Double($0.offset) * 5, end: Double($0.offset) * 5 + 5, text: String($0.element)) }
        let engine = NotesEngine(providers: NotesProviders.defaultChain())
        let t0 = Date()
        let r = await engine.generate(segs)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: (try? enc.encode(r.notes)) ?? Data(), as: UTF8.self))
        print("provider=\(r.provider) validShare=\(r.validShare) seconds=\(Date().timeIntervalSince(t0)) attempts=\(r.attempts)")
        return 0
    }

    static func run(_ args: [String]) async -> Int32 {
        func opt(_ n: String) -> String? { args.firstIndex(of: n).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        guard let path = opt("--transcribe") else { return 2 }
        let url = URL(fileURLWithPath: path)
        let engine = ASRFactory.make(preferWhisper: args.contains("--whisper"), whisperModel: opt("--model") ?? "base")
        let locale = Locale(identifier: opt("--lang") ?? "en-US")
        do {
            let feeder = try FileFeeder(url: url, speed: args.contains("--fast") ? 20 : 1)
            let t0 = Date()
            try await engine.start(locale: locale)
            let loadTime = Date().timeIntervalSince(t0)
            var firstPartial: Double?, finals: [String] = []
            let rec = opt("--record").flatMap { try? MeetingStore(root: URL(fileURLWithPath: $0)).create(title: "Fixture \(url.deletingPathExtension().lastPathComponent)") }
            let feedStart = Date()
            let consumer = Task {
                for await r in engine.results {
                    if args.contains("--verbose") { FileHandle.standardError.write(Data(String(format: "%.2fs final=%d %@\n", Date().timeIntervalSince(feedStart), r.isFinal ? 1 : 0, r.text).utf8)) }
                    if firstPartial == nil { firstPartial = Date().timeIntervalSince(feedStart) }
                    if r.isFinal { finals.append(r.text); rec?.append(Segment(id: finals.count, start: r.start, end: r.end, text: r.text, language: r.language)) }
                }
            }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                feeder.start(onChunk: { engine.append($0) }, onDone: { c.resume() })
            }
            // trailing silence so the VAD closes the last utterance
            for _ in 0..<12 { engine.append([Float](repeating: 0, count: 1600)) }
            await engine.finish(); await consumer.value
            rec?.finish()
            if let rec { FileHandle.standardError.write(Data("recorded: \(rec.dir.path)\n".utf8)) }
            let total = Date().timeIntervalSince(feedStart)
            let hyp = finals.joined(separator: " ")
            let refURL = url.deletingPathExtension().appendingPathExtension("txt")
            let ref = (try? String(contentsOf: refURL, encoding: .utf8)) ?? ""
            let wer = ref.isEmpty ? -1 : WER.rate(reference: ref, hypothesis: hyp)
            let out: [String: Any] = ["engine": engine.name, "audio_seconds": feeder.duration, "load_seconds": loadTime,
                "first_result_seconds": firstPartial ?? -1, "wall_seconds": total, "wer": wer, "text": hyp,
                "language": locale.identifier]
            let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); return 1 }
    }
}


final class Counter: @unchecked Sendable {
    private var n = 0, nonSilent = 0; private var peak: Float = 0; private let l = NSLock()
    func add(_ s: [Float]) {
        l.lock(); n += s.count; if EnergyVAD.rms(s) > 0.005 { nonSilent += s.count }
        peak = max(peak, s.map { abs($0) }.max() ?? 0); l.unlock()
    }
    func snapshot() -> (Int, Float, Int) { l.lock(); defer { l.unlock() }; return (n, peak, nonSilent) }
}
