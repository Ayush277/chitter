import Foundation

/// Fixed-capacity FIFO of Float samples. Thread-safe via a lock; oldest samples are dropped on overflow.
public final class RingBuffer: @unchecked Sendable {
    private var storage: [Float]
    private var head = 0, count = 0
    private let lock = NSLock()
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
        storage = [Float](repeating: 0, count: capacity)
    }

    public var available: Int { lock.lock(); defer { lock.unlock() }; return count }

    public func write(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        for s in samples.suffix(capacity) {
            let idx = (head + count) % capacity
            storage[idx] = s
            if count == capacity { head = (head + 1) % capacity } else { count += 1 }
        }
    }

    public func read(max n: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let m = min(n, count)
        var out = [Float](repeating: 0, count: m)
        for i in 0..<m { out[i] = storage[(head + i) % capacity] }
        head = (head + m) % capacity; count -= m
        return out
    }
}
