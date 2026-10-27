import Foundation
import CoreGraphics

enum WindowPlacement: String, CaseIterable, Identifiable {
    case left = "Left Half", right = "Right Half", top = "Top Half", bottom = "Bottom Half", topLeft = "Top Left", topRight = "Top Right", bottomLeft = "Bottom Left", bottomRight = "Bottom Right", maximize = "Fill Visible Area", center = "Center"
    var id: Self { self }
    func frame(in visible: CGRect, current: CGRect) -> CGRect {
        var result = visible
        switch self {
        case .left: result.size.width /= 2
        case .right: result.size.width /= 2; result.origin.x += result.width
        case .top: result.size.height /= 2; result.origin.y += result.height
        case .bottom: result.size.height /= 2
        case .topLeft: result.size.width /= 2; result.size.height /= 2; result.origin.y += result.height
        case .topRight: result.size.width /= 2; result.size.height /= 2; result.origin.x += result.width; result.origin.y += result.height
        case .bottomLeft: result.size.width /= 2; result.size.height /= 2
        case .bottomRight: result.size.width /= 2; result.size.height /= 2; result.origin.x += result.width
        case .maximize: break
        case .center:
            result.size = CGSize(width: min(visible.width, current.width), height: min(visible.height, current.height))
            result.origin = CGPoint(x: visible.midX-result.width/2, y: visible.midY-result.height/2)
        }
        return result.integral
    }
}
struct SavedWindowPosition: Codable, Equatable, Identifiable {
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
        CGRect(x: visible.minX+x*visible.width, y: visible.minY+y*visible.height, width: width*visible.width, height: height*visible.height).integral
    }
}
struct SavedWindowLayout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var positions: [SavedWindowPosition]
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && !positions.isEmpty && positions.count <= 40 && positions.allSatisfy(\.isValid) && Set(positions.map(\.id)).count == positions.count }
}
