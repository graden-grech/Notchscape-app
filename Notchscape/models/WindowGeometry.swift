import Foundation
import CoreGraphics

enum WindowPlacementGroup: String, CaseIterable, Identifiable, Sendable {
    case halves = "Halves", corners = "Corners", thirds = "Thirds", fourths = "Fourths", sixths = "Sixths", centered = "Size & Position"
    var id: Self { self }
}

enum WindowPlacement: String, CaseIterable, Identifiable, Sendable {
    case left = "Left Half", right = "Right Half", top = "Top Half", bottom = "Bottom Half"
    case topLeft = "Top Left", topRight = "Top Right", bottomLeft = "Bottom Left", bottomRight = "Bottom Right"
    case maximize = "Fill Visible Area", center = "Center"
    case centerHalf = "Center Half"
    case leftThird = "Left Third", centerThird = "Center Third", rightThird = "Right Third"
    case leftTwoThirds = "Left Two Thirds", rightTwoThirds = "Right Two Thirds", centerTwoThirds = "Center Two Thirds"
    case firstFourth = "First Fourth", secondFourth = "Second Fourth", thirdFourth = "Third Fourth", lastFourth = "Last Fourth"
    case leftThreeFourths = "Left Three Fourths", centerThreeFourths = "Center Three Fourths", rightThreeFourths = "Right Three Fourths"
    case topLeftSixth = "Top Left Sixth", topCenterSixth = "Top Center Sixth", topRightSixth = "Top Right Sixth", bottomLeftSixth = "Bottom Left Sixth", bottomCenterSixth = "Bottom Center Sixth", bottomRightSixth = "Bottom Right Sixth"
    case almostFill = "Almost Fill", maximizeHeight = "Fill Height", maximizeWidth = "Fill Width", enlarge = "Make Larger", shrink = "Make Smaller"
    case moveLeft = "Move Left", moveRight = "Move Right", moveUp = "Move Up", moveDown = "Move Down"
    var id: Self { self }
    var group: WindowPlacementGroup {
        switch self {
        case .left, .right, .top, .bottom, .centerHalf: .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: .corners
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds, .centerTwoThirds: .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .leftThreeFourths, .centerThreeFourths, .rightThreeFourths: .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: .sixths
        case .maximize, .center, .almostFill, .maximizeHeight, .maximizeWidth, .enlarge, .shrink, .moveLeft, .moveRight, .moveUp, .moveDown: .centered
        }
    }
    // Stable local shortcut keys do not depend on localized presentation labels.
    var shortcutID: String {
        switch self {
        case .left: "left"; case .right: "right"; case .top: "top"; case .bottom: "bottom"
        case .topLeft: "topLeft"; case .topRight: "topRight"; case .bottomLeft: "bottomLeft"; case .bottomRight: "bottomRight"
        case .maximize: "fill"; case .center: "center"
        case .centerHalf: "centerHalf"; case .centerTwoThirds: "centerTwoThirds"
        case .leftThird: "leftThird"; case .centerThird: "centerThird"; case .rightThird: "rightThird"
        case .leftTwoThirds: "leftTwoThirds"; case .rightTwoThirds: "rightTwoThirds"
        case .firstFourth: "firstFourth"; case .secondFourth: "secondFourth"; case .thirdFourth: "thirdFourth"; case .lastFourth: "lastFourth"
        case .leftThreeFourths: "leftThreeFourths"; case .centerThreeFourths: "centerThreeFourths"; case .rightThreeFourths: "rightThreeFourths"
        case .topLeftSixth: "topLeftSixth"; case .topCenterSixth: "topCenterSixth"; case .topRightSixth: "topRightSixth"; case .bottomLeftSixth: "bottomLeftSixth"; case .bottomCenterSixth: "bottomCenterSixth"; case .bottomRightSixth: "bottomRightSixth"
        case .almostFill: "almostFill"; case .maximizeHeight: "maximizeHeight"; case .maximizeWidth: "maximizeWidth"; case .enlarge: "enlarge"; case .shrink: "shrink"
        case .moveLeft: "moveLeft"; case .moveRight: "moveRight"; case .moveUp: "moveUp"; case .moveDown: "moveDown"
        }
    }
    func frame(in visible: CGRect, current: CGRect, gap: Double = 0) -> CGRect {
        guard WindowLayoutGeometry.valid(visible), WindowLayoutGeometry.valid(current),
              WindowLayoutGeometry.validGap(gap) else { return .null }
        func grid(_ columns: Int, _ first: Int, _ last: Int) -> CGRect {
            WindowGridRegion(columns: columns, rows: 1, firstColumn: first, firstRow: 0, lastColumn: last, lastRow: 0).frame(in: visible, gap: gap)
        }
        switch self {
        case .centerHalf: return WindowLayoutGeometry.centered(width: visible.width * 0.5, height: visible.height, in: visible, gap: gap)
        case .centerTwoThirds: return WindowLayoutGeometry.centered(width: visible.width * 2 / 3, height: visible.height, in: visible, gap: gap)
        case .left: return grid(2, 0, 0)
        case .right: return grid(2, 1, 1)
        case .top: return WindowGridRegion(columns: 1, rows: 2, firstColumn: 0, firstRow: 0, lastColumn: 0, lastRow: 0).frame(in: visible, gap: gap)
        case .bottom: return WindowGridRegion(columns: 1, rows: 2, firstColumn: 0, firstRow: 1, lastColumn: 0, lastRow: 1).frame(in: visible, gap: gap)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let column = (self == .topRight || self == .bottomRight) ? 1 : 0
            let row = (self == .bottomLeft || self == .bottomRight) ? 1 : 0
            return WindowGridRegion(columns: 2, rows: 2, firstColumn: column, firstRow: row, lastColumn: column, lastRow: row).frame(in: visible, gap: gap)
        case .leftThird: return grid(3, 0, 0)
        case .centerThird: return grid(3, 1, 1)
        case .rightThird: return grid(3, 2, 2)
        case .leftTwoThirds: return grid(3, 0, 1)
        case .rightTwoThirds: return grid(3, 1, 2)
        case .firstFourth: return grid(4, 0, 0)
        case .secondFourth: return grid(4, 1, 1)
        case .thirdFourth: return grid(4, 2, 2)
        case .lastFourth: return grid(4, 3, 3)
        case .leftThreeFourths: return grid(4, 0, 2)
        case .centerThreeFourths: return WindowLayoutGeometry.centered(width: visible.width * 0.75, height: visible.height, in: visible, gap: gap)
        case .rightThreeFourths: return grid(4, 1, 3)
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
            let column = (self == .topLeftSixth || self == .bottomLeftSixth) ? 0 : ((self == .topCenterSixth || self == .bottomCenterSixth) ? 1 : 2)
            let row = (self == .topLeftSixth || self == .topCenterSixth || self == .topRightSixth) ? 0 : 1
            return WindowGridRegion(columns: 3, rows: 2, firstColumn: column, firstRow: row, lastColumn: column, lastRow: row).frame(in: visible, gap: gap)
        case .maximize: return WindowLayoutGeometry.contained(visible, in: visible, gap: gap)
        case .center:
            return WindowLayoutGeometry.clamped(CGRect(x: visible.midX - current.width / 2,
                y: visible.midY - current.height / 2, width: current.width, height: current.height), in: visible, gap: gap)
        case .almostFill:
            return WindowLayoutGeometry.centered(width: visible.width * 0.9, height: visible.height * 0.9, in: visible, gap: gap)
        case .maximizeHeight:
            return WindowLayoutGeometry.clamped(CGRect(x: current.minX, y: visible.minY, width: current.width, height: visible.height), in: visible, gap: gap)
        case .maximizeWidth:
            return WindowLayoutGeometry.clamped(CGRect(x: visible.minX, y: current.minY, width: visible.width, height: current.height), in: visible, gap: gap)
        case .enlarge, .shrink:
            let factor = self == .enlarge ? 1.1 : 0.9
            let w = min(visible.width, current.width * factor), h = min(visible.height, current.height * factor)
            return WindowLayoutGeometry.clamped(CGRect(x: current.midX - w / 2, y: current.midY - h / 2, width: w, height: h), in: visible, gap: gap)
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            let dx: CGFloat = self == .moveLeft ? -40 : (self == .moveRight ? 40 : 0)
            let dy: CGFloat = self == .moveDown ? -40 : (self == .moveUp ? 40 : 0)
            return WindowLayoutGeometry.clamped(current.offsetBy(dx: dx, dy: dy), in: visible, gap: gap)
        }
    }
}

struct WindowGridRegion: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let firstColumn: Int
    let firstRow: Int
    let lastColumn: Int
    let lastRow: Int
    var isValid: Bool {
        (1...6).contains(columns) && (1...6).contains(rows) &&
        (0..<columns).contains(firstColumn) && (0..<columns).contains(lastColumn) &&
        (0..<rows).contains(firstRow) && (0..<rows).contains(lastRow)
    }
    func contains(column: Int, row: Int) -> Bool {
        isValid && (min(firstColumn, lastColumn)...max(firstColumn, lastColumn)).contains(column) &&
        (min(firstRow, lastRow)...max(firstRow, lastRow)).contains(row)
    }
    func frame(in visible: CGRect, gap: Double = 0) -> CGRect {
        guard isValid, WindowLayoutGeometry.valid(visible) else { return .null }
        let left = min(firstColumn, lastColumn), top = min(firstRow, lastRow)
        let width = max(firstColumn, lastColumn) - left + 1, height = max(firstRow, lastRow) - top + 1
        let cellWidth = visible.width / Double(columns), cellHeight = visible.height / Double(rows)
        let result = CGRect(x: visible.minX + Double(left) * cellWidth,
            y: visible.maxY - Double(top + height) * cellHeight,
            width: Double(width) * cellWidth, height: Double(height) * cellHeight)
        return WindowLayoutGeometry.contained(result, in: visible, gap: gap)
    }
}

enum WindowLayoutGeometry {
    static func validGap(_ gap: Double) -> Bool { gap.isFinite && (0...32).contains(gap) }

    static func centered(width: CGFloat, height: CGFloat, in visible: CGRect, gap: Double) -> CGRect {
        contained(CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height), in: visible, gap: gap)
    }
    static func clamped(_ rect: CGRect, in visible: CGRect, gap: Double) -> CGRect {
        guard valid(rect), valid(visible), validGap(gap) else { return .null }
        let bounds = contained(visible, in: visible, gap: gap)
        let w = min(rect.width, bounds.width), h = min(rect.height, bounds.height)
        // Movement/centering must preserve size. Re-insetting every current
        // frame would shrink a window each time a movement shortcut is used.
        return CGRect(x: min(max(rect.minX, bounds.minX), bounds.maxX - w),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - h), width: w, height: h)
    }
    static func transferred(_ current: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard valid(current), valid(source), valid(destination) else { return .null }
        let width = min(current.width, destination.width), height = min(current.height, destination.height)
        let x = min(1, max(0, (current.midX - source.minX) / source.width))
        let y = min(1, max(0, (current.midY - source.minY) / source.height))
        return clamped(CGRect(x: destination.minX + x * destination.width - width / 2, y: destination.minY + y * destination.height - height / 2, width: width, height: height), in: destination, gap: 0)
    }
    static func valid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, rect.maxX, rect.maxY,
         rect.size.width * rect.size.height].allSatisfy(\.isFinite) && rect.size.width > 0 && rect.size.height > 0
    }
    static func contained(_ rect: CGRect, in visible: CGRect, gap: Double) -> CGRect {
        guard valid(rect), valid(visible), validGap(gap) else { return .null }
        let result = rect.intersection(visible)
        guard valid(result) else { return .null }
        // Bound the inset even on unusually small displays; never expand through a menu bar or Dock.
        let inset = min(gap, result.width / 4, result.height / 4)
        return result.insetBy(dx: inset, dy: inset)
    }

    /// Prefer the display containing most of the window. An offscreen window
    /// uses the nearest valid display; array order breaks equal-distance ties.
    static func displayIndex(for current: CGRect, in displays: [CGRect]) -> Int? {
        guard valid(current) else { return nil }
        let indices = displays.indices.filter { valid(displays[$0]) }
        guard let first = indices.first else { return nil }
        var best = first, area: CGFloat = 0
        for index in indices {
            let intersection = current.intersection(displays[index])
            let candidate = valid(intersection) ? intersection.width * intersection.height : 0
            if candidate > area { best = index; area = candidate }
        }
        if area > 0 { return best }
        return indices.min {
            hypot(current.midX - displays[$0].midX, current.midY - displays[$0].midY) <
            hypot(current.midX - displays[$1].midX, current.midY - displays[$1].midY)
        }
    }

    static func transferred(_ current: CGRect, among displays: [CGRect], direction: Int) -> CGRect {
        let indices = displays.indices.filter { valid(displays[$0]) }
        guard direction == -1 || direction == 1, indices.count > 1,
              let source = displayIndex(for: current, in: displays),
              let ordinal = indices.firstIndex(of: source) else { return .null }
        let destination = indices[(ordinal + direction + indices.count) % indices.count]
        return transferred(current, from: displays[source], to: displays[destination])
    }
}
struct SavedWindowPosition: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var bundleID: String
    var ordinal: Int
    var displayID: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var isValid: Bool { !bundleID.isEmpty && bundleID.count <= 255 && displayID.count <= 255 && (0..<40).contains(ordinal) && [x,y,width,height].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 } && width >= 0.05 && height >= 0.05 && x+width <= 1.001 && y+height <= 1.001 }
    func frame(in visible: CGRect) -> CGRect {
        guard isValid, WindowLayoutGeometry.valid(visible) else { return .null }
        return WindowLayoutGeometry.clamped(CGRect(x: visible.minX+x*visible.width,
            y: visible.minY+y*visible.height, width: width*visible.width, height: height*visible.height), in: visible, gap: 0)
    }
}
struct SavedWindowLayout: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var positions: [SavedWindowPosition]
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && !positions.isEmpty && positions.count <= 40 && positions.allSatisfy(\.isValid) && Set(positions.map(\.id)).count == positions.count }
}
