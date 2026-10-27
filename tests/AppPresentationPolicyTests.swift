import Foundation
import CoreGraphics

@main struct AppPresentationPolicyTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            precondition(value(), name); checks += 1
        }

        let fresh = InitialPresentationDefaults.missingValues(in: [:])
        check(fresh == ["weatherEnabled": false, "showOnAllDisplays": true], "fresh-install defaults")
        check(InitialPresentationDefaults.missingValues(in: ["firstLaunch": true]) == fresh,
              "unfinished onboarding uses the new defaults")
        let legacy = InitialPresentationDefaults.missingValues(in: ["firstLaunch": false])
        check(legacy == ["weatherEnabled": true, "showOnAllDisplays": false],
              "upgrades preserve both old implicit defaults")

        for used in [false, true] {
            for weather in [false, true] {
                for displays in [false, true] {
                    let persistent: [String: Any] = ["firstLaunch": !used,
                        "weatherEnabled": weather, "showOnAllDisplays": displays]
                    check(InitialPresentationDefaults.missingValues(in: persistent).isEmpty,
                          "explicit user choices are never replaced")
                }
                let partial: [String: Any] = ["firstLaunch": !used, "weatherEnabled": weather]
                check(InitialPresentationDefaults.missingValues(in: partial) == ["showOnAllDisplays": !used],
                      "only the missing display preference is supplied")
            }
        }
        check(InitialPresentationDefaults.missingValues(in: ["weatherEnabled": "custom"])["weatherEnabled"] == nil,
              "do not silently repair or overwrite an existing value")
        check(InitialPresentationDefaults.missingValues(in: ["appTheme": "whiteHouse"])
              == fresh, "unrelated preferences are neither read as onboarding nor rewritten")

        let heights: [Double] = [-1, 0, 20, 24, 30, 32, 37, 40, 48, 64, .nan, .infinity]
        for physical in [false, true] {
            for height in heights {
                let row = NotchHeaderLayoutPolicy.rowHeight(closedHeight: height, hasPhysicalNotch: physical)
                check(row.isFinite && row >= NotchHeaderLayoutPolicy.tabHeight, "no expanded control is clipped by a short row")
                let tabTop = NotchHeaderLayoutPolicy.topInset + (row - NotchHeaderLayoutPolicy.tabHeight) / 2
                let controlTop = NotchHeaderLayoutPolicy.topInset + (row - NotchHeaderLayoutPolicy.controlHeight) / 2
                check(tabTop >= 8 && controlTop >= 8, "tabs, battery and buttons all clear the top edge")
                if !physical {
                    check(row == 32, "notchless expanded row is independent of closed-island height")
                } else if height.isFinite {
                    check(row + NotchHeaderLayoutPolicy.topInset >= height, "hardware lane remains covered")
                }
            }
        }
        let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 950, width: 663.5, height: 32)
        let right = CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        let cutout = PhysicalNotchGeometry.resolve(screenFrame: builtIn, safeTop: 32,
                                                   leftArea: left, rightArea: right)!
        check(cutout.width == 185 && cutout.height == 32, "reported hardware gap has no software width or height padding")
        check(cutout.centerOffset == 0, "centered hardware stays centered")
        for height in [24.0, 32, 38, 45, 64] {
            let row = NotchHeaderLayoutPolicy.rowHeight(closedHeight: height, hasPhysicalNotch: true)
            let coverTop = NotchHeaderLayoutPolicy.topInset + cutout.expandedHeaderTopOffset
            check(coverTop == 0 && coverTop + cutout.height == 32,
                  "expanded physical cover stays at the hardware top/bottom regardless of header height")
            check(row >= 32, "independent physical cover retains control clearance")
        }
        let shiftedFrame = builtIn.offsetBy(dx: -1512, dy: 982)
        let shifted = PhysicalNotchGeometry.resolve(screenFrame: shiftedFrame, safeTop: 32,
            leftArea: left.offsetBy(dx: -1512, dy: 982), rightArea: right.offsetBy(dx: -1512, dy: 982))!
        check(shifted == cutout, "secondary-display origins do not change hardware dimensions")
        let offCenter = PhysicalNotchGeometry.resolve(screenFrame: builtIn, safeTop: 32,
            leftArea: left.offsetBy(dx: 4, dy: 0), rightArea: right.offsetBy(dx: 4, dy: 0))!
        check(offCenter.width == 185 && offCenter.centerOffset == 4, "cover follows the reported gap center")
        for safeTop in [0.0, -1, .nan, .infinity] {
            check(PhysicalNotchGeometry.resolve(screenFrame: builtIn, safeTop: safeTop,
                leftArea: left, rightArea: right) == nil, "notchless/invalid displays do not gain a physical cover")
        }
        check(PhysicalNotchGeometry.resolve(screenFrame: builtIn, safeTop: 32,
            leftArea: nil, rightArea: right) == nil, "missing auxiliary measurements are not guessed")
        check(PhysicalNotchGeometry.resolve(screenFrame: builtIn, safeTop: 32,
            leftArea: right, rightArea: left) == nil, "overlapping auxiliary areas cannot create negative widths")
        check(PhysicalNotchGeometry.resolve(screenFrame: builtIn, safeTop: 32,
            leftArea: left.offsetBy(dx: -1000, dy: 0), rightArea: right) == nil,
              "out-of-screen measurements do not create a physical cover")

        let batteryContentWidth = 612.0
        let batteryLanes = BatteryNotificationLayoutPolicy.compactLanes(
            leadingContentWidth: 22, trailingContentWidth: 34, physicalNotchWidth: cutout.width)!
        check(batteryLanes.leadingWidth == batteryLanes.trailingWidth,
              "short indicators cannot shift the physical camera gap away from the banner center")
        check(batteryLanes.leadingWidth == 36,
              "normal power states reserve only an icon lane and a percentage lane")
        check(batteryLanes.totalWidth + 2 * 14 == 305,
              "charging banner and chin use only the cutout, compact side lanes and existing outer insets")
        var previousWidth = 0.0
        for leadingWidth in [0.0, 22, 48, 72, 110, 184] {
            for offset in [-24.0, 0, 24] {
                let lanes = BatteryNotificationLayoutPolicy.compactLanes(
                    leadingContentWidth: leadingWidth, trailingContentWidth: 34,
                    physicalNotchWidth: cutout.width, centerOffset: offset)!
                check(lanes.leadingWidth >= leadingWidth && lanes.trailingWidth >= 34,
                      "warning or icon and percentage fit their visible lanes at the native measured width")
                check(lanes.leadingWidth >= 36 && lanes.trailingWidth >= 36,
                      "compact banners retain bounded readable minimum side lanes")
                let gapCenter = lanes.leadingWidth + lanes.cutoutWidth / 2 - lanes.totalWidth / 2
                check(gapCenter == offset, "adaptive width keeps the physical housing reservation at its measured center")
            }
            let centered = BatteryNotificationLayoutPolicy.compactLanes(leadingContentWidth: leadingWidth, trailingContentWidth: 34,
                physicalNotchWidth: cutout.width)!
            check(centered.totalWidth >= previousWidth, "only wider visible content can increase the compact banner width")
            previousWidth = centered.totalWidth
        }
        for invalid in [Double.nan, .infinity, -1] {
            check(BatteryNotificationLayoutPolicy.compactLanes(leadingContentWidth: invalid, trailingContentWidth: 34,
                  physicalNotchWidth: cutout.width) == nil, "invalid text measurements cannot create an unbounded notification")
            check(BatteryNotificationLayoutPolicy.compactLanes(leadingContentWidth: 22, trailingContentWidth: invalid,
                  physicalNotchWidth: cutout.width) == nil, "invalid percentage measurements cannot create an unbounded notification")
        }
        for pluggedIn in [false, true] {
            for charging in [false, true] {
                for full in [false, true] {
                    let normal: BatteryNotificationPresentation = charging ? .charging
                        : pluggedIn ? (full ? .fullyCharged : .connectedToPower) : .onBattery
                    check(BatteryNotificationPresentation.resolve(lowAlert: false, criticalAlert: false,
                        pluggedIn: pluggedIn, charging: charging, fullyCharged: full) == normal,
                          "normal battery presentation follows explicit power signals")
                    check(normal.warningTitle == nil, "normal power states use one icon and no visible status sentence")
                    check(BatteryNotificationPresentation.resolve(lowAlert: true, criticalAlert: false,
                        pluggedIn: pluggedIn, charging: charging, fullyCharged: full) == .lowBattery,
                          "a low-battery event retains readable warning copy")
                    check(BatteryNotificationPresentation.resolve(lowAlert: false, criticalAlert: true,
                        pluggedIn: pluggedIn, charging: charging, fullyCharged: full) == .criticalBattery,
                          "a critical-battery event retains readable warning copy")
                    check(BatteryNotificationPresentation.resolve(lowAlert: true, criticalAlert: true,
                        pluggedIn: pluggedIn, charging: charging, fullyCharged: full) == .criticalBattery,
                          "critical warning wins when both alert signals are present")
                }
            }
        }
        check(BatteryNotificationPresentation.lowBattery.warningTitle == "Low battery", "low alert has concise readable copy")
        check(BatteryNotificationPresentation.criticalBattery.warningTitle == "Critical battery", "critical alert has distinct concise copy")
        for contentWidth in [batteryContentWidth, 640, 720] {
            for notchWidth in [185.0, 210, 240] {
                for offset in [-24.0, -4, 0, 4, 24] {
                    let lanes = BatteryNotificationLayoutPolicy.lanes(
                        contentWidth: contentWidth, physicalNotchWidth: notchWidth, centerOffset: offset)!
                    let gapLeft = lanes.leadingWidth - contentWidth / 2
                    let gapRight = gapLeft + lanes.cutoutWidth
                    check(abs(lanes.totalWidth - contentWidth) < 0.001, "lane geometry fills the bounded banner without overflow")
                    check(lanes.leadingWidth > 0 && lanes.trailingWidth > 0, "status and battery indicator both have visible lanes")
                    check(abs((gapLeft + gapRight) / 2 - offset) < 0.001,
                          "camera reservation follows the measured hardware center, including secondary displays")
                    check(gapLeft <= offset - notchWidth / 2 - 10,
                          "status cannot enter the camera housing or its leading clearance")
                    check(gapRight >= offset + notchWidth / 2 + 10,
                          "battery icon cannot enter the camera housing or its trailing clearance")
                }
            }
        }
        for invalid in [Double.nan, .infinity, -1, 0] {
            check(BatteryNotificationLayoutPolicy.lanes(contentWidth: invalid, physicalNotchWidth: 185) == nil,
                  "invalid banner dimensions cannot create invisible or unbounded lanes")
            check(BatteryNotificationLayoutPolicy.lanes(contentWidth: batteryContentWidth, physicalNotchWidth: invalid) == nil,
                  "invalid hardware widths do not create a camera reservation")
        }
        for offset in [Double.nan, .infinity, -400, 400] {
            check(BatteryNotificationLayoutPolicy.lanes(contentWidth: batteryContentWidth,
                  physicalNotchWidth: 185, centerOffset: offset) == nil,
                  "invalid or out-of-banner camera offsets are rejected")
        }
        check(BatteryNotificationLayoutPolicy.lanes(contentWidth: 100, physicalNotchWidth: 185) == nil,
              "a camera gap cannot silently produce negative visible side widths")
        print("PASS: \(checks) fresh-install/upgrade defaults, header and battery-notification layout checks")
    }
}
