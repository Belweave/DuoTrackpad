import Foundation

/// Constant work per sample; low-speed precision and a smooth gain ramp for crossing large displays.
struct PointerResponse {
    private var previousTime = 0.0
    mutating func reset() { previousTime = 0 }
    mutating func apply(x: Double, y: Double, timestamp: Double, sensitivity: Double, accelerated: Bool) -> (x: Double, y: Double) {
        let dt = previousTime > 0 ? min(0.05, max(1.0 / 240, timestamp - previousTime)) : 1.0 / 120
        previousTime = timestamp
        let speed = hypot(x, y) / dt
        let ramp = min(1, max(0, (speed - 60) / 900))
        let gain = accelerated ? 0.55 + 1.65 * ramp * ramp * (3 - 2 * ramp) : 1
        let scale = min(4, max(0.25, sensitivity)) * gain
        return (min(8192, max(-8192, x * scale)), min(8192, max(-8192, y * scale)))
    }
}
