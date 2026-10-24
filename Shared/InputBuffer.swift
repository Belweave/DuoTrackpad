import Foundation

/// A bounded FIFO confined to its owner's serial queue; no locking or internal dispatch.
/// Enqueue/pop are O(1) while storage is uniquely owned. Do not copy a live buffer on the hot path.
struct InputBuffer {
    enum Failure: Error, Equatable { case full, invalidInput }

    let capacity: Int
    private var slots: [Wire.Input?]
    private var head = 0
    private(set) var count = 0
    var isEmpty: Bool { count == 0 }

    init(capacity: Int = 64) {
        precondition(capacity > 0, "InputBuffer capacity must be positive")
        self.capacity = capacity
        slots = Array(repeating: nil, count: capacity)
    }

    /// Only adjacent relative move/scroll events of the same kind may merge. Every other
    /// kind is a barrier, including future protocol kinds. The newest timestamp survives.
    /// If the sum exceeds wire limits, retain separate packets when there is room.
    /// Failure leaves the queue unchanged: the owner should close rather than drop a barrier.
    mutating func enqueue(_ input: Wire.Input) throws {
        guard input.isValid else { throw Failure.invalidInput }
        if count > 0, input.kind == .move || input.kind == .scroll {
            let tail = (head + count - 1) % capacity
            if let previous = slots[tail], previous.kind == input.kind {
                let x = previous.x + input.x, y = previous.y + input.y
                if abs(x) <= 8192, abs(y) <= 8192 {
                    slots[tail] = .init(input.kind, x: x, y: y, timestamp: input.timestamp)
                    return
                }
            }
        }
        guard count < capacity else { throw Failure.full }
        slots[(head + count) % capacity] = input
        count += 1
    }

    mutating func popFirst() -> Wire.Input? {
        guard count > 0 else { return nil }
        let input = slots[head]
        slots[head] = nil
        head = (head + 1) % capacity
        count -= 1
        return input
    }

    /// Scalar packets have no owned resources; stale slots are overwritten before they can be read.
    mutating func removeAll() {
        head = 0
        count = 0
    }
}
