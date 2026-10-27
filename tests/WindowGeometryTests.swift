import Foundation
import CoreGraphics

@main struct WindowGeometryTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); checks += 1 }
        let screen = CGRect(x: -1920, y: 100, width: 1920, height: 1050)
        let current = CGRect(x: -1800, y: 200, width: 800, height: 600)
        for placement in WindowPlacement.allCases {
            let rect = placement.frame(in: screen, current: current)
            check(screen.contains(rect), "placement stays inside visible display: \(placement)")
            check(rect.width > 0 && rect.height > 0, "positive dimensions")
        }
        check(WindowPlacement.left.frame(in: screen, current: current).maxX == screen.midX, "negative-coordinate left half")
        check(WindowPlacement.top.frame(in: screen, current: current).maxY == screen.maxY, "top placement uses AppKit coordinates")
        let p = SavedWindowPosition(bundleID: "com.example.app", ordinal: 0, displayID: "1", x: 0.5, y: 0, width: 0.5, height: 1)
        check(p.isValid, "valid normalized position")
        check(p.frame(in: screen) == WindowPlacement.right.frame(in: screen, current: current), "portable frame")
        var bad = p; bad.width = .nan; check(!bad.isValid, "NaN rejected")
        bad = p; bad.x = 1; check(!bad.isValid, "overflow rejected")
        bad = p; bad.ordinal = -1; check(!bad.isValid, "negative ordinal")
        bad = p; bad.height = 0; check(!bad.isValid, "empty size")
        let layout = SavedWindowLayout(name: "Study", positions: [p])
        check(layout.isValid, "layout valid")
        check(!SavedWindowLayout(name: "", positions: [p]).isValid, "empty name")
        check(!SavedWindowLayout(name: "Study", positions: [p,p]).isValid, "duplicate position IDs")
        let roundTrip = try JSONDecoder().decode(SavedWindowLayout.self, from: JSONEncoder().encode(layout))
        check(roundTrip == layout, "layout roundtrip")
        print("PASS \(checks) window geometry checks")
    }
}
