import AppKit
import Foundation
import CoreGraphics

@main
struct DisplayGeometryPolicyTests {
    @MainActor static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            precondition(value(), name); checks += 1
        }
        func close(_ first: CGFloat, _ second: CGFloat) -> Bool { abs(first - second) < 0.000001 }
        func closePoint(_ first: CGPoint, _ second: CGPoint) -> Bool {
            close(first.x, second.x) && close(first.y, second.y)
        }
        func closeRect(_ first: CGRect, _ second: CGRect) -> Bool {
            closePoint(first.origin, second.origin) && close(first.width, second.width) && close(first.height, second.height)
        }

        let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let spaces: [DisplayCoordinateSpace] = [
            .init(appKitFrame: builtIn, quartzFrame: builtIn)!,
            // Negative X and a vertically offset external display.
            .init(appKitFrame: CGRect(x: -1920, y: -100, width: 1920, height: 1080),
                  quartzFrame: CGRect(x: -1920, y: 2, width: 1920, height: 1080))!,
            // Display above the primary; negative Quartz Y is valid.
            .init(appKitFrame: CGRect(x: -100, y: 982, width: 1440, height: 900),
                  quartzFrame: CGRect(x: -100, y: -900, width: 1440, height: 900))!,
            // Portrait/rotated frames are already expressed in global orientation.
            .init(appKitFrame: CGRect(x: 1512, y: -98, width: 1080, height: 1920),
                  quartzFrame: CGRect(x: 1512, y: -840, width: 1080, height: 1920))!,
            .init(appKitFrame: CGRect(x: 200, y: -1200, width: 1200, height: 1080),
                  quartzFrame: CGRect(x: 200, y: 1102, width: 1200, height: 1080))!,
            // A synthetic matched-frame scale mismatch exercises normalization,
            // rather than assuming native pixels or a fixed Retina multiplier.
            .init(appKitFrame: CGRect(x: -3840, y: 200, width: 1280, height: 800),
                  quartzFrame: CGRect(x: -2560, y: -500, width: 2560, height: 1600))!
        ]
        for space in spaces {
            let a = space.appKitFrame, q = space.quartzFrame
            check(space.appKitPoint(fromQuartz: .init(x: q.minX, y: q.minY))
                  == .init(x: a.minX, y: a.maxY), "Quartz top-left maps to this display's AppKit top-left")
            check(space.appKitPoint(fromQuartz: .init(x: q.maxX, y: q.maxY))
                  == .init(x: a.maxX, y: a.minY), "screen boundaries retain exact orientation")
            check(space.appKitRect(fromQuartz: q) == a && space.quartzRect(fromAppKit: a) == q,
                  "whole matched frames map exactly")
            for x: CGFloat in [0, 0.125, 0.5, 0.9, 1] {
                for y: CGFloat in [0, 0.125, 0.5, 0.9, 1] {
                    let point = CGPoint(x: q.minX + q.width * x, y: q.minY + q.height * y)
                    let mapped = space.appKitPoint(fromQuartz: point)!
                    check(close(mapped.x, a.minX + a.width * x) && close(mapped.y, a.maxY - a.height * y),
                          "per-screen coordinates follow supplied frame extents")
                    check(closePoint(space.quartzPoint(fromAppKit: mapped)!, point), "point round trip")
                }
            }
            let rect = CGRect(x: a.minX + a.width * 0.25, y: a.minY + a.height * 0.3,
                              width: a.width * 0.2, height: a.height * 0.1)
            let mapped = space.quartzRect(fromAppKit: rect)!
            check(closeRect(space.appKitRect(fromQuartz: mapped)!, rect), "rectangle round trip")
            check(close(mapped.width, q.width * 0.2) && close(mapped.height, q.height * 0.1),
                  "rectangle dimensions use the matched frames, not a global primary-screen flip")
            check(space.quartzPoint(fromAppKit: .init(x: a.maxX + 1, y: a.midY)) == nil,
                  "points on another display are not converted with this screen")
            check(space.appKitRect(fromQuartz: q.offsetBy(dx: 1, dy: 0)) == nil,
                  "a rectangle crossing the selected display is rejected")
        }
        let nativeSpace = spaces[0]
        let badRects: [CGRect] = [
            .zero, .null, .infinite, CGRect(x: 0, y: 0, width: -1, height: 50),
            CGRect(x: 0, y: 0, width: 50, height: -1),
            CGRect(x: CGFloat.nan, y: 0, width: 50, height: 50),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 50),
            CGRect(x: 1e300, y: 0, width: 1, height: 50),
            CGRect(x: 1e308, y: 0, width: 1e308, height: 50)
        ]
        for rect in badRects {
            check(DisplayCoordinateSpace(appKitFrame: rect, quartzFrame: builtIn) == nil, "invalid AppKit frame")
            check(DisplayCoordinateSpace(appKitFrame: builtIn, quartzFrame: rect) == nil, "invalid Quartz frame")
            check(nativeSpace.quartzRect(fromAppKit: rect) == nil, "invalid conversion rectangle")
        }
        for point in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity),
                      CGPoint(x: -CGFloat.infinity, y: 0), CGPoint(x: -1, y: 0)] {
            check(nativeSpace.appKitPoint(fromQuartz: point) == nil, "invalid/out-of-display Quartz point")
            check(nativeSpace.quartzPoint(fromAppKit: point) == nil, "invalid/out-of-display AppKit point")
        }

        // Exact existing Mac fixture; this is a legacy notch, not a future island.
        let left = CGRect(x: 0, y: 950, width: 663.5, height: 32)
        let right = CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        for style in DisplayGeometryVisualStyle.allCases {
            let snapshot = DisplayGeometryPolicy.snapshot(coordinates: nativeSpace, systemTopSafeInset: 32,
                auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right, visualStyle: style)!
            let metrics = DisplayGeometryPolicy.legacyNotchMetrics(for: snapshot)!
            check(metrics == .init(width: 185, height: 32, centerOffset: 0), "exact legacy 185 by 32, no new padding")
            check(snapshot.usesLegacyNotchLayout, "positive-safe-top layout behavior is preserved")
            check(snapshot.cameraEvidence == nil && snapshot.physicalCameraExclusionRectsInAppKit.isEmpty,
                  "safe top plus a visual choice does not assert physical camera shape")
            check(snapshot.interactionRectsInQuartz.isEmpty, "native metadata never opts into click interception")
            check(snapshot.visualStyle == style, "visual style remains separate from reported geometry")
            check(snapshot.reportedTopGap?.rectInAppKit == CGRect(x: 663.5, y: 950, width: 185, height: 32),
                  "legacy gap rectangle is measured without software padding")
        }
        for offset: CGFloat in [-24, -4, 0, 4, 24] {
            let l = left.offsetBy(dx: offset, dy: 0), r = right.offsetBy(dx: offset, dy: 0)
            let legacy = PhysicalNotchGeometry.resolve(screenFrame: builtIn, safeTop: 32, leftArea: l, rightArea: r)!
            let gap = DisplayGeometryPolicy.reportedTopGap(screenFrame: builtIn, safeTop: 32, leftArea: l, rightArea: r)!
            check(gap.width == legacy.width && gap.height == legacy.height && gap.centerOffset == legacy.centerOffset,
                  "same gap/offset arithmetic as PhysicalNotchGeometry")
        }
        let shiftedFrame = builtIn.offsetBy(dx: -1512, dy: 982)
        let shiftedSpace = DisplayCoordinateSpace(appKitFrame: shiftedFrame,
            quartzFrame: CGRect(x: -1512, y: -982, width: 1512, height: 982))!
        let shiftedSnapshot = DisplayGeometryPolicy.snapshot(coordinates: shiftedSpace, systemTopSafeInset: 32,
            auxiliaryTopLeftArea: left.offsetBy(dx: -1512, dy: 982),
            auxiliaryTopRightArea: right.offsetBy(dx: -1512, dy: 982))!
        check(DisplayGeometryPolicy.legacyNotchMetrics(for: shiftedSnapshot) == .init(width: 185, height: 32, centerOffset: 0),
              "nonzero display origins preserve the legacy gap")
        let external = DisplayGeometryPolicy.snapshot(coordinates: spaces[1], systemTopSafeInset: 0,
                                                      visualStyle: .floatingIsland)!
        check(!external.usesLegacyNotchLayout && external.reportedTopGap == nil, "notchless layout remains notchless")
        check(DisplayGeometryPolicy.legacyNotchMetrics(for: external) == .init(width: 185, height: 32, centerOffset: 0),
              "legacy fallback remains exactly 185 by 32")
        check(external.conservativeExclusionRectsInAppKit.isEmpty && external.cameraEvidence == nil,
              "a floating visual style does not invent a camera or a protected rectangle")
        let unknownTop = DisplayGeometryPolicy.snapshot(coordinates: nativeSpace, systemTopSafeInset: 32,
                                                        auxiliaryTopLeftArea: left)!
        check(unknownTop.reportedTopGap == nil, "a missing auxiliary area is not guessed")
        check(unknownTop.systemReportedExclusionRectsInAppKit == [CGRect(x: 0, y: 950, width: 1512, height: 32)],
              "unknown positive inset conservatively protects the full top band")
        let invalidAux = DisplayGeometryPolicy.snapshot(coordinates: nativeSpace, systemTopSafeInset: 32,
            auxiliaryTopLeftArea: CGRect(x: CGFloat.nan, y: 950, width: 200, height: 32), auxiliaryTopRightArea: right)!
        check(invalidAux.reportedTopGap == nil && invalidAux.systemReportedExclusionRectsInAppKit == unknownTop.systemReportedExclusionRectsInAppKit,
              "invalid auxiliary values degrade to a conservative band")
        for inset: CGFloat in [-1, .nan, .infinity, 983] {
            check(DisplayGeometryPolicy.snapshot(coordinates: nativeSpace, systemTopSafeInset: inset) == nil, "invalid top-safe inset")
        }
        check(DisplayGeometryPolicy.reportedTopGap(screenFrame: builtIn, safeTop: 32, leftArea: right, rightArea: left) == nil,
              "overlapping/reversed gap boundaries are rejected")
        check(DisplayGeometryPolicy.reportedTopGap(screenFrame: builtIn, safeTop: 32,
            leftArea: left.offsetBy(dx: -1000, dy: 0), rightArea: right) == nil, "offscreen gap boundary")
        check(DisplayGeometryPolicy.legacyNotchMetrics(for: external, fallbackWidth: .nan) == nil, "invalid fallback width")
        check(DisplayGeometryPolicy.legacyNotchMetrics(for: external, fallbackHeight: -1) == nil, "invalid fallback height")
        check(DisplayGeometryPolicy.snapshot(displayID: 0, coordinates: nativeSpace, systemTopSafeInset: 0) == nil,
              "an explicit null Quartz display ID is rejected; simulations can use nil")

        // Explicitly SIMULATED arbitrary geometry; these are not Apple measurements.
        let simulatedSpace = DisplayCoordinateSpace(
            appKitFrame: CGRect(x: -1600, y: 200, width: 1600, height: 1000),
            quartzFrame: CGRect(x: -1600, y: -218, width: 1600, height: 1000))!
        let camera = CGRect(x: -840, y: 1150, width: 80, height: 18)
        let envelope = CGRect(x: -900, y: 1135, width: 200, height: 50)
        let simulated = DisplayFloatingCameraGeometry(coordinates: simulatedSpace, cameraRectInAppKit: camera,
            interactionBoundsInAppKit: envelope, evidence: .simulated)!
        check(simulated.allowedRectsInAppKit.count == 4, "camera subtraction creates four nonoverlapping bands")
        let allowedArea = simulated.allowedRectsInAppKit.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
        check(allowedArea == envelope.width * envelope.height - camera.width * camera.height,
              "allowed area covers the envelope exactly except camera pixels")
        for rect in simulated.allowedRectsInAppKit {
            check(!DisplayGeometryPolicy.overlaps(rect, camera), "no allowed rectangle covers camera pixels")
            let midpoint = CGPoint(x: rect.midX, y: rect.midY)
            check(simulated.containsInteractionPointInAppKit(midpoint), "every derived visible region can be hit")
            check(simulated.containsInteractionPointInQuartz(simulatedSpace.quartzPoint(fromAppKit: midpoint)!),
                  "the same visible point can be hit in CGEvent coordinates")
        }
        for point in [CGPoint(x: camera.midX, y: camera.midY),
                      CGPoint(x: camera.minX, y: camera.midY), CGPoint(x: camera.maxX, y: camera.maxY)] {
            check(!simulated.containsInteractionPointInAppKit(point), "camera interior and boundary are excluded")
            check(!simulated.containsInteractionPointInQuartz(simulatedSpace.quartzPoint(fromAppKit: point)!),
                  "camera exclusion survives coordinate conversion")
        }
        check(!simulated.containsInteractionPointInQuartz(.init(x: CGFloat.nan, y: 0)), "invalid hit point rejected")
        let fractionalSpace = DisplayCoordinateSpace(
            appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            quartzFrame: CGRect(x: -3840, y: -400, width: 1280, height: 1024))!
        let fractional = DisplayFloatingCameraGeometry(coordinates: fractionalSpace,
            cameraRectInAppKit: CGRect(x: 455.25, y: 748.5, width: 77.5, height: 18.25),
            interactionBoundsInAppKit: CGRect(x: 400.1, y: 730.1, width: 205.6, height: 56.8), evidence: .simulated)!
        let protectedQuartz = fractional.physicalCameraExclusionRectsInQuartz[0]
        for point in [CGPoint(x: protectedQuartz.minX, y: protectedQuartz.midY),
                      CGPoint(x: protectedQuartz.maxX, y: protectedQuartz.midY),
                      CGPoint(x: protectedQuartz.midX, y: protectedQuartz.minY),
                      CGPoint(x: protectedQuartz.midX, y: protectedQuartz.maxY)] {
            check(!fractional.containsInteractionPointInQuartz(point),
                  "fractional matched-frame rounding cannot make a camera boundary interactive")
        }
        let explicitAllowed = [CGRect(x: -900, y: 1135, width: 40, height: 50)]
        let manual = DisplayFloatingCameraGeometry(coordinates: simulatedSpace, cameraRectInAppKit: camera,
            interactionBoundsInAppKit: envelope, allowedRectsInAppKit: explicitAllowed, evidence: .manuallyMeasured)!
        check(manual.allowedRectsInAppKit == explicitAllowed && manual.evidence == .manuallyMeasured,
              "explicit manual regions and provenance are preserved")
        let manualSnapshot = DisplayGeometryPolicy.snapshot(coordinates: simulatedSpace, systemTopSafeInset: 0,
            visualStyle: .attachedNotch, floatingCamera: manual)!
        check(manualSnapshot.cameraEvidence == .manuallyMeasured && !manualSnapshot.usesLegacyNotchLayout,
              "manual camera evidence does not rewrite reported safe top or chosen visual style")
        check(manualSnapshot.physicalCameraExclusionRectsInAppKit == [camera], "physical camera stays separate")
        check(manualSnapshot.interactionRectsInQuartz == manual.interactionRectsInQuartz, "click policy receives the same converted regions")
        check(DisplayGeometryPolicy.snapshot(coordinates: nativeSpace, systemTopSafeInset: 0, floatingCamera: simulated) == nil,
              "stale geometry from another matched display is rejected")
        let overlapCamera = CGRect(x: -840, y: 1160, width: 80, height: 18)
        let overlap = DisplayFloatingCameraGeometry(coordinates: simulatedSpace, cameraRectInAppKit: overlapCamera,
            interactionBoundsInAppKit: envelope, evidence: .simulated)!
        let unionSnapshot = DisplayGeometryPolicy.snapshot(coordinates: simulatedSpace, systemTopSafeInset: 32, floatingCamera: overlap)!
        check(unionSnapshot.conservativeExclusionRectsInAppKit.count == 1,
              "overlapping protected areas merge conservatively rather than duplicating protected hit regions")
        check(unionSnapshot.conservativeExclusionRectsInAppKit[0].contains(overlapCamera), "merged set still excludes every camera pixel")

        for badCamera in badRects + [
            camera.offsetBy(dx: -2000, dy: 0),
            CGRect(x: -840, y: 1182, width: 80, height: 18)
        ] {
            check(DisplayFloatingCameraGeometry(coordinates: simulatedSpace, cameraRectInAppKit: badCamera,
                interactionBoundsInAppKit: envelope, evidence: .simulated) == nil, "invalid/offscreen/edge-attached floating camera")
        }
        let hugeEnvelope = CGRect(x: -1599, y: 700, width: 1598, height: 499)
        check(DisplayFloatingCameraGeometry(coordinates: simulatedSpace,
            cameraRectInAppKit: CGRect(x: -1400, y: 1000, width: 900, height: 18),
            interactionBoundsInAppKit: hugeEnvelope, evidence: .simulated) == nil, "oversize camera width")
        check(DisplayFloatingCameraGeometry(coordinates: simulatedSpace,
            cameraRectInAppKit: CGRect(x: -840, y: 800, width: 80, height: 300),
            interactionBoundsInAppKit: hugeEnvelope, evidence: .simulated) == nil, "oversize camera height")
        check(DisplayFloatingCameraGeometry(coordinates: simulatedSpace, cameraRectInAppKit: camera,
            interactionBoundsInAppKit: CGRect(x: -900, y: 600, width: 200, height: 600), evidence: .simulated) == nil,
              "oversize interaction envelope")
        for badEnvelope in badRects + [envelope.offsetBy(dx: -2000, dy: 0), camera] {
            check(DisplayFloatingCameraGeometry(coordinates: simulatedSpace, cameraRectInAppKit: camera,
                interactionBoundsInAppKit: badEnvelope, evidence: .simulated) == nil, "invalid envelope or no visible interaction space")
        }
        for invalidAllowed in [
            [], [camera], [envelope], [explicitAllowed[0], explicitAllowed[0]],
            [CGRect(x: -1000, y: 1135, width: 40, height: 50)],
            [CGRect(x: CGFloat.nan, y: 1135, width: 40, height: 50)]
        ] {
            check(DisplayFloatingCameraGeometry(coordinates: simulatedSpace, cameraRectInAppKit: camera,
                interactionBoundsInAppKit: envelope, allowedRectsInAppKit: invalidAllowed, evidence: .simulated) == nil,
                  "empty, overlapping, camera-covering or out-of-envelope hit regions rejected")
        }

        if CommandLine.arguments.contains("--inspect-connected-displays") {
            // Read-only measurements; no windows, taps, input capture or preferences.
            for screen in NSScreen.screens {
                let snapshot = NSScreenDisplayGeometryAdapter.snapshot(for: screen)!
                check(snapshot.coordinates.appKitFrame == screen.frame, "adapter uses the exact NSScreen frame")
                check(snapshot.cameraEvidence == nil && snapshot.interactionRectsInQuartz.isEmpty,
                      "adapter never enables measured-camera/native interception by itself")
                if let old = PhysicalNotchGeometry.resolve(screenFrame: screen.frame,
                    safeTop: Double(screen.safeAreaInsets.top), leftArea: screen.auxiliaryTopLeftArea,
                    rightArea: screen.auxiliaryTopRightArea) {
                    let new = snapshot.reportedTopGap!
                    check(new.width == old.width && new.height == old.height && new.centerOffset == old.centerOffset,
                          "connected-display legacy geometry is unchanged")
                    print("READ-ONLY display \(snapshot.displayID ?? 0): gap \(new.width) x \(new.height), offset \(new.centerOffset); AppKit \(snapshot.coordinates.appKitFrame), Quartz \(snapshot.coordinates.quartzFrame)")
                } else {
                    check(snapshot.reportedTopGap == nil, "connected notchless display has no fabricated gap")
                    print("READ-ONLY display \(snapshot.displayID ?? 0): no reported top gap")
                }
            }
        }
        print("PASS \(checks) display geometry checks; floating-camera fixtures are SIMULATED.")
    }
}
