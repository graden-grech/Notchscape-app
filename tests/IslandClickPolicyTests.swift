import Foundation
import CoreGraphics

@main struct IslandClickPolicyTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }
        let bounds = CGRect(x: -300, y: 40, width: 300, height: 100)
        let left = CGRect(x: -290, y: 50, width: 90, height: 40)
        let camera = CGRect(x: -200, y: 40, width: 80, height: 70)
        let right = CGRect(x: -110, y: 50, width: 90, height: 40)
        let geometry = IslandClickGeometry.validated(profile: .appOwnedTestWindow,
            boundingRect: bounds, allowedRects: [left, right], protectedRects: [camera])!
        var ready = IslandClickRuntime()
        ready.enabled = true
        ready.sessionIsActive = true
        ready.sessionIsUnlocked = true
        ready.displayIsAwake = true
        ready.appIsActive = true
        ready.testWindowIsActive = true
        ready.geometry = geometry
        func event(_ kind: IslandClickEventKind, _ x: Double = -250, _ y: Double = 65,
                   time: Double = 1, modified: Bool = false) -> IslandClickEvent {
            .init(kind: kind, location: CGPoint(x: x, y: y), timestamp: time,
                  hasConflictingModifiers: modified)
        }

        // Concrete safety barriers must never claim a press, even with geometry.
        let ineligible: [(String, (inout IslandClickRuntime) -> Void)] = [
            ("off", { $0.enabled = false }),
            ("inactive desktop", { $0.sessionIsActive = false }),
            ("locked desktop", { $0.sessionIsUnlocked = false }),
            ("sleeping display", { $0.displayIsAwake = false }),
            ("background test app", { $0.appIsActive = false }),
            ("inactive test window", { $0.testWindowIsActive = false }),
            ("missing geometry", { $0.geometry = nil })
        ]
        for (name, change) in ineligible {
            var runtime = ready; change(&runtime)
            var policy = IslandClickPolicy()
            check(policy.handle(event(.leftDown), runtime: runtime) == .passThrough, "\(name) preserves down")
            check(policy.handle(event(.leftUp, time: 1.1), runtime: runtime) == .passThrough, "\(name) preserves up")
            check(policy.handle(event(.leftDown), runtime: ready) == .consume, "begin before \(name)")
            check(policy.handle(event(.leftUp, time: 1.1), runtime: runtime) == .passThrough, "\(name) fails open during press")
            check(policy.handle(event(.leftUp, time: 1.2), runtime: ready) == .passThrough, "\(name) clears stale press")
        }
        var defaults = IslandClickRuntime(); defaults.geometry = geometry
        var policy = IslandClickPolicy()
        check(policy.handle(event(.leftDown), runtime: defaults) == .passThrough, "defaults remain off")

        // A complete click opens once, on up; an unmatched up never opens.
        check(policy.handle(event(.leftUp), runtime: ready) == .passThrough, "unmatched up preserved")
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "inside down claimed")
        check(policy.handle(event(.leftUp, -248, 66, time: 1.1), runtime: ready) == .consumeAndActivate, "complete click activates on up")
        check(policy.handle(event(.leftUp, time: 1.2), runtime: ready) == .passThrough, "no second activation")
        check(policy.handle(event(.leftDown, -60), runtime: ready) == .consume, "second visible lane is usable")
        check(policy.handle(event(.leftUp, -60, time: 1.1), runtime: ready) == .consumeAndActivate, "second lane completes")

        // No camera, menu gap or other application's press may be stolen.
        for point in [CGPoint(x: -160, y: 65), CGPoint(x: -295, y: 65), CGPoint(x: 10, y: 65)] {
            check(policy.handle(event(.leftDown, point.x, point.y), runtime: ready) == .passThrough, "excluded down passes")
            check(policy.handle(event(.leftUp, time: 1.1), runtime: ready) == .passThrough, "outside-origin up entering a lane passes")
        }
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before outside release")
        check(policy.handle(event(.leftUp, 40, 200, time: 1.1), runtime: ready) == .consume, "paired up outside consumed without activation")
        check(policy.handle(event(.leftDown, modified: true), runtime: ready) == .passThrough, "modifier down passes")
        check(policy.handle(event(.leftUp, time: 1.1), runtime: ready) == .passThrough, "modifier press has no captured up")
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before modifier change")
        check(policy.handle(event(.leftUp, time: 1.1, modified: true), runtime: ready) == .consume, "modifier change cancels activation but pairs up")

        // Drags/moves/long holds cannot turn into a dropdown activation.
        check(policy.handle(event(.leftDragged), runtime: ready) == .passThrough, "unclaimed drag is untouched")
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before drag")
        check(policy.handle(event(.leftDragged, -249, 65, time: 1.05), runtime: ready) == .consume, "captured drag remainder cannot reach another target without a down")
        check(policy.handle(event(.leftDragged, 100, 200, time: 1.07), runtime: ready) == .consume, "captured drag stays paired outside allowed region")
        check(policy.handle(event(.leftUp, time: 1.1), runtime: ready) == .consume, "drag cancels even when returning to origin")
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before distant up")
        check(policy.handle(event(.leftUp, -230, 65, time: 1.1), runtime: ready) == .consume, "large move cancels without a drag event")
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before long hold")
        check(policy.handle(event(.leftUp, time: 4), runtime: ready) == .consume, "long hold does not activate")
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before reverse timestamp")
        check(policy.handle(event(.leftUp, time: 0.5), runtime: ready) == .consume, "reversed time cannot activate")
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before unrelated input")
        check(policy.handle(event(.other), runtime: ready) == .passThrough, "unrelated events are untouched")
        check(policy.handle(event(.leftUp, time: 1.1), runtime: ready) == .consumeAndActivate, "unrelated event does not steal left pair")

        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before geometry change")
        var changed = ready
        changed.geometry = IslandClickGeometry.validated(profile: .appOwnedTestWindow,
            boundingRect: bounds, allowedRects: [right], protectedRects: [camera])
        check(policy.handle(event(.leftUp, time: 1.1), runtime: changed) == .passThrough, "changed geometry fails open")
        check(policy.handle(event(.leftUp, time: 1.2), runtime: ready) == .passThrough, "old geometry cannot revive press")
        check(policy.handle(event(.leftDown), runtime: ready) == .consume, "claim before explicit reset")
        policy.reset()
        check(policy.handle(event(.leftUp, time: 1.1), runtime: ready) == .passThrough, "explicit stop clears press")
        check(policy.handle(event(.leftDown, .nan), runtime: ready) == .passThrough, "invalid coordinate passes")
        check(policy.handle(event(.leftDown, time: .infinity), runtime: ready) == .passThrough, "invalid time passes")

        // Future native route concerns the active desktop, not app foreground,
        // but has an independent explicit acknowledgement and no default opt-in.
        var native = ready
        native.geometry = IslandClickGeometry.validated(profile: .nativeUnverified,
            boundingRect: bounds, allowedRects: [left, right], protectedRects: [camera])
        native.appIsActive = false; native.testWindowIsActive = false
        check(policy.handle(event(.leftDown), runtime: native) == .passThrough, "native defaults unacknowledged")
        native.nativeRoutingAcknowledged = true
        check(policy.handle(event(.leftDown), runtime: native) == .consume, "acknowledged native desktop route does not require app foreground")
        check(policy.handle(event(.leftUp, time: 1.1), runtime: native) == .consumeAndActivate, "native pure routing contract only")
        native.sessionIsActive = false
        check(policy.handle(event(.leftDown), runtime: native) == .passThrough, "inactive native desktop still passes")

        // Geometry validation is conservative at camera, screen and finite-data boundaries.
        check(IslandClickGeometry.validated(profile: .appOwnedTestWindow, boundingRect: bounds,
              allowedRects: [camera], protectedRects: [camera]) == nil, "camera overlap rejected")
        check(IslandClickGeometry.validated(profile: .appOwnedTestWindow, boundingRect: bounds,
              allowedRects: [left, left]) == nil, "overlapping hit regions rejected")
        let touching = IslandClickGeometry.validated(profile: .appOwnedTestWindow,
            boundingRect: bounds, allowedRects: [CGRect(x: -120, y: 50, width: 90, height: 40)],
            protectedRects: [camera])!
        check(!touching.containsAllowedPoint(CGPoint(x: -120, y: 65)), "camera boundary remains protected")
        check(touching.containsAllowedPoint(CGPoint(x: -119, y: 65)), "visible lane beyond camera boundary remains usable")
        check(IslandClickGeometry.validated(profile: .appOwnedTestWindow, boundingRect: bounds,
              allowedRects: [CGRect(x: -400, y: 50, width: 200, height: 40)]) == nil, "off-screen input rejected")
        check(IslandClickGeometry.validated(profile: .appOwnedTestWindow, boundingRect: bounds,
              allowedRects: []) == nil, "empty hit regions rejected")
        for invalid in [CGRect.zero, CGRect.null, CGRect.infinite,
                        CGRect(x: 0, y: 0, width: -2, height: 20),
                        CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20)] {
            check(IslandClickGeometry.validated(profile: .appOwnedTestWindow,
                  boundingRect: invalid, allowedRects: [left]) == nil, "invalid envelope rejected")
        }
        print("PASS \(checks) island click behavior checks")
    }
}
