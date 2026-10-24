import Foundation

/// A bounded handoff before the transport queue. At most one drain block is scheduled,
/// so a congested transport cannot create an unbounded queue of per-touch closures.
final class InputMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = InputBuffer()
    private var scheduled = false
    private var failed = false
    private var closed = false
    func submit(_ input: Wire.Input) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        do { try buffer.enqueue(input) } catch { failed = true }
        if scheduled { return false }
        scheduled = true
        return true
    }
    func next() throws -> Wire.Input? {
        lock.lock(); defer { lock.unlock() }
        if failed { throw InputBuffer.Failure.full }
        guard !closed, let input = buffer.popFirst() else { scheduled = false; return nil }
        return input
    }
    func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true; buffer.removeAll()
    }
}
