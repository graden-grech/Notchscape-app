import Foundation
import CoreGraphics

@main struct DockWidgetPolicyTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ reason: String) { precondition(value(), reason); checks += 1 }
        let token = "55F38626-989C-4E14-917F-E0ED5BFF270B"
        let args = ["--widget", "clock", "--owner-pid", "123", "--control-token", token]
        let config = DockWidgetLaunchConfiguration.parse(args)
        check(config?.widget == .clock && config?.ownerPID == 123 && config?.controlToken == token, "exact launch schema")
        check(DockWidgetLaunchConfiguration.parse(Array(args[4...5]) + Array(args[0...3])) == config, "argument order independent")
        for kind in DockWidgetKind.allCases {
            var changed = args; changed[1] = kind.rawValue
            check(DockWidgetLaunchConfiguration.parse(changed)?.widget == kind, "three implemented widget kinds")
        }
        for pid in ["0", "1", "-1", "1.2", "2147483648", " 123", "123 ", "00123", "9999999999999", "123;ls"] {
            var changed = args; changed[3] = pid
            check(DockWidgetLaunchConfiguration.parse(changed) == nil, "invalid owner PID refused")
        }
        for raw in ["", "CLOCK", "weather", "../clock", String(repeating: "a", count: 81)] {
            var changed = args; changed[1] = raw
            check(DockWidgetLaunchConfiguration.parse(changed) == nil, "unknown/oversized kind refused")
        }
        for raw in ["", "hello", "../anything", token + "x", " " + token] {
            var changed = args; changed[5] = raw
            check(DockWidgetLaunchConfiguration.parse(changed) == nil, "scope token must be UUID")
        }
        check(DockWidgetLaunchConfiguration.parse(args + ["--extra"]) == nil, "extra arguments refused")
        check(DockWidgetLaunchConfiguration.parse(Array(args.dropLast())) == nil, "odd arguments refused")
        var repeated = args; repeated[4] = "--widget"
        check(DockWidgetLaunchConfiguration.parse(repeated) == nil, "duplicate launch field refused")
        check(DockWidgetControl.parse(["command": "quit"]) == .quit, "bounded close command")
        check(DockWidgetControl.parse(["command": "quit", "widget": "clock"]) == nil, "unexpected close payload refused")
        check(DockWidgetControl.parse(["command": "configure", "widget": "clock", "presenting": true]) == .configure(widget: .clock, presenting: true), "strict presentation handshake")
        check(DockWidgetControl.parse(["command": "configure", "widget": "battery", "presenting": false]) == .configure(widget: .battery, presenting: false), "valid configure")
        for value: Any in ["false", 0, 1, NSNull(), [false]] {
            check(DockWidgetControl.parse(["command": "configure", "widget": "calendar", "presenting": value]) == nil, "nonboolean privacy payload refused")
        }
        check(DockWidgetControl.parse(["command": "configure", "widget": "calendar"]) == nil, "no implicit privacy enabling")
        check(DockWidgetControl.parse(["command": "run", "path": "/tmp/test"]) == nil, "no executable command surface")
        check(DockWidgetControl.parse(nil) == nil, "empty notification refused")
        let now = Date(timeIntervalSince1970: 1_793_640_010)
        let reading = DockWidgetBattery.reading(current: 75, maximum: 100, charging: true, onACPower: true)!
        var permitted = DockWidgetPrivacy(); permitted.sessionEligible = true; permitted.locked = false; permitted.presenting = false
        for mask in 0..<64 {
            let privacy = DockWidgetPrivacy(sessionEligible: mask & 1 != 0, locked: mask & 2 != 0,
                awake: mask & 4 != 0, sessionActive: mask & 8 != 0, presenting: mask & 16 != 0, ownerAlive: mask & 32 != 0)
            check(privacy.permitsContent == (mask == 45), "all six lifecycle fences applied")
            for kind in DockWidgetKind.allCases {
                let snapshot = DockWidgetSnapshot.make(widget: kind, privacy: privacy, now: now, battery: reading)
                check(snapshot.redacted == !privacy.permitsContent, "each tile respects privacy")
                if !privacy.permitsContent { check(snapshot.date == nil && snapshot.battery == nil, "redaction clears data rather than covering it") }
            }
        }
        for current in stride(from: 0.0, through: 100, by: 1) {
            let value = DockWidgetBattery.reading(current: current, maximum: 100, charging: false, onACPower: false)
            check(value?.percent == Int(current), "battery capacity conversion")
        }
        for pair in [(Double.nan, 100.0), (1.0, Double.infinity), (-1.0, 100.0), (101.0, 100.0), (0.0, 0.0), (1.0, -1.0), (1.0, 1_000_000_001.0)] {
            check(DockWidgetBattery.reading(current: pair.0, maximum: pair.1, charging: false, onACPower: false) == nil, "invalid capacity never fabricates a reading")
        }
        for offset in [-121.0, -60, -1, 0, 1, 59.5, 60, 12345] {
            let delay = DockWidgetPolicy.nextRefresh(widget: .clock, now: Date(timeIntervalSince1970: offset))!
            check((1...60).contains(delay), "one minute maximum with no tight polling or negative-epoch overflow")
        }
        check(DockWidgetPolicy.nextRefresh(widget: .battery, now: now) == nil, "battery uses events, no repeating poll")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        for components in [DateComponents(year: 2026, month: 11, day: 1, hour: 0), DateComponents(year: 2026, month: 3, day: 8, hour: 0), DateComponents(year: 2026, month: 11, day: 3, hour: 12)] {
            let date = calendar.date(from: components)!
            let delay = DockWidgetPolicy.nextRefresh(widget: .calendar, now: date, calendar: calendar)!
            check(delay > 0 && delay <= 90_000, "calendar refresh follows local next midnight across DST")
            let next = date.addingTimeInterval(delay)
            check(calendar.component(.hour, from: next) == 0 && !calendar.isDate(next, inSameDayAs: date), "calendar midnight is exact, not24hourassumption")
        }
        let first = DockWidgetSnapshot.make(widget: .battery, privacy: permitted, now: now, battery: reading)
        let second = DockWidgetSnapshot.make(widget: .battery, privacy: permitted, now: now.addingTimeInterval(300), battery: reading)
        check(first == second && first.date == nil, "unchanged battery never redraws just because time passed")
        let baseSession: [String: Any] = [kCGSessionUserIDKey as String: 501,
            kCGSessionOnConsoleKey as String: true, kCGSessionLoginDoneKey as String: true]
        check(DockWidgetPolicy.eligibleSession(baseSession, uid: 501, euid: 501), "observed public session fields with absent supplemental lockkey")
        var invalidSession = baseSession; invalidSession["CGSSessionScreenIsLocked"] = true
        check(!DockWidgetPolicy.eligibleSession(invalidSession, uid: 501, euid: 501), "explicit OS locked refuses")
        invalidSession["CGSSessionScreenIsLocked"] = "false"
        check(!DockWidgetPolicy.eligibleSession(invalidSession, uid: 501, euid: 501), "malformed lockkey refuses")
        invalidSession[kCGSessionOnConsoleKey as String] = false
        check(!DockWidgetPolicy.eligibleSession(invalidSession, uid: 501, euid: 501), "inactive console refuses")
        check(!DockWidgetPolicy.eligibleSession(baseSession, uid: 502, euid: 502), "otheruser refuses")
        check(!DockWidgetPolicy.eligibleSession(baseSession, uid: 501, euid: 0), "effective UID mismatch refuses")
        check(!DockWidgetPolicy.eligibleSession(nil, uid: 501, euid: 501), "missingGUI refuses")
        print("PASS \(checks) Dock widget policy checks; synthetic values only, no host launch, Dock mutation, process control or user data")
    }
}
