import Foundation
import CoreGraphics

@main struct DockWorkspacePolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
        let base = DockWorkspaceLayout()
        check(base.isValid && base.pins.isEmpty, "first launch has no arbitrary installed-app inventory")
        check(base.widgets == [.clock, .battery, .system], "small starter widget layout")
        check(DockWorkspaceWidget.allCases.count == 5, "five genuine starter card types")
        check(Set(DockWorkspaceWidget.allCases.map(\.symbol)).count == 5, "distinct native symbols")
        let encoded = try JSONEncoder().encode(base)
        check(DockWorkspacePolicy.decode(encoded) == base, "layout roundtrip")
        check(DockWorkspacePolicy.decode(nil) == nil, "absence is distinguishable from saved layout")
        check(DockWorkspacePolicy.decode(Data("{}".utf8)) == nil, "incomplete layout is refused")
        check(DockWorkspacePolicy.decode(Data(repeating: 0, count: DockWorkspacePolicy.maximumLayoutBytes + 1)) == nil, "oversized input is refused before JSON decode")
        var broken = base; broken.schemaVersion = 2
        let future = try JSONEncoder().encode(broken)
        check(!broken.isValid && DockWorkspacePolicy.decode(future) == nil, "future schema not silently read")
        broken = base; broken.widgets = [.clock, .clock]
        check(!broken.isValid, "duplicate widgets refused")
        let pin = DockWorkspacePin(id: UUID(), title: "My App", kind: .application, bookmark: Data([1, 2, 3]))
        check(pin.isValid, "bounded bookmark metadata accepted without accessing a file")
        for invalid in ["", "  App", "App\nName", String(repeating: "x", count: 81)] {
            var changed = pin; changed.title = invalid
            check(!changed.isValid, "invalid saved pin label refused")
        }
        for size in [0, DockWorkspacePolicy.maximumBookmarkBytes + 1] {
            var changed = pin; changed.bookmark = Data(repeating: 1, count: size)
            check(!changed.isValid, "invalid bookmark size refused")
        }
        var maxBookmark = pin; maxBookmark.bookmark = Data(repeating: 1, count: DockWorkspacePolicy.maximumBookmarkBytes)
        check(maxBookmark.isValid, "maximum bookmark boundary accepted")
        broken = base; broken.pins = [pin, pin]
        check(!broken.isValid, "duplicate pin identity refused")
        broken = base
        broken.pins = (0..<24).map { .init(id: UUID(), title: "App \($0)", kind: .application, bookmark: Data([1])) }
        check(broken.isValid, "24 pins supported")
        broken.pins.append(.init(id: UUID(), title: "Too Many", kind: .folder, bookmark: Data([1])))
        check(!broken.isValid, "25th pin refused")
        check(DockWorkspacePolicy.title("  A\nB\tC  ") == "A B C", "control characters removed")
        check(DockWorkspacePolicy.title(String(repeating: "🎨", count: 90)).count == 80, "unicode labels bounded without splitting graphemes")

        for count in 0...24 {
            let input = Array(0..<count)
            for value in input {
                for direction in [-1, 1] {
                    let result = DockWorkspacePolicy.moving(value, by: direction, in: input)
                    check(result.count == count && Set(result) == Set(input), "arrow reorder never loses or duplicates a pin")
                    let origin = input.firstIndex(of: value)!
                    let destination = min(count - 1, max(0, origin + direction))
                    check(result.firstIndex(of: value) == destination, "one-step reorder reaches the right slot including edges")
                }
                for target in input {
                    let result = DockWorkspacePolicy.placing(value, at: target, in: input)
                    check(result.count == count && Set(result) == Set(input), "drag reorder preserves inventory")
                    check(result.firstIndex(of: value) == input.firstIndex(of: target), "drag reaches target slot in either direction, including the end")
                    check(result.filter { $0 != value } == input.filter { $0 != value }, "drag keeps other pin order")
                }
            }
            check(DockWorkspacePolicy.moving(-1, by: 1, in: input) == input, "unknown arrow identity ignored")
            check(DockWorkspacePolicy.moving(0, by: Int.max, in: input) == input, "invalid delta checked before adding")
            check(DockWorkspacePolicy.placing(-1, at: 0, in: input) == input, "unknown drag identity ignored")
        }
        for mask in 0..<32 {
            let privacy = DockWorkspacePrivacy(enabled: mask & 1 != 0, unlocked: mask & 2 != 0,
                                               awake: mask & 4 != 0, activeSession: mask & 8 != 0,
                                               presenting: mask & 16 != 0)
            check(privacy.permitsDisplay == (mask == 15), "every lifecycle/privacy combination is fail closed")
        }
        let validSession: [String: Any] = [kCGSessionUserIDKey as String: NSNumber(value: 501),
                                          kCGSessionOnConsoleKey as String: true,
                                          kCGSessionLoginDoneKey as String: true]
        func permitted(_ session: [String: Any]?, uid: UInt32 = 501, euid: UInt32 = 501) -> Bool {
            LocalDesktopSessionPolicy.permitsDisplay(session: session, currentUID: uid, effectiveUID: euid)
        }
        check(permitted(validSession), "observed unlocked desktop with omitted supplemental lock key is eligible")
        var flagged = validSession; flagged["CGSSessionScreenIsLocked"] = false
        check(permitted(flagged), "explicit unlocked Boolean is eligible")
        flagged["CGSSessionScreenIsLocked"] = true
        check(!permitted(flagged), "explicit locked Boolean refuses display")
        for value: Any in ["false", "true", 0, 1, -1, NSNull(), [false]] {
            flagged["CGSSessionScreenIsLocked"] = value
            check(!permitted(flagged), "present malformed lock indicator refuses display")
        }
        check(!permitted(nil), "missing GUI session refuses display")
        check(!permitted(validSession, uid: 502), "different real user refuses display")
        check(!permitted(validSession, euid: 0), "effective user mismatch refuses display")
        for key in [kCGSessionOnConsoleKey as String, kCGSessionLoginDoneKey as String] {
            for value: Any in [false, "true", 1, 0, NSNull()] {
                var invalid = validSession; invalid[key] = value
                check(!permitted(invalid), "missing/false/non-Boolean public session flags refuse display")
            }
            var missing = validSession; missing.removeValue(forKey: key)
            check(!permitted(missing), "both public Boolean session flags are mandatory")
        }
        for value: Any in [true, false, "501", -1, 501.5, Double.nan, Double.infinity, UInt64(UInt32.max) + 1] {
            var invalid = validSession; invalid[kCGSessionUserIDKey as String] = value
            check(!permitted(invalid), "only finite exact numeric current-user ID accepted")
        }
        var missingUID = validSession; missingUID.removeValue(forKey: kCGSessionUserIDKey as String)
        check(!permitted(missingUID), "UID mandatory even when supplemental lock indicator is absent")
        for mask in 0..<32 {
            let privacy = DockWorkspacePrivacy(enabled: mask & 1 != 0, unlocked: permitted(validSession) && mask & 2 != 0,
                                               awake: mask & 4 != 0, activeSession: mask & 8 != 0, presenting: mask & 16 != 0)
            check(privacy.permitsDisplay == (mask == 15), "optional OS lock field cannot bypass the caller event/lifecycle fences")
        }
        for panelWidth in stride(from: 456.0, through: 620, by: 1) {
            let contentWidth = panelWidth - 36
            for (minimum, maximum) in [(220.0, 2), (72.0, 7)] {
                let columns = DockWorkspacePolicy.columnCount(contentWidth: contentWidth, minimumItemWidth: minimum, maximumColumns: maximum)
                let itemWidth = (contentWidth - Double(columns - 1) * 12) / Double(columns)
                check((1...maximum).contains(columns), "fixed columns are bounded for every accepted panel width")
                check(itemWidth >= minimum && itemWidth.isFinite, "native fixed card proposals fit supported panel width")
                check(abs(itemWidth * Double(columns) + Double(columns - 1) * 12 - contentWidth) < 0.0001,
                      "eager rows exactly fill the bounded content width without layout feedback")
                for count in 0...24 {
                    let rows = DockWorkspacePolicy.rowRanges(itemCount: count, columns: columns)
                    check(rows.flatMap(Array.init) == Array(0..<count), "eager chunks contain every pin exactly once")
                    check(rows.allSatisfy { !$0.isEmpty && $0.count <= columns }, "no eager row overflows its fixed column proposal")
                }
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
            check(DockWorkspacePolicy.columnCount(contentWidth: invalid, minimumItemWidth: 220, maximumColumns: 2) == 1,
                  "invalid native width gets one conservative column")
        }
        check(DockWorkspacePolicy.rowRanges(itemCount: 25, columns: 2).isEmpty, "oversized eager content rejected")
        check(DockWorkspacePolicy.rowRanges(itemCount: 5, columns: 0).isEmpty, "invalid eager column count rejected")
        let displays = [CGRect(x: 0, y: 80, width: 1512, height: 870),
                        CGRect(x: -1920, y: -800, width: 1920, height: 1080),
                        CGRect(x: 420.5, y: 1000.25, width: 980.5, height: 1431.25),
                        CGRect(x: 0, y: 0, width: 480, height: 280)]
        for display in displays {
            let frame = DockWorkspacePolicy.panelFrame(in: display)!
            check(display.contains(frame), "Dock panel stays inside true visible frame on every display")
            check(frame.midX == display.midX && frame.minY == display.minY + 12, "centered above system Dock, including negative coordinates")
            check(frame.width <= 620 && frame.height <= 500, "panel has bounded dimensions")
        }
        for display in [CGRect.zero, .null, .infinite, CGRect(x: 0, y: 0, width: 479, height: 400),
                        CGRect(x: 0, y: 0, width: 500, height: 279), CGRect(x: CGFloat.nan, y: 0, width: 500, height: 500)] {
            check(DockWorkspacePolicy.panelFrame(in: display) == nil, "invalid display cannot place an offscreen panel")
        }
        print("PASS \(checks) Dock workspace checks; synthetic layout/bookmark bytes only, no app launch, filesystem inventory, windows, camera or user data")
    }
}
