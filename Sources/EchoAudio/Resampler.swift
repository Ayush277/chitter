import AVFoundation

/// Converts any PCM buffer to 16 kHz mono Float32 samples.
public final class AudioResampler {
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    public static let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        if converter == nil || inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: Self.target)
        }
        guard let converter else { return [] }
        let ratio = Self.target.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.target, frameCapacity: cap) else { return [] }
        var supplied = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
        guard err == nil, let ch = out.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
    }
}

public enum AudioFile {
    /// Reads a whole audio file as 16 kHz mono Float32.
    public static func loadSamples(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let r = AudioResampler()
        var all: [Float] = []
        let frames: AVAudioFrameCount = 16_384
        while file.framePosition < file.length {
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
            try file.read(into: buf, frameCount: frames)
            if buf.frameLength == 0 { break }
            all += r.convert(buf)
        }
        return all
    }
}
