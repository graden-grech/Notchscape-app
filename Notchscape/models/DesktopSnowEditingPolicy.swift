import Foundation
import CoreGraphics

/// A volatile editing lease. Nothing enables pointer capture after relaunch.
struct DesktopSnowEditingSession {
    static let idleLimit: Double = 120
    private(set) var isActive = false
    private var lastInteraction: Double = 0

    @discardableResult mutating func begin(eligible: Bool, now: Double) -> Bool {
        isActive = eligible && now.isFinite && now >= 0
        lastInteraction = isActive ? now : 0
        return isActive
    }
    @discardableResult mutating func validate(eligible: Bool, now: Double) -> Bool {
        guard isActive, eligible, now.isFinite, now >= lastInteraction,
              now - lastInteraction <= Self.idleLimit else { end(); return false }
        return true
    }
    mutating func interact(now: Double) {
        guard validate(eligible: true, now: now) else { return }
        lastInteraction = now
    }
    mutating func end() { isActive = false; lastInteraction = 0 }

    /// Fill short gaps in a fast stroke without work scaling with mouse polling.
    static func samples(from: CGPoint, to: CGPoint, radius: Double) -> [CGPoint] {
        guard [from.x, from.y, to.x, to.y, radius].allSatisfy({ $0.isFinite }),
              radius >= 1, radius <= 256, abs(from.x) <= 65_536, abs(from.y) <= 65_536,
              abs(to.x) <= 65_536, abs(to.y) <= 65_536 else { return [] }
        let distance = hypot(to.x - from.x, to.y - from.y)
        let count = max(1, min(32, Int(ceil(distance / max(4, radius * 0.4)))))
        return (1...count).map { index in
            let t = Double(index) / Double(count)
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }
}
