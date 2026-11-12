import AppKit
import CoreGraphics

/// Read-only adapter. Match NSScreen to its own Quartz display ID; do not flip
/// every screen against NSScreen.main or substitute native pixel dimensions.
@MainActor
enum NSScreenDisplayGeometryAdapter {
    static func snapshot(for screen: NSScreen,
                         visualStyle: DisplayGeometryVisualStyle = .automatic,
                         floatingCamera: DisplayFloatingCameraGeometry? = nil) -> DisplayGeometrySnapshot? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              number.uint64Value > 0, number.uint64Value <= UInt64(UInt32.max) else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let coordinates = DisplayCoordinateSpace(appKitFrame: screen.frame,
                                                       quartzFrame: CGDisplayBounds(displayID)) else { return nil }
        return DisplayGeometryPolicy.snapshot(
            displayID: displayID, coordinates: coordinates,
            systemTopSafeInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            visualStyle: visualStyle, floatingCamera: floatingCamera)
    }
}
