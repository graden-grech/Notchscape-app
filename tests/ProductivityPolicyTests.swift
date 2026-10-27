import Foundation

@main
struct ProductivityPolicyTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); count += 1
    }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        for enabled in [false, true] {
            for loaded in [false, true] {
                for locked in [false, true] {
                    for paused in [false, true] {
                        check(ClipboardPolicy.recordingAllowed(enabled: enabled, loaded: loaded, locked: locked, userPaused: paused)
                            == (enabled && loaded && !locked && !paused), "Opt-in, storage, lock and manual pause gates")
                    }
                }
            }
        }
        for type in ClipboardPolicy.privateTypes {
            check(!ClipboardPolicy.canCapture(types: [type, "public.utf8-plain-text"], source: nil, exclusions: []), "Protected copies never enter history")
        }
        for app in ClipboardPolicy.excludedApps {
            check(!ClipboardPolicy.canCapture(types: ["public.utf8-plain-text"], source: app, exclusions: ClipboardPolicy.excludedApps), "Known password app excluded")
        }
        check(!ClipboardPolicy.canCapture(types: [], source: "com.private.test", exclusions: ["com.private.test"]), "Custom app excluded")
        check(ClipboardPolicy.canCapture(types: ["public.utf8-plain-text"], source: nil, exclusions: []), "Unknown app allowed unless clipboard is protected")
        let valid = ClipboardEntry(date: now, text: "hello", source: "Test")
        let expired = ClipboardEntry(date: now.addingTimeInterval(-8 * 86400), text: "expired")
        var pin = expired; pin.id = UUID(); pin.pinned = true
        let future = ClipboardEntry(date: now.addingTimeInterval(1), text: "future")
        check(ClipboardPolicy.retained([valid, expired, pin, future], now: now, days: 7) == [pin, valid], "Pins ignore age; future samples are rejected")
        check(ClipboardPolicy.retained([valid, valid], now: now, days: 7).count == 1, "Duplicate IDs cannot grow storage")
        check(ClipboardPolicy.retained([ClipboardEntry(text: "")], now: now, days: 7).isEmpty, "Empty entries excluded")
        let large = ClipboardEntry(date: now, image: Data(repeating: 0, count: 2_000_001))
        check(ClipboardPolicy.retained([large], now: now, days: 7).isEmpty, "Oversized images rejected")
        let images = (0..<10).map { _ in ClipboardEntry(date: now, image: Data(repeating: 0, count: 2_000_000), pinned: true) }
        check(ClipboardPolicy.retained(images, now: now, days: 7).count == 6, "Pins cannot exceed total byte budget")
        let many = (0..<200).map { _ in ClipboardEntry(date: now, text: "x", pinned: true) }
        check(ClipboardPolicy.retained(many, now: now, days: 7).count == 150, "All records including pins have a count cap")
        check(NotePolicy.bounded(String(repeating: "🍎", count: 50_001)).count == 50_000, "Notes are bounded without splitting graphemes")
        check(QuickNote(text: "First line\nSecond line").title == "First line", "Native note title")
        check(QuickNote().title == "New note", "Empty note placeholder")
        let oldNote = try JSONDecoder().decode(QuickNote.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","text":"Legacy note","modified":0}"#.utf8))
        check(oldNote.appleNote == nil && oldNote.isConflictCopy == nil, "Existing encrypted notes need no destructive migration")
        check(AppleNotesPolicy.resolve(local: "base", remote: "base", base: "base") == .unchanged, "Unchanged notes do not write")
        check(AppleNotesPolicy.resolve(local: "base", remote: "new", base: "base") == .pull, "Remote-only edits pull")
        check(AppleNotesPolicy.resolve(local: "new", remote: "base", base: "base") == .push, "Local-only edits push")
        check(AppleNotesPolicy.resolve(local: "same", remote: "same", base: "old") == .unchanged, "Matching concurrent edits converge")
        check(AppleNotesPolicy.resolve(local: "local", remote: "remote", base: "base") == .conflict, "Different concurrent edits preserve both versions")
        check(AppleNotesPolicy.normalized("A\r\nB\r\n\n") == "A\nB", "Apple Notes terminal line endings normalize")
        check(AppleNotesPolicy.normalized("  A \n B ") == "  A \n B ", "Meaningful whitespace is not stripped")
        check(AppleNotesPolicy.html("<script>&\"\nNext") == "<div>&lt;script&gt;&amp;&quot;</div><div>Next</div>", "Note text cannot inject HTML or scripts")
        check(AppleNotesPolicy.html("A\n\nB") == "<div>A</div><div><br></div><div>B</div>", "Blank lines survive export")
        check(AppleNotesPolicy.scriptLiteral("\"\\\n\r\t") == "\"\\\"\\\\\\n\\r\\t\"", "Text escapes every AppleScript string delimiter")
        check(AppleNotesPolicy.scriptLiteral("end tell\n do shell script \"bad\"").contains("\\n"), "Instructions in a note remain data")
        check(AppleNotesPolicy.supported(text: "plain", html: "<div>plain</div>"), "Simple text is eligible")
        for rich in ["<table></table>", "<ul><li>x</li></ul>", "<img src='x'>", "<a href='x'>x</a>", "<b>bold</b>", "<h1>Title</h1>", "<div data-checked='1'>x</div>", "<span style='font-weight: 700'>bold</span>"] {
            check(!AppleNotesPolicy.supported(text: "x", html: rich), "Rich Notes content must not be overwritten by plain text")
        }
        check(!AppleNotesPolicy.supported(text: "A\0B", html: ""), "Embedded NUL is not sent to AppleScript")
        check(!AppleNotesPolicy.supported(text: String(repeating: "x", count: 50_001), html: ""), "Oversized remote notes are not silently truncated")
        let conflict = QuickNote(text: String(repeating: "x", count: 50_000), isConflictCopy: true)
        check(conflict.text.count == 50_000 && conflict.title.hasSuffix(" (conflict copy)"), "A conflict label never truncates original content")
        let linked = QuickNote(text: "hello", appleNote: .init(remoteID: "id", baseText: "hello"))
        let linkedRoundTrip = try JSONDecoder().decode(QuickNote.self, from: JSONEncoder().encode(linked))
        check(linkedRoundTrip == linked, "Encrypted link metadata round trip")
        let roundTrip = try JSONDecoder().decode(ClipboardEntry.self, from: JSONEncoder().encode(valid))
        check(roundTrip == valid, "Private snapshot round trip")
        check(DeviceBatteryPolicy.percent(0) == 0, "A zero battery is real, not unavailable")
        check(DeviceBatteryPolicy.percent(100) == 100, "Full battery")
        for invalid: Any in [-1, 101, Double.nan, Double.infinity, "90", true] {
            check(DeviceBatteryPolicy.percent(invalid) == nil, "Invalid battery is unavailable")
        }
        check(DeviceBatteryPolicy.address("AA-BB:CC") == "aabbcc", "Normalize device identity without a name guess")
        let report = DeviceBatteryPolicy.report(["device_connected": [["Test AirPods": ["device_address": "AA-BB-CC-DD-EE-FF", "device_batteryLevelLeft": "85%", "device_batteryLevelRight": "0%", "device_batteryLevelCase": "101%", "device_serialNumber": "never retained"]]]])
        check(report["aabbccddeeff"]?["left"] == 85, "System Information per-bud reading")
        check(report["aabbccddeeff"]?["right"] == 0, "Empty earbud remains zero")
        check(report["aabbccddeeff"]?["case"] == nil, "Invalid case level is unavailable")
        check(report["aabbccddeeff"]?.count == 2, "Do not retain serial numbers or other report details")
        check(DeviceBatteryPolicy.report(["device_address": "not an address", "device_batteryLevelLeft": "50%"]).isEmpty, "No battery association based on a name or invalid identity")
        let data: [String: Any] = ["rate_limits": ["primary": ["used_percent": 85, "resets_at": now.addingTimeInterval(3600).timeIntervalSince1970]], "info": ["total_token_usage": ["total_tokens": 1234]]]
        let reading = AgentUsageReading.decode(data, provider: "Codex", now: now, source: "Fixture")!
        check(reading.remainingPercent == 15, "Low usage remains an advisory reading")
        check(reading.tokens == 1234, "Only explicit token counts are reported")
        check(reading.resetsAt == now.addingTimeInterval(3600), "Only future reset dates")
        check(AgentUsageReading.decode(["usage": ["remaining_percent": 0]], provider: "Claude", now: now, source: "Hook")?.remainingPercent == 0, "Actual zero is preserved")
        for invalid: Any in [-1, 101, Double.nan, Double.infinity, true, "15"] {
            check(AgentUsageReading.decode(["remaining_percent": invalid], provider: "Test", now: now, source: "Test") == nil, "Malformed usage cannot create fake progress")
        }
        check(AgentUsageReading.decode(["total_tokens": -1], provider: "T", now: now, source: "Test") == nil, "Negative tokens rejected")
        check(AgentUsageReading.decode(["remaining_percent": 40, "resets_at": 1], provider: "T", now: now, source: "Test")?.resetsAt == nil, "Expired reset hidden")
        check(AgentUsageReading.decode(["prompt": "15% left"], provider: "T", now: now, source: "Test") == nil, "Never guess numeric usage from prompt text")
        print("PASS: \(count) local tools and usage policy checks")
    }
}
