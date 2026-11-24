import Foundation
import EchoCore
import EchoAudio
import EchoASR

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
            let feedStart = Date()
            let consumer = Task {
                for await r in engine.results {
                    if args.contains("--verbose") { FileHandle.standardError.write(Data(String(format: "%.2fs final=%d %@\n", Date().timeIntervalSince(feedStart), r.isFinal ? 1 : 0, r.text).utf8)) }
                    if firstPartial == nil { firstPartial = Date().timeIntervalSince(feedStart) }
                    if r.isFinal { finals.append(r.text) }
                }
            }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                feeder.start(onChunk: { engine.append($0) }, onDone: { c.resume() })
            }
            // trailing silence so the VAD closes the last utterance
            for _ in 0..<12 { engine.append([Float](repeating: 0, count: 1600)) }
            await engine.finish(); await consumer.value
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
