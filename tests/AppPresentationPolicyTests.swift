import Foundation

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
        print("PASS: \(checks) fresh-install/upgrade defaults and header-layout checks")
    }
}
