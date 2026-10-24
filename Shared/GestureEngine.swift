import Foundation

struct TouchPoint: Equatable {
    var x: Double
    var y: Double
    static let zero = TouchPoint(x: 0, y: 0)
    func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
}

/// At most five tracked contacts. No frame-rate timer or recognition delay on single-finger motion.
struct GestureEngine {
    enum Mode { case undecided, scroll, zoom, rotate, command, drag }
    var onInput: ((Wire.Input) -> Void)?
    var onControls: (() -> Void)?
    var threeFingerDrag = false
    private var points: [Int: TouchPoint] = [:]
    private var origins: [Int: TouchPoint] = [:]
    private var maxFingers = 0
    private var beganAt = 0.0
    private var lastTime = 0.0
    private var moved = false
    private var cancelled = false
    private var mode = Mode.undecided
    private var baseCenter = TouchPoint.zero
    private var baseDistance = 0.0
    private var previousDistance = 0.0
    private var baseAngle = 0.0
    private var previousAngle = 0.0
    private var velocity = TouchPoint.zero
    private var scrollLastTime = 0.0
    private var lastTapTime = -10.0
    private var lastTapPoint = TouchPoint.zero
    private var previousTwoTapTime = -10.0
    private var edgeStart = false
    var activeCount: Int { points.count }

    mutating func began(_ additions: [(Int, TouchPoint)], time: Double, rightEdge: Double) {
        if points.isEmpty {
            maxFingers = 0; beganAt = time; moved = false; cancelled = false; mode = .undecided
            velocity = .zero; scrollLastTime = 0; edgeStart = false
        } else {
            endContinuous(allowMomentum: false)
            mode = .undecided
        }
        for (id, point) in additions where points.count < 5 { points[id] = point; origins[id] = point }
        maxFingers = max(maxFingers, points.count)
        if points.count > 1 { lastTapTime = -10 }
        baseCenter = center(); baseDistance = span(); previousDistance = baseDistance
        baseAngle = angle(); previousAngle = baseAngle; lastTime = time
        edgeStart = points.count == 2 && points.values.allSatisfy { $0.x > rightEdge - 44 }
        if points.count == 1, maxFingers == 1, time - lastTapTime < 0.28,
           baseCenter.distance(to: lastTapPoint) < 28 {
            mode = .drag; moved = true; onInput?(.init(.dragStart, timestamp: time))
        }
    }

    mutating func hold(time: Double) {
        guard points.count == 1, maxFingers == 1, !moved, !cancelled, mode == .undecided else { return }
        mode = .drag; moved = true; onInput?(.init(.dragStart, timestamp: time))
    }

    mutating func move(_ updates: [(Int, TouchPoint)], time: Double) {
        guard !points.isEmpty, !cancelled else { return }
        let previous = center()
        for (id, point) in updates where points[id] != nil {
            points[id] = point
            if let origin = origins[id], origin.distance(to: point) > 5 { moved = true }
        }
        let current = center(), dx = current.x - previous.x, dy = current.y - previous.y
        let dt = min(0.05, max(1.0 / 240, time - lastTime)); lastTime = time
        if points.count == 3, maxFingers == 3, threeFingerDrag, mode == .undecided,
           current.distance(to: baseCenter) > 2 {
            mode = .drag; moved = true; onInput?(.init(.dragStart, timestamp: time))
            onInput?(.init(.move, x: current.x - baseCenter.x, y: current.y - baseCenter.y, timestamp: time))
            return
        }
        if mode == .drag || (maxFingers == 1 && points.count == 1) {
            if dx != 0 || dy != 0 { onInput?(.init(.move, x: dx, y: dy, timestamp: time)) }
            return
        }
        guard points.count == maxFingers else { return } // Never reinterpret a lifted multi-finger gesture.
        if points.count == 2 {
            let distance = span(), rotation = normalizedAngle(angle() - baseAngle)
            let translation = current.distance(to: baseCenter)
            if edgeStart, mode == .undecided, current.x - baseCenter.x < -45, abs(current.y - baseCenter.y) < 35 {
                mode = .command; moved = true; onInput?(MacAction.notificationCenter.input); return
            }
            if mode == .undecided {
                if abs(distance - baseDistance) > 6, abs(distance - baseDistance) > translation * 1.25 { mode = .zoom }
                else if abs(rotation) > 0.10, abs(rotation) * max(30, distance) > translation * 1.5 { mode = .rotate }
                else if translation > 3 {
                    mode = .scroll; moved = true; onInput?(.init(.scrollBegin, timestamp: time))
                    onInput?(.init(.scroll, x: current.x - baseCenter.x, y: current.y - baseCenter.y, timestamp: time))
                    velocity = .init(x: dx / dt, y: dy / dt); scrollLastTime = time
                    return
                }
            }
            switch mode {
            case .scroll:
                onInput?(.init(.scroll, x: dx, y: dy, timestamp: time))
                velocity.x = velocity.x * 0.35 + dx / dt * 0.65
                velocity.y = velocity.y * 0.35 + dy / dt * 0.65
                scrollLastTime = time
            case .zoom:
                if previousDistance > 1, distance > 1 {
                    let reference = previousDistance == baseDistance ? baseDistance : previousDistance
                    onInput?(.init(.zoom, x: log(distance / reference), timestamp: time))
                }
                moved = true
            case .rotate:
                let delta = normalizedAngle(angle() - previousAngle) * 180 / .pi
                onInput?(.init(.rotate, x: delta, timestamp: time)); moved = true
            default: break
            }
            previousDistance = distance; previousAngle = angle()
        } else if points.count == 3 || points.count == 4 {
            guard mode != .command else { return }
            let totalX = current.x - baseCenter.x, totalY = current.y - baseCenter.y
            if points.count == 4, baseDistance > 1 {
                let ratio = span() / baseDistance
                if ratio < 0.72 || ratio > 1.28 {
                    onInput?((ratio < 1 ? MacAction.apps : .showDesktop).input)
                    mode = .command; moved = true; return
                }
            }
            if max(abs(totalX), abs(totalY)) > 50 {
                let action: MacAction
                if abs(totalX) > abs(totalY) { action = totalX < 0 ? .nextSpace : .previousSpace }
                else { action = totalY < 0 ? .missionControl : .appExpose }
                onInput?(action.input); mode = .command; moved = true
            }
        }
    }

    mutating func ended(_ ids: [Int], time: Double, cancelled: Bool) {
        guard ids.contains(where: { points[$0] != nil }) else { return }
        self.cancelled = self.cancelled || cancelled
        endContinuous(allowMomentum: !self.cancelled && time - scrollLastTime < 0.08)
        // Lock out reclassification until the last contact lifts.
        if mode == .drag || mode == .scroll { mode = .command }
        for id in ids { points.removeValue(forKey: id); origins.removeValue(forKey: id) }
        guard points.isEmpty else { return }
        if !self.cancelled, !moved, time - beganAt < 0.35 {
            switch maxFingers {
            case 1:
                onInput?(.init(.leftClick, timestamp: time)); lastTapTime = time; lastTapPoint = baseCenter
            case 2:
                if time - previousTwoTapTime < 0.28 { onInput?(MacAction.resetZoom.input); previousTwoTapTime = -10 }
                else { onInput?(.init(.rightClick, timestamp: time)); previousTwoTapTime = time }
            case 3: if !threeFingerDrag { onInput?(MacAction.lookUp.input) }
            case 4: onControls?()
            default: break
            }
        }
    }

    mutating func cancel() {
        endContinuous(allowMomentum: false)
        onInput?(.init(.stop))
        points.removeAll(keepingCapacity: true); origins.removeAll(keepingCapacity: true)
        moved = true; cancelled = true; mode = .command
    }
    private mutating func endContinuous(allowMomentum: Bool) {
        if mode == .drag { onInput?(.init(.dragEnd)) }
        if mode == .scroll {
            onInput?(.init(.scrollEnd, x: allowMomentum ? min(4000, max(-4000, velocity.x)) : 0,
                           y: allowMomentum ? min(4000, max(-4000, velocity.y)) : 0))
        }
    }
    private func center() -> TouchPoint {
        guard !points.isEmpty else { return .zero }
        var result = TouchPoint.zero
        for point in points.values { result.x += point.x; result.y += point.y }
        return .init(x: result.x / Double(points.count), y: result.y / Double(points.count))
    }
    private func span() -> Double {
        let c = center()
        return points.values.reduce(0) { $0 + $1.distance(to: c) } * 2 / Double(max(1, points.count))
    }
    private func angle() -> Double {
        guard points.count == 2 else { return 0 }
        var first: (Int, TouchPoint)?, second: (Int, TouchPoint)?
        for pair in points {
            if first == nil { first = (pair.key, pair.value) }
            else { second = (pair.key, pair.value) }
        }
        guard let first, let second else { return 0 }
        let a = first.0 < second.0 ? first.1 : second.1
        let b = first.0 < second.0 ? second.1 : first.1
        return atan2(b.y - a.y, b.x - a.x)
    }
    private func normalizedAngle(_ value: Double) -> Double { atan2(sin(value), cos(value)) }
}
