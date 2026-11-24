import Foundation
import AVFoundation

/// Voice-over for foreign speech: speaks translated lines one after another, in order. When it falls behind
/// it speaks faster, then drops the oldest line, so the voice never drifts far from the live conversation.
public actor DubQueue {
    private var pending: [(text: String, language: String)] = []
    private var running = false
    private let player = SpeechPlayer()
    public private(set) var spoken = 0
    public private(set) var dropped = 0
    public var maxBacklog = 3
    public var deviceID: UInt32?

    public init() {}

    public func enqueue(_ text: String, language: String) {
        pending.append((text, language))
        while pending.count > maxBacklog { pending.removeFirst(); dropped += 1 }
        if !running { running = true; Task { await self.drain() } }
    }

    /// Speech rate for a given backlog: normal when caught up, up to ~1.3x when behind.
    public static func rate(forBacklog n: Int) -> Float { min(0.65, AVSpeechUtteranceDefaultSpeechRate + 0.05 * Float(max(0, n - 1))) }

    private func drain() async {
        while let next = pending.first {
            pending.removeFirst()
            let bufs = await player.synthesize(next.text, language: next.language, rate: Self.rate(forBacklog: pending.count + 1))
            await player.play(bufs, deviceID: deviceID)
            spoken += 1
        }
        running = false
    }
    public func stop() { pending.removeAll(); player.stop() }
}
