import XCTest
@testable import DuoCore

final class InputBufferTests: XCTestCase {
    func testFIFOAndWraparoundAgainstReference() throws {
        var buffer = InputBuffer(capacity: 7)
        var reference: [Wire.Input] = []
        for step in 0..<20_000 {
            if step % 3 == 0 || reference.count == buffer.capacity {
                XCTAssertEqual(buffer.popFirst(), reference.isEmpty ? nil : reference.removeFirst())
            } else {
                // Non-motion events are barriers and cannot coalesce.
                let input = Wire.Input(step % 2 == 0 ? .leftClick : .rightClick, timestamp: Double(step))
                try buffer.enqueue(input)
                reference.append(input)
            }
            XCTAssertEqual(buffer.count, reference.count)
            XCTAssertEqual(buffer.isEmpty, reference.isEmpty)
        }
        while !reference.isEmpty { XCTAssertEqual(buffer.popFirst(), reference.removeFirst()) }
        XCTAssertNil(buffer.popFirst())
    }

    func testAdjacentMotionCoalescesWithNewestTimestamp() throws {
        var buffer = InputBuffer(capacity: 1)
        try buffer.enqueue(.init(.move, x: 2, y: -4, timestamp: 10))
        try buffer.enqueue(.init(.move, x: 3, y: 1, timestamp: 11))
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.popFirst(), .init(.move, x: 5, y: -3, timestamp: 11))
        try buffer.enqueue(.init(.scroll, x: -1, y: 3, timestamp: 12))
        try buffer.enqueue(.init(.scroll, x: 1, y: -3, timestamp: 13))
        XCTAssertEqual(buffer.popFirst(), .init(.scroll, timestamp: 13))
    }

    func testEveryNonMotionKindIsASemanticBarrier() throws {
        // Derive the vocabulary dynamically so new gesture/control kinds are barriers by default.
        let kinds = (UInt8.min...UInt8.max).compactMap(Wire.Kind.init(rawValue:))
        for kind in kinds where kind != .move && kind != .scroll {
            var buffer = InputBuffer(capacity: 3)
            let first = Wire.Input(.move, x: 1)
            let barrier = Wire.Input(kind)
            let last = Wire.Input(.move, x: 2)
            try buffer.enqueue(first)
            try buffer.enqueue(barrier)
            try buffer.enqueue(last)
            XCTAssertEqual(buffer.count, 3)
            XCTAssertEqual(buffer.popFirst(), first)
            XCTAssertEqual(buffer.popFirst(), barrier)
            XCTAssertEqual(buffer.popFirst(), last)
        }
    }

    func testMotionKindsDoNotMergeAcrossEachOther() throws {
        var buffer = InputBuffer(capacity: 3)
        for kind in [Wire.Kind.move, .scroll, .move] { try buffer.enqueue(.init(kind, x: 1)) }
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.popFirst()?.kind, .move)
        XCTAssertEqual(buffer.popFirst()?.kind, .scroll)
        XCTAssertEqual(buffer.popFirst()?.kind, .move)
    }

    func testFullQueueDoesNotDropBarrierOrMutateExistingInput() throws {
        var buffer = InputBuffer(capacity: 1)
        let input = Wire.Input(.dragStart)
        try buffer.enqueue(input)
        XCTAssertThrowsError(try buffer.enqueue(.init(.dragEnd))) { error in
            XCTAssertEqual(error as? InputBuffer.Failure, .full)
        }
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.popFirst(), input)
    }

    func testLargeMotionStaysInSeparateWireValidPackets() throws {
        var buffer = InputBuffer(capacity: 2)
        let input = Wire.Input(.move, x: 8192, y: -8192)
        try buffer.enqueue(input)
        try buffer.enqueue(input)
        XCTAssertEqual(buffer.count, 2)
        XCTAssertThrowsError(try buffer.enqueue(input))
        XCTAssertEqual(buffer.popFirst(), input)
        XCTAssertEqual(buffer.popFirst(), input)
    }

    func testRejectsInvalidValuesWithoutPoisoningQueue() throws {
        var buffer = InputBuffer(capacity: 2)
        for input in [Wire.Input(.move, x: .nan), .init(.scroll, y: .infinity),
                      .init(.ping, timestamp: -.infinity), .init(.move, x: 8193)] {
            XCTAssertThrowsError(try buffer.enqueue(input)) { error in
                XCTAssertEqual(error as? InputBuffer.Failure, .invalidInput)
            }
        }
        XCTAssertTrue(buffer.isEmpty)
        try buffer.enqueue(.init(.leftClick))
        XCTAssertEqual(buffer.popFirst(), .init(.leftClick))
    }

    func testClearAfterWraparoundAndValueSemantics() throws {
        var buffer = InputBuffer(capacity: 2)
        try buffer.enqueue(.init(.leftClick))
        try buffer.enqueue(.init(.dragStart))
        _ = buffer.popFirst()
        var copy = buffer
        buffer.removeAll()
        try buffer.enqueue(.init(.stop))
        XCTAssertEqual(buffer.popFirst(), .init(.stop))
        XCTAssertNil(buffer.popFirst())
        XCTAssertEqual(copy.popFirst(), .init(.dragStart))
    }
}
