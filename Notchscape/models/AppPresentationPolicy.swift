import Foundation

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
