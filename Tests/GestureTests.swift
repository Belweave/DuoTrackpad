import XCTest
@testable import DuoCore

final class GestureTests: XCTestCase {
    func testPointerMovesImmediatelyWithoutRecognitionDelay() {
        var inputs: [Wire.Input] = [], engine = GestureEngine()
        engine.onInput = { inputs.append($0) }
        engine.began([(1, .init(x: 10, y: 10))], time: 1, rightEdge: 600)
        engine.move([(1, .init(x: 11, y: 12))], time: 1.008)
        XCTAssertEqual(inputs, [.init(.move, x: 1, y: 2, timestamp: 1.008)])
    }
    func testScrollPhasesAndNoPointerAfterFingerLift() {
        var inputs: [Wire.Input] = [], engine = GestureEngine()
        engine.onInput = { inputs.append($0) }
        engine.began([(1, .init(x: 10, y: 10)), (2, .init(x: 100, y: 10))], time: 1, rightEdge: 600)
        engine.move([(1, .init(x: 10, y: 20)), (2, .init(x: 100, y: 20))], time: 1.01)
        engine.ended([1], time: 1.02, cancelled: false)
        engine.move([(2, .init(x: 200, y: 30))], time: 1.03)
        engine.ended([2], time: 1.04, cancelled: false)
        XCTAssertEqual(inputs.map(\.kind), [.scrollBegin, .scroll, .scrollEnd])
        XCTAssertEqual(inputs[1].y, 10)
        XCTAssertGreaterThan(inputs[2].y, 0)
    }
    func testHoldDragAlwaysReleasesOnCancel() {
        var inputs: [Wire.Input] = [], engine = GestureEngine()
        engine.onInput = { inputs.append($0) }
        engine.began([(1, .init(x: 10, y: 10))], time: 1, rightEdge: 600)
        engine.hold(time: 1.38)
        engine.move([(1, .init(x: 30, y: 20))], time: 1.4)
        engine.cancel()
        engine.ended([1], time: 1.5, cancelled: false)
        XCTAssertEqual(inputs.map(\.kind), [.dragStart, .move, .dragEnd, .stop])
    }
    func testSmallRecognizedScrollDoesNotAlsoRightClick() {
        var inputs: [Wire.Input] = [], engine = GestureEngine()
        engine.onInput = { inputs.append($0) }
        engine.began([(1, .init(x: 10, y: 10)), (2, .init(x: 100, y: 10))], time: 1, rightEdge: 600)
        engine.move([(1, .init(x: 10, y: 14)), (2, .init(x: 100, y: 14))], time: 1.01)
        engine.ended([1, 2], time: 1.02, cancelled: false)
        XCTAssertEqual(inputs.map(\.kind), [.scrollBegin, .scroll, .scrollEnd])
    }
    func testPinchNeverLeaksScrollOrClick() {
        var inputs: [Wire.Input] = [], engine = GestureEngine()
        engine.onInput = { inputs.append($0) }
        engine.began([(1, .init(x: 100, y: 100)), (2, .init(x: 200, y: 100))], time: 1, rightEdge: 600)
        engine.move([(1, .init(x: 80, y: 100)), (2, .init(x: 220, y: 100))], time: 1.01)
        engine.ended([1, 2], time: 1.1, cancelled: false)
        XCTAssertEqual(inputs.map(\.kind), [.zoom])
        XCTAssertGreaterThan(inputs[0].x, 0)
    }
    func testThreeFingerCommandFiresOnceAndDoesNotClick() {
        var inputs: [Wire.Input] = [], engine = GestureEngine()
        engine.onInput = { inputs.append($0) }
        engine.began([(1, .init(x: 10, y: 100)), (2, .init(x: 70, y: 100)), (3, .init(x: 130, y: 100))], time: 1, rightEdge: 600)
        engine.move([(1, .init(x: 10, y: 20)), (2, .init(x: 70, y: 20)), (3, .init(x: 130, y: 20))], time: 1.1)
        engine.move([(1, .init(x: 10, y: 0))], time: 1.2)
        engine.ended([1, 2, 3], time: 1.3, cancelled: false)
        XCTAssertEqual(inputs, [MacAction.missionControl.input])
    }
    func testThreeFingerDragAndFourFingerControls() {
        var inputs: [Wire.Input] = [], controls = 0, engine = GestureEngine()
        engine.threeFingerDrag = true; engine.onInput = { inputs.append($0) }; engine.onControls = { controls += 1 }
        engine.began([(1, .init(x: 10, y: 100)), (2, .init(x: 70, y: 100)), (3, .init(x: 130, y: 100))], time: 1, rightEdge: 600)
        engine.move([(1, .init(x: 20, y: 100)), (2, .init(x: 80, y: 100)), (3, .init(x: 140, y: 100))], time: 1.05)
        engine.ended([1, 2, 3], time: 1.1, cancelled: false)
        XCTAssertEqual(inputs.map(\.kind), [.dragStart, .move, .dragEnd])
        engine.began([(1, .init(x: 10, y: 100)), (2, .init(x: 70, y: 100)), (3, .init(x: 130, y: 100)), (4, .init(x: 190, y: 100))], time: 2, rightEdge: 600)
        engine.ended([1, 2, 3, 4], time: 2.1, cancelled: false)
        XCTAssertEqual(controls, 1)
    }
    func testAccelerationIsFinitePreciseAndOptional() {
        var response = PointerResponse()
        let slow = response.apply(x: 0.1, y: -0.1, timestamp: 1, sensitivity: 1, accelerated: true)
        XCTAssertLessThan(slow.x, 0.1)
        response.reset()
        let fast = response.apply(x: 20, y: -20, timestamp: 1, sensitivity: 1, accelerated: true)
        XCTAssertGreaterThan(fast.x, 20)
        let linear = response.apply(x: 2, y: -3, timestamp: 1.008, sensitivity: 1.5, accelerated: false)
        XCTAssertEqual(linear.x, 3); XCTAssertEqual(linear.y, -4.5)
    }
    func testSequentialFourFingerTapWorksWithThreeFingerDragEnabled() {
        var controls = 0, inputs: [Wire.Input] = [], engine = GestureEngine()
        engine.threeFingerDrag = true; engine.onControls = { controls += 1 }; engine.onInput = { inputs.append($0) }
        for id in 1...4 { engine.began([(id, .init(x: Double(id * 40), y: 100))], time: 1 + Double(id) * 0.01, rightEdge: 600) }
        engine.ended([1, 2, 3, 4], time: 1.15, cancelled: false)
        XCTAssertEqual(controls, 1); XCTAssertTrue(inputs.isEmpty)
    }
}
