import Foundation

@main
struct WorkspaceModePolicyTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let visible = ["music", "calendar", "weather", "quickActions"]
        for mode in WorkspaceMode.allCases {
            for activity in WorkspaceActivity.allCases {
                check(!WorkspaceModePolicy.allowed(base: false, mode: mode, activity: activity), "Feature-off always wins")
                check(WorkspaceModePolicy.allowed(base: true, mode: mode, activity: activity) == mode.allows(activity), "Only restrict existing activity")
            }
            check(!WorkspaceModePolicy.hover(base: false, mode: mode), "Never enable hover")
            check(WorkspaceModePolicy.lowImpact(base: true, mode: mode), "Never turn off the user's low-impact choice")
            check(WorkspaceModePolicy.lowImpact(base: false, mode: mode) == mode.lowImpact, "Effective low-impact mode")
            let order = WorkspaceModePolicy.homeOrder(visible, mode: mode)
            check(Set(order) == Set(visible) && order.count == visible.count, "No hidden tile becomes enabled or duplicated")
            check(WorkspaceModePolicy.homeOrder(["weather"], mode: mode) == ["weather"], "Only reorder existing visible tiles")
            for duration in WorkspaceModeDuration.allCases {
                let session = WorkspaceModeSession(mode: mode, duration: duration, now: now)
                check(!session.isExpired(at: now), "Starts active")
                if mode == .presentation || duration == .untilQuit {
                    check(session.expiresAt == nil, "Manual-end sessions have no expiry")
                    check(!session.isExpired(at: now.addingTimeInterval(100_000)), "Presentation must never reveal private content on a timer")
                } else {
                    let seconds = duration.seconds!
                    check(session.expiresAt == now.addingTimeInterval(seconds), "Exact visible wall-clock expiry")
                    check(!session.isExpired(at: now.addingTimeInterval(seconds - 1)), "Not early")
                    check(session.isExpired(at: now.addingTimeInterval(seconds)), "Expires at boundary")
                }
            }
        }
        for activity in WorkspaceActivity.allCases {
            check(WorkspaceModePolicy.allowed(base: true, mode: nil, activity: activity), "Ending a mode returns current base settings")
            check(!WorkspaceModePolicy.allowed(base: false, mode: nil, activity: activity), "Ending never undoes an off preference")
            check(!WorkspaceMode.presentation.allows(activity), "Presentation quiets all live activities")
        }
        check(WorkspaceModePolicy.homeOrder(visible, mode: nil) == visible, "Ending restores current manual order")
        check(WorkspaceModePolicy.homeOrder(visible, mode: .work).first == "calendar", "Work prioritizes Calendar")
        check(WorkspaceModePolicy.homeOrder(visible, mode: .creative).first == "music", "Creative prioritizes Music")
        check(WorkspaceMode.presentation.pauseWallpapers && WorkspaceMode.travel.pauseWallpapers, "Privacy and travel pause automatic rotation")
        check(WorkspaceMode.allCases.filter(\.hidesPrivateContent) == [.presentation], "Only Presentation hides private content")
        check(WorkspaceMode.developer.preferredActivity == "agentOnly" && WorkspaceMode.creative.preferredActivity == "musicOnly", "Existing priority values")
        print("PASS: \(checks) temporary Mode and privacy policy checks")
    }
}
