// Re-encodes an MP4's video at a target bitrate and copies its audio. Usage: shrink in.mp4 out.mp4 kbps
import AVFoundation
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1])), outURL = URL(fileURLWithPath: a[2]); try? FileManager.default.removeItem(at: outURL)
let sem = DispatchSemaphore(value: 0)
Task {
    let v = try await asset.loadTracks(withMediaType: .video)[0], au = try await asset.loadTracks(withMediaType: .audio)[0]
    let size = try await v.load(.naturalSize); let fmt = try await au.load(.formatDescriptions).first
    let reader = try AVAssetReader(asset: asset), writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let vo = AVAssetReaderTrackOutput(track: v, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    let ao = AVAssetReaderTrackOutput(track: au, outputSettings: nil)
    reader.add(vo); reader.add(ao)
    let vi = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(a[3])! * 1000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 90]])
    let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: fmt)
    writer.add(vi); writer.add(ai); reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    await withTaskGroup(of: Void.self) { g in
        for (input, output, label) in [(vi, vo, "v"), (ai, ao, "a")] {
            g.addTask { await withCheckedContinuation { c in
                input.requestMediaDataWhenReady(on: DispatchQueue(label: label)) {
                    while input.isReadyForMoreMediaData {
                        if let b = output.copyNextSampleBuffer() { input.append(b) } else { input.markAsFinished(); c.resume(); return }
                    } } } }
        }
    }
    await writer.finishWriting(); print(writer.status == .completed ? "ok" : "failed \(String(describing: writer.error))"); sem.signal()
}
sem.wait()
