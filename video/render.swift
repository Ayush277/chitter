// Renders video/showcase.html to an MP4 (30 fps, 1920x1080) with a synthesized music bed. macOS only, no ffmpeg.
// Usage: swiftc -O render.swift -o /tmp/render-video && /tmp/render-video showcase.html out.mp4 [fromSecond toSecond]
import AppKit
import WebKit
import AVFoundation
import CoreVideo

let W = 1920, H = 1080, FPS = 30, DUR = 38.0
let args = CommandLine.arguments
let html = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])

// ---------- music: soft pad (Am–F–C–G) + bell plucks on key moments ----------
func makeAudio(to url: URL) {
    let sr = 44_100.0, n = Int(DUR * sr)
    var L = [Float](repeating: 0, count: n), R = L
    let chords: [[Double]] = [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [196.0, 261.63, 329.63], [196.0, 246.94, 293.66]]
    let bar = 4.75
    for b in 0..<8 {
        let ch = chords[b % 4], t0 = Double(b) * bar
        for (k, f) in ch.enumerated() {
            for i in 0..<Int(bar * sr + sr) {
                let idx = Int(t0 * sr) + i; if idx >= n { break }
                let t = Double(i) / sr
                let env = min(1, t / 1.2) * (t < bar ? 1 : max(0, 1 - (t - bar)))
                let ph = 2 * Double.pi * f * t
                let v = Float(env * 0.045 * (sin(ph) + 0.35 * sin(2 * ph) + 0.12 * sin(3 * ph)))
                let pan = Float(k - 1) * 0.25
                L[idx] += v * (1 - max(0, pan)); R[idx] += v * (1 + min(0, pan))
            }
        }
    }
    func bell(_ at: Double, _ f: Double, _ amp: Double = 0.16) {
        for i in 0..<Int(2.2 * sr) {
            let idx = Int(at * sr) + i; if idx >= n { break }
            let t = Double(i) / sr, env = exp(-t * 2.8) * min(1, t / 0.004)
            let v = Float(amp * env * (sin(2 * .pi * f * t) + 0.4 * sin(2 * .pi * f * 2.76 * t) * exp(-t * 3)))
            L[idx] += v; R[idx] += v
        }
    }
    for (t, f) in [(1.0, 880.0), (2.3, 659.25), (5.2, 784.0), (8.6, 784.0), (13.6, 659.25), (16.6, 880.0), (19.4, 987.77), (22.2, 1174.66), (26.3, 659.25), (28.0, 880.0), (31.2, 784.0), (33.7, 1318.5), (34.8, 880.0)] { bell(t, f) }
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
    buf.frameLength = AVAudioFrameCount(n)
    for i in 0..<n {
        let fade = Float(min(1, Double(i) / (1.5 * sr)) * min(1, Double(n - i) / (2.5 * sr)))
        buf.floatChannelData![0][i] = L[i] * fade; buf.floatChannelData![1][i] = R[i] * fade
    }
    try? FileManager.default.removeItem(at: url)
    let f = try! AVAudioFile(forWriting: url, settings: fmt.settings)
    try! f.write(from: buf)
}

// ---------- frame capture ----------
final class Renderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H))
    let win: NSWindow
    var loaded: CheckedContinuation<Void, Never>?
    override init() {
        win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        web.navigationDelegate = self
        win.contentView = web; win.setFrameOrigin(NSPoint(x: 4000, y: 4000)); win.orderFrontRegardless()
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { loaded?.resume(); loaded = nil }
    func load() async { await withCheckedContinuation { loaded = $0; web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent()) }; try? await Task.sleep(nanoseconds: 500_000_000) }
    func frame(at t: Double) async -> CGImage? {
        _ = try? await web.evaluateJavaScript("window.__render(\(t))")
        let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: W)
        guard let img = try? await web.takeSnapshot(configuration: cfg) else { return nil }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

func pixelBuffer(from cg: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
    guard let pb else { return nil }
    CVPixelBufferLockBaseAddress(pb, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    CVPixelBufferUnlockBaseAddress(pb, [])
    return pb
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

Task { @MainActor in
    let from = args.count > 4 ? Double(args[3])! : 0, to = args.count > 4 ? Double(args[4])! : DUR
    let silent = FileManager.default.temporaryDirectory.appendingPathComponent("chitter-silent.mp4")
    let wav = FileManager.default.temporaryDirectory.appendingPathComponent("chitter-music.wav")
    try? FileManager.default.removeItem(at: silent)
    let r = Renderer(); await r.load()
    let writer = try! AVAssetWriter(outputURL: silent, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 14_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes:
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
    writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    let total = Int((to - from) * Double(FPS))
    for f in 0..<total {
        let t = from + Double(f) / Double(FPS)
        guard let cg = await r.frame(at: t), let pool = adaptor.pixelBufferPool, let pb = pixelBuffer(from: cg, pool: pool) else { print("frame \(f) failed"); continue }
        while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 5_000_000) }
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(FPS)))
        if f % 90 == 0 { print("frame \(f)/\(total)") }
    }
    input.markAsFinished(); await writer.finishWriting()
    makeAudio(to: wav)
    // mux
    let comp = AVMutableComposition()
    let v = AVURLAsset(url: silent), a = AVURLAsset(url: wav)
    let vt = try! await v.loadTracks(withMediaType: .video)[0], at = try! await a.loadTracks(withMediaType: .audio)[0]
    let vd = try! await v.load(.duration)
    try! comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: .zero, duration: vd), of: vt, at: .zero)
    try! comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), duration: vd), of: at, at: .zero)
    try? FileManager.default.removeItem(at: out)
    let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
    ex.outputURL = out; ex.outputFileType = .mp4
    await ex.export()
    print("export status:", ex.status.rawValue, ex.error?.localizedDescription ?? "ok")
    exit(0)
}
app.run()
