import Foundation

@main struct MenuBarModulePolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let all = Set(MenuBarModule.allCases)
        check(all.count == 14 && all.contains(.tools), "Thirteen readouts plus one existing-tools launcher")
        check(MenuBarModulePolicy.selected([]).isEmpty, "No default selections produce status items")
        check(MenuBarModulePolicy.selected(["cpu", "cpu", "unknown", "battery"]) == [.cpu, .battery],
              "Duplicate and unknown saved IDs do not create extra items")
        for module in all {
            let restored = try JSONDecoder().decode(MenuBarModule.self, from: JSONEncoder().encode(module))
            check(restored == module && restored.width == module.width, "Saved IDs restore the same fixed-width module")
            check(module.width.isFinite && (28...180).contains(module.width), "Every real module has a bounded native status width")
            check(!module.title.isEmpty && !module.symbol.isEmpty, "Catalog entries have accessible names and symbols")
        }
        for mask in 0..<16 {
            let state = MenuBarModulePrivacyState(consoleUnlocked: mask & 1 != 0, awake: mask & 2 != 0,
                                                 sessionActive: mask & 4 != 0, presenting: mask & 8 != 0)
            let permitted = mask == 7
            check(state.permitsDisplay == permitted, "All privacy gates must agree")
            for module in all {
                let selected: Set<MenuBarModule> = [module]
                let active = MenuBarModulePolicy.active(selected: selected, available: all, privacy: state)
                check(active == (permitted ? selected : []), "Lock, sleep, inactive console or Presentation removes every item")
                check(MenuBarModulePolicy.active(selected: selected, available: [], privacy: state).isEmpty,
                      "Uninstalled/unavailable capabilities never show, even with saved visibility enabled")
            }
        }
        let open = MenuBarModulePrivacyState(consoleUnlocked: true, awake: true, sessionActive: true, presenting: false)
        check(MenuBarModulePolicy.active(selected: all, available: [.battery, .tools], privacy: open) == [.battery, .tools],
              "Availability affects only its own modules")
        for flags in 0..<8 {
            let stopwatch = flags & 1 != 0, event = flags & 2 != 0, awake = flags & 4 != 0
            func interval(_ active: Set<MenuBarModule>) -> TimeInterval? {
                MenuBarModulePolicy.clockInterval(active: active, stopwatchRunning: stopwatch,
                                                  eventCountingDown: event, keepAwakeActive: awake)
            }
            check(interval([]) == nil, "No selected items means no UI update timer")
            check(interval([.cpu, .memory, .network, .storage, .battery, .devices, .music, .timer, .tools]) == nil,
                  "Existing publishers never acquire another polling clock")
            check(interval([.dateTime]) == 60 && interval([.worldClock]) == 60, "Clocks update at minute boundaries")
            check(interval([.stopwatch]) == (stopwatch ? 1 : nil), "Paused stopwatch has no timer")
            check(interval([.countdown]) == (event ? 1 : nil), "No available pinned event has no countdown clock")
            check(interval([.keepAwake]) == (awake ? 60 : nil), "Showing Keep Awake while off starts no clock or assertion")
            check(interval(all) == (stopwatch || event ? 1 : 60), "All items share only the fastest required clock")
        }

        var demand = SystemSamplingDemand()
        check(!demand.shouldSample, "No CPU/filesystem/network sampling without a consumer")
        demand.setMenuBarRequested(true)
        check(demand.shouldSample, "A visible metric requests shared sampling")
        demand.setMenuBarRequested(true)
        demand.setMenuBarRequested(false)
        check(!demand.shouldSample, "Idempotent menu demand needs only one matching release")
        demand.dashboardAppeared(); demand.dashboardAppeared(); demand.setMenuBarRequested(true)
        demand.dashboardDisappeared(); demand.setMenuBarRequested(false)
        check(demand.shouldSample && demand.dashboardReaders == 1, "One screen leaving or a module turning off preserves another dashboard reader")
        demand.setSuspended(true)
        check(!demand.shouldSample && demand.dashboardReaders == 1, "Privacy suspension retains demand but stops the actual sampler")
        demand.setMenuBarRequested(true); demand.setMenuBarRequested(false)
        check(!demand.shouldSample, "Demand changes while asleep cannot restart sampling")
        demand.setSuspended(false)
        check(demand.shouldSample, "A safe resume restores the still-visible dashboard")
        demand.dashboardDisappeared(); demand.dashboardDisappeared()
        check(!demand.shouldSample && demand.dashboardReaders == 0, "Balanced or duplicate release never underflows")
        demand.setSuspended(true); demand.setMenuBarRequested(true)
        check(!demand.shouldSample, "A suspended menu metric cannot sample")
        demand.setMenuBarRequested(false); demand.setSuspended(false)
        check(!demand.shouldSample, "Uninstalling while asleep does not resurrect demand on wake")

        for invalid in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            check(MenuBarModulePolicy.percent(invalid) == "—", "Invalid/missing percentages never look like zero")
        }
        check(MenuBarModulePolicy.percent(nil) == "—", "Unavailable provider data remains unavailable")
        check(MenuBarModulePolicy.percent(0) == "0%" && MenuBarModulePolicy.percent(1) == "100%", "Actual zero and full readings are retained")
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            check(MenuBarModulePolicy.duration(invalid) == "—", "Invalid duration cannot overflow integer formatting")
            check(MenuBarModulePolicy.rate(invalid) == "—", "Invalid network counters never become fabricated traffic")
        }
        check(MenuBarModulePolicy.duration(0) == "00:00", "Real elapsed zero is supported")
        check(MenuBarModulePolicy.duration(59.1) == "01:00", "Remaining fractional second rounds upward")
        check(MenuBarModulePolicy.duration(3601) == "1:00:01", "Hours do not wrap to a misleading minute count")
        check(MenuBarModulePolicy.duration(172800) == "2d 0h", "Long session values remain bounded")
        check(MenuBarModulePolicy.duration(Double.greatestFiniteMagnitude) == "999d+", "Extreme valid durations are bounded before Int conversion")
        check(MenuBarModulePolicy.rate(0) == "0B/s", "Observed idle counters retain actual zero")
        check(MenuBarModulePolicy.rate(1_500_000) == "1.5M/s", "Passive network rates use declared decimal byte units")
        check(MenuBarModulePolicy.rate(Double.greatestFiniteMagnitude).count <= 9, "Large measured rates cannot expand the status width")
        check(MenuBarModulePolicy.text("Track\nTitle\t\0Name") == "Track Title  Name", "Provider strings cannot add menu rows/control characters")
        check(MenuBarModulePolicy.text(String(repeating: "x", count: 100_000), limit: 20).count == 20, "Long provider labels are bounded")

        let iso = ISO8601DateFormatter()
        func date(_ value: String) -> Date { iso.date(from: value)! }
        check(MenuBarModulePolicy.worldClock(date: date("2026-03-08T06:59:00Z"), zoneID: "America/New_York") == "01:59", "World clock before spring DST")
        check(MenuBarModulePolicy.worldClock(date: date("2026-03-08T07:01:00Z"), zoneID: "America/New_York") == "03:01", "World clock honors spring DST jump")
        check(MenuBarModulePolicy.worldClock(date: date("2026-11-01T05:59:00Z"), zoneID: "America/New_York") == "01:59", "World clock before autumn DST")
        check(MenuBarModulePolicy.worldClock(date: date("2026-11-01T06:01:00Z"), zoneID: "America/New_York") == "01:01", "World clock honors repeated autumn hour")
        check(MenuBarModulePolicy.worldClock(date: date("2026-11-02T00:00:00Z"), zoneID: "Asia/Tokyo") == "09:00", "Actual zone offsets come from Foundation")
        check(MenuBarModulePolicy.worldClock(date: Date(), zoneID: "No/Such_Zone") == nil, "Unsupported zones do not silently become UTC")
        check(MenuBarModulePolicy.worldClock(date: Date(timeIntervalSinceReferenceDate: .nan), zoneID: "Etc/UTC") == nil, "Invalid dates fail closed")
        print("PASS \(checks) menu-bar module policy checks (synthetic inputs; no items, sampling, preferences or power changes)")
    }
}
