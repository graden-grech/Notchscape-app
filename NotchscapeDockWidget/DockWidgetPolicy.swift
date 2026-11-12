import Foundation
import CoreGraphics

enum DockWidgetKind: String, CaseIterable, Sendable {
    case clock, battery, calendar
    var title: String {
        switch self { case .clock: "Clock"; case .battery: "Battery"; case .calendar: "Calendar" }
    }
}

struct DockWidgetLaunchConfiguration: Equatable, Sendable {
    let widget: DockWidgetKind
    let ownerPID: Int32
    let controlToken: String

    static func parse(_ arguments: [String]) -> Self? {
        guard arguments.count == 6, arguments.allSatisfy({ $0.utf8.count <= 80 }) else { return nil }
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let key = arguments[index]
            guard ["--widget", "--owner-pid", "--control-token"].contains(key), values[key] == nil else { return nil }
            values[key] = arguments[index + 1]
        }
        guard let raw = values["--widget"], let widget = DockWidgetKind(rawValue: raw),
              let process = values["--owner-pid"], process.range(of: #"^[1-9][0-9]{0,9}$"#, options: .regularExpression) != nil,
              let pid = Int32(process), pid > 1,
              let token = values["--control-token"], token.utf8.count == 36,
              UUID(uuidString: token) != nil else { return nil }
        return .init(widget: widget, ownerPID: pid, controlToken: token)
    }
}

enum DockWidgetControl: Equatable, Sendable {
    case configure(widget: DockWidgetKind, presenting: Bool)
    case quit

    static func parse(_ info: [AnyHashable: Any]?) -> Self? {
        guard let info, let command = info["command"] as? String else { return nil }
        let keys = Set(info.keys.compactMap { $0 as? String })
        guard keys.count == info.count else { return nil }
        if command == "quit", keys == ["command"] { return .quit }
        guard command == "configure", keys == ["command", "widget", "presenting"],
              let raw = info["widget"] as? String, let widget = DockWidgetKind(rawValue: raw),
              let presenting = info["presenting"] as? NSNumber,
              CFGetTypeID(presenting) == CFBooleanGetTypeID() else { return nil }
        return .configure(widget: widget, presenting: presenting.boolValue)
    }
}

struct DockWidgetPrivacy: Equatable, Sendable {
    var sessionEligible = false
    var locked = true
    var awake = true
    var sessionActive = true
    var presenting = true
    var ownerAlive = true
    var permitsContent: Bool { sessionEligible && !locked && awake && sessionActive && !presenting && ownerAlive }
}

struct DockWidgetBattery: Equatable, Sendable {
    let percent: Int
    let charging: Bool
    let onACPower: Bool

    static func reading(current: Double, maximum: Double, charging: Bool, onACPower: Bool) -> Self? {
        guard current.isFinite, maximum.isFinite, maximum > 0, current >= 0, current <= maximum,
              maximum <= 1_000_000_000 else { return nil }
        return .init(percent: Int((current / maximum * 100).rounded()), charging: charging, onACPower: onACPower)
    }
}

struct DockWidgetSnapshot: Equatable, Sendable {
    let widget: DockWidgetKind
    let redacted: Bool
    let date: Date?
    let battery: DockWidgetBattery?

    static func make(widget: DockWidgetKind, privacy: DockWidgetPrivacy, now: Date,
                     battery: DockWidgetBattery?, calendar: Calendar = .current) -> Self {
        guard privacy.permitsContent, now.timeIntervalSince1970.isFinite else {
            return .init(widget: widget, redacted: true, date: nil, battery: nil)
        }
        let date: Date?
        switch widget {
        case .clock: date = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60)
        case .calendar: date = calendar.startOfDay(for: now)
        case .battery: date = nil
        }
        return .init(widget: widget, redacted: false, date: date, battery: widget == .battery ? battery : nil)
    }
}

enum DockWidgetPolicy {
    static let controlName = "com.graden-grech.Notchscape.DockWidget.control"
    static let eventName = "com.graden-grech.Notchscape.DockWidget.event"
    static let mainBundleID = "theboringteam.boringnotch"
    static let hostBundleID = "com.graden-grech.Notchscape.DockWidget"
    static let ownerRequirement = #"identifier "theboringteam.boringnotch" and anchor apple generic and certificate leaf[subject.OU] = "6H86CTRJCP""#

    /// Ordinary desktop content only. Lock notifications remain an independent
    /// fence. macOS may omit its supplemental lock key on an unlocked desktop.
    static func eligibleSession(_ session: [String: Any]?, uid: UInt32, euid: UInt32) -> Bool {
        guard uid == euid, let session,
              let owner = session[kCGSessionUserIDKey as String] as? NSNumber,
              CFGetTypeID(owner) == CFNumberGetTypeID(), owner.doubleValue == Double(uid),
              boolean(session[kCGSessionOnConsoleKey as String]) == true,
              boolean(session[kCGSessionLoginDoneKey as String]) == true else { return false }
        if let lock = session["CGSSessionScreenIsLocked"] { return boolean(lock) == false }
        return true
    }

    static func nextRefresh(widget: DockWidgetKind, now: Date, calendar: Calendar = .current) -> TimeInterval? {
        guard now.timeIntervalSince1970.isFinite else { return nil }
        switch widget {
        case .battery: return nil // Power-source notifications, never polling.
        case .clock:
            let remainder = (now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) + 60).truncatingRemainder(dividingBy: 60)
            return max(1, 60 - remainder)
        case .calendar:
            guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
            return max(1, next.timeIntervalSince(now))
        }
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
}
