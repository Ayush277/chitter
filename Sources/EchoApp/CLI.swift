import Darwin
import Foundation
import EchoCore
import EchoAudio
import EchoASR
import EchoLang
import EchoNotes
import EchoVoice
#if canImport(FoundationModels)
import FoundationModels
#endif
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

    /// `Chitter --interpret-test <wav> <from> <to>` — runs ASR → translate → TTS on a fixture and prints stage timings
    /// (mic capture and BlackHole playback excluded).
    static func interpretTest(_ args: [String]) async -> Int32 {
        guard let i = args.firstIndex(of: "--interpret-test"), i + 3 < args.count else { return 2 }
        let from = args[i + 2], to = args[i + 3]
        do {
            let samples = try AudioFile.loadSamples(url: URL(fileURLWithPath: args[i + 1]))
            let t0 = Date()
            let text = await Interpreter.recognize(samples, language: from) ?? ""
            let tASR = Date().timeIntervalSince(t0)
            var chain: [Translator] = []
            #if compiler(>=6.2)
            if #available(macOS 26, *) { chain.append(AppleTranslator()) }
            #endif
            let tc = TranslatorChain(chain)
            let translated = await tc.translate(text, from: from, to: to)
            let tTr = Date().timeIntervalSince(t0)
            let bufs = await SpeechPlayer().synthesize(translated ?? text, language: translated == nil ? from : to)
            let tTTS = Date().timeIntervalSince(t0)
            let frames = bufs.reduce(0) { $0 + Int($1.frameLength) }
            let rate = bufs.first?.format.sampleRate ?? 1
            let out: [String: Any] = ["audio_seconds": Double(samples.count) / 16_000, "asr_s": tASR, "translate_s": tTr - tASR,
                "tts_s": tTTS - tTr, "total_s": tTTS, "recognized": text, "translated": translated ?? NSNull(),
                "spoken_audio_seconds": Double(frames) / rate, "bluehole_installed": AudioDevices.blackHole() != nil]
            print(String(decoding: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), as: UTF8.self))
            return 0
        } catch { print("error: \(error)"); return 1 }
    }

    /// `Chitter --soak <seconds> <wav>`: loops a fixture through the default engine in real time and samples RSS / CPU.
    static func soak(_ args: [String]) async -> Int32 {
        guard let i = args.firstIndex(of: "--soak"), i + 2 < args.count, let secs = Double(args[i + 1]) else { return 2 }
        do {
            let samples = try AudioFile.loadSamples(url: URL(fileURLWithPath: args[i + 2]))
            let engine = ASRFactory.make(preferWhisper: args.contains("--whisper"))
            try await engine.start(locale: Locale(identifier: "en-US"))
            var finals = 0
            let consumer = Task { for await r in engine.results where r.isFinal { finals += 1 } }
            func rss() -> Double {
                var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
                let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: 1) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
                return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
            }
            func cpuSeconds() -> Double { var u = rusage(); getrusage(RUSAGE_SELF, &u); return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6 }
            let start = Date(); var timeline: [[Double]] = []; var nextSample = 10.0, pos = 0
            let cpu0 = cpuSeconds()
            while Date().timeIntervalSince(start) < secs {
                engine.append(Array(samples[pos..<min(pos + 1600, samples.count)])); pos += 1600
                if pos >= samples.count { pos = 0; for _ in 0..<12 { engine.append([Float](repeating: 0, count: 1600)) } }
                try? await Task.sleep(nanoseconds: 100_000_000)
                let t = Date().timeIntervalSince(start)
                if t >= nextSample { timeline.append([t, rss(), (cpuSeconds() - cpu0) / t * 100]); nextSample += 10
                    FileHandle.standardError.write(Data(String(format: "t=%.0fs rss=%.0fMB cpu=%.1f%% finals=%d\n", t, rss(), (cpuSeconds() - cpu0) / t * 100, finals).utf8)) }
            }
            await engine.finish(); await consumer.value
            let out: [String: Any] = ["engine": engine.name, "seconds": secs, "finals": finals, "timeline": timeline]
            print(String(decoding: try JSONSerialization.data(withJSONObject: out), as: UTF8.self))
            return 0
        } catch { print("error: \(error)"); return 1 }
    }

    /// `Chitter --detect-calls` — prints every process Core Audio says has the mic or speakers open, and the verdict.
    static func detectCalls() -> Int32 {
        let procs = CallDetector.audioProcesses()
        for p in procs { print("pid \(p.pid)  in=\(p.isRunningInput ? 1 : 0) out=\(p.isRunningOutput ? 1 : 0)  \(p.bundleID)") }
        print("verdict:", CallDetector.classify(procs).map { "CALL in \($0.app)" } ?? "no call")
        return 0
    }

    /// `Chitter --dub-test <wav> <targetLang>` — auto-detect language → ASR → translate → voice, with stage timings.
    static func dubTest(_ args: [String]) async -> Int32 {
        guard let i = args.firstIndex(of: "--dub-test"), i + 2 < args.count else { return 2 }
        let to = args[i + 2]
        do {
            let samples = try AudioFile.loadSamples(url: URL(fileURLWithPath: args[i + 1]))
            let engine = ASRFactory.makeMultilingual()
            try await engine.start(locale: Locale(identifier: "en-US"))
            var finals: [ASRResult] = []
            let consumer = Task { for await r in engine.results where r.isFinal { finals.append(r) } }
            let t0 = Date(); var pos = 0
            while pos < samples.count { engine.append(Array(samples[pos..<min(pos + 3_200, samples.count)])); pos += 3_200 }
            for _ in 0..<12 { engine.append([Float](repeating: 0, count: 1_600)) }
            await engine.finish(); await consumer.value
            let tASR = Date().timeIntervalSince(t0)
            let text = finals.map(\.text).joined(separator: " "); let lang = finals.first?.language ?? "?"
            var chain: [Translator] = []
            #if compiler(>=6.2)
            if #available(macOS 26, *) { chain.append(AppleTranslator()); chain.append(AppleModelTranslator()) }
            #endif
            let tc = TranslatorChain(chain)
            #if compiler(>=6.2)
            if #available(macOS 26, *), !args.contains("--cold") { await AppleModelTranslator.warmUp() }   // the app does this when a call starts
            #endif
            let tW = Date()
            let tr = await tc.translate(text, from: lang, to: to)
            let tTrOnly = Date().timeIntervalSince(tW)
            let tTr = Date().timeIntervalSince(t0)
            let bufs = await SpeechPlayer().synthesize(tr ?? text, language: tr == nil ? lang : to)
            let tTTS = Date().timeIntervalSince(t0)
            let voice = SpeechPlayer.bestVoice(for: to)
            let out: [String: Any] = ["detected_language": lang, "heard": text, "translated": tr ?? NSNull(), "translator": await tc.lastUsed ?? NSNull(),
                "asr_s": tASR, "translate_s": tTrOnly, "voice_s": tTTS - tTr, "total_s": tASR + tTrOnly + (tTTS - tTr), "audio_in_s": Double(samples.count) / 16_000,
                "voice": voice.map { "\($0.name) (quality \($0.quality.rawValue))" } ?? "?", "voice_audio_s": Double(bufs.reduce(0) { $0 + Int($1.frameLength) }) / (bufs.first?.format.sampleRate ?? 1)]
            print(String(decoding: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), as: UTF8.self))
            return 0
        } catch { print("error: \(error)"); return 1 }
    }

    /// `Chitter --translate-bench` — compares ways of calling Apple's on-device model for translation.
    static func translateBench() async -> Int32 {
        #if compiler(>=6.2) && canImport(FoundationModels)
        if #available(macOS 26, *) {
            let text = "今天我们来讨论一下项目的进度,并决定下周的工作安排。"
            func time(_ label: String, _ f: () async throws -> String) async {
                let t = Date(); let r = (try? await f()) ?? "ERR"
                print(String(format: "%@: %.2fs  %@", label, Date().timeIntervalSince(t), r))
            }
            let instr = "Translate the user's text into English. Reply with only the translation."
            await time("new session each call (1st)") { try await LanguageModelSession(instructions: instr).respond(to: text).content }
            await time("new session each call (2nd)") { try await LanguageModelSession(instructions: instr).respond(to: text).content }
            let warm = LanguageModelSession(instructions: instr); warm.prewarm()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await time("prewarmed session") { try await warm.respond(to: text).content }
            await time("temperature 0") { try await LanguageModelSession(instructions: instr).respond(to: text, options: GenerationOptions(temperature: 0)).content }
            await time("streamed, first token") {
                var first = ""; let t = Date()
                for try await p in LanguageModelSession(instructions: instr).streamResponse(to: text) { first = p.content; print(String(format: "  first partial at %.2fs", Date().timeIntervalSince(t))); break }
                return first
            }
            let short = LanguageModelSession(instructions: "English:")
            await time("minimal instructions") { try await short.respond(to: text, options: GenerationOptions(temperature: 0)).content }
        }
        #endif
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
