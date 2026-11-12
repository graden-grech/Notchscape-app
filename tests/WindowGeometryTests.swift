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
        func close(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.000001) -> Bool { abs(a - b) <= tolerance }
        func fits(_ frame: CGRect, in display: CGRect) -> Bool {
            WindowLayoutGeometry.valid(frame) && frame.minX >= display.minX - 0.000001 &&
            frame.minY >= display.minY - 0.000001 && frame.maxX <= display.maxX + 0.000001 && frame.maxY <= display.maxY + 0.000001
        }
        check(WindowPlacement.allCases.count == 39, "39 supported placement actions")
        check(Set(WindowPlacement.allCases.map(\.shortcutID)).count == 39, "shortcut identifiers never collide")
        check(WindowPlacementGroup.allCases.flatMap { group in WindowPlacement.allCases.filter { $0.group == group } }.count == 39,
              "every placement is available through one group")

        let displays = [CGRect(x: 0, y: 38, width: 1512, height: 908),
                        CGRect(x: -1728.5, y: -190.25, width: 1728.5, height: 1055.75),
                        CGRect(x: 300.25, y: 1000.5, width: 980.5, height: 1431.25)]
        for display in displays {
            let frame = CGRect(x: display.midX - 160.375, y: display.midY - 120.125, width: 320.75, height: 240.25)
            for gap in [0.0, 7.5, 32.0] {
                for placement in WindowPlacement.allCases {
                    check(fits(placement.frame(in: display, current: frame, gap: gap), in: display),
                          "every placement respects fractional/negative/portrait display visible bounds")
                }
            }
        }
        let fractional = displays[1]
        check(close(WindowPlacement.centerThird.frame(in: fractional, current: current).width, fractional.width / 3), "thirds retain subpoint precision")
        check(close(WindowPlacement.centerThird.frame(in: fractional, current: current).midX, fractional.midX), "middle third is centered")
        check(close(WindowPlacement.leftTwoThirds.frame(in: fractional, current: current).maxX,
                    WindowPlacement.rightThird.frame(in: fractional, current: current).minX), "two-thirds meet last third without overlap or holes")
        check(close(WindowPlacement.centerThreeFourths.frame(in: fractional, current: current).width, fractional.width * 0.75), "center three-fourths size")
        check(close(WindowPlacement.centerThreeFourths.frame(in: fractional, current: current).midX, fractional.midX), "center three-fourths location")
        for columns in 1...6 {
            for rows in 1...6 {
                var cells: [CGRect] = []
                for row in 0..<rows {
                    for column in 0..<columns {
                        let region = WindowGridRegion(columns: columns, rows: rows, firstColumn: column, firstRow: row, lastColumn: column, lastRow: row)
                        let cell = region.frame(in: fractional)
                        check(region.isValid && region.contains(column: column, row: row), "every custom-grid cell selectable")
                        check(fits(cell, in: fractional), "grid cells respect visible fractional bounds")
                        check(cells.allSatisfy { other in
                            let overlap = cell.intersection(other)
                            return overlap.isNull || overlap.width * overlap.height < 0.000001
                        }, "grid partitions do not overlap")
                        cells.append(cell)
                    }
                }
                check(close(cells.reduce(CGFloat.zero) { $0 + $1.width * $1.height }, fractional.width * fractional.height),
                      "every 1...6 by 1...6 grid covers the whole visible display")
                let whole = WindowGridRegion(columns: columns, rows: rows, firstColumn: columns - 1, firstRow: rows - 1, lastColumn: 0, lastRow: 0)
                check(whole.frame(in: fractional) == fractional, "reversed corner selection supports the full grid")
                let edge = WindowGridRegion(columns: columns, rows: rows, firstColumn: 0, firstRow: 0, lastColumn: columns - 1, lastRow: 0)
                check(close(edge.frame(in: fractional).maxY, fractional.maxY), "row zero is visually at the top")
                check(fits(whole.frame(in: fractional, gap: 32), in: fractional), "grid gap remains inside display")
            }
        }
        let region = WindowGridRegion(columns: 6, rows: 5, firstColumn: 4, firstRow: 3, lastColumn: 1, lastRow: 1)
        let reversed = WindowGridRegion(columns: 6, rows: 5, firstColumn: 1, firstRow: 1, lastColumn: 4, lastRow: 3)
        check(region.frame(in: fractional) == reversed.frame(in: fractional), "drag direction does not change selected rectangular region")
        check(region.contains(column: 2, row: 2) && !region.contains(column: 0, row: 2), "multi-cell selection has exact membership")
        for invalid in [WindowGridRegion(columns: 0, rows: 1, firstColumn: 0, firstRow: 0, lastColumn: 0, lastRow: 0),
                        .init(columns: 7, rows: 1, firstColumn: 0, firstRow: 0, lastColumn: 0, lastRow: 0),
                        .init(columns: 1, rows: 0, firstColumn: 0, firstRow: 0, lastColumn: 0, lastRow: 0),
                        .init(columns: 1, rows: 7, firstColumn: 0, firstRow: 0, lastColumn: 0, lastRow: 0),
                        .init(columns: 3, rows: 2, firstColumn: -1, firstRow: 0, lastColumn: 2, lastRow: 1),
                        .init(columns: 3, rows: 2, firstColumn: 0, firstRow: 0, lastColumn: Int.max, lastRow: 1)] {
            check(!invalid.isValid && !invalid.contains(column: 0, row: 0) && invalid.frame(in: fractional).isNull, "invalid or oversized grid is rejected")
        }
        let invalidRects = [CGRect.null, .infinite, .zero, CGRect(x: 0, y: 0, width: -10, height: 10),
                            CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), CGRect(x: 0, y: 0, width: 10, height: CGFloat.infinity),
                            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 10)]
        for invalid in invalidRects {
            for placement in WindowPlacement.allCases {
                check(placement.frame(in: invalid, current: current).isNull, "invalid destination frame rejected")
                check(placement.frame(in: fractional, current: invalid).isNull, "invalid current frame rejected")
            }
            check(WindowLayoutGeometry.transferred(current, from: invalid, to: fractional).isNull, "invalid source display rejected")
            check(p.frame(in: invalid).isNull, "saved position rejects invalid display")
        }
        for gap in [-1.0, 32.01, .nan, .infinity, -.infinity] {
            for placement in WindowPlacement.allCases {
                check(placement.frame(in: fractional, current: current, gap: gap).isNull, "invalid gap rejected rather than clamped silently")
            }
        }
        let roomy = CGRect(x: -1000, y: -300, width: 3000, height: 1800)
        var moving = CGRect(x: 100, y: 200, width: 500.5, height: 360.25)
        let initialSize = moving.size
        for action in [WindowPlacement.moveLeft, .moveRight, .moveUp, .moveDown, .center, .moveLeft, .moveRight] {
            moving = action.frame(in: roomy, current: moving, gap: 12)
            check(moving.size == initialSize, "movement and centering with a gap never cumulatively shrink the window")
        }
        let before = CGRect(x: 100, y: 200, width: 500, height: 360)
        check(WindowPlacement.moveUp.frame(in: roomy, current: before).minY == before.minY + 40, "up moves 40 AppKit points")
        check(WindowPlacement.moveDown.frame(in: roomy, current: before).minY == before.minY - 40, "down moves 40 AppKit points")
        check(WindowPlacement.enlarge.frame(in: roomy, current: before).width == 550, "enlarge grows by ten percent")
        check(WindowPlacement.shrink.frame(in: roomy, current: before).width == 450, "shrink reduces by ten percent")
        let source = CGRect(x: -1200, y: 0, width: 1200, height: 800)
        let destination = CGRect(x: 300, y: 1200, width: 1800, height: 1000)
        let sourceWindow = CGRect(x: -900, y: 250, width: 300, height: 200)
        let moved = WindowLayoutGeometry.transferred(sourceWindow, from: source, to: destination)
        check(moved.size == sourceWindow.size, "display transfer keeps logical point size across differently scaled displays")
        check(close((moved.midX - destination.minX) / destination.width, (sourceWindow.midX - source.minX) / source.width), "display transfer preserves relative horizontal center")
        check(close((moved.midY - destination.minY) / destination.height, (sourceWindow.midY - source.minY) / source.height), "display transfer preserves relative vertical center")
        check(fits(WindowLayoutGeometry.transferred(roomy, from: source, to: destination), in: destination), "oversized display transfer fits destination")
        check(WindowLayoutGeometry.displayIndex(for: sourceWindow, in: [.null, source, destination]) == 1, "display selection ignores invalid entries")
        check(WindowLayoutGeometry.displayIndex(for: CGRect(x: -100, y: 200, width: 500, height: 200), in: [source, CGRect(x: 0, y: 0, width: 1000, height: 800)]) == 1, "spanning window uses greatest intersection")
        check(WindowLayoutGeometry.displayIndex(for: CGRect(x: -1600, y: 100, width: 100, height: 100), in: [source, destination]) == 0, "offscreen window uses nearest display")
        check(WindowLayoutGeometry.transferred(sourceWindow, among: [source], direction: 1).isNull, "single display has no transfer")
        check(WindowLayoutGeometry.transferred(sourceWindow, among: [source, destination], direction: 0).isNull, "unknown display direction is rejected")
        check(WindowLayoutGeometry.transferred(sourceWindow, among: [source, destination], direction: 1) == moved, "next display uses shared transfer policy")
        check(WindowLayoutGeometry.transferred(sourceWindow, among: [source, destination], direction: -1) == moved, "previous display wraps at start")
        check(WindowLayoutGeometry.transferred(moved, among: [source, destination], direction: 1) == sourceWindow, "next display wraps at end without point-size drift")
        var fractionalSaved = p; fractionalSaved.x = 0; fractionalSaved.y = 0; fractionalSaved.width = 1; fractionalSaved.height = 1
        check(fractionalSaved.frame(in: fractional) == fractional, "saved frame never expands beyond fractional visible bounds")
        print("PASS \(checks) window geometry checks; synthetic frames only, no AX/window/input access")
    }
}
