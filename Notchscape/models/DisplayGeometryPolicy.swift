import Foundation
import CoreGraphics

/// A matched pair of global screen frames in logical screen coordinates.
/// Quartz/CGEvent has a downward Y axis; AppKit has an upward Y axis.
/// The frames already reflect display arrangement, scaling and rotation.
/// Backing-pixel scale must not be applied again to points from CGEvent.location.
struct DisplayCoordinateSpace: Equatable, Sendable {
    let appKitFrame: CGRect
    let quartzFrame: CGRect

    init?(appKitFrame: CGRect, quartzFrame: CGRect) {
        guard DisplayGeometryPolicy.isValidRect(appKitFrame),
              DisplayGeometryPolicy.isValidRect(quartzFrame) else { return nil }
        self.appKitFrame = appKitFrame
        self.quartzFrame = quartzFrame
    }

    func appKitPoint(fromQuartz point: CGPoint) -> CGPoint? {
        guard DisplayGeometryPolicy.contains(point, in: quartzFrame) else { return nil }
        let result = CGPoint(
            x: appKitFrame.minX + (point.x - quartzFrame.minX) / quartzFrame.width * appKitFrame.width,
            y: appKitFrame.maxY - (point.y - quartzFrame.minY) / quartzFrame.height * appKitFrame.height)
        return DisplayGeometryPolicy.isFinitePoint(result) ? result : nil
    }

    func quartzPoint(fromAppKit point: CGPoint) -> CGPoint? {
        guard DisplayGeometryPolicy.contains(point, in: appKitFrame) else { return nil }
        let result = CGPoint(
            x: quartzFrame.minX + (point.x - appKitFrame.minX) / appKitFrame.width * quartzFrame.width,
            y: quartzFrame.minY + (appKitFrame.maxY - point.y) / appKitFrame.height * quartzFrame.height)
        return DisplayGeometryPolicy.isFinitePoint(result) ? result : nil
    }

    func appKitRect(fromQuartz rect: CGRect) -> CGRect? {
        guard DisplayGeometryPolicy.contains(rect, in: quartzFrame),
              let first = appKitPoint(fromQuartz: CGPoint(x: rect.minX, y: rect.minY)),
              let second = appKitPoint(fromQuartz: CGPoint(x: rect.maxX, y: rect.maxY)) else { return nil }
        return rectangle(between: first, and: second)
    }

    func quartzRect(fromAppKit rect: CGRect) -> CGRect? {
        guard DisplayGeometryPolicy.contains(rect, in: appKitFrame),
              let first = quartzPoint(fromAppKit: CGPoint(x: rect.minX, y: rect.minY)),
              let second = quartzPoint(fromAppKit: CGPoint(x: rect.maxX, y: rect.maxY)) else { return nil }
        return rectangle(between: first, and: second)
    }

    private func rectangle(between first: CGPoint, and second: CGPoint) -> CGRect? {
        let rect = CGRect(x: min(first.x, second.x), y: min(first.y, second.y),
                          width: abs(second.x - first.x), height: abs(second.y - first.y))
        return DisplayGeometryPolicy.isValidRect(rect) ? rect : nil
    }
}

/// A visual preference, independent of camera evidence or system safe areas.
/// "automatic" does not assert that Apple provides a native island API.
enum DisplayGeometryVisualStyle: String, CaseIterable, Sendable {
    case automatic, attachedNotch, floatingIsland
}

enum DisplayCameraEvidence: String, Sendable {
    case manuallyMeasured, simulated
}

/// These dimensions describe the system-reported top gap, not a hardware shape.
/// In particular, safeTop + auxiliary areas cannot prove floating vs attached.
struct DisplayReportedTopGap: Equatable, Sendable {
    let rectInAppKit: CGRect
    let centerOffset: Double
    var width: Double { Double(rectInAppKit.width) }
    var height: Double { Double(rectInAppKit.height) }
}

struct DisplayNotchMetrics: Equatable, Sendable {
    let width: Double
    let height: Double
    let centerOffset: Double
}

/// Explicit measurements or SIMULATED input only. No product-name inference.
/// The envelope may contain the camera, but allowed hit rectangles never do.
/// Policy coverage limits below are conservative app validation, not Apple specs.
struct DisplayFloatingCameraGeometry: Equatable, Sendable {
    let coordinates: DisplayCoordinateSpace
    let cameraRectInAppKit: CGRect
    let interactionBoundsInAppKit: CGRect
    let allowedRectsInAppKit: [CGRect]
    let evidence: DisplayCameraEvidence
    let interactionBoundsInQuartz: CGRect
    let interactionRectsInQuartz: [CGRect]
    let physicalCameraExclusionRectsInQuartz: [CGRect]

    init?(coordinates: DisplayCoordinateSpace, cameraRectInAppKit: CGRect,
          interactionBoundsInAppKit: CGRect, allowedRectsInAppKit: [CGRect]? = nil,
          evidence: DisplayCameraEvidence) {
        let frame = coordinates.appKitFrame
        guard DisplayGeometryPolicy.contains(cameraRectInAppKit, in: frame),
              cameraRectInAppKit.minX > frame.minX, cameraRectInAppKit.maxX < frame.maxX,
              cameraRectInAppKit.minY > frame.minY, cameraRectInAppKit.maxY < frame.maxY,
              cameraRectInAppKit.width / frame.width <= DisplayGeometryPolicy.maximumCameraWidthFraction,
              cameraRectInAppKit.height / frame.height <= DisplayGeometryPolicy.maximumCameraHeightFraction,
              DisplayGeometryPolicy.contains(interactionBoundsInAppKit, in: frame),
              DisplayGeometryPolicy.contains(cameraRectInAppKit, in: interactionBoundsInAppKit),
              interactionBoundsInAppKit.height / frame.height <= DisplayGeometryPolicy.maximumInteractionHeightFraction
        else { return nil }

        let allowed = allowedRectsInAppKit
            ?? DisplayGeometryPolicy.subtract(cameraRectInAppKit, from: interactionBoundsInAppKit)
        guard !allowed.isEmpty else { return nil }
        for (index, rect) in allowed.enumerated() {
            guard DisplayGeometryPolicy.contains(rect, in: interactionBoundsInAppKit),
                  !DisplayGeometryPolicy.overlaps(rect, cameraRectInAppKit),
                  !allowed.prefix(index).contains(where: { DisplayGeometryPolicy.overlaps($0, rect) })
            else { return nil }
        }
        guard let quartzBounds = coordinates.quartzRect(fromAppKit: interactionBoundsInAppKit),
              let quartzCamera = coordinates.quartzRect(fromAppKit: cameraRectInAppKit) else { return nil }
        let quartzAllowed = allowed.compactMap { coordinates.quartzRect(fromAppKit: $0) }
        guard quartzAllowed.count == allowed.count else { return nil }
        self.coordinates = coordinates
        self.cameraRectInAppKit = cameraRectInAppKit
        self.interactionBoundsInAppKit = interactionBoundsInAppKit
        self.allowedRectsInAppKit = allowed
        self.evidence = evidence
        self.interactionBoundsInQuartz = quartzBounds
        self.interactionRectsInQuartz = quartzAllowed
        self.physicalCameraExclusionRectsInQuartz = [quartzCamera]
    }

    func containsInteractionPointInAppKit(_ point: CGPoint) -> Bool {
        guard !DisplayGeometryPolicy.contains(point, in: cameraRectInAppKit) else { return false }
        return allowedRectsInAppKit.contains { DisplayGeometryPolicy.contains(point, in: $0) }
    }

    func containsInteractionPointInQuartz(_ point: CGPoint) -> Bool {
        guard !physicalCameraExclusionRectsInQuartz.contains(where: { DisplayGeometryPolicy.contains(point, in: $0) }),
              let appKit = coordinates.appKitPoint(fromQuartz: point) else { return false }
        return containsInteractionPointInAppKit(appKit)
    }
}

/// A value snapshot; creating one installs no tap and changes no UI or preference.
/// Native screen metadata leaves physical-camera evidence unknown. Only explicit
/// floating measurements populate physical camera exclusions and interaction areas.
struct DisplayGeometrySnapshot: Equatable, Sendable {
    let displayID: UInt32?
    let coordinates: DisplayCoordinateSpace
    let systemTopSafeInset: CGFloat
    let reportedTopGap: DisplayReportedTopGap?
    let visualStyle: DisplayGeometryVisualStyle
    let floatingCamera: DisplayFloatingCameraGeometry?

    fileprivate init(displayID: UInt32?, coordinates: DisplayCoordinateSpace,
                     systemTopSafeInset: CGFloat, reportedTopGap: DisplayReportedTopGap?,
                     visualStyle: DisplayGeometryVisualStyle, floatingCamera: DisplayFloatingCameraGeometry?) {
        self.displayID = displayID
        self.coordinates = coordinates
        self.systemTopSafeInset = systemTopSafeInset
        self.reportedTopGap = reportedTopGap
        self.visualStyle = visualStyle
        self.floatingCamera = floatingCamera
    }

    var cameraEvidence: DisplayCameraEvidence? { floatingCamera?.evidence }
    /// Compatibility route only; a positive inset is not proof of camera shape.
    var usesLegacyNotchLayout: Bool { systemTopSafeInset > 0 }
    var systemTopSafeAreaRectInAppKit: CGRect? {
        guard systemTopSafeInset > 0 else { return nil }
        let frame = coordinates.appKitFrame
        return CGRect(x: frame.minX, y: frame.maxY - systemTopSafeInset,
                      width: frame.width, height: systemTopSafeInset)
    }
    var systemReportedExclusionRectsInAppKit: [CGRect] {
        if let gap = reportedTopGap { return [gap.rectInAppKit] }
        return systemTopSafeAreaRectInAppKit.map { [$0] } ?? []
    }
    var systemReportedExclusionRectsInQuartz: [CGRect] {
        systemReportedExclusionRectsInAppKit.compactMap { coordinates.quartzRect(fromAppKit: $0) }
    }
    var physicalCameraExclusionRectsInAppKit: [CGRect] {
        floatingCamera.map { [$0.cameraRectInAppKit] } ?? []
    }
    var physicalCameraExclusionRectsInQuartz: [CGRect] {
        floatingCamera?.physicalCameraExclusionRectsInQuartz ?? []
    }
    var interactionRectsInAppKit: [CGRect] { floatingCamera?.allowedRectsInAppKit ?? [] }
    var interactionRectsInQuartz: [CGRect] { floatingCamera?.interactionRectsInQuartz ?? [] }
    var interactionBoundsInQuartz: CGRect? { floatingCamera?.interactionBoundsInQuartz }

    /// A conservative union for callers needing a single protected set. This does
    /// not convert an unverified system top gap into measured camera evidence.
    var conservativeExclusionRectsInAppKit: [CGRect] {
        DisplayGeometryPolicy.mergingOverlaps(
            systemReportedExclusionRectsInAppKit + physicalCameraExclusionRectsInAppKit)
    }
    var conservativeExclusionRectsInQuartz: [CGRect] {
        conservativeExclusionRectsInAppKit.compactMap { coordinates.quartzRect(fromAppKit: $0) }
    }
}

enum DisplayGeometryPolicy {
    // App validation caps, deliberately not dimensions for any announced Mac.
    static let maximumCameraWidthFraction: CGFloat = 0.5
    static let maximumCameraHeightFraction: CGFloat = 0.25
    static let maximumInteractionHeightFraction: CGFloat = 0.5

    static func snapshot(displayID: UInt32? = nil, coordinates: DisplayCoordinateSpace,
                         systemTopSafeInset: CGFloat,
                         auxiliaryTopLeftArea: CGRect? = nil, auxiliaryTopRightArea: CGRect? = nil,
                         visualStyle: DisplayGeometryVisualStyle = .automatic,
                         floatingCamera: DisplayFloatingCameraGeometry? = nil) -> DisplayGeometrySnapshot? {
        guard systemTopSafeInset.isFinite, systemTopSafeInset >= 0,
              systemTopSafeInset <= coordinates.appKitFrame.height,
              displayID == nil || displayID != 0,
              floatingCamera == nil || floatingCamera?.coordinates == coordinates else { return nil }
        let gap = reportedTopGap(screenFrame: coordinates.appKitFrame, safeTop: systemTopSafeInset,
                                 leftArea: auxiliaryTopLeftArea, rightArea: auxiliaryTopRightArea)
        return .init(displayID: displayID, coordinates: coordinates, systemTopSafeInset: systemTopSafeInset,
                     reportedTopGap: gap, visualStyle: visualStyle, floatingCamera: floatingCamera)
    }

    /// Same gap edges and center arithmetic as the existing PhysicalNotchGeometry.
    /// Outer auxiliary edges are not used: a reported gap is bounded independently.
    static func reportedTopGap(screenFrame: CGRect, safeTop: CGFloat,
                               leftArea: CGRect?, rightArea: CGRect?) -> DisplayReportedTopGap? {
        guard isValidRect(screenFrame), safeTop.isFinite, safeTop > 0, safeTop <= screenFrame.height,
              let leftArea, let rightArea, isValidRect(leftArea), isValidRect(rightArea),
              leftArea.maxX >= screenFrame.minX, rightArea.minX <= screenFrame.maxX,
              leftArea.maxX < rightArea.minX else { return nil }
        let left = Double(leftArea.maxX), right = Double(rightArea.minX)
        let rect = CGRect(x: leftArea.maxX, y: screenFrame.maxY - safeTop,
                          width: rightArea.minX - leftArea.maxX, height: safeTop)
        guard contains(rect, in: screenFrame) else { return nil }
        return .init(rectInAppKit: rect,
                     centerOffset: (left + right) / 2 - Double(screenFrame.midX))
    }

    /// Legacy sizing only. This is not a camera measurement for a new Mac.
    /// User custom-height/menu-bar rules remain the caller's responsibility.
    static func legacyNotchMetrics(for snapshot: DisplayGeometrySnapshot,
                                   fallbackWidth: Double = 185, fallbackHeight: Double = 32) -> DisplayNotchMetrics? {
        guard fallbackWidth.isFinite, fallbackWidth > 0,
              fallbackHeight.isFinite, fallbackHeight > 0 else { return nil }
        if let gap = snapshot.reportedTopGap {
            return .init(width: gap.width, height: gap.height, centerOffset: gap.centerOffset)
        }
        return .init(width: fallbackWidth,
                     height: snapshot.systemTopSafeInset > 0 ? Double(snapshot.systemTopSafeInset) : fallbackHeight,
                     centerOffset: 0)
    }

    static func isFinitePoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    static func isValidRect(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
            && rect.maxX.isFinite && rect.maxY.isFinite
            && rect.maxX > rect.minX && rect.maxY > rect.minY
    }

    /// Closed boundaries preserve exact screen-edge point conversion. Camera
    /// boundaries are rejected before allowed regions during interaction tests.
    static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        isValidRect(rect) && isFinitePoint(point)
            && point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }

    static func contains(_ rect: CGRect, in outer: CGRect) -> Bool {
        isValidRect(rect) && isValidRect(outer)
            && rect.minX >= outer.minX && rect.maxX <= outer.maxX
            && rect.minY >= outer.minY && rect.maxY <= outer.maxY
    }

    /// Touching edges are allowed; only positive-area overlap is an invalid region.
    static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        isValidRect(first) && isValidRect(second)
            && max(first.minX, second.minX) < min(first.maxX, second.maxX)
            && max(first.minY, second.minY) < min(first.maxY, second.maxY)
    }

    fileprivate static func subtract(_ inner: CGRect, from outer: CGRect) -> [CGRect] {
        [
            CGRect(x: outer.minX, y: inner.maxY, width: outer.width, height: outer.maxY - inner.maxY),
            CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: inner.minY - outer.minY),
            CGRect(x: outer.minX, y: inner.minY, width: inner.minX - outer.minX, height: inner.height),
            CGRect(x: inner.maxX, y: inner.minY, width: outer.maxX - inner.maxX, height: inner.height)
        ].filter(isValidRect)
    }

    fileprivate static func mergingOverlaps(_ rects: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rects {
            var merged = rect
            var index = 0
            while index < result.count {
                if overlaps(merged, result[index]) {
                    merged = merged.union(result.remove(at: index))
                    index = 0
                } else {
                    index += 1
                }
            }
            result.append(merged)
        }
        return result
    }
}
