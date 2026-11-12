import Foundation
import CoreGraphics

@main struct DockReplacementPolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ reason: String) { precondition(condition(), reason); checks += 1 }
        for content in [false, true] {
            for visible in [false, true] {
                for panel in [false, true] {
                    check(DockReplacementPolicy.permitsUserAction(contentAllowed: content, visible: visible, panelVisible: panel)
                          == (content && visible && panel), "Hidden or not-yet-presented Dock cannot launch Calendar or another app")
                }
            }
        }
        check(!DockReplacementPolicy.shouldTraceFocus(startedAt: nil, now: 100), "No trace before a real Bar enable")
        for age in [-1.0, 0, 0.01, 59.99, 60, 61, 1_000] {
            check(DockReplacementPolicy.shouldTraceFocus(startedAt: 100, now: 100 + age) == (age >= 0 && age < 60),
                  "Diagnostic collection stops after a bounded monotonic window")
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            check(!DockReplacementPolicy.shouldTraceFocus(startedAt: invalid, now: 100), "Invalid trace start rejected")
            check(!DockReplacementPolicy.shouldTraceFocus(startedAt: 100, now: invalid), "Invalid trace time rejected")
        }
        func overlaps(_ left: CGRect, _ right: CGRect) -> Bool {
            let intersection = left.intersection(right)
            return !intersection.isNull && intersection.width * intersection.height > 0.00001
        }
        let kinds = DockReplacementWidgetKind.allCases
        let expectedWidths = [220.0, 200, 124, 128, 136, 120, 168, 180]
        check(kinds.count == expectedWidths.count && zip(kinds, expectedWidths).allSatisfy { DockReplacementPolicy.faceWidth(for: $0.0) == $0.1 }, "all widget types have readable variable face widths")
        check(DockReplacementLayout.starter.widgets.map(\.kind) == [.nowPlaying, .upNext, .battery, .timer, .clock, .calculator], "new widgets remain opt-in; original starter is unchanged")
        let displays = [CGRect(x: 0, y: 80, width: 1512, height: 870),
                        CGRect(x: -1920, y: -800, width: 1920, height: 1080),
                        CGRect(x: 420.5, y: 1000.25, width: 980.5, height: 1431.25),
                        CGRect(x: -600, y: 64, width: 640, height: 460),
                        CGRect(x: 0, y: 0, width: 320, height: 240)]
        for display in displays {
            for apps in [0, 1, 4, 24] {
                for count in [0, 1, 6, 17, 48] {
                    let widgets = (0..<count).map { kinds[$0 % kinds.count] }
                    for iconSize in [32.0, 48, 64] {
                        guard let base = DockReplacementPolicy.barLayout(in: display, appCount: apps, widgetKinds: widgets, iconSize: iconSize) else {
                            fatalError("Supported finite display/count/icon combination must fit")
                        }
                        check(display.contains(base.frame), "bar fits usable negative/fractional/narrow display")
                        check(base.surfaceHeight == max(76, iconSize + 16) && base.frame.minY == display.minY + 8,
                              "compact surface height and baseline are deterministic")
                        check(base.frame.height >= base.surfaceHeight && base.frame.height <= base.surfaceHeight + 24,
                              "small fixed top envelope fits magnification without a tall overlay")
                        check(base.magnificationReserve == (base.appSlots.isEmpty ? 0 : 48), "only real visible icons reserve horizontal hover room")
                        check(base.appSlots.count + base.hiddenAppCount == apps, "every app has a slot or overflow menu")
                        check(base.galleryButtonFrame.width == 32, "gallery is always available")
                        var covered: [Int] = []
                        for page in 0..<base.pageCount {
                            let layout = DockReplacementPolicy.barLayout(in: display, appCount: apps, widgetKinds: widgets,
                                iconSize: iconSize, requestedPage: page)!
                            check(layout.frame == base.frame, "last/other pages never resize or shift the bar")
                            check(layout.overflowButtonFrame == base.overflowButtonFrame && layout.galleryButtonFrame == base.galleryButtonFrame,
                                  "page navigation remains under the pointer")
                            check(layout.widgetSlots.map(\.index) == Array(layout.visibleWidgetRange), "exact contiguous widget mapping")
                            covered.append(contentsOf: layout.visibleWidgetRange)
                            let rectangles = layout.appSlots + layout.widgetSlots.map(\.frame) +
                                [layout.galleryButtonFrame] + [layout.appOverflowButtonFrame, layout.overflowButtonFrame].compactMap { $0 }
                            let localBounds = CGRect(origin: .zero, size: layout.frame.size)
                            for (index, rect) in rectangles.enumerated() {
                                check(DockReplacementPolicy.validRect(rect) && localBounds.contains(rect), "all control/face slots stay inside fixed local bounds")
                                check(rectangles.enumerated().allSatisfy { $0.offset == index || !overlaps(rect, $0.element) }, "no app/widget/navigation hit regions overlap")
                            }
                            for slot in layout.widgetSlots {
                                let card = DockReplacementPolicy.expandedCardFrame(for: slot.frame, in: layout, usableFrame: display)!
                                check(display.contains(card), "expanded panel fits actual display")
                                let surface = CGRect(x: layout.frame.minX, y: layout.frame.minY, width: layout.frame.width, height: layout.surfaceHeight)
                                check(card.minY >= surface.maxY + 8 && !overlaps(card, surface), "expanded panel stays above compact surface without resizing bar")
                                check(card.width <= 320 && card.height <= 280, "expanded card is bounded on narrow/short screens")
                            }
                        }
                        check(covered == Array(0..<count), "all independent widget instances appear exactly once across pages")
                        let baseRectangles = base.appSlots
                        for hovered in [nil] + baseRectangles.indices.map(Optional.some) {
                            let magnification = DockReplacementPolicy.magnification(appCount: baseRectangles.count,
                                hoveredIndex: hovered, iconSize: iconSize, maxExtra: base.magnificationReserve)!
                            let presented = DockReplacementPolicy.appPresentationFrames(in: base, hoveredIndex: hovered)
                            check(magnification.scales.count == baseRectangles.count && magnification.offsets.count == baseRectangles.count,
                                  "one transform per visible icon")
                            check(magnification.totalExtra >= 0 && magnification.totalExtra <= base.magnificationReserve + 0.00001,
                                  "total growth never exceeds fixed reserved width")
                            let bounds = CGRect(origin: .zero, size: base.frame.size)
                            let movingControls = base.widgetSlots.map(\.frame) + [base.galleryButtonFrame] +
                                [base.appOverflowButtonFrame, base.overflowButtonFrame].compactMap { $0 }
                            let controls = movingControls.map { $0.offsetBy(dx: magnification.totalExtra / 2, dy: 0) }
                            let glassWidth = base.frame.width - base.magnificationReserve + magnification.totalExtra
                            let glass = CGRect(x: (base.frame.width - glassWidth) / 2, y: 0, width: glassWidth, height: base.surfaceHeight)
                            check(bounds.contains(glass), "dynamic visual glass stays within constant window envelope")
                            for (index, rect) in presented.enumerated() {
                                check(bounds.contains(rect), "magnified icon never clips fixed window")
                                check(rect.minY == baseRectangles[index].minY, "icon magnification retains one baseline")
                                check(controls.allSatisfy { !overlaps(rect, $0) }, "magnified icons never overlap widget/menu hit regions")
                                check(presented.enumerated().allSatisfy { $0.offset == index || !overlaps(rect, $0.element) },
                                      "neighboring magnified icons reflow without overlap")
                                check(DockReplacementPolicy.hoveredAppIndex(at: CGPoint(x: baseRectangles[index].midX, y: baseRectangles[index].midY), in: base) == index,
                                      "hover classification depends only on static rest geometry")
                            }
                            check(controls.allSatisfy(bounds.contains), "all moved controls fit reserved fixed width")
                            if hovered == nil { check(magnification.totalExtra == 0 && magnification.offsets.allSatisfy { $0 == 0 }, "hover exit restores exact rest presentation") }
                        }
                        let last = DockReplacementPolicy.barLayout(in: display, appCount: apps, widgetKinds: widgets, iconSize: iconSize, requestedPage: Int.max)!
                        let first = DockReplacementPolicy.barLayout(in: display, appCount: apps, widgetKinds: widgets, iconSize: iconSize, requestedPage: Int.min)!
                        check(last.page == base.pageCount - 1 && first.page == 0, "oversized/negative pages clamp safely")
                        let stack = DockReplacementPolicy.barLayout(in: display, appCount: apps, widgetKinds: widgets,
                            iconSize: iconSize, requestedPage: Int.max, overflow: .stack)!
                        check(stack.page == 0 && stack.visibleWidgetRange == base.visibleWidgetRange, "stack keeps the first stable face set")
                        let hidden = DockReplacementPolicy.hiddenWidgetIndices(count: count, visibleRange: stack.visibleWidgetRange)
                        check(Set(hidden).isDisjoint(with: Set(stack.visibleWidgetRange)), "stack menu never duplicates visible widgets")
                        check(Set(hidden).union(stack.visibleWidgetRange) == Set(0..<count), "every hidden widget is reachable through the stack menu")
                    }
                }
            }
        }
        let standard = displays[0]
        for invalid in [CGRect.zero, .null, .infinite, CGRect(x: CGFloat.nan, y: 0, width: 1000, height: 800),
                        CGRect(x: 0, y: 0, width: 319, height: 800), CGRect(x: 0, y: 0, width: 800, height: 91),
                        CGRect(x: 1e100, y: 0, width: 800, height: 600)] {
            check(DockReplacementPolicy.barLayout(in: invalid, appCount: 1, widgetKinds: kinds) == nil, "impossible display frames refused")
        }
        for apps in [-1, 25, Int.max] {
            check(DockReplacementPolicy.barLayout(in: standard, appCount: apps, widgetKinds: kinds) == nil, "invalid app counts refused before arithmetic")
        }
        for size in [Double.nan, .infinity, -.infinity, 0, 31.99, 64.01, Double.greatestFiniteMagnitude] {
            check(DockReplacementPolicy.barLayout(in: standard, appCount: 1, widgetKinds: kinds, iconSize: size) == nil, "invalid icon proposals refused")
        }
        check(DockReplacementPolicy.barLayout(in: standard, appCount: 0, widgetKinds: Array(repeating: .clock, count: 49)) == nil, "49widget overflow refused")
        for invalid in [Double.nan, .infinity, -.infinity, -1, 48.01] {
            check(DockReplacementPolicy.magnification(appCount: 4, hoveredIndex: 0, iconSize: 48, maxExtra: invalid) == nil,
                  "invalid growth budget refused")
        }
        for invalid in [-1, 25, Int.max] {
            check(DockReplacementPolicy.magnification(appCount: invalid, hoveredIndex: 0, iconSize: 48) == nil, "invalid icon count refused before allocation")
        }
        for budget in [0.0, 1, 12, 24, 48] {
            let result = DockReplacementPolicy.magnification(appCount: 24, hoveredIndex: 12, iconSize: 64, maxExtra: budget)!
            check(result.totalExtra <= budget + 0.00001 && result.scales.allSatisfy { $0.isFinite && (1...1.35).contains($0) },
                  "all icon sizes and clipped budgets scale proportionally")
        }
        for invalid in [Int.min, -1, 24, Int.max] {
            let result = DockReplacementPolicy.magnification(appCount: 4, hoveredIndex: invalid, iconSize: 48)!
            check(result.totalExtra == 0, "unknown hover returns resting state without overflow arithmetic")
        }
        // Regression for live313: sampling only nearest-index end states did
        // not exercise the transition. The view must animate the two inputs,
        // then derive every icon/control from this one coupled output.
        func checkContinuousPose(_ layout: DockReplacementBarLayout, x: Double?, presence: Double) {
            let values = DockReplacementPolicy.magnification(in: layout, pointerX: x, presence: presence)!
            let frames = DockReplacementPolicy.appPresentationFrames(in: layout, pointerX: x, presence: presence)
            let bounds = CGRect(origin: .zero, size: layout.frame.size).insetBy(dx: -0.000001, dy: -0.000001)
            check(values.totalExtra >= 0 && values.totalExtra <= layout.magnificationReserve + 0.000001,
                  "continuous intermediate state respects fixed growth budget")
            check(values.scales.count == frames.count && values.scales.allSatisfy { (1...1.3500001).contains($0) },
                  "continuous kernel never exceeds the reserved vertical envelope")
            let controls = (layout.widgetSlots.map(\.frame) + [layout.galleryButtonFrame] +
                [layout.appOverflowButtonFrame, layout.overflowButtonFrame].compactMap { $0 })
                .map { $0.offsetBy(dx: values.totalExtra / 2, dy: 0) }
            check(frames.allSatisfy(bounds.contains) && controls.allSatisfy(bounds.contains),
                  "every interpolated icon/control remains inside the unchanged window")
            check(frames.allSatisfy { rect in controls.allSatisfy { !overlaps(rect, $0) } },
                  "every interpolated icon remains separate from widgets/menus")
            for index in frames.indices.dropLast() {
                let restingGap = layout.appSlots[index + 1].minX - layout.appSlots[index].maxX
                let presentedGap = frames[index + 1].minX - frames[index].maxX
                check(abs(presentedGap - restingGap) < 0.000001,
                      "shared extras preserve the exact neighbor gap throughout the animation path")
            }
            let glassWidth = layout.frame.width - layout.magnificationReserve + values.totalExtra
            check(bounds.contains(CGRect(x: (layout.frame.width - glassWidth) / 2, y: 0,
                width: glassWidth, height: layout.surfaceHeight)), "glass and controls derive from the same intermediate total")
        }
        for display in [displays[0], displays[3], displays[4], CGRect(x: -3440, y: -200, width: 3440, height: 1000)] {
            for requestedApps in [1, 2, 4, 24] {
                for iconSize in [32.0, 48, 64] {
                    let layout = DockReplacementPolicy.barLayout(in: display, appCount: requestedApps, widgetKinds: kinds, iconSize: iconSize)!
                    let centers = layout.appSlots.map { Double($0.midX) }
                    let pitch = iconSize + DockReplacementPolicy.gap
                    let left = (centers.first ?? 0) - pitch / 2
                    let right = (centers.last ?? 0) + pitch / 2
                    let start = left - pitch, end = right + pitch
                    let sampleCount = max(16, (centers.count + 3) * 8)
                    for step in 0...sampleCount {
                        let x = start + (end - start) * Double(step) / Double(sampleCount)
                        for presence in [0.0, 0.125, 0.25, 0.5, 0.75, 1] { checkContinuousPose(layout, x: x, presence: presence) }
                    }
                    for (first, second) in zip(centers, centers.dropFirst()) {
                        let midpoint = (first + second) / 2
                        let before = DockReplacementPolicy.magnification(in: layout, pointerX: midpoint - 0.00001)!
                        let after = DockReplacementPolicy.magnification(in: layout, pointerX: midpoint + 0.00001)!
                        check(zip(before.scales, after.scales).allSatisfy { abs($0.0 - $0.1) < 0.00001 } &&
                            zip(before.offsets, after.offsets).allSatisfy { abs($0.0 - $0.1) < 0.001 },
                              "crossing old nearest-center boundary is continuous instead of jumping indices")
                    }
                    for edge in [left, right] {
                        let before = DockReplacementPolicy.magnification(in: layout, pointerX: edge - 0.00001)!
                        let at = DockReplacementPolicy.magnification(in: layout, pointerX: edge)!
                        let after = DockReplacementPolicy.magnification(in: layout, pointerX: edge + 0.00001)!
                        check(at.totalExtra == 0 && before.totalExtra < 0.000001 && after.totalExtra < 0.000001,
                              "enter/exit ends fade continuously to exact resting geometry")
                    }
                    // Fast pointer sweeps and simultaneous presence changes
                    // model a single AnimatablePair rather than independent
                    // implicit frame animations on individual buttons.
                    for (initialPresence, finalPresence) in [(1.0, 1.0), (0, 1), (1, 0), (0.2, 0.9), (1.1, -0.1)] {
                        for step in 0...40 {
                            let t = Double(step) / 40
                            checkContinuousPose(layout, x: start + (end - start) * t,
                                presence: initialPresence + (finalPresence - initialPresence) * t)
                        }
                    }
                    let resting = DockReplacementPolicy.magnification(in: layout, pointerX: nil)!
                    check(resting.totalExtra == 0 && resting.offsets.allSatisfy { $0 == 0 }, "nil pointer restores exact resting state")
                    checkContinuousPose(layout, x: centers.first, presence: 0)
                }
            }
        }
        let validCenters = [40.0, 94.0, 148.0]
        for invalidCenters in [[40.0], [40, 94, Double.nan], [40, 45, 148], [148, 94, 40]] {
            check(DockReplacementPolicy.magnification(appCount: 3, pointerX: 94, iconSize: 48, restCenters: invalidCenters) == nil,
                  "invalid/unordered/overlapping rest centers refused before continuous math")
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            check(DockReplacementPolicy.magnification(appCount: 3, pointerX: invalid, iconSize: 48, restCenters: validCenters) == nil,
                  "nonfinite pointer refused")
            check(DockReplacementPolicy.magnification(appCount: 3, pointerX: 94, iconSize: 48, restCenters: validCenters, presence: invalid) == nil,
                  "nonfinite presence refused")
        }
        let over = DockReplacementPolicy.magnification(appCount: 3, pointerX: 94, iconSize: 48, restCenters: validCenters, presence: 1.2)!
        let full = DockReplacementPolicy.magnification(appCount: 3, pointerX: 94, iconSize: 48, restCenters: validCenters, presence: 1)!
        check(over == full, "finite animation overshoot clamps safely to full presence")
        let bar = DockReplacementPolicy.barLayout(in: standard, appCount: 4, widgetKinds: kinds)!
        for invalidSize in [CGSize.zero, CGSize(width: CGFloat.nan, height: 280), CGSize(width: 320, height: CGFloat.infinity), CGSize(width: 2049, height: 280)] {
            check(DockReplacementPolicy.expandedCardFrame(for: bar.galleryButtonFrame, in: bar, usableFrame: standard, preferredSize: invalidSize) == nil, "invalid preferred card size refused")
        }
        check(DockReplacementPolicy.expandedCardFrame(for: CGRect(x: -1, y: 0, width: 30, height: 30), in: bar, usableFrame: standard) == nil,
              "card anchor must belong to the bar")
        let fullScreen = CGRect(x: -1512, y: 400, width: 1512, height: 982)
        let hardwareSafe = DockReplacementPolicy.usableFrame(screenFrame: fullScreen, visibleFrame: fullScreen, topSafeInset: 38)!
        check(hardwareSafe.maxY == fullScreen.maxY - 38, "physical top housing excluded even with menu bar auto-hidden")
        let reduced = CGRect(x: fullScreen.minX, y: fullScreen.minY + 80, width: fullScreen.width, height: fullScreen.height - 120)
        check(DockReplacementPolicy.usableFrame(screenFrame: fullScreen, visibleFrame: reduced, topSafeInset: 38) == reduced,
              "existing menu/systemDock exclusions are retained")
        check(DockReplacementPolicy.usableFrame(screenFrame: fullScreen, visibleFrame: fullScreen, topSafeInset: -1) == nil, "negative hardware inset refused")
        check(DockReplacementPolicy.usableFrame(screenFrame: fullScreen, visibleFrame: fullScreen, topSafeInset: .nan) == nil, "nonfinite inset refused")

        let repeated = DockReplacementLayout(widgets: [
            .init(kind: .clock, timeZoneIdentifier: "America/Detroit"),
            .init(kind: .clock, timeZoneIdentifier: "Asia/Tokyo"),
            .init(kind: .timer, timerDuration: 600)])
        check(repeated.isValid, "same-kind instances are independent and valid")
        let originalByID = Dictionary(uniqueKeysWithValues: repeated.widgets.map { ($0.id, $0) })
        for instance in repeated.widgets {
            for target in repeated.widgets {
                let reordered = DockReplacementPolicy.placing(instance.id, at: target.id, in: repeated)!
                check(reordered.widgets.firstIndex(where: { $0.id == instance.id }) == repeated.widgets.firstIndex(where: { $0.id == target.id }),
                      "drag moves to every target including the last slot")
                check(Dictionary(uniqueKeysWithValues: reordered.widgets.map { ($0.id, $0) }) == originalByID,
                      "drag preserves timezone/timer config and stable IDs")
            }
            for direction in [-1, 1] {
                let moved = DockReplacementPolicy.moving(instance.id, by: direction, in: repeated)!
                check(moved.isValid && Set(moved.widgets.map(\.id)) == Set(originalByID.keys), "accessible moves preserve every instance")
            }
        }
        check(DockReplacementPolicy.adding(repeated.widgets[0], to: repeated) == nil, "duplicate instance ID refused")
        let added = DockReplacementPolicy.adding(.init(kind: .clock), to: repeated)!
        check(added.widgets.count == 4, "same kind may be added again")
        let removed = DockReplacementPolicy.removing(repeated.widgets[0].id, from: repeated)!
        check(removed.widgets.count == 2 && removed.widgets.contains(repeated.widgets[1]), "removing one clock preserves other clock")
        check(DockReplacementPolicy.moving(UUID(), by: 1, in: repeated) == nil, "unknown reorder ID refused")
        check(DockReplacementPolicy.moving(repeated.widgets[0].id, by: Int.max, in: repeated) == nil, "invalid move direction refused before addition")
        var invalidLayout = repeated; invalidLayout.widgets.append(repeated.widgets[0])
        check(DockReplacementPolicy.placing(repeated.widgets[0].id, at: repeated.widgets[1].id, in: invalidLayout) == nil, "invalid saved layout cannot be edited into silent repair")
        var invalidInstance = repeated.widgets[0]; invalidInstance.timerDuration = .nan
        check(DockReplacementPolicy.adding(invalidInstance, to: repeated) == nil, "nonfinite config refused")
        invalidInstance = repeated.widgets[0]; invalidInstance.timeZoneIdentifier = "../unknown"
        check(!invalidInstance.isValid, "unrecognized timezone refused")
        let encoded = try JSONEncoder().encode(repeated)
        check(DockReplacementLayout.decode(encoded) == repeated, "independent configs roundtrip")
        let systemWidgets = [DockReplacementWidgetInstance(kind: .clock), .init(kind: .system), .init(kind: .weather)]
        check(!DockReplacementPolicy.needsSystemSampling(widgets: systemWidgets, visibleRange: 0..<1, expandedID: nil, active: true), "off-page System releases sampling")
        check(DockReplacementPolicy.needsSystemSampling(widgets: systemWidgets, visibleRange: 1..<2, expandedID: nil, active: true), "visible System owns a lease")
        check(DockReplacementPolicy.needsSystemSampling(widgets: systemWidgets, visibleRange: 0..<1, expandedID: systemWidgets[1].id, active: true), "expanded off-page System owns a lease")
        check(!DockReplacementPolicy.needsSystemSampling(widgets: systemWidgets, visibleRange: 0..<3, expandedID: systemWidgets[1].id, active: false), "suspended Dock releases visible and expanded demand")
        check(!DockReplacementPolicy.needsSystemSampling(widgets: systemWidgets, visibleRange: 0..<1, expandedID: UUID(), active: true), "unknown expanded identity cannot start sampling")
        check(DockReplacementPolicy.hiddenWidgetIndices(count: 49, visibleRange: 0..<1).isEmpty, "unbounded menu input refused")
        check(DockReplacementPolicy.percentage(0) == "0%" && DockReplacementPolicy.percentage(1) == "100%", "usage endpoints display correctly")
        for invalid: Double? in [nil, .nan, .infinity, -.infinity, -0.1, 1.1] {
            check(DockReplacementPolicy.usageFraction(invalid) == nil && DockReplacementPolicy.percentage(invalid) == "—", "missing or invalid reading is unavailable, not zero")
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        for age in [-301.0, -300, 0, 900, 901, .infinity] {
            check(DockReplacementPolicy.weatherIsCurrent(updatedAt: now.addingTimeInterval(-age), now: now, failed: false) == (-300...900).contains(age), "weather freshness bounds")
        }
        check(!DockReplacementPolicy.weatherIsCurrent(updatedAt: now, now: now, failed: true), "failed refresh marks cached weather as last-known")
        print("PASS \(checks) replacement Dock geometry/instance checks; synthetic rectangles and models only, no GUI, preferences, process control, camera or user data")
    }
}
