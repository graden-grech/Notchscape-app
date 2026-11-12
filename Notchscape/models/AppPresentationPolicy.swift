import Foundation
import CoreGraphics

/// Shared measurements for expanded controls, not the closed hardware notch.
enum NotchHeaderLayoutPolicy {
    static let controlHeight = 30.0
    static let tabHeight = 32.0
    static let topInset = 8.0

    static func rowHeight(closedHeight: Double, hasPhysicalNotch: Bool) -> Double {
        let hardwareRow = hasPhysicalNotch && closedHeight.isFinite
            ? closedHeight - topInset : tabHeight
        return max(tabHeight, hardwareRow)
    }
}

enum NotchGestureLayoutPolicy {
    /// Hardware does not shrink with a software gesture. Keep its horizontal
    /// exclusion at display scale while retaining the existing vertical motion.
    static func horizontalScale(requested: Double, hasPhysicalNotch: Bool) -> Double {
        hasPhysicalNotch ? 1 : requested
    }
}

/// The camera housing stays at the display's top edge even when the expanded
/// header's controls have additional breathing room. All values are in points.
struct PhysicalNotchGeometry: Equatable {
    let width: Double
    let height: Double
    let centerOffset: Double
    var expandedHeaderTopOffset: Double { -NotchHeaderLayoutPolicy.topInset }

    static func resolve(screenFrame: CGRect, safeTop: Double,
                        leftArea: CGRect?, rightArea: CGRect?) -> Self? {
        guard safeTop.isFinite, safeTop > 0,
              screenFrame.minX.isFinite, screenFrame.width.isFinite, screenFrame.width > 0,
              let leftArea, let rightArea,
              leftArea.maxX.isFinite, rightArea.minX.isFinite,
              leftArea.maxX >= screenFrame.minX,
              rightArea.minX <= screenFrame.maxX,
              leftArea.maxX < rightArea.minX else { return nil }
        let left = Double(leftArea.maxX), right = Double(rightArea.minX)
        return .init(width: right - left, height: safeTop,
                     centerOffset: (left + right) / 2 - Double(screenFrame.midX))
    }
}

/// Fixed visible lanes around the measured camera gap. Implicit stack spacing
/// or shorter decorative notch widths must not put the start of a HUD slider
/// behind the physical housing. Values are in logical display points.
struct InlineHUDLanes: Equatable {
    let leadingWidth: Double
    let cutoutWidth: Double
    let trailingWidth: Double
    var totalWidth: Double { leadingWidth + cutoutWidth + trailingWidth }
}

enum InlineHUDLayoutPolicy {
    static let cutoutClearance = 10.0

    static func lanes(sideWidth: Double, physicalNotchWidth: Double,
                      centerOffset: Double = 0) -> InlineHUDLanes? {
        guard sideWidth.isFinite, sideWidth > 0,
              physicalNotchWidth.isFinite, physicalNotchWidth > 0,
              centerOffset.isFinite else { return nil }
        let cutout = physicalNotchWidth + 2 * cutoutClearance
        let side = sideWidth + abs(centerOffset)
        let leading = side + centerOffset, trailing = side - centerOffset
        guard cutout.isFinite, leading.isFinite, trailing.isFinite,
              (leading + cutout + trailing).isFinite else { return nil }
        return .init(leadingWidth: leading, cutoutWidth: cutout, trailingWidth: trailing)
    }
}

/// A closed battery banner keeps its two visible lanes separate from the camera
/// housing. Unequal status/indicator intrinsic widths must not move that gap.
struct BatteryNotificationLanes: Equatable {
    let leadingWidth: Double
    let cutoutWidth: Double
    let trailingWidth: Double
    var totalWidth: Double { leadingWidth + cutoutWidth + trailingWidth }
}

enum BatteryNotificationPresentation: Equatable {
    case lowBattery, criticalBattery, charging, connectedToPower, onBattery, fullyCharged

    var warningTitle: String? {
        switch self {
        case .lowBattery: "Low battery"
        case .criticalBattery: "Critical battery"
        default: nil
        }
    }

    static func resolve(lowAlert: Bool, criticalAlert: Bool, pluggedIn: Bool,
                        charging: Bool, fullyCharged: Bool) -> Self {
        if criticalAlert { return .criticalBattery }
        if lowAlert { return .lowBattery }
        if charging { return .charging }
        if pluggedIn { return fullyCharged ? .fullyCharged : .connectedToPower }
        return .onBattery
    }
}

enum BatteryNotificationLayoutPolicy {
    static let cutoutClearance = 10.0
    static let minimumSideWidth = 36.0
    static let symbolWidth = 22.0

    static func compactLanes(leadingContentWidth: Double, trailingContentWidth: Double, physicalNotchWidth: Double,
                             centerOffset: Double = 0) -> BatteryNotificationLanes? {
        guard leadingContentWidth.isFinite, leadingContentWidth >= 0,
              trailingContentWidth.isFinite, trailingContentWidth >= 0 else { return nil }
        let sideWidth = max(minimumSideWidth, leadingContentWidth.rounded(.up), trailingContentWidth.rounded(.up))
        let contentWidth = physicalNotchWidth + 2 * cutoutClearance
            + 2 * (sideWidth + abs(centerOffset))
        return lanes(contentWidth: contentWidth, physicalNotchWidth: physicalNotchWidth,
                     centerOffset: centerOffset)
    }

    static func lanes(contentWidth: Double, physicalNotchWidth: Double,
                      centerOffset: Double = 0) -> BatteryNotificationLanes? {
        guard contentWidth.isFinite, physicalNotchWidth.isFinite, centerOffset.isFinite,
              contentWidth > 0, physicalNotchWidth > 0 else { return nil }
        let cutoutWidth = physicalNotchWidth + 2 * cutoutClearance
        let halfVisibleWidth = (contentWidth - cutoutWidth) / 2
        let leadingWidth = halfVisibleWidth + centerOffset
        let trailingWidth = halfVisibleWidth - centerOffset
        guard leadingWidth >= 0, trailingWidth >= 0 else { return nil }
        return .init(leadingWidth: leadingWidth, cutoutWidth: cutoutWidth,
                     trailingWidth: trailingWidth)
    }
}

/// Supply only missing values once. An upgrade must retain even the old
/// implicit defaults; changing a Key's default alone would change those users.
enum InitialPresentationDefaults {
    static let migrationKey = "didApplyPresentationDefaultsV1"

    static func missingValues(in persistent: [String: Any]) -> [String: Bool] {
        let previouslyUsedApp = persistent["firstLaunch"] as? Bool == false
        var result: [String: Bool] = [:]
        if persistent["weatherEnabled"] == nil {
            result["weatherEnabled"] = previouslyUsedApp
        }
        if persistent["showOnAllDisplays"] == nil {
            result["showOnAllDisplays"] = !previouslyUsedApp
        }
        return result
    }
}
