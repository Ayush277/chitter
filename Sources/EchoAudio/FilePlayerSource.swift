import Foundation

/// Feeds a file's samples to a callback at (a multiple of) real time. Used for fixtures, bench and the sample meeting.
public final class FileFeeder: @unchecked Sendable {
    public let samples: [Float]
    public var speed: Double
    private var task: Task<Void, Never>?

    public init(url: URL, speed: Double = 1.0) throws {
        self.samples = try AudioFile.loadSamples(url: url)
        self.speed = speed
    }
    public init(samples: [Float], speed: Double = 1.0) { self.samples = samples; self.speed = speed }

    public var duration: TimeInterval { Double(samples.count) / 16_000 }

    public func start(chunkSeconds: Double = 0.1, onChunk: @escaping @Sendable ([Float]) -> Void,
                      onDone: @escaping @Sendable () -> Void = {}) {
        let n = Int(16_000 * chunkSeconds)
        let samples = self.samples, speed = self.speed
        task = Task.detached {
            var i = 0
            while i < samples.count, !Task.isCancelled {
                onChunk(Array(samples[i..<min(i + n, samples.count)]))
                i += n
                try? await Task.sleep(nanoseconds: UInt64(chunkSeconds / speed * 1_000_000_000))
            }
            onDone()
        }
    }
    public func stop() { task?.cancel() }
}
